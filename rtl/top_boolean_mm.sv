// Minimal board wrapper for the Boolean Spartan-7 board constraints.
// Only required pins are exposed:
// - clk (100 MHz oscillator)
// - UART_txd (FPGA -> USB-UART RX)
//
// Reset is generated internally (power-on reset).
module top_boolean_mm #(
  parameter int CLK_HZ = 100_000_000,
  parameter int BAUD   = 115200
) (
  input  logic clk,
  output logic UART_txd
);

  logic rst_n /* synthesis keep */;
  logic done;

  // Simple power-on reset: hold rst_n low for a short time after configuration.
  // ~2^20 / 100 MHz ~= 10.5 ms
  logic [19:0] por_ctr;
  always_ff @(posedge clk) begin
    if (por_ctr != {20{1'b1}}) begin
      por_ctr <= por_ctr + 1'b1;
      rst_n   <= 1'b0;
    end else begin
      rst_n <= 1'b1;
    end
  end

  mm_systolic_tiled_top #(
    .CLK_HZ(CLK_HZ),
    .BAUD  (BAUD)
  ) u_top (
    .clk     (clk),
    .rst_n   (rst_n),
    .uart_txd(UART_txd),
    .done    (done)
  );

endmodule

