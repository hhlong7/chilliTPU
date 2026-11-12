// out_stage.sv - fused output stage: bias, ReLU, requantize with rounding and saturation to INT8.
//
// Status: SKELETON. Ports and behavior are TBD (see PROJECT_PLAN.md sections 4-5).
// Rules: synthesizable only, no initial blocks or delays, explicit reset,
// registered outputs on module boundaries, valid/ready on data ports.
// Parameter defaults come from dnn_pkg (referenced as dnn_pkg::NAME, not imported,
// so module parameters do not shadow package names).

module out_stage
#(
  parameter int COLS = dnn_pkg::COLS
) (
  input  logic clk,
  input  logic rst_n
  // TODO: ports
);

  // TODO: implementation

endmodule : out_stage
