// out_stage.sv - fused output stage: bias, ReLU, requantize (round half up), saturate to INT8.
//
// Implements the frozen D1 rule exactly (must match sw/py/golden.py requantize):
//   s   = acc + bias                        33-bit, no wraparound
//   r   = relu ? max(s, 0) : s
//   p   = r * scale                         scale is UNSIGNED 16-bit
//   q   = shift > 0 ? (p + (1 << (shift-1))) >>> shift : p     (round half up, toward +inf)
//   out = clamp(q, -128, 127)
//
// D2: LANES (= OUT_LANES = 2) requantize lanes. Columns stream through them one
// beat at a time during drain. keep[i] = 1 marks lane i as a real column (for an
// odd width the last beat has keep = 2'b01); keep passes through unchanged.
//
// Pipeline (3 register stages, latency 3):
//   S1  r = relu(acc + bias)        33-bit add
//   S2  p = r * scale               33 x 17 signed multiply (2 DSP48E1 per lane)
//   S3  out = clamp(round(p))       rounding add, arithmetic shift, saturate
// scale/shift/relu are sampled with each input beat and travel down the pipe with
// the data, so a settings change between layers never mixes two layers' values.
//
// Handshake: valid/ready on both sides. The whole pipe advances together when the
// output register is empty or being read (adv). in_ready = adv is the one
// combinational output (a single gate from out_ready); everything else is registered.
//
// Rules: synthesizable only, no initial blocks or delays, synchronous active-low
// reset. Parameter defaults come from dnn_pkg.


module out_stage#(
  parameter int LANES = dnn_pkg::OUT_LANES,
  parameter int ACC_W = dnn_pkg::ACC_W,
  parameter int BIAS_W = dnn_pkg::BIAS_W,
  parameter int SCALE_W = dnn_pkg::SCALE_W,
  parameter int SHIFT_W = dnn_pkg::SHIFT_W,
  parameter int DATA_W = dnn_pkg::DATA_W
)(
  input logic clk,
  input logic rst_n,
  
  // per layer settings
  input logic [SCALE_W-1:0] scale,
  input logic [SHIFT_W-1:0] shift,
  input logic relu,

  // input stream: one acc + bias per lane
  input logic in_valid,
  output logic in_ready,
  input logic [LANES-1:0][ACC_W-1:0] in_acc,
  input logic [LANES-1:0][BIAS_W-1:0] in_bias,
  input logic [LANES-1:0] in_keep,

  // output stream: one INT8 per lane
  output logic out_valid,
  input logic out_ready,
  output logic [LANES-1:0][DATA_W-1:0] out_data,
  output logic [LANES-1:0] out_keep
);

  localparam int S_W = ((ACC_W > BIAS_W) ? ACC_W : BIAS_W) + 1;
  localparam int P_W = S_W + SCALE_W + 1;

  localparam logic signed [P_W-1:0] OUT_MAX = P_W'((1 << (DATA_W - 1)) - 1); // 127
  localparam logic signed [P_W-1:0] OUT_MIN = P_W'(-(1 << (DATA_W - 1))); // -128

  // pipe control: everything moves when the output reg
  // is free or being read
  logic adv;
  assign adv = !out_valid || out_ready;
  assign in_ready = adv;

  // stage registers
  logic v1, v2;
  logic [LANES-1:0] k1, k2;
  logic [SCALE_W-1:0] scale1;
  logic [SHIFT_W-1:0] shift1, shift2;
  logic signed [S_W-1:0] r1[LANES];
  logic signed [P_W-1:0] p2[LANES];

  // combination per lane values
  logic signed [S_W-1:0] s_c[LANES];
  logic signed [P_W-1:0] q_c[LANES];
  logic signed [P_W-1:0] rnd2;

  assign rnd2 = (shift2 == '0) ? '0 : (P_W'(1) << (shift2 - 1'b1));

  for(genvar i = 0; i < LANES; i++) begin: g_lane
    assign s_c[i] = S_W'($signed(in_acc[i])) + S_W'($signed(in_bias[i]));
    assign q_c[i] = (p2[i] + rnd2) >>> shift2;
  end

  function automatic logic signed [DATA_W-1:0] sat(input logic signed [P_W-1:0] q);
    if(q > OUT_MAX) return OUT_MAX[DATA_W-1:0];
    if(q < OUT_MIN) return OUT_MIN[DATA_W-1:0];
    
    return q[DATA_W-1:0];
  endfunction

  
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      v1 <= 1'b0; v2 <= 1'b0; out_valid <= 1'b0;
      k1 <= '0; k2 <= '0; out_keep <= '0;
      scale1 <= '0; shift1 <= '0; shift2 <= '0;
      out_data <= '0;

      for(int i = 0; i < LANES; i++) begin
        r1[i] <= '0; p2[i] <= '0;
      end
    end else if(adv) begin
      v1 <= in_valid; k1 <= in_keep; scale1 <= scale; shift1 <= shift;
      
      for(int i = 0; i < LANES; i++)
        r1[i] <= (relu && s_c[i][S_W-1]) ? '0 : s_c[i];

      v2 <= v1; k2 <= k1; shift2 <= shift1;
      for(int i = 0; i < LANES; i++)
        p2[i] <= r1[i] * $signed({1'b0, scale1});

      out_valid <= v2; out_keep <= k2;
      for(int i = 0; i < LANES; i++)
        out_data[i] <= sat(q_c[i]);
    end
  end

endmodule: out_stage
