# Testbenches

Every RTL module has a full UVM environment in `tb/<module>/` (PROJECT_PLAN.md section 6).

```
tb/<module>/
  <module>_if.sv     interface
  <module>_pkg.sv    UVM classes: item, sequences, agents, ref model, scoreboard, coverage, env, tests
  <module>_sva.sv    assertions, bound to the DUT in tb_top.sv
  tb_top.sv          clock/reset, DUT, interface, config_db, run_test()
  files.f            source list (repo-relative), shared by Verilator and xsim
  tests.txt          "<uvm_test_name> <seed>" lines that `make sim` runs
```

`tb/common/` is the shared kit. `tb/smoke/` is a working UVM example: copy its structure.

## Running

```bash
make sim TB=pe          # one env (Verilator, Mac)
make sim                # every env listed in TBS in the Makefile
make sim-xsim TB=pe     # xsim (Vivado PC; needs bash)
```

The array also has a standalone directed test for matrix products, stalls,
partition gates, and shadow-weight loading/swapping. Run it with Icarus Verilog
from the repo root (Bash):

```bash
mkdir -p build/systolic_array
iverilog -g2012 -s tb_systolic_array_directed -o build/systolic_array/directed.vvp \
  rtl/pkg/dnn_pkg.sv rtl/pe.sv rtl/systolic_array.sv tb/systolic_array/tb_directed.sv
vvp build/systolic_array/directed.vvp
```

Each test must print exactly one `PASS <tb>.<test> seed=<s>` or `FAIL ...` line.
The runner treats a missing PASS line, any UVM_ERROR or UVM_FATAL, or a non-zero exit as a failure.
Logs go to `build/<tb>/`.

## Simulator support (keep testbenches portable)

| Feature | Verilator 5.048 (Mac) | xsim (Vivado PC) |
|---|---|---|
| UVM 2020.3.1 classes, factory, config_db, sequences, TLM | Yes (tested 2026-11-12, needs `+define+UVM_NO_DPI`) | Expected yes (confirm in M0) |
| Constrained `randomize()` | Yes (tested) | Yes |
| Immediate / concurrent assertions, `cover property` | Yes | Yes |
| `covergroup` / coverpoints / bins | **No: silently ignored, reports 0%** | Yes: **use xsim for coverage numbers** |
| UVM DPI features (regex, HDL backdoor) | No (`UVM_NO_DPI`) | Avoid, to stay portable |

Add rows here when you find something that works in one simulator and not the other.
