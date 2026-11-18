// accum_mem.sv - adds partial sums across K tiles in INT32; flags overflow.
//
// Status: SKELETON. Ports and behavior are TBD (see PROJECT_PLAN.md sections 4-5).
// Rules: synthesizable only, no initial blocks or delays, explicit reset,
// registered outputs on module boundaries, valid/ready on data ports.
// Parameter defaults come from dnn_pkg (referenced as dnn_pkg::NAME, not imported,
// so module parameters do not shadow package names).

// accum_mem.sv - accumulates the array's column sums across K tiles in INT32.
//
// One input beat = one output row m of one K tile: COLS INT32 sums (from deskew_buf)
// plus tags from tile_ctrl: the row address, and whether this is the first and/or
// last K tile of the current N tile (D3: K tiles inner).
//   first = 1        : the row starts fresh (memory not read)
//   first = 0        : the row is added to the partial sum stored for that address
//   last  = 0        : the new partial sum is written back to memory
//   last  = 1        : the finished row goes out to out_stage (not written back)
//   first = last = 1 : K <= ROWS, the row passes straight through
//
// Pipeline (1 row per cycle when out_ready stays high):
//   accept   : in_valid && in_ready; issue the memory read for in_addr
//   stage 1  : old value arrives; sum = old + in (or in if first); write back or emit
//   out reg  : finished rows, valid/ready to out_stage (registered outputs)
// Back-to-back rows to the same address are handled by forwarding the value being
// written (the RAM is read-first, so it would otherwise return the stale value).
//
// Overflow: sums wrap at 32 bits like the RTL adders; any INT32 overflow sets the
// sticky ovf flag (cleared by ovf_clr; a new overflow in the same cycle wins).
// golden.matmul_int8 treats overflow as an error, so ovf=1 means a bad layer setup.


module accum_mem
#(
  parameter int COLS = dnn_pkg::COLS,
  parameter int ACC_W = dnn_pkg::ACC_W,
  parameter int DEPTH = 1024, //for max M rows per tile
  parameter int ADDR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1
) (
  input logic clk,
  input logic rst_n,

  //rows in (deskw_buf data and tile_ctrl tags)
  input logic in_valid,
  output logic in_ready,
  
  input logic [ADDR_W-1:0] in_addr,
  input logic in_first,
  input logic in_last,
  input logic signed [ACC_W-1:0] in_data [COLS],

  //finished rows out (to out-stage)
  output logic out_valid,
  input logic out_ready,
  output logic [ADDR_W-1:0] out_addr,
  output logic signed [ACC_W-1:0] out_data [COLS],

  //overflow status=> to axil_regs
  input logic ovf_clr,
  output logic ovf
);

  localparam int ROW_W = COLS * ACC_W; //one memory word = one whole row

  //memory
  logic rd_en, wr_en, rd_valid_unused;
  logic [ROW_W-1:0] rd_row, wr_row;
  logic [ADDR_W-1:0] wr_addr;

  bram_sdp #(.DATA_W(ROW_W), .DEPTH(DEPTH), .ADDR_W(ADDR_W)) 
  u_mem (.clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_addr(wr_addr), 
        .wr_data(wr_row), .rd_en(rd_en), .rd_addr(in_addr), 
        .rd_data(rd_row), .rd_valid(rd_valid_unused));
  
  //handshake
  logic s1_valid, s1_first, s1_last, s1_fwd;
  logic [ADDR_W-1:0] s1_addr;
  logic signed [ACC_W-1:0] s1_data [COLS];
  logic [ROW_W-1:0] s1_fwd_row;
  logic s1_go, accept;

  //s1_go: stage 1 finishes this cycle, a non last row always finishes, bc writing to memory never blocks
  //       a last row needs room in the output register: either its empty (!out_valid) or its emptying this cycle =>out_ready
  //in ready: a new row can come in if stage 1 is empty or is finishing
  //accept: the standard valid/ready rule, a transfer happens when both are high
  //rd_en: read only when the old value is needed

  //stage 1 can finish unless it is a last row an the output register is ful
  assign s1_go = s1_valid && (!s1_last || !out_valid || out_ready);
  assign in_ready = !s1_valid || s1_go;
  assign accept = in_valid && in_ready;
  assign rd_en = accept && !in_first; //first tile never needs the old value

  //add
  logic [ROW_W-1:0] old_row, sum_row;
  logic signed [ACC_W-1:0] sum [COLS];
  logic [COLS-1:0] col_ovf;

  assign old_row = s1_fwd ? s1_fwd_row : rd_row; //fwd value beats the stale ram read

  for (genvar c = 0; c < COLS; c++) begin : g_col
    logic [ACC_W-1:0] old_v;
    logic [ACC_W:0] wide; //extra btit for overflow
    assign old_v = s1_first ? '0 : old_row[c*ACC_W +: ACC_W];
    assign wide = {old_v[ACC_W-1], old_v} + {s1_data[c][ACC_W-1], s1_data[c]}; //unpacking the row => starting at bit c * 32, take 32 bits
    assign sum[c] = wide[ACC_W-1:0];
    assign col_ovf[c] = wide[ACC_W] ^ wide[ACC_W-1]; //sign bits disagree -> ovf
    assign sum_row[c*ACC_W +: ACC_W] = wide[ACC_W-1:0]; //repacking, put the 12 results back into one 384 bit word (32*12) for writing
  end

  assign wr_en = s1_go && !s1_last;
  assign wr_addr = s1_addr;
  assign wr_row = sum_row;

  //registers (pipeline)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s1_valid <= 1'b0;
      s1_first <= 1'b0;
      s1_last <= 1'b0; 
      s1_fwd <= 1'b0;
      s1_addr <= '0;
      s1_data <= '{default: '0};
      s1_fwd_row <= '0;
    end else if (accept) begin
      s1_valid <= 1'b1;
      s1_first <= in_first;
      s1_last <= in_last;
      s1_addr <= in_addr;
      s1_data <= in_data;
      s1_fwd <= wr_en && (wr_addr == in_addr);
      s1_fwd_row <= sum_row;
    end else if (s1_go) begin
      s1_valid <= 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      out_valid <= 1'b0;
      out_addr <= '0;
      out_data <= '{default: '0};
    end else if (s1_go && s1_last) begin
      out_valid <= 1'b1;
      out_addr <= s1_addr;
      out_data <= sum;
    end else if (out_ready) begin
      out_valid <= 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) 
      ovf <= 1'b0;
    else
      ovf <= (ovf && !ovf_clr) || (s1_go && |col_ovf); //overflow flag
  end

endmodule : accum_mem


// The array is only 12 rows tall, so a layer with K = 150 (LeNet conv2) is split into 13 K tiles (D3). Each K tile produces part of every output row’s dot product, and accum_mem adds those parts together:

// First K tile: store the result.
// Middle tiles: read the stored value, add the new part, write it back.
// Last tile: add, then send the finished row to out_stage instead of storing it.

// Design choice: no separate read-out phase. The final sum goes straight to out_stage on the last tile, so tile_ctrl never has to run a read-out pass. That saves M cycles per N tile, and keeps accum_mem to just one input stream and one output stream.
