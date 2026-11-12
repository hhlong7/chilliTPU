// stream_if.sv - generic valid/ready stream interface used by stream_agent.
// Status: SKELETON.

interface stream_if #(parameter int W = 8) (input logic clk);
  logic         rst_n;
  logic         valid;
  logic         ready;
  logic [W-1:0] data;
  // TODO: clocking blocks and modports
endinterface : stream_if
