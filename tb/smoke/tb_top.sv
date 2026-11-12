// tb_top.sv - smoke test top: clock, reset, DUT, interface, bound SVA, run_test().

`include "uvm_macros.svh"

module tb_top;
  import uvm_pkg::*;
  import smoke_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  smoke_if vif (clk);

  smoke_dut dut (
    .clk       (clk),
    .rst_n     (vif.rst_n),
    .in_valid  (vif.in_valid),
    .a         (vif.a),
    .b         (vif.b),
    .out_valid (vif.out_valid),
    .y         (vif.y)
  );

  bind smoke_dut smoke_sva u_sva (.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .out_valid(out_valid));

  initial begin
    vif.rst_n = 1'b0;
    repeat (3) @(posedge clk);
    vif.rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual smoke_if)::set(null, "*", "vif", vif);
    run_test();
  end
endmodule : tb_top
