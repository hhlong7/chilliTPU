// skew_buf.sv - staggers the ROWS input streams so row r is delayed r cycles before entering the array.
//
// Each row's activation is delayed by its row index, measured in array advances.
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
  input logic in_valid,
  output logic in_ready,
  input logic signed [DATA_W-1:0] in_data [ROWS],

  // Staggered row values and a common indication that all rows are populated.
  output logic out_valid,
  output logic signed [DATA_W-1:0] out_data [ROWS],

  input logic advance
);

  // A rectangular array is used for simple static indexing. Only stages
  // 0..r-1 are meaningful for row r; row zero is registered separately so it
  // has no additional skew delay.
  logic signed [DATA_W-1:0] data_delay [ROWS][ROWS];
  logic                    valid_delay[ROWS][ROWS];
  logic signed [DATA_W-1:0] row0_data_q;
  logic                    row0_valid_q;

  // The global controller resolves downstream availability into `advance`.
  // This module must not independently stall while the PE array advances.
  assign in_ready = advance;

  always_comb begin
    out_valid = row0_valid_q;
    out_data[0] = row0_data_q;

    for (int r = 1; r < ROWS; r++) begin
      out_data[r] = data_delay[r][r-1];
      out_valid &= valid_delay[r][r-1];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      row0_data_q  <= '0;
      row0_valid_q <= 1'b0;
      for (int r = 1; r < ROWS; r++) begin
        for (int stage = 0; stage < r; stage++) begin
          data_delay[r][stage]  <= '0;
          valid_delay[r][stage] <= 1'b0;
        end
      end
    end else if (advance) begin
      // Row 0 has zero skew. Its output register captures each accepted bundle.
      row0_data_q  <= in_valid ? in_data[0] : '0;
      row0_valid_q <= in_valid;

      // Rows 1..ROWS-1 advance through their own delay lines. Data and valid
      // move together; invalid cycles insert bubbles without changing order.
      for (int r = 1; r < ROWS; r++) begin
        data_delay[r][0]  <= in_valid ? in_data[r] : '0;
        valid_delay[r][0] <= in_valid;
        for (int stage = 1; stage < r; stage++) begin
          data_delay[r][stage]  <= data_delay[r][stage-1];
          valid_delay[r][stage] <= valid_delay[r][stage-1];
        end
      end
    end
    // With advance low all registers hold, keeping skew_buf aligned with PE.en.
  end

endmodule : skew_buf
