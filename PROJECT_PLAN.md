# chilliTPU — Project Plan

Multi-tenant INT8 systolic array accelerator on the Digilent Zybo Z7-20.
CPE 5350 final project. Background and rationale: [docs/PROJECT_BRIEF.md](docs/PROJECT_BRIEF.md).

This is the working plan for the group. If you change a date, a task, or a decision, edit this file in a PR so everyone sees it.

---

## 1. One-paragraph summary (use this wording everywhere)

The reference (Reshadi & Gregg, PDP 2023) splits the systolic array into equal column partitions regardless of layer size, which leaves columns idle or forces extra passes. We implement the design in RTL and replace the equal split with a hardware partition controller that sizes each partition from the layer's output channels and MAC count, then reassigns or gates the freed columns. This lets the accelerator run multiple networks at once while keeping more of the array busy.

**Open question that decides our headline:** do tenants in the paper share each row's feed port? If yes, concurrency is capped and *per-partition feed injection* becomes our main improvement. The Python cycle model (Milestone 1) answers this. Nobody claims it either way until `results/cyclemodel.md` exists.

---

## 2. How we work together

There are no fixed owners or roles. We pick tasks at each meeting, and anyone can work on any part. The **systolic array and the dynamic partitioning RTL are done together as a group**, since they are the core of the project and the two are tightly linked (Mul_En in the PE, partition boundaries in the array, `part_ctrl` driving both).

Parts of the project, for reference when choosing tasks:

| Part | Files |
|---|---|
| Spec | `spec/regmap.yaml`, `rtl/pkg/dnn_pkg.sv` |
| Python models | `quantize.py`, `golden.py`, `vecgen.py`, `cyclemodel.py`, `analyze.py` |
| Core RTL (together) | `pe`, `systolic_array`, `skew_buf`, `deskew_buf`, `part_ctrl` |
| Rest of the datapath | `bram_sdp`, `tile_ctrl`, `accum_mem`, `out_stage` |
| Verification | UVM shared kit (`tb/common/`), per-module UVM envs, system env, SVA, coverage, `make sim` regression |
| FPGA + firmware | `axil_regs`, `dnn_top`, Vivado Tcl, block design, Vitis app, board measurements |

Rules:
- To take a task, put your name next to its checkbox in section 4 (or say so in the group chat) so two people don't do the same thing by accident.
- Every RTL module ships with its own UVM environment (section 6), written alongside the RTL. Someone other than the person who wrote the RTL reviews the env and adds corner-case tests, so no module is verified only by its author.
- Any PR needs at least one other person's review before merging.
- If you are blocked for more than a day, post it in the group chat and add it to section 10.

---

## 3. Schedule

> **Deadline: TBD — confirm as a group.** Dates below assume the final demo is in finals week (around Dec 10). Thanksgiving is Thu Nov 26. Adjust once confirmed.

| Week | Dates | Target | Gate |
|---|---|---|---|
| 1 | Nov 12 – Nov 18 | M0 done. M1 done. `pe` + `systolic_array` started. Vivado path smoke test (blinky + 1 AXI-Lite register). | `make sim` passes; `results/cyclemodel.md` written |
| 2 | Nov 19 – Nov 25 | M2: single-tenant core verified in simulation. `axil_regs` + block design started. | Full single-tenant layer matches golden bit for bit |
| 3 | Nov 26 – Dec 2 | M3: board bring-up. M4: `part_ctrl` in simulation. | Same vectors PASS on the board with cycle counts |
| 4 | Dec 3 – Dec 9 | M4: 2 tenants on board. M5: evaluation runs, report, slides. | Two concurrent networks PASS on board; report draft |
| Finals | ~Dec 10 | Demo + submission | |

**Priority if time runs short:** the "must have" (one network verified on the board) is protected first. Stretch work is cut before core work slips.

---

## 4. Milestones, tasks, and gates

