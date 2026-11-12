// axil_regs_sva.sv - assertions for axil_regs, attached to the DUT with `bind` in tb_top.sv.
// Status: SKELETON. Use only SVA both Verilator and xsim support (see tb/README.md).
// Give every assertion a label (a_*) and add cover properties (c_*) for the interesting cases.

module axil_regs_sva (
  input logic clk,
  input logic rst_n
  // TODO: DUT signals to observe
);
  // a_example: assert property (@(posedge clk) disable iff (!rst_n) ...);
endmodule : axil_regs_sva
