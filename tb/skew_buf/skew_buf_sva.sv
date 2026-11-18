// Assertions for the shared-advance skew-buffer contract.
module skew_buf_sva #(
  parameter int ROWS = dnn_pkg::ROWS,
  parameter int DATA_W = dnn_pkg::DATA_W
) (
  input logic clk,
  input logic rst_n,
  input logic advance,
  input logic in_valid,
  input logic in_ready,
  input logic out_valid,
  input logic signed [DATA_W-1:0] out_data [ROWS]
);
  a_ready_tracks_advance: assert property (@(posedge clk) disable iff (!rst_n)
    in_ready == advance);

  a_valid_holds_when_stalled: assert property (@(posedge clk) disable iff (!rst_n)
    !advance |=> $stable(out_valid));

  for (genvar r = 0; r < ROWS; r++) begin : g_row_stall_assertions
    a_row_data_holds_when_stalled: assert property (@(posedge clk) disable iff (!rst_n)
      !advance |=> $stable(out_data[r]));
  end

  c_input_accepted: cover property (@(posedge clk) disable iff (!rst_n)
    advance && in_valid);

  c_valid_output: cover property (@(posedge clk) disable iff (!rst_n)
    out_valid);
endmodule : skew_buf_sva
