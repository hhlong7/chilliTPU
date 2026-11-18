// bram_sdp_if.sv - interface between the UVM env and the bram_sdp DUT.
// The driver changes inputs on the falling edge; the monitor samples on the rising edge.

interface bram_sdp_if #(parameter int DATA_W = 32, parameter int ADDR_W = 4) (input logic clk);
  logic              rst_n;
  logic              wr_en;
  logic [ADDR_W-1:0] wr_addr;
  logic [DATA_W-1:0] wr_data;
  logic              rd_en;
  logic [ADDR_W-1:0] rd_addr;
  logic [DATA_W-1:0] rd_data;
  logic              rd_valid;
endinterface : bram_sdp_if
