// tb_top.sv - top of the out_stage UVM testbench: clock, reset, DUT, interface, SVA, run_test().

`include "uvm_macros.svh"

module tb_top;
  import uvm_pkg::*;
  import out_stage_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  out_stage_if vif (clk);

  out_stage dut(
    .clk       (clk),
    .rst_n     (vif.rst_n),
    .scale     (vif.scale),
    .shift     (vif.shift),
    .relu      (vif.relu),
    .in_valid  (vif.in_valid),
    .in_ready  (vif.in_ready),
    .in_acc    (vif.in_acc),
    .in_bias   (vif.in_bias),
    .in_keep   (vif.in_keep),
    .out_valid (vif.out_valid),
    .out_ready (vif.out_ready),
    .out_data  (vif.out_data),
    .out_keep  (vif.out_keep)
  );

  bind out_stage out_stage_sva #(.LANES(LANES), .DATA_W(DATA_W)) u_sva (.*);

  initial begin
    vif.rst_n = 1'b0;
    repeat(3) @(negedge clk);
    vif.rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual out_stage_if)::set(null, "*", "vif", vif);
    run_test();
  end

endmodule: tb_top