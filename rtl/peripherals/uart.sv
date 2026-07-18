// UART Peripheral
// ===============
// Wishbone B4 slave. 8N1 serial protocol.
// Configurable baud rate. 8-byte TX and RX FIFOs.
//
// Register map:
//   0x00  UART_CTRL     R/W  Control register
//   0x04  UART_BAUD     R/W  Baud rate divisor
//   0x08  UART_STATUS   R    Status register
//   0x0C  UART_TX_DATA  W    Transmit data
//   0x10  UART_RX_DATA  R    Receive data
//   0x14  UART_RX_LEVEL R    RX FIFO level

module uart #(
    parameter int FIFO_DEPTH = 8
) (
    input  logic        clk,
    input  logic        reset_n,

    // Wishbone slave
    input  logic        wb_cyc,
    input  logic        wb_stb,
    input  logic        wb_we,
    input  logic [31:0] wb_adr,
    input  logic [31:0] wb_dat_w,
    input  logic [3:0]  wb_sel,
    output logic [31:0] wb_dat_r,
    output logic        wb_ack,

    // Serial I/O
    input  logic        rx,
    output logic        tx
);

    // Registers
    logic [31:0] ctrl;     // { reserved[30:0], enable }
    logic [31:0] baud_div; // Baud rate divisor

    // Status signals
    logic tx_busy;
    logic rx_ready;
    logic rx_overrun;

    // FIFO signals
    logic tx_fifo_full, tx_fifo_empty;
    logic [7:0] tx_fifo_data;
    logic tx_fifo_rd;
    logic rx_fifo_full, rx_fifo_empty;
    logic [7:0] rx_fifo_data;
    logic rx_fifo_wr;
    logic [7:0] rx_data_byte;
    logic rx_data_byte_valid;

    // Wishbone address decoding (word-aligned)
    logic wb_rd, wb_wr;
    assign wb_rd = wb_stb && wb_cyc && !wb_we;
    assign wb_wr = wb_stb && wb_cyc &&  wb_we;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ctrl     <= '0;
            baud_div <= 32'd868; // 100 MHz / 115200 ≈ 868
        end else if (wb_wr) begin
            case (wb_adr[4:2])
                3'h0: ctrl     <= wb_dat_w;
                3'h1: baud_div <= wb_dat_w;
            endcase
        end
    end

    // Wishbone read
    always_comb begin
        wb_dat_r = '0;
        case (wb_adr[4:2])
            3'h0: wb_dat_r = ctrl;
            3'h1: wb_dat_r = baud_div;
            3'h2: wb_dat_r = {28'h0, tx_busy, rx_ready, tx_fifo_full, rx_overrun};
            3'h4: wb_dat_r = {24'h0, rx_fifo_data};
        endcase
    end

    assign wb_ack = wb_stb && wb_cyc;

    // TX FIFO write from Wishbone
    wire tx_fifo_wr = wb_wr && (wb_adr[4:2] == 3'h3);

    // TX FIFO
    fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) tx_fifo (
        .clk(clk), .reset_n(reset_n),
        .wr_en(tx_fifo_wr),
        .wr_data(wb_dat_w[7:0]),
        .full(tx_fifo_full),
        .rd_en(tx_fifo_rd),
        .rd_data(tx_fifo_data),
        .empty(tx_fifo_empty),
        .count()
    );

    // RX FIFO
    fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) rx_fifo (
        .clk(clk), .reset_n(reset_n),
        .wr_en(rx_fifo_wr),
        .wr_data(rx_data_byte),
        .full(rx_fifo_full),
        .rd_en(wb_rd && (wb_adr[4:2] == 3'h4)),
        .rd_data(rx_fifo_data),
        .empty(rx_fifo_empty),
        .count()
    );

    // TX shift register and FSM
    typedef enum logic [1:0] { TX_IDLE, TX_START, TX_DATA, TX_STOP } tx_state_t;
    tx_state_t tx_state;
    logic [3:0] tx_bit_cnt;
    logic [7:0] tx_shift;
    logic [15:0] tx_tick_cnt;
    logic tx_tick;

    // Baud rate tick generator (shared)
    logic [15:0] baud_tick_cnt;
    logic baud_tick;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            baud_tick_cnt <= '0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_tick_cnt >= baud_div[15:0] - 1) begin
                baud_tick_cnt <= '0;
                baud_tick <= 1'b1;
            end else begin
                baud_tick_cnt <= baud_tick_cnt + 1'b1;
                baud_tick <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tx_state  <= TX_IDLE;
            tx_shift  <= '0;
            tx_bit_cnt <= '0;
            tx_busy   <= 1'b0;
            tx_fifo_rd <= 1'b0;
            tx        <= 1'b1;
        end else begin
            tx_fifo_rd <= 1'b0;
            case (tx_state)
                TX_IDLE: begin
                    tx <= 1'b1;
                    if (!tx_fifo_empty && ctrl[0]) begin
                        tx_fifo_rd <= 1'b1;
                        tx_state   <= TX_START;
                        tx_busy    <= 1'b1;
                    end
                end
                TX_START: begin
                    tx <= 1'b0;
                    if (baud_tick) begin
                        tx_shift  <= tx_fifo_data;
                        tx_bit_cnt <= 4'd0;
                        tx_state  <= TX_DATA;
                    end
                end
                TX_DATA: begin
                    tx <= tx_shift[0];
                    if (baud_tick) begin
                        tx_shift  <= {1'b0, tx_shift[7:1]};
                        tx_bit_cnt <= tx_bit_cnt + 1'b1;
                        if (tx_bit_cnt == 4'd7) begin
                            tx_state <= TX_STOP;
                        end
                    end
                end
                TX_STOP: begin
                    tx <= 1'b1;
                    if (baud_tick) begin
                        tx_busy  <= 1'b0;
                        tx_state <= TX_IDLE;
                    end
                end
            endcase
        end
    end

    // RX sampling and FSM
    typedef enum logic [2:0] { RX_IDLE, RX_START, RX_DATA, RX_STOP, RX_ERROR } rx_state_t;
    rx_state_t rx_state;
    logic [3:0] rx_bit_cnt;
    logic [7:0] rx_shift;
    logic [15:0] rx_tick_cnt;
    logic rx_start_bit;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rx_state   <= RX_IDLE;
            rx_shift   <= '0;
            rx_bit_cnt <= '0;
            rx_ready   <= 1'b0;
            rx_overrun <= 1'b0;
            rx_fifo_wr <= 1'b0;
        end else begin
            rx_fifo_wr <= 1'b0;
            case (rx_state)
                RX_IDLE: begin
                    if (!rx && ctrl[0]) begin
                        rx_tick_cnt <= baud_div[16:1]; // half bit period
                        rx_state    <= RX_START;
                    end
                end
                RX_START: begin
                    if (baud_tick) begin
                        // Sample mid-bit
                        rx_tick_cnt <= '0;
                        rx_bit_cnt  <= 4'd0;
                        rx_state    <= RX_DATA;
                    end
                end
                RX_DATA: begin
                    if (baud_tick) begin
                        rx_shift <= {rx, rx_shift[7:1]};
                        rx_bit_cnt <= rx_bit_cnt + 1'b1;
                        if (rx_bit_cnt == 4'd7) begin
                            rx_state <= RX_STOP;
                        end
                    end
                end
                RX_STOP: begin
                    if (baud_tick) begin
                        if (rx) begin
                            // Valid stop bit
                            rx_ready   <= 1'b1;
                            rx_data_byte <= rx_shift;
                            rx_state <= RX_IDLE;
                            if (!rx_fifo_full) begin
                                rx_fifo_wr <= 1'b1;
                            end else begin
                                rx_overrun <= 1'b1;
                            end
                        end else begin
                            // Framing error
                            rx_state <= RX_ERROR;
                        end
                    end
                end
                RX_ERROR: begin
                    // Wait for line to return to idle
                    if (rx) rx_state <= RX_IDLE;
                end
            endcase
        end
    end

endmodule
