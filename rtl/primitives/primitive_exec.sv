`default_nettype none

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

    // H3: Extended protocol - 4-word EXEC_PRIM, 3-word PRIM_RESULT
    typedef enum logic [2:0] {
        RX_IDLE,
        RX_DATA0,
        RX_DATA1,
        RX_DATA2,
        TX_HEADER,
        TX_DATA0,
        TX_DATA1
    } rx_state_t;

    rx_state_t state;

    logic [7:0]  rx_node_id;
    logic [7:0]  rx_opcode;
    logic [31:0] rx_op0, rx_op1;
    logic [31:0] result;
    logic [2:0]  word_cnt;

    always_comb begin
        case (rx_opcode)
            8'h10: result = rx_op0 + rx_op1;
            8'h11: result = rx_op0 - rx_op1;
            8'h12: result = rx_op0 * rx_op1;
            // M7: Consistent div-by-zero with RISC-V (quotient=-1, remainder=dividend)
            8'h13: result = rx_op1 != 0 ? rx_op0 / rx_op1 : 32'hFFFF_FFFF;
            8'h14: result = rx_op1 != 0 ? rx_op0 % rx_op1 : rx_op0;
            8'h15: result = {31'h0, rx_op0 == rx_op1};
            8'h16: result = {31'h0, $signed(rx_op0) < $signed(rx_op1)};
            8'h17: result = {31'h0, $signed(rx_op0) > $signed(rx_op1)};
            8'h18: result = {31'h0, $signed(rx_op0) <= $signed(rx_op1)};
            8'h19: result = {31'h0, $signed(rx_op0) >= $signed(rx_op1)};
            default: result = 32'h0;
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
        end else begin
            msg_in_ready <= 1'b0;
            msg_out_valid <= 1'b0;

            case (state)
                RX_IDLE: begin
                    msg_in_ready <= 1'b1;
                    if (msg_in_valid) begin
                        // Header word received
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
                        // H3: Full 32-bit op0
                        rx_op0 <= msg_in_data;
                        state <= RX_DATA2;
                    end
                end

                RX_DATA2: begin
                    msg_in_ready <= 1'b1;
                    if (msg_in_valid && msg_in_last) begin
                        // H3: Full 32-bit op1, verify LAST
                        rx_op1 <= msg_in_data;
                        state <= TX_HEADER;
                    end else if (msg_in_valid && !msg_in_last) begin
                        // M7: Protocol error - expected LAST
                        state <= RX_IDLE;
                    end
                end

                TX_HEADER: begin
                    msg_out_valid <= 1'b1;
                    msg_out_data <= {8'd0, 8'd1, 8'h31, 8'h00};
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
                    // H3: Full 32-bit result
                    msg_out_data <= result;
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
