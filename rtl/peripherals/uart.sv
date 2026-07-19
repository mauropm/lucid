`default_nettype none

module uart #(
    parameter int FIFO_DEPTH = 8
) (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        wb_cyc,
    input  logic        wb_stb,
    input  logic        wb_we,
    input  logic [31:0] wb_adr,
    input  logic [31:0] wb_dat_w,
    input  logic [3:0]  wb_sel,
    output logic [31:0] wb_dat_r,
    output logic        wb_ack,

    input  logic        rx,
    output logic        tx
);

    logic [31:0] ctrl;
    logic [15:0] baud_div;

    logic tx_busy;
    logic rx_ready;
    logic rx_overrun;
    logic rx_overrun_clr;

    logic tx_fifo_full, tx_fifo_empty;
    logic [7:0] tx_fifo_data;
    logic tx_fifo_rd;
    logic rx_fifo_full, rx_fifo_empty;
    logic [7:0] rx_fifo_data;
    logic rx_fifo_wr;
    logic [7:0] rx_data_byte;
    logic rx_data_byte_valid;
    logic [$clog2(FIFO_DEPTH):0] rx_fifo_count;

    logic wb_rd, wb_wr;
    assign wb_rd = wb_stb && wb_cyc && !wb_we;
    assign wb_wr = wb_stb && wb_cyc &&  wb_we;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ctrl     <= '0;
            baud_div <= 16'd868;
            rx_overrun_clr <= 1'b0;
        end else begin
            rx_overrun_clr <= 1'b0;
            if (wb_wr) begin
                case (wb_adr[4:2])
                    3'h0: ctrl     <= wb_dat_w;
                    3'h1: baud_div <= wb_dat_w[15:0];
                    3'h2: if (wb_dat_w[6]) rx_overrun_clr <= 1'b1;
                    default: ;
                endcase
            end
        end
    end

    // C7: RX data path uses registered ack to match FIFO's registered read
    logic rx_read_pending;
    logic [7:0] rx_read_data_r;

    always_comb begin
        wb_dat_r = '0;
        case (wb_adr[4:2])
            3'h0: wb_dat_r = ctrl;
            3'h1: wb_dat_r = baud_div;
            3'h2: wb_dat_r = {28'h0, tx_busy, rx_ready, tx_fifo_full, rx_overrun};
            3'h4: wb_dat_r = rx_read_pending ? {24'h0, rx_fifo_data} : {24'h0, rx_read_data_r};
            3'h5: wb_dat_r = {27'h0, rx_fifo_count};
            default: wb_dat_r = '0;
        endcase
    end

    // C7: Registered ack for RX data reads, combinational for others
    assign wb_ack = rx_read_pending ||
                    (wb_stb && wb_cyc && !(wb_rd && wb_adr[4:2] == 3'h4));

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rx_read_pending <= 1'b0;
            rx_read_data_r <= '0;
        end else begin
            if (rx_read_pending) begin
                rx_read_data_r <= rx_fifo_data;
                rx_read_pending <= 1'b0;
            end else if (wb_rd && wb_adr[4:2] == 3'h4 && !rx_fifo_empty) begin
                rx_read_pending <= 1'b1;
            end
        end
    end

    wire tx_fifo_wr = wb_wr && (wb_adr[4:2] == 3'h3);

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

    wire rx_fifo_rd = wb_rd && (wb_adr[4:2] == 3'h4) && !rx_fifo_empty && !rx_read_pending;

    fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) rx_fifo (
        .clk(clk), .reset_n(reset_n),
        .wr_en(rx_fifo_wr),
        .wr_data(rx_data_byte),
        .full(rx_fifo_full),
        .rd_en(rx_fifo_rd),
        .rd_data(rx_fifo_data),
        .empty(rx_fifo_empty),
        .count(rx_fifo_count)
    );

    // H4: 2-FF synchronizer for rx input
    logic rx_sync1, rx_sync2;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    // H4: Clear rx_ready when RX data is read
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            rx_ready <= 1'b0;
        else if (rx_fifo_rd && !rx_fifo_empty)
            rx_ready <= 1'b0;
        else if (rx_data_byte_valid)
            rx_ready <= 1'b1;
    end

    // TX FSM
    typedef enum logic [1:0] { TX_IDLE, TX_START, TX_DATA, TX_STOP } tx_state_t;
    tx_state_t tx_state;
    logic [3:0] tx_bit_cnt;
    logic [7:0] tx_shift;

    logic [15:0] baud_tick_cnt;
    logic baud_tick;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            baud_tick_cnt <= '0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_tick_cnt >= baud_div - 1) begin
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
            tx_state   <= TX_IDLE;
            tx_shift   <= '0;
            tx_bit_cnt <= '0;
            tx_busy    <= 1'b0;
            tx_fifo_rd <= 1'b0;
            tx         <= 1'b1;
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
                        tx_shift   <= tx_fifo_data;
                        tx_bit_cnt <= 4'd0;
                        tx_state   <= TX_DATA;
                    end
                end
                TX_DATA: begin
                    tx <= tx_shift[0];
                    if (baud_tick) begin
                        tx_shift   <= {1'b0, tx_shift[7:1]};
                        tx_bit_cnt <= tx_bit_cnt + 1'b1;
                        if (tx_bit_cnt == 4'd7)
                            tx_state <= TX_STOP;
                    end
                end
                TX_STOP: begin
                    tx <= 1'b1;
                    if (baud_tick) begin
                        tx_busy  <= 1'b0;
                        tx_state <= TX_IDLE;
                    end
                end
                default: begin
                    tx_state <= TX_IDLE;
                    tx <= 1'b1;
                end
            endcase
        end
    end

    // H4: RX with dedicated bit timer and mid-bit sampling
    typedef enum logic [2:0] { RX_IDLE, RX_START, RX_DATA, RX_STOP, RX_ERROR } rx_state_t;
    rx_state_t rx_state;
    logic [3:0]  rx_bit_cnt;
    logic [7:0]  rx_shift;
    logic [15:0] rx_tick_cnt;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rx_state       <= RX_IDLE;
            rx_shift       <= '0;
            rx_bit_cnt     <= '0;
            rx_overrun     <= 1'b0;
            rx_fifo_wr     <= 1'b0;
            rx_data_byte   <= '0;
            rx_data_byte_valid <= 1'b0;
            rx_tick_cnt    <= '0;
        end else begin
            rx_fifo_wr     <= 1'b0;
            rx_data_byte_valid <= 1'b0;
            if (rx_overrun_clr)
                rx_overrun <= 1'b0;
            case (rx_state)
                RX_IDLE: begin
                    if (!rx_sync2 && ctrl[0]) begin
                        rx_tick_cnt <= baud_div >> 1;
                        rx_state    <= RX_START;
                    end
                end
                RX_START: begin
                    if (rx_tick_cnt == 0) begin
                        if (!rx_sync2) begin
                            rx_tick_cnt <= baud_div - 1;
                            rx_bit_cnt  <= 4'd0;
                            rx_state    <= RX_DATA;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_tick_cnt <= rx_tick_cnt - 1'b1;
                    end
                end
                RX_DATA: begin
                    if (rx_tick_cnt == 0) begin
                        rx_shift   <= {rx_sync2, rx_shift[7:1]};
                        rx_bit_cnt <= rx_bit_cnt + 1'b1;
                        rx_tick_cnt <= baud_div - 1;
                        if (rx_bit_cnt == 4'd7)
                            rx_state <= RX_STOP;
                    end else begin
                        rx_tick_cnt <= rx_tick_cnt - 1'b1;
                    end
                end
                RX_STOP: begin
                    if (rx_tick_cnt == 0) begin
                        if (rx_sync2) begin
                            rx_data_byte_valid <= 1'b1;
                            rx_data_byte <= rx_shift;
                            rx_state <= RX_IDLE;
                            if (!rx_fifo_full) begin
                                rx_fifo_wr <= 1'b1;
                            end else begin
                                rx_overrun <= 1'b1;
                            end
                        end else begin
                            rx_state <= RX_ERROR;
                        end
                    end else begin
                        rx_tick_cnt <= rx_tick_cnt - 1'b1;
                    end
                end
                RX_ERROR: begin
                    if (rx_sync2) rx_state <= RX_IDLE;
                end
                default: begin
                    rx_state <= RX_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
