// deskew_buf.sv - realigns the COLS column outputs leaving the bottom of the array.
//
// Timing rule (D4): Y[m][c] leaves array column c at cycle m + ROWS + c (column 0 first).
// Column c is delayed by COLS-c advances, so every column of row m comes out together,
// COLS advances after column 0 left the array. Every column is a plain delay line of
// COLS-c registers (the last column included), so no column is a special case.
//
// Fix 2026-11-18: the last column used to have its own register (delay 1) while column c
// had COLS-1-c stages, so columns COLS-2 and COLS-1 had the same delay and each output
// bundle paired row m (columns 0..COLS-2) with row m-1 (last column). See results/log.md.
//
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

  // Column c uses stages 0..COLS-1-c (COLS-c registers).
  logic signed [DATA_W-1:0] data_delay  [COLS][COLS];
  logic                     valid_delay [COLS][COLS];

  // The controller resolves input/output availability into the shared array
  // advance. Deskew must never stall independently of the PE array.
  assign in_ready = advance;

  always_comb begin
    out_valid = 1'b1;
    for (int c = 0; c < COLS; c++) begin
      out_data[c] = data_delay[c][COLS-1-c];
      out_valid  &= valid_delay[c][COLS-1-c];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int c = 0; c < COLS; c++) begin
        for (int stage = 0; stage < COLS-c; stage++) begin
          data_delay[c][stage]  <= '0;
          valid_delay[c][stage] <= 1'b0;
        end
      end
    end else if (advance) begin
      // Earlier columns wait longer. Bubbles are delayed too.
      for (int c = 0; c < COLS; c++) begin
        data_delay[c][0]  <= in_valid ? in_data[c] : '0;
        valid_delay[c][0] <= in_valid;
        for (int stage = 1; stage < COLS-c; stage++) begin
          data_delay[c][stage]  <= data_delay[c][stage-1];
          valid_delay[c][stage] <= valid_delay[c][stage-1];
        end
      end
    end
    // With advance low, every delay stage holds, matching PE.en.
  end

endmodule : deskew_buf
