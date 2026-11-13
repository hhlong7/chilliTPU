// pe.sv - one processing element: holds a weight, multiplies the incoming input (DSP), adds the partial sum from above, passes the input right. Mul_En gate: when low, adds zero and still forwards the input.
//
// Status: SKELETON. Ports and behavior are TBD (see PROJECT_PLAN.md sections 4-5).
// Rules: synthesizable only, no initial blocks or delays, explicit reset,
// registered outputs on module boundaries, valid/ready on data ports.
// Parameter defaults come from dnn_pkg (referenced as dnn_pkg::NAME, not imported,
// so module parameters do not shadow package names).

module pe
#(
  parameter int DATA_W = dnn_pkg::DATA_W,
  parameter int PSUM_W = dnn_pkg::PSUM_W
) (
  input  logic                         clk,
  input  logic                         rst_n,

  input  logic                         weight_we,
  input  logic signed [DATA_W-1:0]     weight_in,
  input  logic                         mul_en,

  input  logic                         in_valid,
  output logic                         in_ready,
  input  logic signed [DATA_W-1:0]     data_in,
  input  logic signed [PSUM_W-1:0]     psum_in,

  output logic                         out_valid,
  input  logic                         out_ready,
  output logic signed [DATA_W-1:0]     data_out,
  output logic signed [PSUM_W-1:0]     psum_out
);

  localparam int PROD_W = 2 * DATA_W;

  logic signed [DATA_W-1:0] weight_q;
  logic signed [PROD_W-1:0] product;
  logic signed [PSUM_W-1:0] product_ext;

  assign in_ready    = ~out_valid | out_ready;
  assign product     = data_in * weight_q;
  assign product_ext = {{(PSUM_W-PROD_W){product[PROD_W-1]}}, product};

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      weight_q <= '0;
      out_valid <= 1'b0;
      data_out <= '0;
      psum_out <= '0;
    end else begin
      if (weight_we)
        weight_q <= weight_in;

      if (in_ready) begin
        out_valid <= in_valid;
        if (in_valid) begin
          data_out <= data_in;
          psum_out <= psum_in + (mul_en ? product_ext : '0);
        end
      end
    end
  end

endmodule : pe
