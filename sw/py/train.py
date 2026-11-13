"""Train a demo network, quantize it, and check INT8 accuracy against the float model.

Usage (from the repo root):
    python3 sw/py/train.py --model lenet5            # MNIST, ~1 min on Apple GPU
    python3 sw/py/train.py --model mnist-fc
    python3 sw/py/train.py --model cifar-cnn --epochs 10
    python3 sw/py/train.py --model lenet5 --fake-data --epochs 1   # no download, pipeline check only

What it does:
  1. trains quantize.build_model(<model>) on MNIST or CIFAR-10 (torchvision,
     downloaded to data/ on first use). Inputs are ToTensor() only, i.e. [0, 1],
     no normalization, so the input quantization step stays simple.
  2. saves  build/models/<model>.pt              checkpoint (state_dict)
            build/models/<model>_calib.npz       calibration samples (x) for quantize.py
            build/models/<model>_test.npz        test images (x, y) for vecgen.py --images
  3. quantizes with quantize.py (same steps as its CLI) and exports
            build/quantized/<model>/             model.json + W[K,N] hex files
  4. evaluates the float model and the bit-exact INT8 model (golden.py via
     quantize.int8_forward) on the test set and writes results/accuracy_<model>.md

The INT8 accuracy is what the board must reproduce; the float-vs-INT8 gap shows
whether the requantize format (D1: u16 scale, 5-bit shift) is wide enough.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np

import quantize as q

REPO = Path(__file__).resolve().parents[2]
DATASET = {"mnist-fc": "mnist", "lenet5": "mnist", "cifar-cnn": "cifar10"}
SHAPE = {"mnist": (1, 28, 28), "cifar10": (3, 32, 32)}


def load_data(name: str, fake: bool, data_dir: Path):
    """Return (train_x, train_y, test_x, test_y) as float32 [N, C, H, W] in [0, 1] and int64 labels."""
    if fake:   # random images, random labels: exercises the pipeline, accuracy is meaningless
        rng = np.random.default_rng(0)
        c, h, w = SHAPE[name]
        mk = lambda n: (rng.random((n, c, h, w), dtype=np.float32), rng.integers(0, 10, n))
        return (*mk(2048), *mk(512))
    import os
    try:   # python.org macOS builds ship without CA certs; certifi's bundle fixes the download
        import certifi
        os.environ.setdefault("SSL_CERT_FILE", certifi.where())
    except ImportError:
        pass
    import torchvision
    cls = {"mnist": torchvision.datasets.MNIST, "cifar10": torchvision.datasets.CIFAR10}[name]
    out = []
    for train in (True, False):
        ds = cls(str(data_dir), train=train, download=True)
        x = np.asarray(ds.data, dtype=np.float32) / 255.0
        x = x[:, None] if x.ndim == 3 else x.transpose(0, 3, 1, 2)   # MNIST [N,H,W], CIFAR [N,H,W,C]
        out += [np.ascontiguousarray(x), np.asarray(ds.targets, dtype=np.int64)]
    return tuple(out)


def pick_device(torch, requested: str):
    if requested != "auto":
        return torch.device(requested)
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


def train(model, x, y, epochs: int, lr: float, batch: int, device, seed: int, log=print):
    torch = q._torch()
    torch.manual_seed(seed)
    model.to(device).train()
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=max(1, epochs * (len(x) // batch)))
    xt, yt = torch.from_numpy(x), torch.from_numpy(y)
    g = torch.Generator().manual_seed(seed)
    for ep in range(epochs):
        perm = torch.randperm(len(x), generator=g)
        total, correct, loss_sum = 0, 0, 0.0
        for i in range(0, len(x), batch):
            idx = perm[i:i + batch]
            xb, yb = xt[idx].to(device), yt[idx].to(device)
            out = model(xb)
            loss = torch.nn.functional.cross_entropy(out, yb)
            opt.zero_grad()
            loss.backward()
            opt.step()
            sched.step()
            loss_sum += loss.item() * len(idx)
            correct += int((out.argmax(1) == yb).sum())
            total += len(idx)
        log(f"  epoch {ep + 1}/{epochs}: loss {loss_sum / total:.4f}, train acc {correct / total:.2%}")
    return model.cpu().eval()


def float_predict(model, x, batch: int = 1000) -> np.ndarray:
    torch = q._torch()
    preds = []
    with torch.inference_mode():
        for i in range(0, len(x), batch):
            preds.append(model(torch.from_numpy(x[i:i + batch])).argmax(1).numpy())
    return np.concatenate(preds)


def int8_predict(layers, input_step: float, x, batch: int = 250) -> np.ndarray:
    """Bit-exact INT8 inference through golden.py, in batches to bound im2col memory."""
    preds = []
    for i in range(0, len(x), batch):
        xi = q.quantize_input(x[i:i + batch], input_step)
        preds.append(q.int8_forward(layers, xi).argmax(1))
    return np.concatenate(preds)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Train, quantize, and check a demo network.")
    p.add_argument("--model", choices=sorted(DATASET), required=True)
    p.add_argument("--epochs", type=int, default=None, help="default: 3 for MNIST, 10 for CIFAR")
    p.add_argument("--lr", type=float, default=2e-3)
    p.add_argument("--batch", type=int, default=128)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--calib-samples", type=int, default=1000)
    p.add_argument("--test-samples", type=int, default=None, help="limit the INT8 evaluation (default: all)")
    p.add_argument("--device", default="auto", help="auto, cpu, mps, or cuda")
    p.add_argument("--data-dir", type=Path, default=REPO / "data")
    p.add_argument("--fake-data", action="store_true", help="random data, no download (pipeline check)")
    p.add_argument("--no-report", action="store_true", help="do not write results/accuracy_<model>.md")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    torch = q._torch()
    ds = DATASET[args.model]
    epochs = args.epochs if args.epochs is not None else (10 if ds == "cifar10" else 3)
    device = pick_device(torch, args.device)
    models_dir, qdir = REPO / "build" / "models", REPO / "build" / "quantized" / args.model
    models_dir.mkdir(parents=True, exist_ok=True)

    print(f"train.py: {args.model} on {ds}{' (FAKE DATA)' if args.fake_data else ''}, "
          f"{epochs} epochs, device {device}, seed {args.seed}")
    xtr, ytr, xte, yte = load_data(ds, args.fake_data, args.data_dir)
    if args.test_samples:
        xte, yte = xte[:args.test_samples], yte[:args.test_samples]

    t0 = time.time()
    torch.manual_seed(args.seed)
    model = train(q.build_model(args.model), xtr, ytr, epochs, args.lr, args.batch, device, args.seed)
    train_s = time.time() - t0

    rng = np.random.default_rng(args.seed)
    calib = xtr[rng.choice(len(xtr), min(args.calib_samples, len(xtr)), replace=False)]
    ckpt = models_dir / f"{args.model}.pt"
    torch.save(model.state_dict(), ckpt)
    np.savez_compressed(models_dir / f"{args.model}_calib.npz", x=calib)
    np.savez_compressed(models_dir / f"{args.model}_test.npz", x=xte[:64], y=yte[:64])

    # Same steps as quantize.py's CLI
    samples = torch.from_numpy(calib)
    steps = q.calibrate_model(model, samples)
    peak = float(samples.abs().max())
    steps["__input__"] = peak / q.INT8_MAX if peak else 1.0
    layers = q.quantize_model(model, steps)
    q.export_layers(layers, qdir, args.model, steps["__input__"])

    t1 = time.time()
    acc_f = float(np.mean(float_predict(model, xte) == yte))
    p8 = int8_predict(layers, steps["__input__"], xte)
    acc_8 = float(np.mean(p8 == yte))
    eval_s = time.time() - t1

    print(f"float accuracy {acc_f:.2%}   INT8 accuracy {acc_8:.2%}   (n={len(yte)})")
    print(f"saved {ckpt.relative_to(REPO)}, calibration + test NPZ, export in {qdir.relative_to(REPO)}/")
    print(f"next: python3 sw/py/vecgen.py --model-dir {qdir.relative_to(REPO)} "
          f"--images build/models/{args.model}_test.npz")

    if not args.no_report and not args.fake_data:
        rows = "\n".join(f"| {L.name} | {L.kind} | {L.weight_int8.shape[0]}x{L.weight_int8.shape[1]} | "
                         f"{L.scale} | {L.shift} | {L.multiplier_error:+.2e} | {'yes' if L.relu else 'no'} | "
                         f"{L.pool or '-'} |" for L in layers)
        report = REPO / "results" / f"accuracy_{args.model}.md"
        report.write_text(f"""# {args.model} accuracy (MEASURED in software)

Generated by `python3 sw/py/train.py --model {args.model}` (seed {args.seed}, {epochs} epochs, {ds}).
INT8 = bit-exact golden model (`quantize.int8_forward`), i.e. what the board must reproduce.

| | Accuracy | Test images |
|---|---|---|
| Float (PyTorch) | {acc_f:.2%} | {len(yte)} |
| INT8 (golden) | {acc_8:.2%} | {len(yte)} |
| Gap | {acc_f - acc_8:+.2%} | |

Per-layer quantization (W is K x N; pool = max pool size after the layer):

| Layer | Kind | W | scale | shift | multiplier error | ReLU | pool |
|---|---|---|---|---|---|---|---|
{rows}

Train time {train_s:.0f} s, INT8 eval time {eval_s:.0f} s, device {device}.
""")
        print(f"wrote {report.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
