"""Quantize supported PyTorch demo networks for chilliTPU.

Usage:
  python3 sw/py/quantize.py --model mnist-fc --checkpoint model.pt \\
      --calibration-data mnist_calibration.npz --output build/quantized

The NPZ must contain ``x``: float32 input samples shaped [samples, 1, 28, 28]
for MNIST/LeNet, or [samples, 3, 32, 32] for CIFAR. A checkpoint is either a
state_dict or a mapping containing ``state_dict``. Networks defined below are
starter architectures; checkpoint keys must match their modules.

Design decisions documented here (keep aligned with spec.py and RTL):
* Weights use per-layer symmetric max-absolute INT8 quantization. Activations
  use per-layer symmetric max-absolute calibration from supplied samples.
* Bias is converted to INT32 accumulator units: bias/(input_step*weight_step).
* Requantization encodes real_multiplier=input_step*weight_step/output_step
  as nearest integer ``scale / 2**shift``; ties use NumPy round-to-even when
  choosing the encoder value. RTL's output rounding remains its frozen half-up
  rule. The achieved multiplier error is recorded in model.json.
* The supplied starter networks use ReLU between supported layers. Calibration
  hooks Linear/Conv outputs and uses the next supported layer's input step.
  Pooling/flatten/ReLU operations retain the stored step. This simple scheme is
  a starting point, not QAT or per-channel
  quantization; compare validation accuracy before treating a model as usable.
* Pooling is 2x2 MaxPool only (no AvgPool: it needs a division with its own
  rounding rule). It runs on the Arm side on INT8 layer outputs; golden.maxpool2d
  is the reference. Each model lists the layers followed by a pool in POOL_AFTER.
* Weights are exported as the hardware matrix W[K, N] (results/log.md D6):
  Linear [out,in] -> transpose; Conv [out,in,kh,kw] -> reshape(out, -1).T,
  so K is ordered (c, i, j) to match golden.im2col. The hex file is W row-major
  (line k*N + n). int8_forward() runs the exported network bit-exactly.
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np

try:
    from spec import INT8_MAX, INT8_MIN, SCALE_W, SHIFT_W
    import golden
except ImportError:
    from sw.py.spec import INT8_MAX, INT8_MIN, SCALE_W, SHIFT_W
    from sw.py import golden


@dataclass
class QuantizedLayer:
    name: str
    kind: str
    weight_int8: np.ndarray
    bias_int32: np.ndarray
    input_step: float
    weight_step: float
    output_step: float
    scale: int
    shift: int
    real_multiplier: float
    multiplier_error: float
    relu: bool
    kernel: tuple[int, int] | None = None   # conv only: (kh, kw)
    stride: int = 1
    padding: int = 0
    pool: int = 0                           # 0 = none, k = k x k max pool after this layer


def _torch():
    try:
        import torch
    except ImportError as exc:
        raise RuntimeError("PyTorch is required; install a compatible torch build") from exc
    return torch


def symmetric_int8_quantize(values: np.ndarray) -> tuple[np.ndarray, float]:
    """Return signed INT8 values and the real value represented by one LSB."""
    values = np.asarray(values, dtype=np.float64)
    if not np.all(np.isfinite(values)):
        raise ValueError("quantization input contains NaN or infinity")
    peak = float(np.max(np.abs(values))) if values.size else 0.0
    step = peak / INT8_MAX if peak else 1.0
    quantized = np.clip(np.rint(values / step), INT8_MIN, INT8_MAX).astype(np.int8)
    return quantized, step


def quantize_bias(bias: np.ndarray, input_step: float, weight_step: float) -> np.ndarray:
    """Convert real bias to accumulator units and reject INT32 overflow."""
    if input_step <= 0 or weight_step <= 0:
        raise ValueError("input and weight steps must be positive")
    values = np.rint(np.asarray(bias, dtype=np.float64) / (input_step * weight_step))
    limits = np.iinfo(np.int32)
    if np.any(values < limits.min) or np.any(values > limits.max):
        raise OverflowError("quantized bias does not fit INT32")
    return values.astype(np.int32)


def encode_requant_multiplier(real_multiplier: float) -> tuple[int, int, float]:
    """Choose nearest representable unsigned scale / power-of-two shift.

    Among all legal shifts, minimize absolute multiplier error; on an exact tie,
    prefer the larger shift. Returns (scale, shift, signed approximation error).
    """
    if not np.isfinite(real_multiplier) or real_multiplier < 0:
        raise ValueError("requantization multiplier must be finite and nonnegative")
    max_scale = (1 << SCALE_W) - 1
    max_shift = (1 << SHIFT_W) - 1
    best: tuple[float, int, int] | None = None
    for shift in range(max_shift + 1):
        raw = real_multiplier * (1 << shift)
        scale = int(np.clip(np.rint(raw), 0, max_scale))
        approximation = scale / float(1 << shift)
        candidate = (abs(approximation - real_multiplier), -shift, scale)
        if best is None or candidate < best:
            best = candidate
    assert best is not None
    error, neg_shift, scale = best
    shift = -neg_shift
    return scale, shift, (scale / float(1 << shift)) - real_multiplier


def weight_to_kn(weight: np.ndarray) -> np.ndarray:
    """PyTorch weight ([out,in] or [out,in,kh,kw]) -> hardware W[K, N]."""
    weight = np.asarray(weight)
    return np.ascontiguousarray(weight.reshape(weight.shape[0], -1).T)


def int8_forward(layers: list[QuantizedLayer], x: np.ndarray) -> np.ndarray:
    """Run the exported INT8 network with the golden model. x: INT8 [B, C, H, W].

    Returns the final layer's INT8 outputs [B, classes]. This is the bit-exact
    expected result for the board; argmax gives the predicted class.
    """
    x = np.asarray(x)
    for layer in layers:
        if layer.kind == "conv2d":
            kh, kw = layer.kernel
            x = golden.conv2d(x, layer.weight_int8, layer.bias_int32, layer.scale, layer.shift,
                              layer.relu, kh, kw, layer.stride, layer.padding)
        else:
            x = golden.layer(x.reshape(x.shape[0], -1), layer.weight_int8, layer.bias_int32,
                             layer.scale, layer.shift, layer.relu)
        if layer.pool:
            x = golden.maxpool2d(x, layer.pool)
    return x


def quantize_input(x: np.ndarray, input_step: float) -> np.ndarray:
    """Float input samples -> INT8 with the calibrated input step."""
    return np.clip(np.rint(np.asarray(x, dtype=np.float64) / input_step),
                   INT8_MIN, INT8_MAX).astype(np.int8)


def build_model(model_name: str):
    """Construct one of the documented starter networks."""
    torch = _torch()
    nn = torch.nn

    class MnistFC(nn.Module):
        def __init__(self):
            super().__init__()
            self.fc1 = nn.Linear(28 * 28, 128)
            self.relu1 = nn.ReLU()
            self.fc2 = nn.Linear(128, 10)

        def forward(self, x):
            x = x.flatten(1)
            return self.fc2(self.relu1(self.fc1(x)))

    class LeNet5(nn.Module):
        POOL_AFTER = ("conv1", "conv2")

        def __init__(self):
            super().__init__()
            self.conv1 = nn.Conv2d(1, 6, 5)
            self.pool1 = nn.MaxPool2d(2)
            self.conv2 = nn.Conv2d(6, 16, 5)
            self.pool2 = nn.MaxPool2d(2)
            self.fc1 = nn.Linear(16 * 4 * 4, 120)
            self.fc2 = nn.Linear(120, 84)
            self.fc3 = nn.Linear(84, 10)

        def forward(self, x):
            x = self.pool1(torch.relu(self.conv1(x)))
            x = self.pool2(torch.relu(self.conv2(x)))
            x = x.flatten(1)
            return self.fc3(torch.relu(self.fc2(torch.relu(self.fc1(x)))))

    class CifarCNN(nn.Module):
        POOL_AFTER = ("conv1", "conv2")

        def __init__(self):
            super().__init__()
            self.conv1 = nn.Conv2d(3, 16, 3, padding=1)
            self.conv2 = nn.Conv2d(16, 32, 3, padding=1)
            self.pool = nn.MaxPool2d(2)
            self.fc1 = nn.Linear(32 * 8 * 8, 128)
            self.fc2 = nn.Linear(128, 10)

        def forward(self, x):
            x = self.pool(torch.relu(self.conv1(x)))
            x = self.pool(torch.relu(self.conv2(x)))
            x = x.flatten(1)
            return self.fc2(torch.relu(self.fc1(x)))

    models = {"mnist-fc": MnistFC, "lenet5": LeNet5, "cifar-cnn": CifarCNN}
    return models[model_name]()


def load_model(model_name: str, checkpoint: Path):
    torch = _torch()
    model = build_model(model_name)
    try:
        state = torch.load(checkpoint, map_location="cpu", weights_only=True)
    except TypeError:  # PyTorch versions before weights_only
        state = torch.load(checkpoint, map_location="cpu")
    if isinstance(state, dict) and "state_dict" in state:
        state = state["state_dict"]
    if not isinstance(state, dict):
        raise ValueError("checkpoint must contain a PyTorch state_dict")
    # Accept DataParallel checkpoints without silently altering other names.
    if state and all(key.startswith("module.") for key in state):
        state = {key.removeprefix("module."): value for key, value in state.items()}
    model.load_state_dict(state, strict=True)
    model.eval()
    return model


def calibration_input(path: Path):
    """Load calibration samples from an NPZ containing a float array named x."""
    torch = _torch()
    with np.load(path) as data:
        if "x" not in data:
            raise ValueError(f"{path} must contain an array named 'x'")
        x = np.asarray(data["x"], dtype=np.float32)
    if x.ndim < 2 or x.shape[0] == 0 or not np.all(np.isfinite(x)):
        raise ValueError("calibration x must be a nonempty finite batch")
    return torch.from_numpy(x)


def calibrate_model(model, samples) -> dict[str, float]:
    """Collect max-absolute activation step at each supported affine layer."""
    torch = _torch()
    observed: dict[str, float] = {}
    handles = []

    def hook(name):
        def record(_module, _inputs, output):
            value = output.detach()
            if not torch.isfinite(value).all():
                raise ValueError(f"non-finite activation at {name}")
            observed[name] = max(observed.get(name, 0.0), float(value.abs().max()))
        return record

    for name, module in model.named_modules():
        if isinstance(module, (torch.nn.Linear, torch.nn.Conv2d)):
            handles.append(module.register_forward_hook(hook(name)))
    if not handles:
        raise ValueError("model has no supported Linear or Conv2d layers")
    try:
        with torch.inference_mode():
            batch_size = 128
            for start in range(0, len(samples), batch_size):
                model(samples[start:start + batch_size])
    finally:
        for handle in handles:
            handle.remove()
    return {name: (peak / INT8_MAX if peak else 1.0) for name, peak in observed.items()}


def quantize_model(model, activation_steps: dict[str, float]) -> list[QuantizedLayer]:
    """Convert supported affine layers using observed output ranges."""
    torch = _torch()
    affine = [(name, module) for name, module in model.named_modules()
              if isinstance(module, (torch.nn.Linear, torch.nn.Conv2d))]
    layers = []
    pool_after = set(getattr(model, "POOL_AFTER", ()))
    input_step = activation_steps.get("__input__")
    if input_step is None:
        raise ValueError("input activation step is missing")
    for index, (name, module) in enumerate(affine):
        if name not in activation_steps:
            raise ValueError(f"no calibration range collected for {name}")
        output_step = activation_steps[name]
        weight_i8, weight_step = symmetric_int8_quantize(module.weight.detach().cpu().numpy())
        bias = (module.bias.detach().cpu().numpy() if module.bias is not None
                else np.zeros(module.weight.shape[0], dtype=np.float32))
        bias_i32 = quantize_bias(bias, input_step, weight_step)
        # In these starter architectures every non-final affine layer is
        # followed by ReLU. The final classifier emits signed class scores.
        relu = index < len(affine) - 1
        real_multiplier = input_step * weight_step / output_step
        scale, shift, error = encode_requant_multiplier(real_multiplier)
        is_conv = isinstance(module, torch.nn.Conv2d)
        if is_conv and (module.groups != 1 or module.dilation != (1, 1)
                        or module.stride[0] != module.stride[1]
                        or module.padding[0] != module.padding[1]):
            raise ValueError(f"{name}: only square stride/padding, groups=1, dilation=1 supported")
        layers.append(QuantizedLayer(
            name=name,
            kind="conv2d" if is_conv else "linear",
            weight_int8=weight_to_kn(weight_i8),
            bias_int32=bias_i32,
            input_step=input_step,
            weight_step=weight_step,
            output_step=output_step,
            scale=scale,
            shift=shift,
            real_multiplier=real_multiplier,
            multiplier_error=error,
            relu=relu,
            kernel=tuple(module.kernel_size) if is_conv else None,
            stride=module.stride[0] if is_conv else 1,
            padding=module.padding[0] if is_conv else 0,
            pool=2 if name in pool_after else 0,
        ))
        input_step = output_step
    return layers


def export_layers(layers: list[QuantizedLayer], output_dir: Path,
                  model_name: str, input_step: float) -> None:
    """Write flattened, two's-complement hex arrays and machine-readable metadata."""
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest = {"model": model_name, "format_version": 2, "weight_layout": "KN",
                "input_step": input_step, "layers": []}
    for index, layer in enumerate(layers):
        stem = f"layer_{index:02d}"
        weight_path = output_dir / f"{stem}_weight.hex"
        bias_path = output_dir / f"{stem}_bias.hex"
        _write_hex(weight_path, layer.weight_int8, 8)
        _write_hex(bias_path, layer.bias_int32, 32)
        entry = asdict(layer)
        entry.pop("weight_int8")
        entry.pop("bias_int32")
        entry["weight_shape"] = list(layer.weight_int8.shape)
        entry["bias_shape"] = list(layer.bias_int32.shape)
        entry["weight_file"] = weight_path.name
        entry["bias_file"] = bias_path.name
        manifest["layers"].append(entry)
    (output_dir / "model.json").write_text(json.dumps(manifest, indent=2) + "\n")


