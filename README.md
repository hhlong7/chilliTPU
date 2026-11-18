# chilliTPU

Multi-tenant INT8 systolic array accelerator with a dynamic partition controller, on the Digilent Zybo Z7-20.
CPE 5350 final project.

- **Plan, schedule, and task list:** [PROJECT_PLAN.md](PROJECT_PLAN.md)
- **Original brief:** [docs/PROJECT_BRIEF.md](docs/PROJECT_BRIEF.md)
- **Decisions and results:** [results/log.md](results/log.md)

## Quick start (Mac)

```bash
python3 -m pip install -r requirements.txt
make help
make sim TB=smoke      # UVM smoke test in Verilator
make lint              # lint all RTL
```

To lint only the PE and systolic array with Verilator (Bash on Mac/Linux or the
MSYS2 UCRT64 shell on Windows):

```bash
bash scripts/lint.sh                 # both modules; fails if either fails
bash scripts/lint.sh pe              # PE only
bash scripts/lint.sh systolic_array  # array, including its PE dependency
```

Terminal synthesis and directed simulation (Bash or MSYS2 UCRT64):

```bash
bash scripts/synth.sh                 # Vivado synthesis: PE and default 12x12 array
bash scripts/synth.sh pe              # PE only; or use systolic_array
bash scripts/run_tb.sh                # all six directed test configurations
bash scripts/run_tb.sh 12 12          # one array configuration
bash scripts/run_tb.sh 2 3 4 16       # ROWS COLS DATA_W PSUM_W
```

Synthesis requires Vivado; the script detects standard Windows installs or
accepts `VIVADO=/path/to/vivado`. Set `FPGA_PART` and `CLK_PERIOD_NS` to override
the Zybo Z7-20 part (`xc7z020clg400-1`) and 10 ns clock. Checkpoints, netlists,
and utilization/timing reports go to `build/synth/<top>/`. Timing reports are
unplaced synthesis estimates. Install Vivado's Zynq-7000 device support for the
Zybo target. Stock Yosys cannot read this array's unpacked
ports directly. Tests require Icarus Verilog (`iverilog` and `vvp`); compile and
run logs go to `build/systolic_array/<configuration>/`.

Without Bash, run synthesis from a Vivado command prompt or PowerShell with
Vivado on `PATH`:

```text
vivado -mode batch -source scripts/synth.tcl -tclargs all xc7z020clg400-1 10
```

## Layout

| Folder | What lives there |
|---|---|
| `spec/` | `regmap.yaml`: registers and layer descriptor (source of truth) |
| `sw/py/` | Golden model, quantization, vector generation, cycle model, analysis |
| `rtl/` | Synthesizable SystemVerilog (`rtl/pkg/dnn_pkg.sv` holds shared parameters) |
| `tb/` | `common/` shared UVM kit, one UVM env folder per RTL module, `smoke/` |
| `fw/` | Bare-metal C for the Arm core |
| `fpga/` | Vivado batch Tcl and constraints (run on the Vivado PC) |
| `scripts/` | Test runners and generators |
| `third_party/` | Accellera UVM 2020.3.1 (pinned) |
| `results/` | Tooling report, decision log, cycle-model write-up, reports |
