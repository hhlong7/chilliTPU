// axil_if.sv - AXI4-Lite interface used by axil_agent.
// Status: SKELETON.

interface axil_if #(parameter int ADDR_W = 12, parameter int DATA_W = 32) (input logic clk);
  logic                  rst_n;
  // write address
  logic [ADDR_W-1:0]     awaddr;  logic awvalid, awready;
  // write data
  logic [DATA_W-1:0]     wdata;   logic [DATA_W/8-1:0] wstrb; logic wvalid, wready;
  // write response
  logic [1:0]            bresp;   logic bvalid, bready;
  // read address
  logic [ADDR_W-1:0]     araddr;  logic arvalid, arready;
  // read data
  logic [DATA_W-1:0]     rdata;   logic [1:0] rresp; logic rvalid, rready;
  // TODO: clocking blocks and modports
endinterface : axil_if