def _write_hex(path: Path, values: np.ndarray, bits: int) -> None:
    mask = (1 << bits) - 1
    width = bits // 4
    with path.open("w", encoding="ascii") as stream:
        for value in np.asarray(values).reshape(-1):
            stream.write(f"{int(value) & mask:0{width}X}\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", choices=("mnist-fc", "lenet5", "cifar-cnn"), required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--calibration-data", type=Path, required=True,
                        help="NPZ file containing representative float samples in array 'x'")
    parser.add_argument("--output", type=Path, default=Path("build/quantized"))
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if not args.checkpoint.is_file():
            raise ValueError(f"checkpoint not found: {args.checkpoint}")
        if not args.calibration_data.is_file():
            raise ValueError(f"calibration data not found: {args.calibration_data}")
        torch = _torch()
        model = load_model(args.model, args.checkpoint)
        samples = calibration_input(args.calibration_data)
        # Include input tensor range along with each affine layer's output range.
        input_peak = float(samples.abs().max())
        steps = calibrate_model(model, samples)
        steps["__input__"] = input_peak / INT8_MAX if input_peak else 1.0
        layers = quantize_model(model, steps)
        export_layers(layers, args.output, args.model, steps["__input__"])
        print(f"Exported {len(layers)} layers to {args.output}")
        print("Quantization is parameter export only; validate accuracy and RTL layout before board use.")
    except (RuntimeError, ValueError, OverflowError, OSError) as exc:
        print(f"quantize.py: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
