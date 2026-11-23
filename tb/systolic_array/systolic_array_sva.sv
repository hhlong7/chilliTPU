// Check the shared enable at the boundaries of the assembled array core.
module systolic_array_sva (
  input logic clk, rst_n, advance,
  input logic feed_ready, deskew_ready, feed_valid, skew_valid, deskew_valid,
  input dnn_pkg::psum_t result [dnn_pkg::COLS]
);
  a_ready: assert property (@(posedge clk) disable iff (!rst_n)
    (feed_ready == advance) && (deskew_ready == advance));
  a_valid_holds: assert property (@(posedge clk) disable iff (!rst_n)
    !advance |=> $stable(skew_valid) && $stable(deskew_valid));
  for (genvar c = 0; c < dnn_pkg::COLS; c++) begin : g_hold
    a_data_holds: assert property (@(posedge clk) disable iff (!rst_n)
      !advance |=> $stable(result[c]));
  end
  c_feed: cover property (@(posedge clk) disable iff (!rst_n) advance && feed_valid);
  c_drain: cover property (@(posedge clk) disable iff (!rst_n) advance && deskew_valid);
  c_stall_with_result: cover property (@(posedge clk) disable iff (!rst_n)
    !advance && deskew_valid);
endmodule : systolic_array_sva