Do not start a milestone's RTL until the previous gate passes. Python and FPGA-path work may run ahead in parallel.

### M0 — Repo and tooling (Week 1)
- [x] Directory layout (section 7) and `Makefile` targets: `vectors`, `regs`, `sim`, `sim-xsim`, `lint`, `bitstream`, `fw`, `report` (most are stubs until their milestone)
- [ ] `results/tooling.md`: tools found on each machine (Mac done; Vivado PC section still to fill in)
- [x] Add Accellera UVM 2020.3.1 (IEEE 1800.2-2020, Apache-2.0) under `third_party/uvm-core/`, pinned to a fixed commit
- [x] UVM smoke test (tiny DUT + agent + scoreboard) wired into `make sim`; passes in Verilator on the Mac
- [ ] Same smoke test in xsim on the Vivado PC (`make sim-xsim TB=smoke`)
- [x] `tb/common/` shared UVM kit skeleton (section 6); stub files only
- [x] `results/log.md` started
- [x] Stub files for every RTL module (lint clean), UVM env skeleton per module, Python/firmware/FPGA stubs
- **Gate:** `make sim` prints PASS for the UVM smoke test on a clean clone, in Verilator and in xsim.

### M1 — Python golden model and cycle model (Week 1)
- [ ] Freeze the shared spec first (section 5) as a group
- [ ] `golden.py`: bit-exact matmul, bias, ReLU, requantize, saturation, rounding
- [ ] `vecgen.py`: `.hex` vectors + expected outputs, including edge cases (section 6)
- [ ] `cyclemodel.py`: array with partitioning under two feed assumptions
  - (A) shared feed port: one tenant's stream on the row wires at a time
  - (B) per-partition feed injection
  - Reports total cycles and column utilization for: sequential, equal split, proportional split
  - Randomized layer mixes and arrival times, fixed seeds
- [ ] `quantize.py`: INT8 quantization of MNIST-FC and LeNet-5 (needs PyTorch; can finish in Week 2)
- **Gate:** `results/cyclemodel.md` states whether the shared feed port caps concurrency gains, and by how much. The group decides the headline improvement from it.

### M2 — Single-tenant core in RTL (Week 2)
- [ ] `dnn_pkg.sv`, `pe.sv`, `systolic_array.sv`, `skew_buf.sv`, `deskew_buf.sv`, each with its UVM env
- [ ] `bram_sdp.sv`, `tile_ctrl.sv`, `accum_mem.sv`, `out_stage.sv`, each with its UVM env
- [ ] Single-tenant datapath UVM env driving the whole datapath from `.hex` vectors
- **Gate:** a full layer, including multi-tile (K > ROWS, N > COLS) and edge cases, matches golden bit for bit.

### M3 — Board bring-up (Weeks 2–3)
- [ ] Week 1: Vivado smoke test (LED + one AXI-Lite register read/write from the Arm core)
- [ ] `axil_regs.sv` generated from `spec/regmap.yaml`, `dnn_top.sv`
- [ ] `fpga/build.tcl`: batch-mode block design, synth, impl, bitstream, XSA, reports
- [ ] Vitis bare-metal app: loads vectors, runs, compares, prints PASS/FAIL + cycle counts over UART (115200)
- [ ] Fallback if Vitis blocks us: JTAG-to-AXI Master driven from Tcl, plus ILA/VIO
- **Gate:** the same vectors used in M2 PASS on the board, with cycle counts.

### M4 — Partitioning and improvements (Weeks 3–4, core RTL done together)
- [ ] `part_ctrl.sv` paper-faithful mode (equal split, first layer gets full array, merge on free)
- [ ] Mul_En partitioning in `pe` (AND/mux/clock enable — no tri-states)
- [ ] Our mode: proportional widths, snapped to allowed widths, leftover reassignment
- [ ] Improvements in order: fused output stage → shadow weight registers → per-partition feed injection* → idle-partition gating
- [ ] SVA: partitions never overlap; Mul_En correct per column per cycle; column only accumulates its owning tenant's products
- **Gate:** two concurrent networks PASS bit for bit in simulation, then on the board.

