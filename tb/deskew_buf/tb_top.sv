`include "uvm_macros.svh"
module tb_top;
  import uvm_pkg::*;import deskew_buf_pkg::*;
  logic clk=0;always #5 clk=~clk;
  deskew_buf_if vif(clk);
  deskew_buf dut(.clk(clk),.rst_n(vif.rst_n),.advance(vif.advance),
    .in_valid(vif.in_valid),.in_ready(vif.in_ready),.in_data(vif.in_data),
    .out_valid(vif.out_valid),.out_data(vif.out_data));
  bind deskew_buf deskew_buf_sva u_sva(
    .clk(clk),.rst_n(rst_n),.advance(advance),.in_ready(in_ready),.out_valid(out_valid));
  initial begin vif.rst_n=0;repeat(3)@(negedge clk);vif.rst_n=1;end
  initial begin uvm_config_db#(virtual deskew_buf_if)::set(null,"*","vif",vif);run_test();end
endmodule
