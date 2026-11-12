# Project brief: Multi-tenant systolic array accelerator on Zybo Z7-20

Hand this file to Claude Code as the starting context. It says what we are building, why, how the repo is laid out, and what to do first. Nothing here has been built yet.

## 1. What we are building

A small TPU-style INT8 accelerator written in SystemVerilog and run on a Digilent Zybo Z7-20 (Zynq 7020). The Arm core (PS) loads neural network layers and data, starts runs, and reads results. The accelerator computes the layers in hardware.

The accelerator can run several networks at once by splitting its systolic array into vertical column partitions. This is the idea from the reference paper. Our contribution is replacing the paper's equal column split with a hardware partition controller that sizes each partition from the layer's needs, then reassigns or gates the freed columns.

This is the final project for CPE 5350 (Digital Systems Design, Cal Poly SLO). The rubric asks for: clear RTL structure, assertions, appropriate pipelining, testbenches with edge cases, a working FPGA demo, and an evaluation of power, performance, and utilization that keeps **measured** numbers separate from **tool estimates**. "Outstanding" work improves on the reference, uses more than one paper, solves a useful problem, and shows substantial effort and some novelty.

### Reference paper
Reshadi and Gregg, "Dynamic Resource Partitioning for Multi-Tenant Systolic Array Based DNN Accelerator", Euromicro PDP 2023, arXiv:2302.10806. A copy is in the repo owner's CPE 5300 folder as `dnn accelerator.pdf`.

What the paper does, as we understand it:
- Weight-stationary systolic array. Rows are the reduction dimension K, columns are output channels. Weights load into PEs, inputs stream left to right, partial sums flow down and drain at the bottom.
- Partitions are vertical column ranges only (a horizontal split would break partial sums).
- A Mul_En gate in each PE lets data pass through a partition without computing. The paper calls it a tri-state gate. FPGAs have no internal tri-states, so we use an enable or mux.
- Partitions are equal (width divided by number of tenants). The first layer gets the whole array. Partitions merge when freed.
- Layers are sorted by MAC count. Results come from SCALE-Sim plus Accelergy on a 128x128 array: about 35% (heavy nets) and 62% (light nets) energy savings, and 56% and 44% time savings.
- The paper has no RTL, omits tiling, and omits cycle-level feed timing.

### Our claim (one paragraph, keep it consistent everywhere)
The reference splits the systolic array into equal column partitions regardless of layer size, which leaves columns idle or forces extra passes. We implement the design in RTL and replace the equal split with a hardware partition controller that sizes each partition from the layer's output channels and MAC count, then reassigns or gates the freed columns. This lets the accelerator run multiple networks at once while keeping more of the array busy.

### Open hypothesis (verify before building on it)
We think tenants in the paper share each row's feed port, because inputs enter at the left edge and pass through other partitions with Mul_En off. If so, concurrency gains are capped. This is our reading of the paper, not something it states. The cycle-level model in Milestone 1 must confirm or rule it out. If confirmed, per-partition feed injection (a 2:1 mux per row at each partition boundary) becomes the headline improvement. If not, proportional widths and shadow weights carry the story.

Also: the paper's Opr formula appears to use H x W where P x Q may be intended. Do not depend on it.

## 2. Target platform

| Item | Value |
|---|---|
| Board | Digilent Zybo Z7-20 (Zynq 7020) |
| DSP48E1 slices | 220 |
| LUTs / FFs | 53,200 / 106,400 |
| Block RAM | 140 x 36 Kb (about 4.9 Mb) |
| Board clock | 125 MHz (we may use a PS FCLK instead) |
| Array size | 12x12 default, parameterized. 14x14 fits with DSP use of about 210/220. 16x16 needs some LUT-built PEs, so it is a stretch. |
| Clocking | Single clock domain |
| Interface | AXI-Lite slave on the PS side, plus BRAM buffers |

Notes:
- The fused output stage uses DSPs for requantization, so count them against the 220.
- FPGAs have no internal tri-states. Implement Mul_En with an AND, mux, or DSP clock enable.
- Idle-partition gating should use clock enables on registers and DSP inputs, not true clock gating.

