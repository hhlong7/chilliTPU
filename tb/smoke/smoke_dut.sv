// smoke_dut.sv - tiny registered adder used only to prove the UVM flow works.
// Lives in tb/ because it is not part of the accelerator.

module smoke_dut (
  input  logic              clk,
  input  logic              rst_n,
  input  logic              in_valid,
  input  logic signed [7:0] a,
  input  logic signed [7:0] b,
  output logic              out_valid,
  output logic signed [8:0] y
);
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      out_valid <= 1'b0;
      y         <= '0;
    end else begin
      out_valid <= in_valid;
      y         <= 9'(a) + 9'(b);
    end
  end
endmodule : smoke_dut
