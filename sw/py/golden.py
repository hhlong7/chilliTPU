"""Bit-exact golden model: matmul, bias, ReLU, requantize (rounding + saturation).

This is the source of truth for every testbench. Status: SKELETON.
Use NumPy integer types only (no floats) so results are exact.
"""
import numpy as np

from spec import INT8_MIN, INT8_MAX  # noqa: F401  (used once implemented)


def matmul_int8(x: np.ndarray, w: np.ndarray) -> np.ndarray:
    """Y[M,N] = X[M,K] @ W[K,N] with INT8 inputs and INT32 accumulation."""
    raise NotImplementedError


def requantize(acc: np.ndarray, bias: np.ndarray, scale: int, shift: int, relu: bool) -> np.ndarray:
    """clamp(round((relu(acc + bias) * scale) >> shift), -128, 127) -> INT8.

    The rounding rule must match rtl/out_stage.sv exactly (spec.ROUNDING).
    """
    raise NotImplementedError


def layer(x: np.ndarray, w: np.ndarray, bias: np.ndarray, scale: int, shift: int, relu: bool) -> np.ndarray:
    """One fully connected / im2col-lowered layer: matmul + requantize."""
    return requantize(matmul_int8(x, w), bias, scale, shift, relu)
