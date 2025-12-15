// Top: 16x16 matrix multiply using a tiled P x P systolic array.
// - Matrices A and B are stored in BRAM-inferred synchronous ROMs.
// - Result C is written to a BRAM-inferred true dual-port RAM.
// - After computation, C is streamed over UART as hex.
//
// This is resource-friendly on XC7S50: the systolic core uses P*P multipliers (default 16).
module mm_systolic_tiled_top #(
  parameter int N       = 16,
  parameter int P       = 4,
  parameter int DATA_W  = 16,
  parameter int ACC_W   = 32,
  parameter int CLK_HZ  = 100_000_000,
  parameter int BAUD    = 115200
) (
  input  logic clk,
  input  logic rst_n,
  output logic uart_txd,
  output logic done
);

  localparam int DEPTH   = N*N;
  localparam int ADDR_W  = $clog2(DEPTH);
  localparam int K       = N;
  localparam int T_CYC   = K + (2*P) - 2; // schedule length for each P x P tile

  // ---------------------------------------------------------------------------
  // A/B ROM banks (replicated to get enough read ports per cycle).
  // ---------------------------------------------------------------------------
  logic [ADDR_W-1:0] a_addr [P];
  logic [ADDR_W-1:0] b_addr [P];
  logic [DATA_W-1:0] a_data_u [P];
  logic [DATA_W-1:0] b_data_u [P];

  genvar bi;
  generate
    for (bi = 0; bi < P; bi = bi + 1) begin : GEN_A_BANKS
      bram_rom_sync #(
        .WIDTH(DATA_W),
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W),
        .N(N),
        .INIT_MODE(0)
      ) u_a_rom (
        .clk(clk),
        .rd_addr(a_addr[bi]),
        .rd_data(a_data_u[bi])
      );
    end
    for (bi = 0; bi < P; bi = bi + 1) begin : GEN_B_BANKS
      bram_rom_sync #(
        .WIDTH(DATA_W),
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W),
        .N(N),
        .INIT_MODE(1)
      ) u_b_rom (
        .clk(clk),
        .rd_addr(b_addr[bi]),
        .rd_data(b_data_u[bi])
      );
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Result BRAM (C)
  // ---------------------------------------------------------------------------
  logic               c_we;
  logic [ADDR_W-1:0]  c_waddr;
  logic [ACC_W-1:0]   c_wdata;
  logic [ADDR_W-1:0]  c_raddr;
  logic [ACC_W-1:0]   c_rdata;

  bram_tdp #(
    .WIDTH(ACC_W),
    .DEPTH(DEPTH),
    .ADDR_W(ADDR_W)
  ) u_c_bram (
    .clk    (clk),
    .a_we   (c_we),
    .a_addr (c_waddr),
    .a_wdata(c_wdata),
    .b_addr (c_raddr),
    .b_rdata(c_rdata)
  );

  // ---------------------------------------------------------------------------
  // Systolic tile core
  // ---------------------------------------------------------------------------
  logic en_sa, clear_sa;
  logic signed [DATA_W-1:0] a_in_sa [P];
  logic signed [DATA_W-1:0] b_in_sa [P];
  logic signed [ACC_W-1:0]  c_tile  [P][P];

  systolic_array_p #(
    .P(P),
    .DATA_W(DATA_W),
    .ACC_W(ACC_W)
  ) u_sa (
    .clk  (clk),
    .rst_n(rst_n),
    .en   (en_sa),
    .clear(clear_sa),
    .a_in (a_in_sa),
    .b_in (b_in_sa),
    .c_out(c_tile)
  );

  // ---------------------------------------------------------------------------
  // UART TX
  // ---------------------------------------------------------------------------
  logic       tx_start;
  logic [7:0] tx_byte;
  logic       tx_busy;

  uart_tx #(
    .CLK_HZ(CLK_HZ),
    .BAUD  (BAUD)
  ) u_uart (
    .clk     (clk),
    .rst_n   (rst_n),
    .tx_start(tx_start),
    .tx_data (tx_byte),
    .tx_busy (tx_busy),
    .tx      (uart_txd)
  );

  // ---------------------------------------------------------------------------
  // Helper: nibble to ASCII hex.
  // ---------------------------------------------------------------------------
  function automatic logic [7:0] hex_char(input logic [3:0] nib);
    if (nib < 4'd10) hex_char = 8'h30 + nib;       // '0'..'9'
    else             hex_char = 8'h41 + (nib-10);  // 'A'..'F'
  endfunction

  // ---------------------------------------------------------------------------
  // Controller FSM
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    S_CLEAR      = 4'd0,
    S_RUN        = 4'd1,
    S_WRITEBACK  = 4'd2,
    S_NEXTBLOCK  = 4'd3,
    S_UART_HDR   = 4'd4,
    S_UART_SET   = 4'd5,
    S_UART_WAIT  = 4'd6,
    S_UART_HEX   = 4'd7,
    S_UART_SEP   = 4'd8,
    S_UART_CR    = 4'd9,
    S_UART_LF    = 4'd10,
    S_DONE       = 4'd11
  } state_t;

  state_t state;

  logic [$clog2(N)-1:0] blk_i, blk_j;  // 0..15, but step by P
  logic [$clog2(T_CYC+1)-1:0] step_run;

  // BRAM-latency alignment
  logic [P-1:0] valid_a_feed, valid_b_feed;

  // writeback
  logic [$clog2(P*P)-1:0] wb_idx;

  // UART streaming
  logic [$clog2(DEPTH)-1:0] uart_addr;
  logic [3:0]               uart_row, uart_col;
  logic [2:0]               hex_nib_idx; // 0..7 (8 nibbles = 32-bit)
  logic [ACC_W-1:0]         cur_word;

  // header string: "C (hex) 16x16:\r\n"
  logic [4:0] hdr_idx;
  function automatic logic [7:0] hdr_byte(input logic [4:0] idx);
    unique case (idx)
      5'd0:  hdr_byte = "C";
      5'd1:  hdr_byte = " ";
      5'd2:  hdr_byte = "(";
      5'd3:  hdr_byte = "h";
      5'd4:  hdr_byte = "e";
      5'd5:  hdr_byte = "x";
      5'd6:  hdr_byte = ")";
      5'd7:  hdr_byte = " ";
      5'd8:  hdr_byte = "1";
      5'd9:  hdr_byte = "6";
      5'd10: hdr_byte = "x";
      5'd11: hdr_byte = "1";
      5'd12: hdr_byte = "6";
      5'd13: hdr_byte = ":";
      5'd14: hdr_byte = 8'h0D; // \r
      5'd15: hdr_byte = 8'h0A; // \n
      default: hdr_byte = 8'h00;
    endcase
  endfunction

  // Feed systolic array inputs from BRAM outputs (aligned with valid_*_feed).
  genvar gi;
  generate
    for (gi = 0; gi < P; gi = gi + 1) begin : GEN_FEED
      assign a_in_sa[gi] = valid_a_feed[gi] ? $signed(a_data_u[gi]) : '0;
      assign b_in_sa[gi] = valid_b_feed[gi] ? $signed(b_data_u[gi]) : '0;
    end
  endgenerate

  // Issue address and valid computation for a given t_issue
  function automatic logic [ADDR_W-1:0] a_lin_addr(input int row, input int k);
    a_lin_addr = logic'((row*N) + k);
  endfunction
  function automatic logic [ADDR_W-1:0] b_lin_addr(input int k, input int col);
    b_lin_addr = logic'((k*N) + col);
  endfunction

  // Main FSM
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= S_CLEAR;
      blk_i        <= '0;
      blk_j        <= '0;
      step_run     <= '0;
      en_sa        <= 1'b0;
      clear_sa     <= 1'b1;
      valid_a_feed <= '0;
      valid_b_feed <= '0;
      wb_idx       <= '0;
      done         <= 1'b0;

      tx_start     <= 1'b0;
      tx_byte      <= 8'h00;

      hdr_idx      <= '0;
      uart_row     <= 4'd0;
      uart_col     <= 4'd0;
      uart_addr    <= '0;
      hex_nib_idx  <= 3'd0;
      cur_word     <= '0;
      c_raddr      <= '0;

      // init BRAM addresses and write controls
      for (int i = 0; i < P; i++) begin
        a_addr[i] <= '0;
        b_addr[i] <= '0;
      end
      c_we    <= 1'b0;
      c_waddr <= '0;
      c_wdata <= '0;
    end else begin
      // defaults each cycle
      tx_start <= 1'b0;
      done     <= (state == S_DONE);

      // drive systolic control defaults
      clear_sa <= 1'b0;
      en_sa    <= 1'b0;

      // default: no write
      c_we    <= 1'b0;
      c_waddr <= '0;
      c_wdata <= '0;

      unique case (state)
        // One cycle to clear the systolic tile and pre-issue t=0 addresses.
        S_CLEAR: begin : CLEAR_BLK
          logic [P-1:0] va_next;
          logic [P-1:0] vb_next;

          clear_sa <= 1'b1;
          en_sa    <= 1'b0;
          step_run <= '0;
          wb_idx   <= '0;

          // Issue addresses for t_issue = 0 (for next cycle feed)
          for (int r = 0; r < P; r++) begin
            int t;
            int k;
            int row;
            t   = 0;
            k   = t - r;
            row = blk_i + r;
            va_next[r] = (t >= r) && (k >= 0) && (k < K);
            a_addr[r]  <= a_lin_addr(row, (k < 0) ? 0 : k);
          end
          for (int c = 0; c < P; c++) begin
            int t;
            int k;
            int col;
            t   = 0;
            k   = t - c;
            col = blk_j + c;
            vb_next[c] = (t >= c) && (k >= 0) && (k < K);
            b_addr[c]  <= b_lin_addr((k < 0) ? 0 : k, col);
          end

          valid_a_feed <= va_next;
          valid_b_feed <= vb_next;

          state <= S_RUN;
        end

        // Feed systolic tile for T_CYC cycles.
        S_RUN: begin : RUN_BLK
          logic [P-1:0] va_next;
          logic [P-1:0] vb_next;

          en_sa <= 1'b1;

          // While feeding step_run = s, issue addresses for t_issue = s+1.
          if (step_run < T_CYC-1) begin
            int t;
            t = step_run + 1;
            for (int r = 0; r < P; r++) begin
              int k;
              int row;
              k   = t - r;
              row = blk_i + r;
              va_next[r] = (t >= r) && (k >= 0) && (k < K);
              a_addr[r]  <= a_lin_addr(row, (k < 0) ? 0 : k);
            end
            for (int c = 0; c < P; c++) begin
              int k;
              int col;
              k   = t - c;
              col = blk_j + c;
              vb_next[c] = (t >= c) && (k >= 0) && (k < K);
              b_addr[c]  <= b_lin_addr((k < 0) ? 0 : k, col);
            end
            valid_a_feed <= va_next;
            valid_b_feed <= vb_next;
          end else begin
            // last feed: don't care about next issue
            valid_a_feed <= '0;
            valid_b_feed <= '0;
          end

          if (step_run == T_CYC-1) begin
            state    <= S_WRITEBACK;
            wb_idx   <= '0;
            en_sa    <= 1'b1; // still accumulate for this last cycle
          end else begin
            step_run <= step_run + 1'b1;
          end
        end

        // Write P*P tile results to C BRAM.
        S_WRITEBACK: begin
          int r;
          int c;
          int row;
          int col;
          r   = wb_idx / P;
          c   = wb_idx % P;
          row = blk_i + r;
          col = blk_j + c;

          c_we    <= 1'b1;
          c_waddr <= logic'((row*N) + col);
          c_wdata <= c_tile[r][c];

          if (wb_idx == (P*P - 1)) begin
            state <= S_NEXTBLOCK;
          end else begin
            wb_idx <= wb_idx + 1'b1;
          end
        end

        // Advance to next tile or start UART.
        S_NEXTBLOCK: begin
          if ((blk_i == (N-P)) && (blk_j == (N-P))) begin
            // done computing all tiles
            state    <= S_UART_HDR;
            hdr_idx  <= '0;
            uart_row <= 4'd0;
            uart_col <= 4'd0;
            uart_addr<= '0;
          end else begin
            if (blk_j == (N-P)) begin
              blk_j <= '0;
              blk_i <= blk_i + P[$clog2(N)-1:0];
            end else begin
              blk_j <= blk_j + P[$clog2(N)-1:0];
            end
            state <= S_CLEAR;
          end
        end

        // Send header bytes.
        S_UART_HDR: begin
          if (!tx_busy) begin
            tx_start <= 1'b1;
            tx_byte  <= hdr_byte(hdr_idx);
            if (hdr_idx == 5'd15) begin
              state     <= S_UART_SET;
              uart_row  <= 4'd0;
              uart_col  <= 4'd0;
              uart_addr <= '0;
            end else begin
              hdr_idx <= hdr_idx + 1'b1;
            end
          end
        end

        // Schedule a C BRAM read for the current element.
        S_UART_SET: begin
          c_raddr <= uart_addr;
          state   <= S_UART_WAIT;
        end

        // Wait 1 cycle for BRAM read data after setting c_raddr.
        S_UART_WAIT: begin
          cur_word    <= c_rdata;
          hex_nib_idx <= 3'd7;
          state       <= S_UART_HEX;
        end

        // Send 8 hex chars for cur_word (32-bit).
        S_UART_HEX: begin
          if (!tx_busy) begin
            logic [3:0] nib;
            nib = cur_word[hex_nib_idx*4 +: 4];
            tx_start <= 1'b1;
            tx_byte  <= hex_char(nib);
            if (hex_nib_idx == 3'd0) begin
              state <= S_UART_SEP;
            end else begin
              hex_nib_idx <= hex_nib_idx - 1'b1;
            end
          end
        end

        // Send separator: space between columns, or CR at end of row.
        S_UART_SEP: begin
          if (!tx_busy) begin
            if (uart_col == (N-1)) begin
              tx_start <= 1'b1;
              tx_byte  <= 8'h0D;
              state    <= S_UART_LF;
            end else begin
              tx_start <= 1'b1;
              tx_byte  <= " ";
              uart_col <= uart_col + 1'b1;
              uart_addr<= uart_addr + 1'b1;
              state    <= S_UART_SET;
            end
          end
        end

        // Send LF, then advance to next row or finish.
        S_UART_LF: begin
          if (!tx_busy) begin
            tx_start <= 1'b1;
            tx_byte  <= 8'h0A;
            if (uart_row == (N-1)) state <= S_DONE;
            else begin
              uart_row  <= uart_row + 1'b1;
              uart_col  <= 4'd0;
              uart_addr <= logic'((uart_row + 1'b1) * N);
              state     <= S_UART_SET;
            end
          end
        end

        S_DONE: begin
          // hold
          en_sa    <= 1'b0;
          clear_sa <= 1'b0;
        end

        default: begin
          state <= S_CLEAR;
        end
      endcase
    end
  end

endmodule

