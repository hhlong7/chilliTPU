// accum_mem_if.sv - interface between the UVM env and the accum_mem DUT.
// The driver changes inputs on the falling edge; the monitor samples on the rising edge,
// where a beat transfers if valid && ready.

interface accum_mem_if #(parameter int COLS = dnn_pkg::COLS, parameter int ACC_W = dnn_pkg::ACC_W,
                         parameter int ADDR_W = 6) (input logic clk);
  logic                    rst_n;
  // input stream (from deskew_buf / tile_ctrl)
  logic                    in_valid, in_ready;
  logic [ADDR_W-1:0]       in_addr;
  logic                    in_first, in_last;
  logic signed [ACC_W-1:0] in_data [COLS];
  // output stream (to out_stage)
  logic                    out_valid, out_ready;
  logic [ADDR_W-1:0]       out_addr;
  logic signed [ACC_W-1:0] out_data [COLS];
  // sticky overflow flag
  logic                    ovf_clr, ovf;
endinterface : accum_mem_if
