`timescale 1ns/1ps

module tb_mm_systolic_tiled_top;
  localparam int N      = 16;
  localparam int P      = 4;
  localparam int DATA_W = 16;
  localparam int ACC_W  = 32;

  // Speed up UART for simulation: CLKS_PER_BIT ~= 1
  localparam int CLK_HZ = 10_000_000;
  localparam int BAUD   = 10_000_000;

  logic clk;
  logic rst_n;
  logic uart_txd;
  logic done;

  mm_systolic_tiled_top #(
    .N(N),
    .P(P),
    .DATA_W(DATA_W),
    .ACC_W(ACC_W),
    .CLK_HZ(CLK_HZ),
    .BAUD(BAUD)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .uart_txd(uart_txd),
    .done(done)
  );

  // clock: 10 MHz
  initial clk = 1'b0;
  always #50 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Reference math (keep it tool-friendly for XSim):
  // - Avoid declaring variables mid-block.
  // - Avoid loop-variable declarations inside the for() header.
  // ---------------------------------------------------------------------------
  function automatic integer a_val(input integer r, input integer c);
    a_val = (3*r + 5*c) % 16;
  endfunction

  function automatic integer b_val(input integer r, input integer c);
    b_val = (7*r + 11*c) % 16;
  endfunction

  function automatic integer c_exp(input integer i, input integer j);
    integer k;
    integer sum;
    begin
      sum = 0;
      for (k = 0; k < N; k = k + 1) begin
        sum = sum + a_val(i,k) * b_val(k,j);
      end
      c_exp = sum;
    end
  endfunction

  integer timeout_cycles;
  integer errors;
  integer i;
  integer j;
  integer addr;
  integer got_int;
  integer exp_int;

  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    // wait for completion (includes UART stream)
    timeout_cycles = 200_000;
    while (!done && timeout_cycles > 0) begin
      @(posedge clk);
      timeout_cycles--;
    end
    if (!done) begin
      $fatal(1, "TIMEOUT: done never asserted");
    end

    $display("\n---- C (hex) read from dut BRAM ----");
    for (i = 0; i < N; i = i + 1) begin
      $write("row %0d: ", i);
      for (j = 0; j < N; j = j + 1) begin
        addr = i*N + j;
        $write("%08x ", dut.u_c_bram.mem[addr]);
      end
      $write("\n");
    end

    // Check all values against reference
    errors = 0;
    for (i = 0; i < N; i = i + 1) begin
      for (j = 0; j < N; j = j + 1) begin
        addr    = i*N + j;
        got_int = dut.u_c_bram.mem[addr];
        exp_int = c_exp(i,j);
        if (got_int !== exp_int) begin
          errors++;
          if (errors < 10) begin
            $display("Mismatch C[%0d,%0d]: got=%0d exp=%0d", i, j, got_int, exp_int);
          end
        end
      end
    end
    if (errors == 0) $display("PASS: DUT C matches reference.");
    else $display("FAIL: %0d mismatches.", errors);

    $finish;
  end
endmodule

