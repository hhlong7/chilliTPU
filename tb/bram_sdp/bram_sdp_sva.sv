// bram_sdp_sva.sv - assertions for bram_sdp, bound to the DUT in tb_top.sv.

module bram_sdp_sva #(parameter int DATA_W = 32, parameter int ADDR_W = 4) (
  input logic              clk,
  input logic              rst_n,
  input logic              wr_en,
  input logic [ADDR_W-1:0] wr_addr,
  input logic              rd_en,
  input logic [ADDR_W-1:0] rd_addr,
  input logic [DATA_W-1:0] rd_data,
  input logic              rd_valid
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // read latency is exactly 1: rd_valid is rd_en delayed by one cycle
  a_valid_latency: assert property (rd_valid == $past(rd_en));
  // no read: rd_data holds its last value (out_stage / tile_ctrl may rely on this)
  a_hold:          assert property (!rd_en |=> $stable(rd_data));

  c_same_addr_rw:  cover property (wr_en && rd_en && wr_addr == rd_addr);   // read-first case
  c_b2b_reads:     cover property (rd_en ##1 rd_en);
  c_hold:          cover property (rd_valid ##1 (rd_en == 1'b0) [*3]);
endmodule : bram_sdp_sva
