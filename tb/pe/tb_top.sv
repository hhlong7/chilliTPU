// tb_top.sv - top of the pe UVM testbench: clock, reset, DUT, interface, SVA, run_test().

`include "uvm_macros.svh"

module tb_top;
  import uvm_pkg::*;
  import pe_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  pe_if vif (clk);

  pe dut (
    .clk        (clk),
    .rst_n      (vif.rst_n),
    .en         (vif.en),
    .w_load     (vif.w_load),
    .w_swap     (vif.w_swap),
    .w_in       (vif.w_in),
    .w_out      (vif.w_out),
    .mul_en_in  (vif.mul_en_in),
    .mul_en_out (vif.mul_en_out),
    .a_in       (vif.a_in),
    .a_out      (vif.a_out),
    .psum_in    (vif.psum_in),
    .psum_out   (vif.psum_out)
  );

  bind pe pe_sva #(.DATA_W(DATA_W), .PSUM_W(PSUM_W)) u_sva (.*);

  // Reset is released on a falling edge so it never races the DUT's rising edge.
  initial begin
    vif.rst_n = 1'b0;
    repeat (3) @(negedge clk);
    vif.rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual pe_if)::set(null, "*", "vif", vif);
    run_test();
  end
endmodule : tb_top
