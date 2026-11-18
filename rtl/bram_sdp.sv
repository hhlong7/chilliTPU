// bram_sdp.sv - simple dual-port BRAM wrapper (one write port, one read port) for weight, feed, and drain buffers.
//
// Used for the weight, feed, and drain buffers and inside accum_mem.

// Status: SKELETON. Ports and behavior are TBD (see PROJECT_PLAN.md sections 4-5).
// Rules: synthesizable only, no initial blocks or delays, explicit reset,
// registered outputs on module boundaries, valid/ready on data ports.
// Parameter defaults come from dnn_pkg (referenced as dnn_pkg::NAME, not imported,
// so module parameters do not shadow package names).


// Behavior:
//   write: wr_en=1 -> mem[wr_addr] <= wr_data at the clock edge
//   read:  rd_en=1 -> rd_data = mem[rd_addr] one cycle later (read latency 1).
//          rd_data holds its value while rd_en=0 (callers can stall without losing it).
//   same address, same cycle: the read returns the OLD value (read-first).
//   rd_valid = rd_en delayed one cycle (convenience; reset to 0).

module bram_sdp
#(
  parameter int DATA_W = 32,
  parameter int DEPTH = 1024,
  parameter int ADDR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1
) (
  input logic clk,
  input logic rst_n,
  //write ins
  input logic wr_en,
  input logic [ADDR_W-1:0] wr_addr,
  input logic [DATA_W-1:0] wr_data,
  //read ins
  input logic rd_en,
  input logic [ADDR_W-1:0] rd_addr,
  
  output logic [DATA_W-1:0] rd_data,
  output logic rd_valid

);
  //this tells vivado to use block ram on the fpga board
  (* ram_style = "block" *) logic [DATA_W-1:0] mem [DEPTH]; //memory array, depth words of data_w bits each

  //memory: no rest, both ports in one block so read during write is read first

  //read and write logic
  always_ff @(posedge clk) begin
    if (wr_en) 
      mem[wr_addr] <= wr_data;
    if (rd_en)
      rd_data <= mem[rd_addr];
  end

  always_ff @(posedge clk) begin
    if (!rst_n) 
      rd_valid <= 1'b0;
    else
      rd_valid <= rd_en;
  end

endmodule : bram_sdp


//A RAM with one port that only writes and one that only reads, both on the same clock. 
//That’s called “simple dual-port” (SDP). 
//It’s the building block for every buffer in the design (weights, X feed, output drain) 
//and for accum_mem. A dual port lets one side fill a buffer while the other side 
//reads it in the same cycle.
