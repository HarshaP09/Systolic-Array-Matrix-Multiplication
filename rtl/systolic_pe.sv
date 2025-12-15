module systolic_pe #(
  parameter int DATA_W = 16,
  parameter int ACC_W  = 32
) (
  input  logic                      clk,
  input  logic                      rst_n,
  input  logic                      en,
  input  logic                      clear,

  input  logic signed [DATA_W-1:0]   a_in,
  input  logic signed [DATA_W-1:0]   b_in,
  output logic signed [DATA_W-1:0]   a_out,
  output logic signed [DATA_W-1:0]   b_out,
  output logic signed [ACC_W-1:0]    c_out
);

  (* use_dsp = "yes" *) logic signed [2*DATA_W-1:0] prod;
  logic signed [DATA_W-1:0] a_reg, b_reg;
  logic signed [ACC_W-1:0]  acc;

  assign prod = a_in * b_in;
  assign a_out = a_reg;
  assign b_out = b_reg;
  assign c_out = acc;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_reg <= '0;
      b_reg <= '0;
      acc   <= '0;
    end else begin
      if (clear) begin
        a_reg <= '0;
        b_reg <= '0;
        acc   <= '0;
      end else if (en) begin
        a_reg <= a_in;
        b_reg <= b_in;
        acc   <= acc + {{(ACC_W-2*DATA_W){prod[2*DATA_W-1]}}, prod}; // sign-extend
      end
    end
  end

endmodule

