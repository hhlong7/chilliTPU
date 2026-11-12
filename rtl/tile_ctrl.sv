// tile_ctrl.sv - cuts a layer into array-sized tiles (K-tiling, N-tiling, M rows) and generates buffer addresses.
//
// Status: SKELETON. Ports and behavior are TBD (see PROJECT_PLAN.md sections 4-5).
// Rules: synthesizable only, no initial blocks or delays, explicit reset,
// registered outputs on module boundaries, valid/ready on data ports.
// Parameter defaults come from dnn_pkg (referenced as dnn_pkg::NAME, not imported,
// so module parameters do not shadow package names).

module tile_ctrl
#(
  parameter int ROWS = dnn_pkg::ROWS,
  parameter int COLS = dnn_pkg::COLS
) (
  input  logic clk,
  input  logic rst_n
  // TODO: ports
);

  // TODO: implementation

endmodule : tile_ctrl
