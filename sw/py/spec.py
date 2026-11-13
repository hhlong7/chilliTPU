"""Shared constants: Python mirror of rtl/pkg/dnn_pkg.sv.

Keep this file and dnn_pkg.sv identical. Change both in the same `spec-change` PR.
Requantize values frozen 2026-11-12 (see results/log.md).
"""

# Array geometry
ROWS = 12
COLS = 12
MAX_TENANTS = 4

# Data widths
DATA_W = 8            # INT8 signed
PROD_W = 2 * DATA_W   # 16-bit signed product
PSUM_W = 32           # in-array partial sum
ACC_W = 32            # INT32 cross-tile accumulation

# Requantize (frozen 2026-11-12, D1/D2). Must match rtl/pkg/dnn_pkg.sv.
#   s   = acc + bias                     (33-bit, no wraparound)
#   r   = max(s, 0) if relu else s
#   p   = r * scale                      (scale is UNSIGNED)
#   q   = (p + (1 << (shift-1))) >> shift if shift > 0 else p   (round half up, toward +inf)
#   out = clamp(q, -128, 127)
BIAS_W = ACC_W        # INT32 bias, added once after the last K tile
SCALE_W = 16          # unsigned
SHIFT_W = 5           # shift 0..31
OUT_LANES = 2         # requantize lanes in out_stage (2 DSP48E1 each)
ROUNDING = "half_up"

INT8_MIN, INT8_MAX = -128, 127
