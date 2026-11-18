// out_stage_sva.sv - assertions for out_stage, bound to the DUT in tb_top.sv.

module out_stage_sva #(parameter int LANES = 2, parameter int DATA_W = 8) (
  input logic clk,
  input logic rst_n,
  input logic in_valid,
  input logic in_ready,
  input logic out_valid,
  input logic out_ready,
  input logic [LANES-1:0][DATA_W-1:0] out_data,
  input logic [LANES-1:0]  out_keep
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // the pipe moves as one: ready means "output register free or being read"
  a_ready_rule: assert property (in_ready == (!out_valid || out_ready));
  // a stalled output beat stays put until it is taken
  a_hold_valid: assert property (out_valid && !out_ready |=> out_valid);
  a_hold_data:  assert property (out_valid && !out_ready |=> $stable(out_data) && $stable(out_keep));
  // handshake signals are never X/Z out of reset
  a_known:      assert property (!$isunknown({in_ready, out_valid}));

  c_backpressure: cover property (out_valid && !out_ready);
  c_back_to_back: cover property (in_valid && in_ready ##1 in_valid && in_ready);
  c_partial_beat: cover property (out_valid && out_ready && out_keep != '1);
  c_sat_high:     cover property (out_valid && out_ready && out_keep[0] && $signed(out_data[0]) == 127);
  c_sat_low:      cover property (out_valid && out_ready && out_keep[0] && $signed(out_data[0]) == -128);
endmodule : out_stage_sva