\* Per-partition feed injection moves up to first place if M1 confirms the shared-feed cap.

### M5 — Evaluation and write-up (Week 4, everyone)
- [ ] Same workloads on three versions: sequential, paper-faithful partitioning, ours
- [ ] Array size sweep: 8×8, 12×12, 14×14 (utilization/timing at minimum; board runs if time)
- [ ] Results table with **measured** and **estimated** columns kept separate (section 8)
- [ ] Report + slides + demo script

---

## 5. Shared spec (freeze in Week 1, then change only by PR)

The single source of truth is `rtl/pkg/dnn_pkg.sv` + `spec/regmap.yaml`, mirrored in `sw/py/`. If you need to change any of these, open a PR tagged `spec-change`, get the group's agreement (in the PR or at a meeting), then regenerate everything.

| Item | Value |
|---|---|
| Computation | `Y[M,N] = X[M,K] · W[K,N]`; convs lowered with im2col in Python |
| Array mapping | Rows = K, columns = N (output channels). Weight-stationary. |
| Default array | `ROWS = COLS = 12`, parameterized (sweep 8, 12, 14) |
| Weights, activations | INT8 signed |
| Products | 16-bit signed |
| In-array partial sum | `PSUM_W` parameter, default 32 (19 bits is the minimum for 12 rows) |
| Cross-tile accumulation | INT32 |
| Requantize | `out = clamp(round((relu(acc + bias) * scale) >> shift), -128, 127)` |
| Rounding rule | **TBD in Week 1** — proposed: add `1 << (shift-1)` then arithmetic shift right (round half up). Must also cover layers with ReLU disabled (negative values). |
| `scale` / `shift` widths | **TBD in Week 1** (proposed: 16-bit unsigned scale, 5-bit shift) |
| ReLU | Per-layer enable bit (the final layer usually has none) |
| Mul_En low | PE adds zero; psum passes down unchanged; input still passes right |
| Weight load | Own path, not the psum wires (needed for shadow weights) |
| Clock | Single domain; 125 MHz target (board clock or PS FCLK) |
| Module handshake | `valid`/`ready` streams on module boundaries wherever data flows (so one generic UVM stream agent covers most modules); active-low synchronous reset `rst_n` |

### Test vector format (Python side writes, RTL/UVM/firmware read)
- One value per line, two's-complement hex, zero-padded to the type width (e.g. INT8 `80` = -128, INT32 `FFFFFF80`).
- Row-major order. Files per test case in `vectors/<case>/`: `x.hex`, `w.hex`, `bias.hex`, `y_expected.hex`, plus `meta.json` (M, K, N, scale, shift, relu, seed).
- TBs read with `$readmemh` and compare every output; print `PASS <case>` or `FAIL <case> idx=<i> got=<g> exp=<e>`.

---

## 6. Verification plan

### Methodology: UVM for every module
Every synthesizable module in `rtl/` gets a full UVM environment. Packages (`dnn_pkg.sv`, `dnn_regs_pkg.sv`) have no logic of their own and are covered through the modules that import them.

**Library and simulators (tested 2026-11-12):**
- Accellera UVM **2020.3.1** (IEEE 1800.2-2020), compiled from source in `third_party/uvm-core/`. Both simulators compile this same copy, so we don't depend on xsim's built-in UVM 1.2.
- **Verilator 5.048 (Mac):** works. A test with a sequence, driver, monitor, scoreboard, config_db, factory, and constrained `randomize()` passed. Needs `--binary --timing +define+UVM_NO_DPI`. Building UVM takes about 45 s per testbench on an M-series Mac, so build one env at a time with `make sim TB=<module>`.
- **Verilator does NOT support covergroups.** It prints a warning, drops them, and reports 0% coverage. Assertions and `cover property` do work.
- **xsim (Vivado PC):** runs the same envs and is the **official coverage simulator**. Coverage numbers in the report come from xsim. (Compiling UVM 2020.3.1 in xsim still needs to be confirmed in M0.)

