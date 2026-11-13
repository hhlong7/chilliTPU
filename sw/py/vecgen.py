"""Write .hex test vectors and expected outputs for the testbenches and the board.

Usage (from the repo root):
    python3 sw/py/vecgen.py                    # all unit cases -> vectors/
    python3 sw/py/vecgen.py --only layer       # one group
    python3 sw/py/vecgen.py --list             # print the case names
    python3 sw/py/vecgen.py --model-dir build/quantized/lenet5 --images build/models/lenet5_test.npz
                                               # + end-to-end network cases (from train.py)

Layout (results/log.md D5):  vectors/<group>/<case>/
    x.hex             X[M, K]  INT8   (matmul input, convs already im2col-lowered)
    w.hex             W[K, N]  INT8
    bias.hex          [N]      INT32
    acc_expected.hex  [M, N]   INT32  X @ W, before bias (systolic_array / accum_mem)
    y_expected.hex    [M, N]   INT8   requantize(acc, bias, scale, shift, relu)
    meta.txt          key=value lines for SystemVerilog ($fscanf)
    meta.json         same keys for Python
Groups that test one block write only the files that block needs (out_stage has
acc.hex instead of x/w).

Hex format (PROJECT_PLAN.md section 5): one value per line, two's complement,
zero-padded to the type width (2 digits INT8, 8 digits INT32), row-major.
Every expected value comes from golden.py. Random cases use fixed seeds that are
printed and stored in meta.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

import golden
from spec import COLS, INT8_MAX, INT8_MIN, ROWS

WIDTHS = {"x": 8, "w": 8, "bias": 32, "acc": 32, "acc_expected": 32, "y_expected": 8, "label": 32}


# --------------------------------------------------------------------------- hex I/O
def write_hex(path: Path, values, bits: int) -> None:
    """Two's complement, zero padded, one value per line, row-major."""
    mask, digits = (1 << bits) - 1, bits // 4
    flat = np.asarray(values).reshape(-1)
    path.write_text("".join(f"{int(v) & mask:0{digits}X}\n" for v in flat), encoding="ascii")


def read_hex(path: Path, bits: int, shape=None) -> np.ndarray:
    """Inverse of write_hex: signed values, optionally reshaped."""
    raw = [int(line, 16) for line in path.read_text(encoding="ascii").split()]
    vals = np.array([v - (1 << bits) if v >> (bits - 1) else v for v in raw], dtype=np.int64)
    return vals.reshape(shape) if shape is not None else vals


# --------------------------------------------------------------------------- cases
@dataclass
class Case:
    group: str
    name: str
    arrays: dict[str, np.ndarray]
    meta: dict = field(default_factory=dict)

    def write(self, root: Path) -> Path:
        d = root / self.group / self.name
        if d.exists():
            shutil.rmtree(d)
        d.mkdir(parents=True)
        for key, arr in self.arrays.items():
            write_hex(d / f"{key}.hex", arr, WIDTHS[key])
        meta = {"group": self.group, "case": self.name, **self.meta}
        (d / "meta.json").write_text(json.dumps(meta, indent=2) + "\n")
        (d / "meta.txt").write_text("".join(f"{k}={int(v) if isinstance(v, bool) else v}\n"
                                            for k, v in meta.items() if not isinstance(v, (list, dict))))
        return d


def load_case(case_dir: Path) -> dict:
    """Read a case back: meta plus every array, shaped. Used by tests and analyze tools."""
    case_dir = Path(case_dir)
    meta = json.loads((case_dir / "meta.json").read_text())
    M, K, N = meta.get("M"), meta.get("K"), meta.get("N")
    shapes = {"x": (M, K), "w": (K, N), "bias": (N,), "acc": (M, N), "acc_expected": (M, N),
              "y_expected": (M, N), "label": None}
    out = {"meta": meta}
    for key, bits in WIDTHS.items():
        p = case_dir / f"{key}.hex"
        if p.exists():
            out[key] = read_hex(p, bits, shapes[key])
    return out


