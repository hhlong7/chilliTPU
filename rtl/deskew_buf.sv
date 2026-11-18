// deskew_buf.sv - realigns the COLS column outputs leaving the bottom of the array.
//
// Column c is delayed by COLS-1-c array advances to align staggered outputs.
// Rules: synthesizable only, no initial blocks or delays, explicit reset,
// registered outputs on module boundaries, valid/ready on data ports.
// Parameter defaults come from dnn_pkg (referenced as dnn_pkg::NAME, not imported,
// so module parameters do not shadow package names).

module deskew_buf
#(
  parameter int COLS = dnn_pkg::COLS,
  parameter int DATA_W = dnn_pkg::PSUM_W
) (
  input  logic clk,
  input  logic rst_n,
  input  logic advance,
  input  logic in_valid,
  output logic in_ready,
  input  logic signed [DATA_W-1:0] in_data [COLS],
  output logic out_valid,
  output logic signed [DATA_W-1:0] out_data [COLS]
);

  // Rectangular storage simplifies static indexing. For column c, only
  // stages 0 through COLS-2-c are used. The rightmost column has no skew.
  logic signed [DATA_W-1:0] data_delay [COLS][COLS];
  logic                    valid_delay[COLS][COLS];
  logic signed [DATA_W-1:0] last_col_data_q;
  logic                    last_col_valid_q;

  // The controller resolves input/output availability into the shared array
  // advance. Deskew must never stall independently of the PE array.
  assign in_ready = advance;

  always_comb begin
    out_valid = last_col_valid_q;
    out_data[COLS-1] = last_col_data_q;
    for (int c = 0; c < COLS-1; c++) begin
      out_data[c] = data_delay[c][COLS-2-c];
      out_valid &= valid_delay[c][COLS-2-c];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      last_col_data_q <= '0;
      last_col_valid_q <= 1'b0;
      for (int c = 0; c < COLS-1; c++) begin
        for (int stage = 0; stage < COLS-1-c; stage++) begin
          data_delay[c][stage] <= '0;
          valid_delay[c][stage] <= 1'b0;
        end
      end
    end else if (advance) begin
      // Rightmost column arrives latest, so it forms the zero-delay reference.
      last_col_data_q <= in_valid ? in_data[COLS-1] : '0;
      last_col_valid_q <= in_valid;

      // Earlier columns wait progressively longer. Bubbles are delayed too.
      for (int c = 0; c < COLS-1; c++) begin
        data_delay[c][0] <= in_valid ? in_data[c] : '0;
        valid_delay[c][0] <= in_valid;
        for (int stage = 1; stage < COLS-1-c; stage++) begin
          data_delay[c][stage] <= data_delay[c][stage-1];
          valid_delay[c][stage] <= valid_delay[c][stage-1];
        end
      end
    end
    // With advance low, every delay stage holds, matching PE.en.
  end

endmodule : deskew_buf
