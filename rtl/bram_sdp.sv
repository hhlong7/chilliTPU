// bram_sdp.sv - simple dual-port BRAM wrapper (one write port, one read port) for weight, feed, and drain buffers.
//
// Status: SKELETON. Ports and behavior are TBD (see PROJECT_PLAN.md sections 4-5).
// Rules: synthesizable only, no initial blocks or delays, explicit reset,
// registered outputs on module boundaries, valid/ready on data ports.
// Parameter defaults come from dnn_pkg (referenced as dnn_pkg::NAME, not imported,
// so module parameters do not shadow package names).

module bram_sdp
#(
  parameter int DATA_W = 32,
  parameter int DEPTH  = 1024
) (
  input  logic clk,
  input  logic rst_n
  // TODO: ports
);

  // TODO: implementation

endmodule : bram_sdp
