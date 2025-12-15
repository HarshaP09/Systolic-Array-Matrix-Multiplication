// Board wrapper for the Boolean Spartan-7 board constraints you provided.
// Exposes ports that match the official XDC names (clk, btn[], led[], UART_txd).
//
// Reset: uses btn[0] as active-high button, converted to active-low rst_n.
module top_boolean_mm #(
  parameter int CLK_HZ = 100_000_000,
  parameter int BAUD   = 115200
) (
  input  logic        clk,
  input  logic [3:0]  btn,
  output logic [15:0] led,
  output logic        UART_txd
);

  logic rst_n;
  logic done;

  // btn[0] pressed -> reset asserted
  assign rst_n = ~btn[0];

  mm_systolic_tiled_top #(
    .CLK_HZ(CLK_HZ),
    .BAUD  (BAUD)
  ) u_top (
    .clk     (clk),
    .rst_n   (rst_n),
    .uart_txd(UART_txd),
    .done    (done)
  );

  // LEDs: show done on LED0
  always_comb begin
    led = '0;
    led[0] = done;
  end

endmodule

