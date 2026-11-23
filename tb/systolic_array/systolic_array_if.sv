// The driver writes on falling edges. The monitor samples before rising-edge updates.
interface systolic_array_if (input logic clk);
  logic rst_n = 0;
  logic advance, feed_valid, deskew_in_valid, w_load, w_swap;
  logic feed_ready, deskew_ready, skew_valid, deskew_valid;
  logic [dnn_pkg::COLS-1:0] mul_en;
  dnn_pkg::data_t x [dnn_pkg::ROWS];
  dnn_pkg::data_t weights [dnn_pkg::COLS];
  dnn_pkg::psum_t result [dnn_pkg::COLS];
endinterface : systolic_array_if
