`include "uvm_macros.svh"

module tb_top;
  import uvm_pkg::*;
  import skew_buf_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  skew_buf_if vif(clk);
  skew_buf dut (
    .clk(clk), .rst_n(vif.rst_n), .in_valid(vif.in_valid),
    .in_ready(vif.in_ready), .in_data(vif.in_data),
    .out_valid(vif.out_valid), .out_data(vif.out_data),
    .advance(vif.advance)
  );

  bind skew_buf skew_buf_sva #(.ROWS(ROWS), .DATA_W(DATA_W)) u_sva (
    .clk(clk), .rst_n(rst_n), .advance(advance), .in_valid(in_valid),
    .in_ready(in_ready), .out_valid(out_valid), .out_data(out_data)
  );

  initial begin
    vif.rst_n = 1'b0;
    repeat (3) @(negedge clk);
    vif.rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual skew_buf_if)::set(null, "*", "vif", vif);
    run_test();
  end
endmodule : tb_top
