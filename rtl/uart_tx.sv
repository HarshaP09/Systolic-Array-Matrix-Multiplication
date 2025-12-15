// Simple UART transmitter: 8N1, LSB-first.
module uart_tx #(
  parameter int CLK_HZ = 100_000_000,
  parameter int BAUD   = 115200
) (
  input  logic       clk,
  input  logic       rst_n,

  input  logic       tx_start,
  input  logic [7:0] tx_data,
  output logic       tx_busy,
  output logic       tx
);

  localparam int CLKS_PER_BIT = (CLK_HZ + (BAUD/2)) / BAUD;
  localparam int CTR_W        = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

  typedef enum logic [1:0] {S_IDLE, S_START, S_DATA, S_STOP} state_t;
  state_t state;

  logic [CTR_W-1:0] clk_ctr;
  logic [2:0]       bit_idx;
  logic [7:0]       shreg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= S_IDLE;
      clk_ctr <= '0;
      bit_idx <= '0;
      shreg   <= 8'h00;
      tx      <= 1'b1;
      tx_busy <= 1'b0;
    end else begin
      unique case (state)
        S_IDLE: begin
          tx      <= 1'b1;
          tx_busy <= 1'b0;
          clk_ctr <= '0;
          bit_idx <= '0;
          if (tx_start) begin
            shreg   <= tx_data;
            state   <= S_START;
            tx_busy <= 1'b1;
          end
        end

        S_START: begin
          tx <= 1'b0; // start bit
          if (clk_ctr == CLKS_PER_BIT-1) begin
            clk_ctr <= '0;
            state   <= S_DATA;
            bit_idx <= 3'd0;
          end else begin
            clk_ctr <= clk_ctr + 1'b1;
          end
        end

        S_DATA: begin
          tx <= shreg[bit_idx];
          if (clk_ctr == CLKS_PER_BIT-1) begin
            clk_ctr <= '0;
            if (bit_idx == 3'd7) begin
              state <= S_STOP;
            end else begin
              bit_idx <= bit_idx + 1'b1;
            end
          end else begin
            clk_ctr <= clk_ctr + 1'b1;
          end
        end

        S_STOP: begin
          tx <= 1'b1; // stop bit
          if (clk_ctr == CLKS_PER_BIT-1) begin
            clk_ctr <= '0;
            state   <= S_IDLE;
          end else begin
            clk_ctr <= clk_ctr + 1'b1;
          end
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule

