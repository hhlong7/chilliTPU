// accum_mem_sva.sv - assertions for accum_mem, bound to the DUT in tb_top.sv.
// Bound with .*, so it can also see DUT internals by name (s1_valid, s1_go, s1_fwd, col_ovf).

module accum_mem_sva #(parameter int COLS = 12, parameter int ACC_W = 32, parameter int ADDR_W = 6) (
  input logic                    clk,
  input logic                    rst_n,
  input logic                    in_valid,
  input logic                    in_ready,
  input logic [ADDR_W-1:0]       in_addr,
  input logic                    in_first,
  input logic                    in_last,
  input logic                    out_valid,
  input logic                    out_ready,
  input logic [ADDR_W-1:0]       out_addr,
  input logic signed [ACC_W-1:0] out_data [COLS],
  input logic                    ovf_clr,
  input logic                    ovf,
  // DUT internals
  input logic                    s1_valid,
  input logic                    s1_go,
  input logic                    s1_fwd,
  input logic [COLS-1:0]         col_ovf
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // flatten out_data so $stable can compare it in one go
  logic [COLS*ACC_W-1:0] out_flat;
  for (genvar c = 0; c < COLS; c++) begin : g_flat
    assign out_flat[c*ACC_W +: ACC_W] = out_data[c];
  end

  // output stream rule: once valid, hold valid and data until ready
  a_out_hold:     assert property (out_valid && !out_ready |=> out_valid && $stable(out_addr) && $stable(out_flat));
  // input stream rule (checks the driver now, tile_ctrl later): same thing on the input side
  a_in_hold:      assert property (in_valid && !in_ready |=> in_valid && $stable(in_addr) && $stable(in_first) && $stable(in_last));
  // stage 1 empty means the input is always ready
  a_ready_empty:  assert property (!s1_valid |-> in_ready);
  // ovf is sticky: only ovf_clr can lower it
  a_ovf_sticky:   assert property (ovf && !ovf_clr |=> ovf);
  // ovf_clr lowers it unless a new overflow arrives in the same cycle (set wins)
  a_ovf_clear:    assert property (ovf_clr && !(s1_go && |col_ovf) |=> !ovf);
  a_ovf_set:      assert property (s1_go && |col_ovf |=> ovf);

  c_forward:      cover property (s1_valid && s1_fwd && s1_go);   // back-to-back same address
  c_out_stall:    cover property (out_valid && !out_ready);
  c_in_stall:     cover property (in_valid && !in_ready);
  c_ovf:          cover property (s1_go && |col_ovf);
  c_clr_and_set:  cover property (ovf_clr && s1_go && |col_ovf);
endmodule : accum_mem_sva