### Structure of each module's env
```
tb/<module>/
  <module>_if.sv        interface (+ clocking blocks)
  <module>_pkg.sv       seq_item, sequences, agent(s), ref model, scoreboard, coverage, env, tests
  <module>_sva.sv       assertions, bound to the DUT with `bind`
  tb_top.sv             clock/reset, DUT, interface, config_db, run_test()
  files.f               source list (repo-relative), shared by Verilator and xsim
  tests.txt             list of tests + seeds that make sim runs
```
Every env has: an agent (driver + monitor + sequencer) per DUT port group, a reference model, a scoreboard that compares every output, a coverage collector, and at least a `smoke`, `edge`, and `random` test. Every test ends with one line: `PASS <module>.<test> seed=<s>` or `FAIL ...`.

### Shared kit (`tb/common/`, Week 1)
Write these once and reuse them so 12+ envs fit in the schedule:
- `stream_agent` — generic, parameterized `valid`/`ready` agent with random backpressure (used by most datapath modules)
- `axil_agent` — AXI-Lite master agent with protocol checks (for `axil_regs`, `dnn_top`, system env)
- `bram_agent` — memory model / backdoor loader for weight, feed, and drain buffers
- `hex_vector_reader` — loads `vectors/<case>/` files into transactions and expected outputs
- `base_test` — seed printing, timeout, PASS/FAIL summary, report-server setup
- `int8_ref` — SV reference functions (MAC, requantize) that match `golden.py` bit for bit, used by small-block scoreboards

### Reference models
- Small blocks (`pe`, `skew_buf`, `deskew_buf`, `bram_sdp`, `out_stage`): an SV reference model in the scoreboard, plus a directed test that replays `golden.py` vectors to show the SV model agrees with Python.
- Datapath and system level (`systolic_array`, `tile_ctrl`, `accum_mem`, `dnn_top`): expected outputs come from `golden.py` through `.hex` vectors.
- `part_ctrl`: an SV model of the allocation rule, cross-checked against `cyclemodel.py` decisions on fixed seeds.

### Planned envs
| Env | Main agents | Key checks |
|---|---|---|
| `pe` | input stream, psum-in, weight load, Mul_En | MAC exact; Mul_En low passes psum unchanged and still forwards input |
| `systolic_array` | row feed, weight load, column drain | Matmul tile vs golden; partition isolation |
| `skew_buf` / `deskew_buf` | stream in/out | Per-row/column delay exact; no drop/dup |
| `bram_sdp` | 2 × bram ports | Read-after-write, simultaneous ports |
| `tile_ctrl` | layer descriptor in, address out | Address sequence vs Python tiling for non-multiple sizes |
| `accum_mem` | psum in, result out | INT32 accumulation across K tiles; overflow flag |
| `out_stage` | acc in, int8 out | Bias/ReLU/rounding/saturation exact |
| `part_ctrl` | layer queue in, partition map out | No overlap, width ≤ COLS, merge/reassign, gating |
| `axil_regs` | axil_agent | Register map vs `regmap.yaml`; AXI-Lite protocol |
| `dnn_top` (system) | axil_agent + bram_agent | Plays the Arm core through the same registers the firmware uses; full networks vs golden |

**System level:** the `dnn_top` env plays the Arm core through the same register interface the firmware uses. Its sequences mirror the C driver's calls, so a sequence that passes in sim is a recipe for the firmware.

