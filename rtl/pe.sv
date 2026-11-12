// pe.sv - one processing element: holds a weight, multiplies the incoming input (DSP), adds the partial sum from above, passes the input right. Mul_En gate: when low, adds zero and still forwards the input.
//
// Status: SKELETON. Ports and behavior are TBD (see PROJECT_PLAN.md sections 4-5).
// Rules: synthesizable only, no initial blocks or delays, explicit reset,
// registered outputs on module boundaries, valid/ready on data ports.
// Parameter defaults come from dnn_pkg (referenced as dnn_pkg::NAME, not imported,
// so module parameters do not shadow package names).

module pe
#(
  parameter int PSUM_W = dnn_pkg::PSUM_W
) (
  input  logic clk,
  input  logic rst_n
  // TODO: ports
);

  // TODO: implementation

endmodule : pe
