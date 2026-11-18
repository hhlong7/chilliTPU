// skew_buf.sv - staggers the ROWS input streams so row r enters the array one cycle after row r-1.
//
// Timing rule (D4): a bundle X[m][0..ROWS-1] accepted on one advance comes out with
// row r delayed by r+1 advances, i.e. X[m][r] enters array row r at cycle m + 1 + r.
// The partial sum for row m moves down one PE per cycle, so each row must be exactly
// one cycle behind the row above it. Every row is a plain delay line of r+1 registers
// (row 0 included), so the outputs are registered and no row is a special case.
//
// Fix 2026-11-18: row 0 used to have its own register (delay 1) while row r had r stages
// (delay r), so rows 0 and 1 came out on the same cycle. In the array that adds X[m][0]
// to X[m+1][1..ROWS-1]: wrong results with no error. See results/log.md.
//
// `advance` must be the same global enable used by every PE in the array.
// Rules: synthesizable only, no initial blocks or delays, explicit reset,
// registered outputs on module boundaries, valid/ready on data ports.
// Parameter defaults come from dnn_pkg (referenced as dnn_pkg::NAME, not imported,
// so module parameters do not shadow package names).

module skew_buf
#(
  parameter int ROWS = dnn_pkg::ROWS,
  parameter int DATA_W = dnn_pkg::DATA_W
) (
  input  logic clk,
  input  logic rst_n,

  // One input activation bundle has one value for each array row.
  input  logic in_valid,
  output logic in_ready,
  input  logic signed [DATA_W-1:0] in_data [ROWS],

  // Staggered row values and a common indication that all rows are populated.
  output logic out_valid,
  output logic signed [DATA_W-1:0] out_data [ROWS],

  input  logic advance
);

  // Row r uses stages 0..r (r+1 registers); unused stages of the square array are
  // never written or read and are removed by synthesis.
  logic signed [DATA_W-1:0] data_delay  [ROWS][ROWS];
  logic                     valid_delay [ROWS][ROWS];

  // The global controller resolves downstream availability into `advance`.
  // This module must not independently stall while the PE array advances.
  assign in_ready = advance;

  always_comb begin
    out_valid = 1'b1;
    for (int r = 0; r < ROWS; r++) begin
      out_data[r] = data_delay[r][r];
      out_valid  &= valid_delay[r][r];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int r = 0; r < ROWS; r++) begin
        for (int stage = 0; stage <= r; stage++) begin
          data_delay[r][stage]  <= '0;
          valid_delay[r][stage] <= 1'b0;
        end
      end
    end else if (advance) begin
      // Data and valid move together; invalid cycles insert bubbles without changing order.
      for (int r = 0; r < ROWS; r++) begin
        data_delay[r][0]  <= in_valid ? in_data[r] : '0;
        valid_delay[r][0] <= in_valid;
        for (int stage = 1; stage <= r; stage++) begin
          data_delay[r][stage]  <= data_delay[r][stage-1];
          valid_delay[r][stage] <= valid_delay[r][stage-1];
        end
      end
    end
    // With advance low all registers hold, keeping skew_buf aligned with PE.en.
  end

endmodule : skew_buf
