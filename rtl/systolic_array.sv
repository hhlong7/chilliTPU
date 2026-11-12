// systolic_array.sv - ROWS x COLS grid of PEs (weight-stationary). Rows = K, columns = N.
//
// Status: SKELETON. Ports and behavior are TBD (see PROJECT_PLAN.md sections 4-5).
// Rules: synthesizable only, no initial blocks or delays, explicit reset,
// registered outputs on module boundaries, valid/ready on data ports.
// Parameter defaults come from dnn_pkg (referenced as dnn_pkg::NAME, not imported,
// so module parameters do not shadow package names).

module systolic_array
#(
  parameter int ROWS = dnn_pkg::ROWS,
  parameter int COLS = dnn_pkg::COLS
) (
  input  logic clk,
  input  logic rst_n
  // TODO: ports
);

  // TODO: implementation

endmodule : systolic_array
