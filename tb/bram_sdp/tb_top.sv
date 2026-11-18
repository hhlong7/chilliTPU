// tb_top.sv - top of the bram_sdp UVM testbench: clock, reset, DUT, interface, SVA, run_test().

`include "uvm_macros.svh"

module tb_top;
  import uvm_pkg::*;
  import bram_sdp_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  bram_sdp_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) vif (clk);

  bram_sdp #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (
    .clk      (clk),
    .rst_n    (vif.rst_n),
    .wr_en    (vif.wr_en),
    .wr_addr  (vif.wr_addr),
    .wr_data  (vif.wr_data),
    .rd_en    (vif.rd_en),
    .rd_addr  (vif.rd_addr),
    .rd_data  (vif.rd_data),
    .rd_valid (vif.rd_valid)
  );

  bind bram_sdp bram_sdp_sva #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_sva (.*);

  // Reset is released on a falling edge so it never races the DUT's rising edge.
  initial begin
    vif.rst_n = 1'b0;
    repeat (3) @(negedge clk);
    vif.rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual bram_sdp_if #(DATA_W, ADDR_W))::set(null, "*", "vif", vif);
    run_test();
  end
endmodule : tb_top
