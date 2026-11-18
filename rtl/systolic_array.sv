// systolic_array.sv - ROWS x COLS grid of weight-stationary PEs.
// Rows reduce K; columns produce N. Activations move right; weights,
// partial sums, and Mul_En move down.
//
// All datapath PEs share en. The caller supplies row-skewed activations and
// column-aligned Mul_En; skew/deskew buffers handle stream handshakes outside
// this core. Each hop takes one enabled clock, with no extra boundary register.
//
// Load one weight per column on each w_load cycle, bottom row first. After
// ROWS loads, pulse w_swap once the previous computation has drained. Loading
// is independent of en and can fill shadow registers while active weights run.

module systolic_array #(
  parameter int ROWS   = dnn_pkg::ROWS,
  parameter int COLS   = dnn_pkg::COLS,
  parameter int DATA_W = dnn_pkg::DATA_W,
  parameter int PSUM_W = dnn_pkg::PSUM_W
) (
  input  logic                      clk,
  input  logic                      rst_n,
  input  logic                      en,

  input  logic                      w_load,
  input  logic                      w_swap,
  input  logic signed [DATA_W-1:0]  w_in  [0:COLS-1],
  output logic signed [DATA_W-1:0]  w_out [0:COLS-1],

  input  logic signed [DATA_W-1:0]  a_in  [0:ROWS-1],
  output logic signed [DATA_W-1:0]  a_out [0:ROWS-1],

  input  logic [COLS-1:0]           mul_en_in,
  output logic [COLS-1:0]           mul_en_out,
  output logic signed [PSUM_W-1:0]  psum_out [0:COLS-1]
);

  if (ROWS < 1 || COLS < 1) begin : g_invalid_geometry
    $error("systolic_array: ROWS and COLS must both be positive");
  end

  // Include the boundary at index zero and the output after the last PE.
  logic signed [DATA_W-1:0] a_link [0:ROWS-1][0:COLS];
  logic signed [DATA_W-1:0] w_link [0:ROWS][0:COLS-1];
  logic signed [PSUM_W-1:0] p_link [0:ROWS][0:COLS-1];
  logic                    m_link [0:ROWS][0:COLS-1];

  generate
    for (genvar j = 0; j < COLS; j++) begin : col_boundary
      assign w_link[0][j] = w_in[j];
      assign w_out[j] = w_link[ROWS][j];
      assign p_link[0][j] = '0;
      assign psum_out[j] = p_link[ROWS][j];
      assign m_link[0][j] = mul_en_in[j];
      // This is the pipelined partition gate, not a result-valid signal.
      assign mul_en_out[j] = m_link[ROWS][j];
    end

    for (genvar i = 0; i < ROWS; i++) begin : row_loop
      assign a_link[i][0] = a_in[i];
      assign a_out[i] = a_link[i][COLS];

      for (genvar j = 0; j < COLS; j++) begin : col_loop
        pe #(
          .DATA_W(DATA_W),
          .PSUM_W(PSUM_W)
        ) pe_inst (
          .clk(clk),
          .rst_n(rst_n),
          .en(en),
          .w_load(w_load),
          .w_swap(w_swap),
          .w_in(w_link[i][j]),
          .w_out(w_link[i+1][j]),
          .a_in(a_link[i][j]),
          .a_out(a_link[i][j+1]),
          .mul_en_in(m_link[i][j]),
          .mul_en_out(m_link[i+1][j]),
          .psum_in(p_link[i][j]),
          .psum_out(p_link[i+1][j])
        );
      end
    end
  endgenerate

endmodule : systolic_array
