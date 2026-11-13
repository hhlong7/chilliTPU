# Decisions and results log

Newest at the bottom. One entry per decision or result: date, what, why. Gate sign-offs go here too.

## 2026-11-12
- Project plan written (PROJECT_PLAN.md). No fixed owners; tasks picked at meetings. Systolic array + dynamic partitioning RTL done together as a group.
- Verilator is the primary simulator on the Mac; xsim on the Vivado PC is the cross-check and the coverage simulator.
- Every RTL module gets a full UVM env. Accellera UVM 2020.3.1 vendored in `third_party/uvm-core/` (commit 78c0654).
- Result: UVM 2020.3.1 runs in Verilator 5.048 (smoke test: 50 transactions, 0 errors). Covergroups are not supported in Verilator.
- Milestone 0 skeleton created: folder layout, Makefile (`sim`, `lint`, `sim-xsim`, stubs for the rest), stub files for every RTL module, UVM env skeleton per module, shared kit stubs, Python/firmware/FPGA stubs.
- `make sim` → `PASS smoke.smoke_test seed=1`, `PASS smoke.smoke_test seed=42`, `== SIM PASS`. `make lint` → all 11 RTL stubs lint clean.
- Open for M0 gate: run `make sim-xsim TB=smoke` on the Vivado PC.


Long: 
- Spec frozen (D1): requantize rounds half up (add 1 << (shift-1), arithmetic shift right; shift = 0 skips rounding). scale = unsigned 16-bit, shift = 5-bit (0..31), bias = INT32, acc + bias computed at 33 bits.
- D2: out_stage has OUT_LANES = 2 requantize lanes (2 DSP48E1 each), so the 14x14 sweep stays under 220 DSPs.
- D3: tiling order is N tiles outer, K tiles inner, all M rows streamed per tile; accum_mem holds M x width INT32.
- D4/D5: adopted the proposals in docs/meeting-2026-11-12.md (1-cycle PE hops, global array enable, weight shift chain down columns, per-column Mul_En; meta.txt key=value vectors).- D6 (pooling + layout): pooling is 2x2 MaxPool only (LeNet-5 switched from AvgPool), run on the Arm side on INT8 layer outputs; no pooling RTL. Exact because max commutes with requantize (scale >= 0). Activations are INT8 NCHW; weights export as W[K, N] (Linear: weight.T, Conv: weight.reshape(N, -1).T, K ordered (c, i, j)); im2col rows ordered (b, oy, ox). Reference: golden.im2col / conv2d / maxpool2d, quantize.int8_forward. model.json format_version 2.
