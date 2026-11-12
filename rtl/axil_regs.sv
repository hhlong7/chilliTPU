// axil_regs.sv - AXI-Lite slave: layer queue, start/done, cycle counters. Register map generated from spec/regmap.yaml.
//
// Status: SKELETON. Ports and behavior are TBD (see PROJECT_PLAN.md sections 4-5).
// Rules: synthesizable only, no initial blocks or delays, explicit reset,
// registered outputs on module boundaries, valid/ready on data ports.
// Parameter defaults come from dnn_pkg (referenced as dnn_pkg::NAME, not imported,
// so module parameters do not shadow package names).

module axil_regs
#(
  parameter int ADDR_W = 12,
  parameter int DATA_W = 32
) (
  input  logic clk,
  input  logic rst_n
  // TODO: ports
);

  // TODO: implementation

endmodule : axil_regs
