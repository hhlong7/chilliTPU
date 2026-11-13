// pe_if.sv - interface between the UVM env and the pe DUT.
// The driver changes inputs on the falling edge; the monitor samples on the
// rising edge (inputs about to be registered + outputs from the previous edge).

interface pe_if #(parameter int DATA_W = dnn_pkg::DATA_W, parameter int PSUM_W = dnn_pkg::PSUM_W)
                 (input logic clk);
  logic                     rst_n;
  logic                     en;
  logic                     w_load, w_swap;
  logic signed [DATA_W-1:0] w_in, w_out;
  logic                     mul_en_in, mul_en_out;
  logic signed [DATA_W-1:0] a_in, a_out;
  logic signed [PSUM_W-1:0] psum_in, psum_out;
endinterface : pe_if
