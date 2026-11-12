# Tooling report

Checked 2026-11-12. Re-run the checks and update this file when a machine's tools change.

## Mac (simulation, Python, firmware compile checks)

Apple M3 Pro, macOS (Darwin 25.6).

| Tool | Version | Status | Used for |
|---|---|---|---|
| Python | 3.13.3 | ✅ | Golden model, vectors, cycle model, analysis |
| NumPy | 2.4.2 | ✅ | Golden model |
| PyYAML | — | ❌ not installed | `scripts/gen_regs.py` (`pip install -r requirements.txt`) |
| PyTorch | — | ❌ not installed | `sw/py/quantize.py` only |
| Verilator | 5.048 | ✅ | Primary simulator, UVM, lint |
| Icarus Verilog | 13.0 | ✅ (backup only) | No UVM support; weak SVA |
| Yosys | 0.66 | ✅ | Optional quick LUT/DSP estimates (`synth_xilinx`); label as estimates |
| arm-none-eabi-gcc | 15.3.1 | ✅ | Compile checks only; real firmware builds in Vitis |
| GNU Make | 3.81 | ✅ | `Makefile` |
| Vivado / xsim / Vitis | — | ❌ not on the Mac | Use the Vivado PC |

### UVM on Verilator (tested)
- Library: Accellera UVM 2020.3.1 (IEEE 1800.2-2020) in `third_party/uvm-core/`.
- Flags: `--binary --timing +define+UVM_NO_DPI`.
- `make sim TB=smoke`: build ~60 s (most of it compiling UVM), tests run in under a second.
- Works: factory, config_db, sequences, driver/monitor/scoreboard, analysis ports, constrained `randomize()`, `assert property`, `cover property`, `bind`.
- **Does not work: `covergroup`.** Verilator prints a COVERIGN warning, ignores it, and reports 0%. Coverage numbers come from xsim.
- Expected warnings in every log: `NO_DPI_USED` and `NO_VISIT_CHECK` (consequences of `UVM_NO_DPI`; harmless).

## Vivado PC (bitstream, xsim, Vitis, board)

To fill in on that machine:

| Tool | Version | Status |
|---|---|---|
| OS (Windows / Linux) | | |
| Vivado | | |
| xsim | | |
| Vitis | | |
| bash + make (Git Bash / WSL on Windows) | | needed for `make sim-xsim` |
| `make sim-xsim TB=smoke` with UVM 2020.3.1 | | **untested**; fallback: xsim built-in UVM 1.2 (`-L uvm`) |
