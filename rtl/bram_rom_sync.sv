// Synchronous-read ROM, intended to infer Block RAM (BRAM) in Vivado.
// Contents are deterministically initialized (no external .mem needed).
//
// NOTE: Vivado supports BRAM initialization via initial blocks for ROMs.
//
// INIT_MODE:
// 0: A[i,j] = (3*i + 5*j) % 16
// 1: B[i,j] = (7*i + 11*j) % 16
//
// Addressing is linear: addr = row*N + col, with N=16 by default.
module bram_rom_sync #(
  parameter int WIDTH     = 16,
  parameter int DEPTH     = 256,
  parameter int ADDR_W    = 8,
  parameter int N         = 16,
  parameter int INIT_MODE = 0
) (
  input  logic                 clk,
  input  logic [ADDR_W-1:0]     rd_addr,
  output logic [WIDTH-1:0]      rd_data
);

  (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

  function automatic logic [WIDTH-1:0] init_val(input int idx);
    int r;
    int c;
    int v;
    begin
      r = idx / N;
      c = idx % N;
      unique case (INIT_MODE)
        0: v = (3*r + 5*c) % 16;       // Matrix A
        1: v = (7*r + 11*c) % 16;      // Matrix B
        default: v = idx % (1 << WIDTH);
      endcase
      init_val = logic'(v[WIDTH-1:0]);
    end
  endfunction

  integer i;
  initial begin
    for (i = 0; i < DEPTH; i = i + 1) begin
      mem[i] = init_val(i);
    end
  end

  // 1-cycle synchronous read.
  always_ff @(posedge clk) begin
    rd_data <= mem[rd_addr];
  end

endmodule

