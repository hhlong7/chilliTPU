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
