// pe.sv - one processing element of the weight-stationary systolic array (D4).
//
// Holds a weight, multiplies the input coming from the left (DSP), adds the
// partial sum from above, and passes the input right and the sum down. Every
// hop is one register, so row r sees a given input r cycles after row 0.
//
// Control (results/log.md D4):
//   en        global array enable. No per-PE valid/ready: the whole array
//             stalls together, handshakes live only at the array edges
//             (skew_buf in, deskew_buf out), so the systolic timing never slips.
//   w_load    weight shift chain down the column: w_shadow <= w_in, and
//             w_out = w_shadow feeds the PE below. Loading takes ROWS cycles,
//             runs on its own wires, and ignores en, so the next tile's weights
//             can load while the current tile computes.
//   w_swap    w_active <= w_shadow. Pulse it once the array has drained the
//             previous tile (tile_ctrl). If w_load and w_swap are both high,
//             w_active takes the OLD shadow value.
//   mul_en    Mul_En partition gate, one bit per column from part_ctrl. It
//             travels down the column with the partial sum (mul_en_in ->
//             mul_en_out), so a partition change reaches row r exactly when
//             that row sees the matching input. When low, the PE adds zero but
//             still forwards a and psum.
//
// Rules: synthesizable only, no initial blocks or delays, synchronous active-low
// reset, every output registered. Parameter defaults come from dnn_pkg.

module pe
#(
  parameter int DATA_W = dnn_pkg::DATA_W,
  parameter int PSUM_W = dnn_pkg::PSUM_W
) (
  input  logic                      clk,
  input  logic                      rst_n,
  input  logic                      en,

  // weight shift chain (down the column) and shadow -> active swap
  input  logic                      w_load,
  input  logic                      w_swap,
  input  logic signed [DATA_W-1:0]  w_in,
  output logic signed [DATA_W-1:0]  w_out,

  // Mul_En, pipelined down the column with the partial sum
  input  logic                      mul_en_in,
  output logic                      mul_en_out,

  // activations: left -> right
  input  logic signed [DATA_W-1:0]  a_in,
  output logic signed [DATA_W-1:0]  a_out,

  // partial sums: top -> bottom
  input  logic signed [PSUM_W-1:0]  psum_in,
  output logic signed [PSUM_W-1:0]  psum_out
);

  localparam int PROD_W = 2 * DATA_W;

  // Elaboration check: the partial sum must hold at least one full product.
  if (PSUM_W < PROD_W) begin : g_psum_too_narrow
    $error("pe: PSUM_W (%0d) must be >= 2*DATA_W (%0d)", PSUM_W, PROD_W);
  end

  logic signed [DATA_W-1:0] w_shadow, w_active;
  logic signed [PROD_W-1:0] product;

  assign product = a_in * w_active;   // INT8 x INT8 -> INT16, one DSP48E1
  assign w_out   = w_shadow;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      w_shadow   <= '0;
      w_active   <= '0;
      mul_en_out <= 1'b0;
      a_out      <= '0;
      psum_out   <= '0;
    end else begin
      if (w_load) w_shadow <= w_in;
      if (w_swap) w_active <= w_shadow;
      if (en) begin
        a_out      <= a_in;
        mul_en_out <= mul_en_in;
        psum_out   <= psum_in + (mul_en_in ? PSUM_W'(product) : '0);
      end
    end
  end

endmodule : pe
