# Firmware

Bare-metal C for the Zynq Arm core. Built in **Vitis on the Vivado PC** from the XSA that
`fpga/build.tcl` exports. `arm-none-eabi-gcc` on the Mac can be used for quick compile checks only.

Fallback if Vitis blocks bring-up: JTAG-to-AXI Master driven from Tcl, plus ILA/VIO (PROJECT_PLAN.md M3).
