interface deskew_buf_if #(parameter int COLS=dnn_pkg::COLS,
                          parameter int DATA_W=dnn_pkg::PSUM_W)(input logic clk);
  logic rst_n, advance, in_valid, in_ready, out_valid;
  logic signed [DATA_W-1:0] in_data[COLS];
  logic signed [DATA_W-1:0] out_data[COLS];
endinterface