## 3. Language and tool split

| Part | Language | Share of effort | Role |
|---|---|---|---|
| Accelerator | SystemVerilog | about 45-50% | The graded core |
| Testbenches and verification | SystemVerilog (SVA) | about 25-30% | Proof it is correct |
| Arm firmware | C (bare metal) | about 10-15% | Remote control and measurement |
| Glue | Python | about 10% | Quantization, golden model, vectors, cycle model, analysis |

Tooling constraints to respect:
- The user is on macOS. Vivado and Vitis are not native on macOS, so do not assume they are available locally. Check what exists before relying on it.
- For simulation, prefer something that runs locally (Verilator or Icarus) for fast iteration, and keep the testbenches portable so they also run in Vivado xsim. Check which SVA constructs the local simulator supports.
- Software without Vitis: a JTAG-to-AXI Master IP driven by Tcl, plus ILA/VIO, cycle counters, and LEDs, is an acceptable fallback for bring-up. Bare-metal C on the Arm core is preferred when Vitis is available.
- Python glue: NumPy for the golden model, PyTorch only for quantization.

## 4. Architecture

```
Arm core (PS)
  | AXI-Lite                       weights / inputs
  v                                      |
AXI-Lite registers --> Partition ctrl --> Tile ctrl
  (layer queue,         (widths, assign,   (addresses,
   counters)             merge, gating)     K-tiling)
                                              |
Weight buffer --> [ Systolic array, ROWS x COLS INT8, Mul_En PEs ] <-- Feed buffer + skew
                                    |
                      Deskew + accumulator (INT32)
                                    |
                        Output stage (bias, ReLU, requantize)
                                    |
                           Drain buffer --> Arm core
```

### Modules

| Module | Job |
|---|---|
| `pe` | Holds a weight, multiplies by the incoming input (DSP slice), adds the partial sum from above, passes the input right. Has the Mul_En gate. |
| `systolic_array` | `ROWS x COLS` grid of PEs, fully parameterized. |
| `skew_buf`, `deskew_buf` | Stagger inputs going in and realign column outputs coming out. |
| `bram_sdp` | Simple dual-port BRAM wrapper for weight, feed, and drain buffers (one slice per partition). |
| `tile_ctrl` | Cuts layers into array-sized tiles and generates addresses. |
| `accum_mem` | Adds partial sums across K tiles in INT32. |
| `out_stage` | Bias, ReLU, requantize with saturation to INT8. |
| `part_ctrl` | The key block. Sizes partitions, assigns layers, merges freed columns, drives gating. |
| `axil_regs` | AXI-Lite slave: layer queue, start/done, cycle counters. |
| `dnn_top` | Top level, connects to the Zynq PS. |

### Dataflow conventions (pin these down in `dnn_pkg.sv` and the Python model, then never change them silently)
- Computation is `Y[M,N] = X[M,K] * W[K,N]`. Convolutions are lowered to this with im2col in Python before they reach the hardware.
- Rows of the array are K, columns are N (output channels). A tile is at most `ROWS` deep in K and at most the partition width in N.
- Data types: INT8 signed for weights and activations. Products are 16 bits. In-array partial sums need 20 bits for 12 rows (12 x 2^14 < 2^18, so signed 20 is enough). Use a `PSUM_W` parameter (default 32 for simplicity, can be narrowed). Accumulation across tiles is INT32.
- PE behavior with Mul_En low: the PE contributes zero to its column's partial sum (the partial sum passes down unchanged) and the input still passes right. The invariant to assert is that a column's partial sum only accumulates products from the tenant that owns that column.
- Requantization: `out = clamp(round((relu(acc + bias) * scale) >> shift), -128, 127)`. The exact rounding rule is fixed in the shared spec and must match the Python golden model bit for bit.
- Weights load over their own path, not the partial-sum wires (this matters for the shadow-weight improvement). The baseline version may serialize load and compute, as the paper does.

