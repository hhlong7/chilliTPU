// systolic_array.sv - ROWS x COLS grid of PEs (weight-stationary). Rows = K, columns = N.
//
// Status: SKELETON. Ports and behavior are TBD (see PROJECT_PLAN.md sections 4-5).
// Rules: synthesizable only, no initial blocks or delays, explicit reset,
// registered outputs on module boundaries, valid/ready on data ports.
// Parameter defaults come from dnn_pkg (referenced as dnn_pkg::NAME, not imported,
// so module parameters do not shadow package names).

module systolic_array
#(
  parameter int ROWS = dnn_pkg::ROWS,
  parameter int COLS = dnn_pkg::COLS
) (
  input  logic clk,
  input  logic rst_n,
  input logic w_load,
  input logic [31:0] w_data, //Variable based on number of PEs
  input logic w_load,
  input logic w_valid,

);

logic [31:0]psum_out;
logic [31:0]a_in;
logic [31:0]a_out;
logic mul_en_out;
logic w_load;
logic w_data;
logic w_valid;


integer i, j;
generate
  for (i = 0; i < ROWS; i++) begin : row_loop
    for (j = 0; j < COLS; j++) begin : col_loop
      pe #(
        .DATA_W(dnn_pkg::DATA_W),
        .PSUM_W(dnn_pkg::PSUM_W)
      ) pe_inst (
        .clk(clk),
        .rst_n(rst_n),
        .w_load(w_load), 
        .w_data(w_data), 
        .w_valid(w_valid),

        //Data Shifted Left -> Right
        .a_in(a_in[i][j]),
        .a_out(a_out[i][j-1]),
        .en(en),
        
        //Data Shifted Vertically Down
        .mul_en_in(mul_en_out[i-1][j]),
        .mul_en_out(mul_en_out[i][j]),
        .psum_in(psum_out[i-1][j]),
        .psum_out(psum_out[i][j])
      );
    end 
  end
end generate

endmodule : systolic_array
