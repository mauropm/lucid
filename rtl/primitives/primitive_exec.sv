`default_nettype none

import lucid_msg_pkg::*;

module primitive_exec (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        msg_in_valid,
    input  logic [31:0] msg_in_data,
    input  logic        msg_in_last,
    output logic        msg_in_ready,

    output logic        msg_out_valid,
    output logic [31:0] msg_out_data,
    output logic        msg_out_last,
    input  logic        msg_out_ready
);

    typedef enum logic [3:0] {
        RX_IDLE,
        RX_DATA0,
        RX_DATA1,
        RX_DATA2,
        RX_DIV,
        TX_HEADER,
        TX_DATA0,
        TX_DATA1
    } rx_state_t;

    rx_state_t state;

    logic [7:0]  rx_node_id;
    logic [7:0]  rx_opcode;
    logic [31:0] rx_op0, rx_op1;
    logic [2:0]  word_cnt;

    logic [4:0]  div_cnt;
    logic [31:0] div_rem, div_quo, div_divisor;
    logic [31:0] div_result;
    wire [31:0]  div_rem_shifted = {div_rem[30:0], div_quo[31]};
    wire [31:0]  div_sub_result  = div_rem_shifted - div_divisor;
    wire         div_sub_ok      = ~div_sub_result[31];

    logic [31:0] result_comb;
    always_comb begin
        case (rx_opcode[7:0])
            8'h10: result_comb = rx_op0 + rx_op1;
            8'h11: result_comb = rx_op0 - rx_op1;
            8'h12: result_comb = rx_op0 * rx_op1;
            8'h13: result_comb = div_result;
            8'h14: result_comb = div_result;
            8'h15: result_comb = {31'h0, rx_op0 == rx_op1};
            8'h16: result_comb = {31'h0, $signed(rx_op0) < $signed(rx_op1)};
            8'h17: result_comb = {31'h0, $signed(rx_op0) > $signed(rx_op1)};
            8'h18: result_comb = {31'h0, $signed(rx_op0) <= $signed(rx_op1)};
            8'h19: result_comb = {31'h0, $signed(rx_op0) >= $signed(rx_op1)};
            default: result_comb = 32'h0;
        endcase
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= RX_IDLE;
            rx_node_id <= '0;
            rx_opcode  <= '0;
            rx_op0 <= '0;
            rx_op1 <= '0;
            word_cnt <= '0;
            msg_in_ready <= 1'b0;
            msg_out_valid <= 1'b0;
            msg_out_data <= '0;
            msg_out_last <= 1'b0;
            div_cnt <= '0;
            div_rem <= '0;
            div_quo <= '0;
            div_divisor <= '0;
            div_result <= '0;
        end else begin
            msg_in_ready <= 1'b0;
            msg_out_valid <= 1'b0;

            case (state)
                RX_IDLE: begin
                    msg_in_ready <= 1'b1;
                    if (msg_in_valid) begin
                        state <= RX_DATA0;
                    end
                end

                RX_DATA0: begin
                    msg_in_ready <= 1'b1;
                    if (msg_in_valid) begin
                        rx_node_id <= msg_in_data[31:24];
                        rx_opcode  <= msg_in_data[23:16];
                        state <= RX_DATA1;
                    end
                end

                RX_DATA1: begin
                    msg_in_ready <= 1'b1;
                    if (msg_in_valid) begin
                        rx_op0 <= msg_in_data;
                        state <= RX_DATA2;
                    end
                end

                RX_DATA2: begin
                    msg_in_ready <= 1'b1;
                    if (msg_in_valid && msg_in_last) begin
                        rx_op1 <= msg_in_data;
                        if (rx_opcode == 8'h13 || rx_opcode == 8'h14) begin
                            if (msg_in_data == 0) begin
                                div_result <= 32'd0;
                                state <= TX_HEADER;
                            end else begin
                                state <= RX_DIV;
                                div_cnt <= 5'd31;
                                div_quo <= rx_op0;
                                div_rem <= '0;
                                div_divisor <= msg_in_data;
                            end
                        end else begin
                            state <= TX_HEADER;
                        end
                    end
                end

                RX_DIV: begin
                    if (div_sub_ok) begin
                        div_rem <= div_sub_result;
                        div_quo <= {div_quo[30:0], 1'b1};
                    end else begin
                        div_rem <= div_rem_shifted;
                        div_quo <= {div_quo[30:0], 1'b0};
                    end
                    if (div_cnt == 5'd0) begin
                        if (rx_opcode == 8'h14)
                            div_result <= div_sub_ok ? div_sub_result : div_rem_shifted;
                        else
                            div_result <= div_sub_ok ? {div_quo[30:0], 1'b1} : {div_quo[30:0], 1'b0};
                        state <= TX_HEADER;
                    end else begin
                        div_cnt <= div_cnt - 1'b1;
                    end
                end

                TX_HEADER: begin
                    msg_out_valid <= 1'b1;
                    msg_out_data <= make_header(MODULE_SCHEDULER, MODULE_ARITH, MSG_PRIM_RESULT, 8'h00);
                    msg_out_last <= 1'b0;
                    if (msg_out_ready)
                        state <= TX_DATA0;
                end

                TX_DATA0: begin
                    msg_out_valid <= 1'b1;
                    msg_out_data <= {rx_node_id, 24'h0};
                    msg_out_last <= 1'b0;
                    if (msg_out_ready)
                        state <= TX_DATA1;
                end

                TX_DATA1: begin
                    msg_out_valid <= 1'b1;
                    msg_out_data <= result_comb;
                    msg_out_last <= 1'b1;
                    if (msg_out_ready)
                        state <= RX_IDLE;
                end

                default: state <= RX_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
