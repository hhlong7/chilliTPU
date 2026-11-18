// tb_top.sv - top of the accum_mem UVM testbench: clock, reset, DUT, interface, SVA, run_test().

`include "uvm_macros.svh"

module tb_top;
  import uvm_pkg::*;
  import accum_mem_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  accum_mem_if #(.COLS(COLS), .ACC_W(ACC_W), .ADDR_W(ADDR_W)) vif (clk);

  accum_mem #(.COLS(COLS), .ACC_W(ACC_W), .DEPTH(DEPTH)) dut (
    .clk       (clk),
    .rst_n     (vif.rst_n),
    .in_valid  (vif.in_valid),
    .in_ready  (vif.in_ready),
    .in_addr   (vif.in_addr),
    .in_first  (vif.in_first),
    .in_last   (vif.in_last),
    .in_data   (vif.in_data),
    .out_valid (vif.out_valid),
    .out_ready (vif.out_ready),
    .out_addr  (vif.out_addr),
    .out_data  (vif.out_data),
    .ovf_clr   (vif.ovf_clr),
    .ovf       (vif.ovf)
  );

  bind accum_mem accum_mem_sva #(.COLS(COLS), .ACC_W(ACC_W), .ADDR_W(ADDR_W)) u_sva (.*);

  // Reset is released on a falling edge so it never races the DUT's rising edge.
  initial begin
    vif.rst_n = 1'b0;
    repeat (3) @(negedge clk);
    vif.rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual accum_mem_if #(COLS, ACC_W, ADDR_W))::set(null, "*", "vif", vif);
    run_test();
  end
endmodule : tb_top
