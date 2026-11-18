// out_stage_if.sv - interface between the UVM env and the out_stage DUT.
// The driver changes inputs on the falling edge; the monitor samples on the
// rising edge (the values the DUT is about to register).

interface out_stage_if #(
  parameter int LANES = dnn_pkg::OUT_LANES,
  parameter int ACC_W = dnn_pkg::ACC_W,
  parameter int BIAS_W  = dnn_pkg::BIAS_W,
  parameter int SCALE_W = dnn_pkg::SCALE_W,
  parameter int SHIFT_W = dnn_pkg::SHIFT_W,
  parameter int DATA_W  = dnn_pkg::DATA_W
)(input logic clk);
  logic rst_n;
  logic [SCALE_W-1:0] scale;
  logic [SHIFT_W-1:0] shift;
  logic relu;
  logic in_valid, in_ready;
  logic [LANES-1:0][ACC_W-1:0] in_acc;
  logic [LANES-1:0][BIAS_W-1:0] in_bias;
  logic [LANES-1:0] in_keep;
  logic out_valid, out_ready;
  logic [LANES-1:0][DATA_W-1:0] out_data;
  logic [LANES-1:0] out_keep;

endinterface: out_stage_if
  