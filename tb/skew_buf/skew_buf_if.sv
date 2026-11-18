// Interface between the UVM environment and skew_buf.
interface skew_buf_if #(parameter int ROWS = dnn_pkg::ROWS,
                        parameter int DATA_W = dnn_pkg::DATA_W)
                       (input logic clk);
  logic rst_n;
  logic advance;
  logic in_valid;
  logic in_ready;
  logic signed [DATA_W-1:0] in_data [ROWS];
  logic out_valid;
  logic signed [DATA_W-1:0] out_data [ROWS];
endinterface : skew_buf_if
