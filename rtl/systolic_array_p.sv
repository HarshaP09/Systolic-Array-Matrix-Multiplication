// P x P systolic array for one output tile of matrix multiplication.
// Data injection:
// - a_in[r] enters from the left of row r
// - b_in[c] enters from the top of column c
//
// Each PE accumulates: acc += a*b each cycle when en=1.
module systolic_array_p #(
  parameter int P      = 4,
  parameter int DATA_W = 16,
  parameter int ACC_W  = 32
) (
  input  logic                          clk,
  input  logic                          rst_n,
  input  logic                          en,
  input  logic                          clear,

  input  logic signed [DATA_W-1:0]      a_in [P],
  input  logic signed [DATA_W-1:0]      b_in [P],

  output logic signed [ACC_W-1:0]       c_out [P][P]
);

  logic signed [DATA_W-1:0] a_bus [P][P+1];
  logic signed [DATA_W-1:0] b_bus [P+1][P];

  genvar r, c;
  generate
    for (r = 0; r < P; r = r + 1) begin : GEN_A_EDGE
      assign a_bus[r][0] = a_in[r];
    end
    for (c = 0; c < P; c = c + 1) begin : GEN_B_EDGE
      assign b_bus[0][c] = b_in[c];
    end

    for (r = 0; r < P; r = r + 1) begin : GEN_ROW
      for (c = 0; c < P; c = c + 1) begin : GEN_COL
        systolic_pe #(
          .DATA_W(DATA_W),
          .ACC_W (ACC_W)
        ) u_pe (
          .clk   (clk),
          .rst_n (rst_n),
          .en    (en),
          .clear (clear),
          .a_in  (a_bus[r][c]),
          .b_in  (b_bus[r][c]),
          .a_out (a_bus[r][c+1]),
          .b_out (b_bus[r+1][c]),
          .c_out (c_out[r][c])
        );
      end
    end
  endgenerate

endmodule