**SVA (minimum set):**
- Partitions never overlap and never exceed `COLS`
- Mul_En is correct for every column, every cycle
- A column's partial sum only accumulates its owning tenant's products
- AXI-Lite protocol rules on `axil_regs`
- Drained result count equals queued count
- Accumulator overflow flags (assert + cover)

**Edge cases that must have a test:**
- -128 and 127 extremes, all-zero inputs
- M, K, N not multiples of the array size
- K > ROWS (multi-tile accumulate), N > partition width
- Back-to-back layers
- A layer arriving while another is mid-run
- A layer finishing while others continue

**Randomized:** constrained-random sequences with fixed seeds, seed printed on every run; `make sim` runs the seeds in each env's `tests.txt`.
**Coverage (covergroups, measured in xsim):** partition widths, tile counts, tenant counts, INT8 extremes, overflow flags. `cover property` checks also run in Verilator.

Use only UVM/SVA features both simulators support; keep the list in `tb/README.md`.

---

## 7. Repo layout and workflow

```
chilliTPU/
  PROJECT_PLAN.md   this file
  docs/             PROJECT_BRIEF.md, papers, report drafts
  spec/             regmap.yaml (source of truth for registers + layer descriptor)
  sw/py/            quantize.py, golden.py, vecgen.py, cyclemodel.py, analyze.py
  rtl/              pkg/dnn_pkg.sv and all synthesizable modules
  tb/               common/ (shared UVM kit) + one UVM env folder per module + system env
  third_party/      uvm-core (Accellera UVM 2020.3.1, pinned)
  fw/               Arm bare-metal C driver and test app
  fpga/             Vivado Tcl, block design, constraints
  scripts/          helpers, generators (regmap -> .sv/.h/.py)
  results/          tooling.md, log.md, cyclemodel.md, reports, plots
  Makefile          make vectors | sim | bitstream | fw | report
```

### Two-machine flow
- **Mac (everyone):** Python, Verilator sim, Yosys quick estimates.
- **Vivado/Vitis PC:** `vivado -mode batch -source fpga/build.tcl` → bitstream, XSA, utilization/timing/power reports. Vitis app build. Board runs.
- Everything moves through git. Board results and Vivado reports are committed to `results/` with the commit hash they were built from.

### Git rules
- **Nobody pushes to `main` directly.** GitHub blocks it (branch ruleset on `main`), and `make hooks` adds a local check that stops it before it leaves your machine. Run `make hooks` once after cloning.
- `main` must always pass `make sim`.
- Work on branches named `<name>/<topic>` (e.g. `alex/pe-mulen`).
- Open a PR for every merge. At least one other person approves. The PR template asks for the `make sim` output.
- Spec changes (section 5) need the group's agreement.
- Never commit generated files that `make` can rebuild, except the reports in `results/`.

Day-to-day flow:
```bash
git switch main && git pull                 # start from the latest main
git switch -c <name>/<topic>                # new branch for your task
# ...edit, make sim, make lint...
git add -A && git commit -m "pe: add Mul_En gate"
git push -u origin <name>/<topic>           # then open a PR on GitHub
```
After the PR is approved and merged on GitHub: `git switch main && git pull`, and delete your branch.

### RTL coding rules
- Synthesizable SystemVerilog only in `rtl/`: no `initial`, no delays, explicit reset, no latches.
- Registered outputs on module boundaries.
- `ROWS`, `COLS`, and all widths are parameters. No magic numbers.
- Testbench-only code lives in `tb/`.

---

## 8. Evaluation plan (measured vs estimated — never mix)

| Metric | Measured on board | Tool estimate |
|---|---|---|
| Latency / throughput | HW cycle counters, Arm timer | Post-route Fmax (Vivado timing) |
| Utilization (LUT/FF/DSP/BRAM) | n/a | Vivado utilization report |
| Power | USB inline meter, idle baseline subtracted | Vivado power report |
| MAC utilization, energy/inference | Derived from measured | Derived from estimates |