### Partition controller (the project's core logic)
Inputs per waiting layer: output channels `N_i`, MAC count `MACS_i`, arrival time. Rule to implement and compare:
1. **Paper-faithful baseline:** width = `COLS / n_tenants` for every layer (first layer gets the whole array, merge on free).
2. **Ours:** width_i = min(`N_i`, proportional share by `MACS_i`), snapped to an allowed width set that fits the array (for 12 columns: 2, 3, 4, 6, and multiples). Total width never exceeds `COLS`. Leftover columns go to layers that still have passes remaining. When a layer finishes, its columns merge with free neighbors and are reassigned, or clock-enable gated if nothing is waiting.
3. Optional stretch: order waiting layers with the odd-even sorted queue from the hardware HEFT scheduler paper (Fusco et al., VLSI-SoC 2022).

## 5. Repo layout

```
project/
  spec/        regmap.yaml           single source of truth for registers and layer descriptor
  sw/py/       quantize.py, golden.py, vecgen.py, cyclemodel.py, analyze.py
  rtl/         pkg/dnn_pkg.sv, pe.sv, systolic_array.sv, skew_buf.sv, deskew_buf.sv,
               bram_sdp.sv, tile_ctrl.sv, accum_mem.sv, out_stage.sv,
               part_ctrl.sv, axil_regs.sv, dnn_top.sv
  tb/          unit testbenches, system testbench, SVA assertion modules
  fw/          Arm C driver and test app
  fpga/        Vivado project scripts, block design, constraints, XSA
  scripts/     Tcl and helper scripts
  results/     logs, utilization/power reports, plots
  Makefile     make vectors | sim | bitstream | fw | report
```

How the languages connect:
- Python writes `.hex` test vectors and expected outputs. Testbenches read them with `$readmemh` and compare bit for bit.
- `spec/regmap.yaml` generates `dnn_regs_pkg.sv`, `dnn_regs.h`, and `dnn_regs.py`, so RTL, C, and Python agree on registers.
- The same vectors go to the board. The Arm C app runs them and prints PASS or FAIL plus cycle counts over UART (115200).

## 6. Milestones and gates

Work in order. Do not start a phase until the previous gate passes. If time gets short, cut stretch items first and keep a verified single-tenant core on the board.

### Milestone 0: Repo and tooling check
- Create the layout above with a working Makefile skeleton.
- Detect which tools exist locally (Python, Verilator, Icarus, Vivado, xsim, Vitis, arm toolchain) and write the result to `results/tooling.md`.
- Gate: `make sim` runs a trivial passing testbench.

### Milestone 1: Python golden model and cycle-level model (do this first)
- `quantize.py`: INT8 quantization of small networks.
- `golden.py`: bit-exact reference for matmul, bias, ReLU, requantize, including saturation and rounding. This is the source of truth for all testbenches.
- `vecgen.py`: writes `.hex` vectors and expected outputs, including edge cases (-128, 127, zeros, non-multiple-of-array sizes).
- `cyclemodel.py`: cycle-level model of the array with partitioning. It must model the feed-port behavior under two assumptions: (A) a shared feed port, where one tenant's stream occupies the row wires at a time, and (B) per-partition feed injection. It reports total cycles and column utilization for: sequential baseline, equal split, and proportional split, over randomized layer mixes and arrival times.
- Gate: a written result in `results/cyclemodel.md` saying whether the shared feed port caps concurrency gains, and by how much. This decides the headline improvement.

### Milestone 2: Single-tenant core in RTL
- `dnn_pkg.sv`, `pe.sv`, `systolic_array.sv` (parameterized), `skew_buf.sv`, `deskew_buf.sv`, with self-checking testbenches against the golden model.
- Then `bram_sdp.sv`, `tile_ctrl.sv`, `accum_mem.sv`, `out_stage.sv`.
- Gate: a full single-tenant layer, including multi-tile layers and edge cases, matches the golden model bit for bit in simulation.

### Milestone 3: Board bring-up
- `axil_regs.sv`, `dnn_top.sv`, Vivado block design, firmware or Tcl driver, cycle counters.
- Gate: the same vectors pass on the board, with PASS/FAIL and cycle counts reported.

