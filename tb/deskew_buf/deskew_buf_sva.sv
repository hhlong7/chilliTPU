module deskew_buf_sva(input logic clk,rst_n,advance,in_ready,out_valid);
  a_ready_matches_advance: assert property(@(posedge clk) disable iff(!rst_n) in_ready==advance);
  c_advance: cover property(@(posedge clk) disable iff(!rst_n) advance);
  c_valid_output: cover property(@(posedge clk) disable iff(!rst_n) out_valid);
endmodule