- Every table and plot labels each column **measured** or **estimated**.
- Compare *trends* with the paper, not absolute numbers (they used 128×128 in simulation).
- If the dynamic split loses to the equal split on some mixes (e.g. similar-sized layers), report it.

**Workloads:** MNIST fully connected, LeNet-5 (main demo), small CIFAR-10 CNN if time. No MobileNet/ResNet (needs DDR streaming).

**Resource budget (12×12):** 144 DSPs for the array + output stage DSPs ≤ 220. 14×14 ≈ 210 DSPs (tight). 16×16 is a stretch.

---

## 9. Scope tiers

| Tier | What runs | Status |
|---|---|---|
| Must have | 1 network verified on the board | Fallback demo — protect this |
| Core goal | 2 concurrent networks with dynamic widths | The project |
| Stretch | 3–4 tenants, feed injection*, gating, 14×14 sweep | Only if core is solid |
| Stretch (separate) | Per-tenant latency guarantee, checksum column, covert-channel check | Only after everything above |
| Out of scope | Multi-board, DDR streaming, training | Future work section |

\* Becomes core if M1 confirms the shared-feed cap.

Design for N tenants with parameters from the start; verify and demo 2.

---

## 10. Risks and open items

| # | Risk / open item | Mitigation / status |
|---|---|---|
| 1 | Final deadline not confirmed | Confirm this week; adjust section 3 |
| 2 | Tasks not yet picked | Choose tasks at the first meeting (section 4 checkboxes) |
| 3 | Vivado/Vitis only on one PC | Batch Tcl build; smoke test in Week 1 |
| 4 | Rounding rule and scale/shift widths not fixed | Decide in Week 1 before any `out_stage` RTL |
| 5 | Shared-feed hypothesis may cap concurrency | Cycle model decides; plan already has both paths |
| 6 | Per-partition feed needs a feed-buffer read port + skew per partition, not just muxes | Budget BRAM ports early |
| 7 | 12×12 is small: `min(N_i, …)` rarely binds, so MAC-proportional share drives most decisions | State honestly in report |
| 8 | PyTorch not installed on the Mac | `pip install torch` before `quantize.py` |
| 9 | Thanksgiving week reduces availability | Front-load M1/M2 into Weeks 1–2 |
| 10 | Full UVM env for every module is a lot of work in 4 weeks | Shared kit in Week 1; one `valid`/`ready` convention so the stream agent is reused; author writes the env alongside the RTL, not after |
| 11 | Verilator drops covergroups | Coverage measured in xsim; `cover property` in Verilator for fast feedback |
| 12 | UVM build is ~45 s per env in Verilator | `make sim TB=<module>` for daily work; full regression before merging to `main` |
| 13 | UVM 2020.3.1 in xsim not yet confirmed | Check in M0; fallback is xsim's built-in UVM 1.2 with a shared API subset |

---

## 11. Meetings and communication

- Standup: _TBD (suggest 2× per week, 15 min)_. Each person: done, next, blocked.
- Decisions and results go in `results/log.md` (date, decision, why, who).
- Gate reviews: the group agrees a milestone gate has passed and records it in `results/log.md` before the next RTL phase starts.

---

## 12. Decision log (summary)

| Date | Decision |
|---|---|
| 2026-11-12 | Verilator is the primary simulator; xsim cross-check on the Vivado PC |
| 2026-11-12 | FPGA builds are batch Tcl on the Vivado PC; results flow back through git |
| 2026-11-12 | Python cycle model (M1) runs before RTL and decides the headline improvement |
| 2026-11-12 | Every RTL module gets a full UVM env; Accellera UVM 2020.3.1 from source in both simulators |
| 2026-11-12 | Verilator 5.048 runs UVM (smoke test passed); covergroups unsupported there, so xsim is the coverage simulator |
| 2026-11-12 | No fixed owners; tasks picked at meetings. Systolic array + dynamic partitioning RTL done together as a group |