### Milestone 4: Partitioning and improvements
- `part_ctrl.sv`, Mul_En partitioning, then improvements in this order: fused output stage (if not already done), shadow weight registers, proportional widths, per-partition feed injection, idle-partition gating.
- Gate: two concurrent networks pass bit for bit in simulation, then on the board.

### Milestone 5: Evaluation and write-up
- Compare three versions on the same workloads: sequential baseline, paper-faithful partitioning, our design.
- Sweep array size (8x8, 12x12, 14x14).
- Report measured and estimated numbers in separate columns (see section 8).

## 7. Verification requirements

- Unit testbenches for each module, all self-checking, with a clear PASS/FAIL print.
- A full-system testbench that plays the Arm core through the same register interface the firmware uses.
- SVA assertions for at least:
  - Partitions never overlap and never exceed the array width.
  - Mul_En is correct for every column on every cycle.
  - A column's partial sum only accumulates products from its owning tenant.
  - AXI-Lite protocol rules on the register interface.
  - Drained result counts match what was queued.
  - Accumulator overflow flags (and cover them).
- Edge cases: -128 and 127 extremes, all-zero inputs, layers that are not multiples of the array size, K larger than `ROWS`, N larger than the partition width, back-to-back layers, a layer arriving while another is mid-run, and a layer finishing while others continue.
- Randomized layer mixes with fixed seeds so failures reproduce.
- Functional coverage on partition widths, tile counts, and tenant counts.

## 8. Evaluation requirements (be strict about measured vs estimated)

| Metric | Measured on the board | Tool estimate |
|---|---|---|
| Latency / throughput | Hardware cycle counters, Arm timer | Post-route Fmax from Vivado timing |
| Utilization (LUT, FF, DSP, BRAM) | n/a | Vivado utilization report |
| Power | USB inline meter with an idle baseline subtracted | Vivado power report |
| MAC utilization and energy per inference | Derived from the measured values | Derived from the estimates |

Rules:
- Never mix the two kinds of number in one column without saying which is which.
- Compare trends against the paper, not absolute values (they used 128x128 in simulation, we use 12x12 on hardware).
- If the dynamic split does not beat equal splitting on some workload mixes (for example when layers are all similar in size), report that honestly.

## 9. Workloads for the demo

Small enough to fit in about 600 KB of block RAM:
- A fully connected MNIST network.
- LeNet-5 (about 60K weights). Safest demo network.
- A small CIFAR-10 CNN of roughly 100-300 KB if tiled.
- Skip MobileNet and ResNet unless the core is done early (needs DDR streaming).

## 10. Scope control

| Level | What runs | Status |
|---|---|---|
| Must have | 1 network verified on the board | Fallback demo |
| Core goal | 2 concurrent networks with dynamic widths | The project |
| Stretch | 3-4 tenants, feed injection, gating, 14x14 sweep | Only if the core is solid |
| Stretch (separate) | Guaranteed per-tenant latency, checksum column for fault detection, covert-channel check | Only after everything above |
| Out of scope | Multi-board, DDR streaming of large models, training | Mention as future work |

Design for N tenants with parameters from the start, but only verify and demo 2 at first.

## 11. Working conventions for the agent

- Write clean, synthesizable SystemVerilog (no `initial` blocks or delays in RTL, registered outputs on module boundaries, explicit reset, no latches). Keep testbench-only code in `tb/`.
- Parameterize `ROWS`, `COLS`, and widths from the first line. No magic numbers.
- Keep one source of truth: if a width, rounding rule, or register layout changes, change it in `dnn_pkg.sv` and `spec/regmap.yaml`, and regenerate.
- Run `make sim` before declaring anything done, and report the actual output.
- Keep a short `results/log.md` of decisions and results as you go.
- Do not claim a hypothesis is confirmed until a model or simulation shows it.

## 12. Start here

1. Do Milestone 0.
2. Do Milestone 1 completely and write up `results/cyclemodel.md`.
3. Stop and report the result of the cycle-level model before starting RTL, since it may change which improvement we lead with.