def layer_case(group: str, name: str, x, w, bias, scale: int, shift: int, relu: bool, seed=None, **extra) -> Case:
    """Full layer: X, W, bias -> acc and y via golden."""
    x, w, bias = np.asarray(x), np.asarray(w), np.asarray(bias)
    acc = golden.matmul_int8(x, w)
    y = golden.requantize(acc, bias, scale, shift, relu)
    M, K = x.shape
    N = w.shape[1]
    meta = {"M": M, "K": K, "N": N, "scale": int(scale), "shift": int(shift), "relu": bool(relu),
            "seed": -1 if seed is None else seed,
            "k_tiles": -(-K // ROWS), "n_tiles": -(-N // COLS), **extra}
    return Case(group, name, {"x": x, "w": w, "bias": bias, "acc_expected": acc, "y_expected": y}, meta)


def requant_case(name: str, acc, bias, scale: int, shift: int, relu: bool, seed=None) -> Case:
    """out_stage only: acc, bias -> y."""
    acc, bias = np.asarray(acc, dtype=np.int64), np.asarray(bias, dtype=np.int64)
    y = golden.requantize(acc, bias, scale, shift, relu)
    M, N = acc.shape
    meta = {"M": M, "N": N, "scale": int(scale), "shift": int(shift), "relu": bool(relu),
            "seed": -1 if seed is None else seed}
    return Case("out_stage", name, {"acc": acc, "bias": bias, "y_expected": y}, meta)


def _rng_i8(rng, shape):
    return rng.integers(INT8_MIN, INT8_MAX + 1, shape, dtype=np.int64)


def _scale_for(K: int, rng) -> tuple[int, int]:
    """A scale/shift that maps typical |acc| ~ sqrt(K) * 128 * 74 into INT8 without saturating everything."""
    shift = int(rng.integers(14, 20))
    typical = max(1.0, (K ** 0.5) * 128 * 74)
    scale = int(np.clip(round(100 * (1 << shift) / typical), 1, (1 << 16) - 1))
    return scale, shift


def layer_cases(seed: int) -> list[Case]:
    """Full layers: edge cases first, then shapes around the array size, then random."""
    cases = []
    z = lambda *s: np.zeros(s, dtype=np.int64)
    # extremes: all -128 (largest positive acc), -128 x 127 (most negative), saturation both ways
    cases.append(layer_case("layer", "extreme_min_min", np.full((4, ROWS), -128), np.full((ROWS, COLS), -128),
                            z(COLS), 1, 20, False))
    cases.append(layer_case("layer", "extreme_min_max", np.full((4, ROWS), -128), np.full((ROWS, COLS), 127),
                            z(COLS), 1, 20, False))
    cases.append(layer_case("layer", "saturate", np.full((3, 5), 127), np.full((5, 4), 127),
                            np.array([0, -10 ** 6, 10 ** 6, 0]), 1, 0, False))
    cases.append(layer_case("layer", "zeros", z(5, 7), z(7, 3), z(3), 1, 0, True))
    cases.append(layer_case("layer", "one_by_one", np.array([[-3]]), np.array([[5]]), np.array([1]), 1, 1, False))
    # requantize corners through the full path
    rng = np.random.default_rng(seed)
    x, w = _rng_i8(rng, (6, ROWS)), _rng_i8(rng, (ROWS, COLS))
    b = rng.integers(-50_000, 50_000, COLS)
    cases.append(layer_case("layer", "shift0_relu", x, w, b, 1, 0, True, seed))
    cases.append(layer_case("layer", "shift31_scale_max", x, w, b, (1 << 16) - 1, 31, False, seed))
    cases.append(layer_case("layer", "scale0", x, w, b, 0, 5, False, seed))
    # shapes: exactly one tile, not multiples, K > ROWS, N > COLS, both, tall M
    shapes = {
        "one_tile": (8, ROWS, COLS),
        "k_lt_rows_n_lt_cols": (5, 7, 9),
        "k_not_multiple": (7, 30, 17),
        "k_gt_rows_n_gt_cols": (5, 100, 25),
        "n_multi_tile": (3, ROWS, 3 * COLS + 1),
        "tall_m": (200, 25, 6),            # LeNet conv1 style: big M, small K/N
        "fc_like": (1, 256, 120),           # LeNet fc1 style: M = 1
    }
    for i, (name, (M, K, N)) in enumerate(shapes.items()):
        s = seed + 100 + i
        r = np.random.default_rng(s)
        sc, sh = _scale_for(K, r)
        cases.append(layer_case("layer", name, _rng_i8(r, (M, K)), _rng_i8(r, (K, N)),
                                r.integers(-20_000, 20_000, N), sc, sh, bool(i % 2), s))
    for i in range(8):
        s = seed + 200 + i
        r = np.random.default_rng(s)
        M, K, N = int(r.integers(1, 40)), int(r.integers(1, 80)), int(r.integers(1, 40))
        sc, sh = _scale_for(K, r)
        cases.append(layer_case("layer", f"random_{i:02d}", _rng_i8(r, (M, K)), _rng_i8(r, (K, N)),
                                r.integers(-20_000, 20_000, N), sc, sh, bool(r.integers(2)), s))
    return cases


def array_cases(seed: int) -> list[Case]:
    """systolic_array: one tile (K <= ROWS, N <= COLS), checked on acc_expected only."""
    cases = []
    for i, (M, K, N) in enumerate([(1, ROWS, COLS), (ROWS, ROWS, COLS), (20, ROWS, COLS), (6, 5, 7),
                                   (10, ROWS, 1), (10, 1, COLS)]):
        s = seed + 300 + i
        r = np.random.default_rng(s)
        c = layer_case("systolic_array", f"tile_{M}x{K}x{N}", _rng_i8(r, (M, K)), _rng_i8(r, (K, N)),
                       np.zeros(N, dtype=np.int64), 1, 0, False, s)
        cases.append(c)
    cases.append(layer_case("systolic_array", "extremes", np.full((ROWS, ROWS), -128),
                            np.where(np.arange(COLS) % 2, 127, -128)[None, :].repeat(ROWS, 0),
                            np.zeros(COLS, dtype=np.int64), 1, 0, False))
    return cases


def out_stage_cases(seed: int) -> list[Case]:
    """requantize alone: rounding ties, saturation, 33-bit sum, ReLU after bias."""
    i32max, i32min = 2 ** 31 - 1, -2 ** 31
    cases = [
        requant_case("ties", [[5, -5, 3, -3, 1, -1]], [0] * 6, 1, 1, False),
        requant_case("non_ties", [[5, 7, -5, -7]], [0] * 4, 1, 2, False),
        requant_case("saturate", [[-1000, -129, -128, 127, 128, 1000]], [0] * 6, 1, 0, False),
        requant_case("relu_after_bias", [[-10, -10, 0, 5]], [15, 5, 0, -6], 1, 0, True),
        requant_case("sum_33bit", [[i32max, i32min]], [i32max, i32min], 1, 31, False),
        requant_case("worst_product", [[i32max, i32min]], [i32max, i32min], 65535, 31, False),
        requant_case("scale0", [[99999, -99999]], [7, 7], 0, 5, False),
    ]
    for i in range(6):
        s = seed + 400 + i
        r = np.random.default_rng(s)
        M, N = int(r.integers(1, 20)), int(r.integers(1, 2 * COLS))
        lim = 2 ** 31 if i % 2 else 2 ** 18
        cases.append(requant_case(f"random_{i:02d}", r.integers(-lim, lim, (M, N)), r.integers(-lim, lim, N),
                                  int(r.integers(0, 2 ** 16)), int(r.integers(0, 32)), bool(r.integers(2)), s))
    return cases


def network_cases(model_dir: Path, images: Path, n_images: int = 4) -> list[Case]:
    """End to end: every layer of an exported model on a few real images, plus the final logits.

    model_dir: quantize.py output (model.json + layer_XX_*.hex, W[K,N] layout).
    images:    NPZ from train.py with x (float [B, C, H, W]) and y (labels).
    Each layer's x.hex is the INT8 input after the previous layer and any pooling,
    so a testbench can check one layer at a time or the firmware the whole chain.
    """
    manifest = json.loads((model_dir / "model.json").read_text())
    if manifest.get("weight_layout") != "KN":
        raise ValueError(f"{model_dir}: need format_version 2 (W[K,N]) export from quantize.py")
    with np.load(images) as data:
        xf, labels = data["x"][:n_images], data["y"][:n_images]
    x = np.clip(np.rint(xf / manifest["input_step"]), INT8_MIN, INT8_MAX).astype(np.int64)
    group, cases = f"net_{manifest['model']}", []
    for i, L in enumerate(manifest["layers"]):
        w = read_hex(model_dir / L["weight_file"], 8, tuple(L["weight_shape"]))
        b = read_hex(model_dir / L["bias_file"], 32)
        if L["kind"] == "conv2d":
            kh, kw = L["kernel"]
            B, _, H, W = x.shape
            Ho = (H + 2 * L["padding"] - kh) // L["stride"] + 1
            Wo = (W + 2 * L["padding"] - kw) // L["stride"] + 1
            X = golden.im2col(x, kh, kw, L["stride"], L["padding"])
            geom = {"kh": kh, "kw": kw, "stride": L["stride"], "padding": L["padding"],
                    "in_c": x.shape[1], "in_h": H, "in_w": W, "out_h": Ho, "out_w": Wo}
        else:
            X, geom = x.reshape(x.shape[0], -1), {}
        c = layer_case(group, f"{i:02d}_{L['name']}", X, w, b, L["scale"], L["shift"], L["relu"],
                       layer=L["name"], kind=L["kind"], batch=x.shape[0], pool=L.get("pool", 0), **geom)
        cases.append(c)
        y = c.arrays["y_expected"]
        if L["kind"] == "conv2d":
            y = y.reshape(x.shape[0], geom["out_h"], geom["out_w"], -1).transpose(0, 3, 1, 2)
        if L.get("pool"):
            y = golden.maxpool2d(y, L["pool"])
        x = y
    logits = x.reshape(x.shape[0], -1)
    cases.append(Case(group, "result", {"y_expected": logits, "label": labels},
                      {"M": logits.shape[0], "N": logits.shape[1], "batch": logits.shape[0],
                       "predicted": [int(v) for v in logits.argmax(1)], "labels": [int(v) for v in labels]}))
    return cases


GROUPS = {"layer": layer_cases, "systolic_array": array_cases, "out_stage": out_stage_cases}


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Generate .hex test vectors (see module docstring).")
    p.add_argument("--out", type=Path, default=Path("vectors"))
    p.add_argument("--seed", type=int, default=20261112, help="base seed; each random case adds an offset")
    p.add_argument("--only", choices=sorted(GROUPS), action="append", help="limit to these groups")
    p.add_argument("--list", action="store_true", help="print case names and exit")
    p.add_argument("--model-dir", type=Path, help="quantize.py export to build network cases from")
    p.add_argument("--images", type=Path, help="NPZ with x/y test images (from train.py)")
    p.add_argument("--n-images", type=int, default=4)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if bool(args.model_dir) != bool(args.images):
        print("vecgen.py: --model-dir and --images go together", file=sys.stderr)
        return 1
    cases = [c for g in (args.only or GROUPS) for c in GROUPS[g](args.seed)]
    if args.model_dir:
        cases += network_cases(args.model_dir, args.images, args.n_images)
    if args.list:
        for c in cases:
            print(f"{c.group}/{c.name}")
        return 0
    for c in cases:
        c.write(args.out)
    groups = sorted({c.group for c in cases})
    print(f"vecgen: wrote {len(cases)} cases to {args.out}/ ({', '.join(groups)}), base seed {args.seed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
