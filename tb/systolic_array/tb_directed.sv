// Standalone datapath regression; the UVM environment is separate.
// From the repo root (Bash):
//   mkdir -p build/systolic_array
//   iverilog -g2012 -s tb_systolic_array_directed -o build/systolic_array/directed.vvp \
//     rtl/pkg/dnn_pkg.sv rtl/pe.sv rtl/systolic_array.sv tb/systolic_array/tb_directed.sv
//   vvp build/systolic_array/directed.vvp
module tb_systolic_array_directed #(
  parameter int ROWS = 3,
  parameter int COLS = 2,
  parameter int DATA_W = 8,
  parameter int PSUM_W = 32
);
  timeunit 1ns;
  timeprecision 1ps;

  localparam int SAMPLES = 7;
  typedef logic signed [DATA_W-1:0] data_t;
  typedef logic signed [PSUM_W-1:0] psum_t;

  logic clk = 0;
  logic rst_n = 0, en = 0, w_load = 0, w_swap = 0;
  data_t w_in [0:COLS-1];
  wire signed [DATA_W-1:0] w_out [0:COLS-1];
  data_t a_in [0:ROWS-1];
  wire signed [DATA_W-1:0] a_out [0:ROWS-1];
  logic [COLS-1:0] mul_en_in = '0;
  wire [COLS-1:0] mul_en_out;
  wire signed [PSUM_W-1:0] psum_out [0:COLS-1];

  always #5 clk = ~clk;

  systolic_array #(
    .ROWS(ROWS), .COLS(COLS), .DATA_W(DATA_W), .PSUM_W(PSUM_W)
  ) dut (.*);

  function automatic int activation(input int sample, row);
    if (sample < 0 || sample >= SAMPLES) return 0;
    if (sample == 0)
      return row % 2 == 0 ? -(1 << (DATA_W-1)) : (1 << (DATA_W-1))-1;
    return (sample * 5 + row * 3) % 11 - 5;
  endfunction

  function automatic int weight(input int tile, row, col);
    if (tile == 2) return 0;  // reset leaves active weights zero
    if (tile == 0 && row == 0) return -(1 << (DATA_W-1));
    if (tile == 1 && row == ROWS-1) return (1 << (DATA_W-1))-1;
    return (tile * 7 + row * 3 + col * 5) % 9 - 4;
  endfunction

  function automatic bit gate(input int sample, col);
    return sample >= 0 && sample < SAMPLES && (sample + col) % 3 != 1;
  endfunction

  // Mathematical dot product, independent of the PE implementation.
  function automatic psum_t expected_sum(input int tile, sample, col);
    int total;
    total = 0;
    if (gate(sample, col))
      for (int r = 0; r < ROWS; r++)
        total += activation(sample, r) * weight(tile, r, col);
    return psum_t'(total);
  endfunction

  // Called after inputs change on a falling edge; sample after NBA updates.
  task automatic step(input bit check_hold);
    data_t held_a [0:ROWS-1];
    psum_t held_p [0:COLS-1];
    logic [COLS-1:0] held_m;
    for (int r = 0; r < ROWS; r++) held_a[r] = a_out[r];
    for (int c = 0; c < COLS; c++) held_p[c] = psum_out[c];
    held_m = mul_en_out;
    @(posedge clk);
    #1;
    if (check_hold) begin
      for (int r = 0; r < ROWS; r++)
        if (a_out[r] !== held_a[r]) $fatal(1, "activation changed during stall");
      for (int c = 0; c < COLS; c++)
        if (psum_out[c] !== held_p[c]) $fatal(1, "partial sum changed during stall");
      if (mul_en_out !== held_m) $fatal(1, "Mul_En changed during stall");
    end
  endtask

  task automatic reset_core;
    @(negedge clk);
    rst_n = 0;
    en = 0;
    w_load = 0;
    w_swap = 0;
    mul_en_in = '0;
    for (int r = 0; r < ROWS; r++) a_in[r] = '0;
    for (int c = 0; c < COLS; c++) w_in[c] = '0;
    step(0);
    for (int r = 0; r < ROWS; r++)
      if (a_out[r] !== '0) $fatal(1, "activation reset failed");
    for (int c = 0; c < COLS; c++)
      if (psum_out[c] !== '0 || w_out[c] !== '0)
        $fatal(1, "partial sum or weight reset failed");
    if (mul_en_out !== '0) $fatal(1, "Mul_En reset failed");
    @(negedge clk);
    rst_n = 1;
  endtask

  task automatic check_bottom_weights(input int tile);
    for (int c = 0; c < COLS; c++)
      if (w_out[c] !== data_t'(weight(tile, ROWS-1, c)))
        $fatal(1, "weight chain col=%0d got=%0d expected=%0d",
               c, w_out[c], weight(tile, ROWS-1, c));
  endtask

  task automatic load_first_tile;
    // The entire shadow chain must fill in exactly ROWS clocks, even with en=0.
    for (int r = ROWS-1; r >= 0; r--) begin
      @(negedge clk);
      en = 0;
      w_load = 1;
      for (int c = 0; c < COLS; c++) w_in[c] = data_t'(weight(0, r, c));
      step(1);
    end
    check_bottom_weights(0);
    @(negedge clk);
    w_load = 0;
    w_swap = 1;
    step(1);
    @(negedge clk);
    w_swap = 0;
  endtask

  task automatic stream_tile(input int tile, input bit preload_next);
    int sample;
    for (int t = 0; t < SAMPLES + ROWS + COLS - 2; t++) begin
      if (t % 3 == 1) begin
        @(negedge clk);
        en = 0;
        w_load = 0;
        mul_en_in = '1;
        for (int r = 0; r < ROWS; r++) a_in[r] = data_t'(13);
        step(1);
      end

      @(negedge clk);
      en = 1;
      w_load = preload_next && t < ROWS;
      for (int c = 0; c < COLS; c++) begin
        mul_en_in[c] = gate(t-c, c);  // align gates with horizontal travel
        w_in[c] = data_t'(weight(1, ROWS-1-t, c));
      end
      for (int r = 0; r < ROWS; r++) a_in[r] = data_t'(activation(t-r, r));
      step(0);

      for (int c = 0; c < COLS; c++) begin
        sample = t - (ROWS-1) - c;
        if (psum_out[c] !== expected_sum(tile, sample, c))
          $fatal(1, "tile=%0d t=%0d col=%0d got=%0d expected=%0d",
                 tile, t, c, psum_out[c], expected_sum(tile, sample, c));
        if (mul_en_out[c] !== gate(sample, c))
          $fatal(1, "Mul_En alignment failed at t=%0d col=%0d", t, c);
      end
      for (int r = 0; r < ROWS; r++)
        if (a_out[r] !== data_t'(activation(t-r-(COLS-1), r)))
          $fatal(1, "activation forwarding failed at t=%0d row=%0d", t, r);
    end
  endtask

  initial begin
    reset_core();
    load_first_tile();
    stream_tile(0, 1);  // active weights must survive concurrent shadow loads
    check_bottom_weights(1);

    // Simultaneous load+swap must activate the OLD shadow weights.
    @(negedge clk);
    en = 0;
    w_load = 1;
    w_swap = 1;
    for (int c = 0; c < COLS; c++) w_in[c] = '0;
    step(1);
    @(negedge clk);
    w_load = 0;
    w_swap = 0;
    stream_tile(1, 0);

    reset_core();
    stream_tile(2, 0);
    $display("PASS systolic_array.directed seed=1 ROWS=%0d COLS=%0d DATA_W=%0d PSUM_W=%0d",
             ROWS, COLS, DATA_W, PSUM_W);
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "test timed out");
  end
endmodule : tb_systolic_array_directed
