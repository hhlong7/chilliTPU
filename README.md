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
