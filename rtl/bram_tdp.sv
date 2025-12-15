// True dual-port BRAM (1 write port + 1 read port), synchronous read.
// Intended to infer Block RAM in Vivado.
module bram_tdp #(
  parameter int WIDTH  = 32,
  parameter int DEPTH  = 256,
  parameter int ADDR_W = 8
) (
  input  logic                 clk,

  // Port A: write
  input  logic                 a_we,
  input  logic [ADDR_W-1:0]     a_addr,
  input  logic [WIDTH-1:0]      a_wdata,

  // Port B: read
  input  logic [ADDR_W-1:0]     b_addr,
  output logic [WIDTH-1:0]      b_rdata
);

  (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (a_we) begin
      mem[a_addr] <= a_wdata;
    end
    b_rdata <= mem[b_addr];
  end

endmodule

