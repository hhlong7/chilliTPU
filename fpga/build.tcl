# build.tcl - batch Vivado build for the Zybo Z7-20 (run on the Vivado PC).
#
#   vivado -mode batch -source fpga/build.tcl
#
# Plan: create the block design (Zynq PS + dnn_top over AXI-Lite), synth, impl,
# write the bitstream and XSA, and write utilization / timing / power reports to
# results/ (tagged with the git commit they were built from).
#
# Status: SKELETON.

set part xc7z020clg400-1
puts "build.tcl: not implemented yet (Milestone 3). Target part: $part"
