// smoke_sva.sv - example of a bound assertion module.

module smoke_sva (
  input logic              clk,
  input logic              rst_n,
  input logic              in_valid,
  input logic              out_valid
);
  // out_valid follows in_valid by exactly one cycle
  a_valid_latency: assert property (@(posedge clk) disable iff (!rst_n) in_valid |=> out_valid);
  c_valid_seen:    cover  property (@(posedge clk) disable iff (!rst_n) out_valid);
endmodule : smoke_sva
