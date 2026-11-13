"""Bit-exact golden model: matmul, bias, ReLU, requantize (rounding + saturation).

This is the source of truth for every testbench. Status: SKELETON.
Use NumPy integer types only (no floats) so results are exact.
"""
import numpy as np

from spec import ACC_W, BIAS_W, INT8_MIN, INT8_MAX, ROUNDING, SCALE_W, SHIFT_W

ACC_MIN = -(1 << (ACC_W - 1))
ACC_MAX = (1 << (ACC_W - 1)) - 1
BIAS_MIN = -(1 << (BIAS_W - 1))
BIAS_MAX = (1 << (BIAS_W - 1)) - 1
SCALE_MAX = (1 << SCALE_W) - 1   # scale is unsigned
SHIFT_MAX = (1 << SHIFT_W) - 1

# This file implements exactly one rounding rule. If the spec changes, fail
# loudly here instead of silently producing the wrong expected outputs.
assert ROUNDING == "half_up", f"golden.py only implements half_up, spec says {ROUNDING!r}"

def check_range(name: str, a: np.ndarray, lo: int, hi: int) -> None:
    """ Rejects non int arrays and values outside of [lo, hi]"""

    if not np.issubdtype(a.dtype, np.integer):
        raise TypeError(f"{name} must be an integer array, instead got {a.dtype}")
    if a.size and (a.min() < lo or a.max() > hi):
        raise ValueError(f"{name} has values outside [{lo}, {hi}]: min = {a.min()}, max = {a.max()}")


def matmul_int8(x: np.ndarray, w: np.ndarray) -> np.ndarray:
    """Y[M,N] = X[M,K] @ W[K,N] with INT8 inputs and INT32 accumulation.

    inputs can be any integer dtype as long as every value fits in INT8.
    Products and sums are computed in int64 (int8 @ int8 in NumPy would wrap),
    then checked against the INT32 accumulator range. Raises instead of
    wrapping: real layers are nowhere near the limit (|sum| <= K * 2**14), so an
    overflow here means a bad test case, not behavior we want to model!
    """

    x = np.asarray(x)
    w = np.asarray(w)

    if x.ndim != 2 or w.ndim != 2:
        raise ValueError(f"x and w must be 2-D, instead got x.ndim={x.ndim}, w.ndim={w.ndim}")
    if x.shape[1] != w.shape[0]:
        raise ValueError(f"inner dims differ: x is {x.shape}, w is {w.shape}")
    
    check_range("x", x, INT8_MIN, INT8_MAX)
    check_range("w", w, INT8_MIN, INT8_MAX)

    acc = x.astype(np.int64) @ w.astype(np.int64)
    check_range("acc", acc, ACC_MIN, ACC_MAX)

    return acc.astype(np.int32)



def requantize(acc: np.ndarray, bias: np.ndarray, scale: int, shift: int, relu: bool) -> np.ndarray:
    """clamp(round((relu(acc + bias) * scale) >> shift), -128, 127) -> INT8.

    The rounding rule must match rtl/out_stage.sv exactly (spec.ROUNDING).
    Frozen rule (spec.py, results/log.md D1):
        s   = acc + bias                  33-bit, no wraparound
        r   = max(s, 0) if relu else s
        p   = r * scale                   scale is unsigned 16-bit
        q   = (p + (1 << (shift-1))) >> shift   if shift > 0, else p
        out = clamp(q, -128, 127)

    acc:  [M, N] INT32 accumulator values.
    bias: [N] INT32, one per output column, added to every row.
    Round half up means ties go toward +inf: 2.5 -> 3, but -2.5 -> -2.
    All math is in int64 (worst case |p| < 2**49), so nothing wraps.
    """
    acc = np.asarray(acc)
    bias = np.asarray(bias)

    # Checks

    if acc.ndim != 2:
        raise ValueError(f"acc must be 2-D [M, N], instead got acc.ndim={acc.ndim}")
    if bias.shape != (acc.shape[1], ):
        raise ValueError(f"bias must have shape ({acc.shape[1]},) to match acc {acc.shape}, instead got {bias.shape}")
    
    check_range("acc", acc, ACC_MIN, ACC_MAX)
    check_range("bias", bias, BIAS_MIN, BIAS_MAX)

    if not 0 <= scale <= SCALE_MAX:
        raise ValueError(f"scale must be in [0, {SCALE_MAX}], instead got {scale}")
    if not 0 <= shift <= SHIFT_MAX:
        raise ValueError(f"shift must be in [0, {SHIFT_MAX}], instead got {shift}")
    scale, shift = int(scale), int(shift)


    # Mat mul logic

    s = acc.astype(np.int64) + bias.astype(np.int64)    # bias broadcasts across rows
    r = np.maximum(s, 0) if relu else s
    p = r * scale
    q = (p + (1 << (shift - 1))) >> shift if shift > 0 else p   # >> on signed ints is arithmetic
    
    return np.clip(q, INT8_MIN, INT8_MAX).astype(np.int8)


def layer(x: np.ndarray, w: np.ndarray, bias: np.ndarray, scale: int, shift: int, relu: bool) -> np.ndarray:
    """One fully connected / im2col-lowered layer: matmul + requantize."""
    
    return requantize(matmul_int8(x, w), bias, scale, shift, relu)
