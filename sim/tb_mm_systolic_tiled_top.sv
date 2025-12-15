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

  function automatic int a_val(input int r, input int c);
    a_val = (3*r + 5*c) % 16;
  endfunction
  function automatic int b_val(input int r, input int c);
    b_val = (7*r + 11*c) % 16;
  endfunction

  int c_ref [0:N-1][0:N-1];

  initial begin
    // build reference C = A*B
    for (int i = 0; i < N; i++) begin
      for (int j = 0; j < N; j++) begin
        int sum = 0;
        for (int k = 0; k < N; k++) begin
          sum += a_val(i,k) * b_val(k,j);
        end
        c_ref[i][j] = sum;
      end
    end
  end

  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    // wait for completion (includes UART stream)
    int timeout_cycles = 200_000;
    while (!done && timeout_cycles > 0) begin
      @(posedge clk);
      timeout_cycles--;
    end
    if (!done) begin
      $fatal(1, "TIMEOUT: done never asserted");
    end

    $display("\n---- C (hex) read from dut BRAM ----");
    for (int i = 0; i < N; i++) begin
      $write("row %0d: ", i);
      for (int j = 0; j < N; j++) begin
        int addr = i*N + j;
        logic signed [ACC_W-1:0] got;
        got = dut.u_c_bram.mem[addr];
        $write("%08x ", got);
      end
      $write("\n");
    end

    // check a few values
    int errors = 0;
    for (int i = 0; i < N; i++) begin
      for (int j = 0; j < N; j++) begin
        int addr = i*N + j;
        int got  = dut.u_c_bram.mem[addr];
        if (got !== c_ref[i][j]) begin
          errors++;
          if (errors < 10) begin
            $display("Mismatch C[%0d,%0d]: got=%0d exp=%0d", i, j, got, c_ref[i][j]);
          end
        end
      end
    end
    if (errors == 0) $display("PASS: DUT C matches reference.");
    else $display("FAIL: %0d mismatches.", errors);

    $finish;
  end
endmodule

