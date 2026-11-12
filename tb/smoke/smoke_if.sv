// smoke_if.sv - interface for the smoke test.

interface smoke_if (input logic clk);
  logic              rst_n;
  logic              in_valid;
  logic signed [7:0] a, b;
  logic              out_valid;
  logic signed [8:0] y;
endinterface : smoke_if
