module tb_top;
  timeunit 1ns;
  timeprecision 1ps;

  import uvm_pkg::*;
  import systolic_array_pkg::*;

  logic clk = 0;
  always #5 clk = ~clk;

  systolic_array_if vif(clk);
  dnn_pkg::data_t skewed [dnn_pkg::ROWS];
  dnn_pkg::psum_t partial [dnn_pkg::COLS];

  skew_buf skew (
    .clk(clk), .rst_n(vif.rst_n), .advance(vif.advance),
    .in_valid(vif.feed_valid), .in_ready(vif.feed_ready), .in_data(vif.x),
    .out_valid(vif.skew_valid), .out_data(skewed)
  );

  systolic_array array_dut (
    .clk(clk), .rst_n(vif.rst_n), .en(vif.advance),
    .w_load(vif.w_load), .w_swap(vif.w_swap), .w_in(vif.weights), .w_out(),
    .a_in(skewed), .a_out(), .mul_en_in(vif.mul_en), .mul_en_out(),
    .psum_out(partial)
  );

  deskew_buf deskew (
    .clk(clk), .rst_n(vif.rst_n), .advance(vif.advance),
    .in_valid(vif.deskew_in_valid), .in_ready(vif.deskew_ready), .in_data(partial),
    .out_valid(vif.deskew_valid), .out_data(vif.result)
  );

  systolic_array_sva checks (
    .clk(clk), .rst_n(vif.rst_n), .advance(vif.advance),
    .feed_ready(vif.feed_ready), .deskew_ready(vif.deskew_ready),
    .feed_valid(vif.feed_valid), .skew_valid(vif.skew_valid),
    .deskew_valid(vif.deskew_valid), .result(vif.result)
  );

  initial begin
    uvm_config_db#(virtual systolic_array_if)::set(null, "uvm_test_top.env.*", "vif", vif);
    run_test();
  end
endmodule : tb_top
