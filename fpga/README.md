# FPGA

Everything here runs on the **Vivado PC**, in batch mode:

```bash
vivado -mode batch -source fpga/build.tcl
```

Outputs (bitstream, XSA) go to `fpga/build/` (gitignored). Reports that go in the write-up
are copied to `results/` with the git commit hash they were built from.

Week 1 smoke test (M3): LED blink plus one AXI-Lite register the Arm core can read and write.
