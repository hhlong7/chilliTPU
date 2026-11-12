"""Shared constants: Python mirror of rtl/pkg/dnn_pkg.sv.

Keep this file and dnn_pkg.sv identical. Change both in the same `spec-change` PR.
Values marked TBD are proposals until the group freezes the spec in Week 1.
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

# Requantize: out = clamp(round((relu(acc + bias) * scale) >> shift), -128, 127)
BIAS_W = ACC_W        # TBD
SCALE_W = 16          # TBD: proposed unsigned 16-bit
SHIFT_W = 5           # TBD: proposed 5-bit
ROUNDING = "TBD"      # proposed: "half_up" = add 1 << (shift-1), then arithmetic shift right

INT8_MIN, INT8_MAX = -128, 127
