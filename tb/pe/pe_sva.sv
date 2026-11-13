// pe_sva.sv - assertions for pe (D4 timing), bound to the DUT in tb_top.sv.

module pe_sva #(parameter int DATA_W = 8, parameter int PSUM_W = 32) (
  input logic                     clk,
  input logic                     rst_n,
  input logic                     en,
  input logic                     w_load,
  input logic                     w_swap,
  input logic signed [DATA_W-1:0] w_in,
  input logic signed [DATA_W-1:0] w_out,
  input logic                     mul_en_in,
  input logic                     mul_en_out,
  input logic signed [DATA_W-1:0] a_in,
  input logic signed [DATA_W-1:0] a_out,
  input logic signed [PSUM_W-1:0] psum_in,
  input logic signed [PSUM_W-1:0] psum_out
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // stall: en low freezes the datapath outputs
  a_stall_holds:  assert property (!en |=> $stable(a_out) && $stable(psum_out) && $stable(mul_en_out));
  // one-cycle hops
  a_a_hop:        assert property (en |=> a_out == $past(a_in));
  a_mul_en_hop:   assert property (en |=> mul_en_out == $past(mul_en_in));
  // Mul_En low: the partial sum passes through unchanged
  a_gate_passes:  assert property (en && !mul_en_in |=> psum_out == $past(psum_in));
  // weight chain: shifts on w_load (even during a stall), holds otherwise
  a_w_shift:      assert property (w_load |=> w_out == $past(w_in));
  a_w_hold:       assert property (!w_load |=> $stable(w_out));

  c_stall:          cover property (!en);
  c_gate_off:       cover property (en && !mul_en_in);
  c_load_and_swap:  cover property (w_load && w_swap);
  c_load_in_stall:  cover property (w_load && !en);
  c_neg_product:    cover property (en && mul_en_in && a_in == -128 && w_out != 0);
endmodule : pe_sva
