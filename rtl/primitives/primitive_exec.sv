// Primitive Execution Unit
// ========================
// Receives EXEC_PRIM messages from the scheduler, computes results,
// and sends PRIM_RESULT responses back.
//
// Message protocol (3-word EXEC_PRIM):
//   Word 0: Header  {DEST=1, SRC, TYPE=0x30, FLAGS}
//   Word 1: Data 0  {node_id[7:0], opcode[7:0], op0[15:0]}
//   Word 2: Data 1  {op1[31:0]}  LAST=1
//
// Response (2-word PRIM_RESULT):
//   Word 0: Header  {DEST=0, SRC=1, TYPE=0x31, FLAGS}
//   Word 1: Data    {node_id[7:0], result[23:0]}  LAST=1

module primitive_exec (
    input  logic        clk,
    input  logic        reset_n,

    // Message input (from dispatcher)
    input  logic        msg_in_valid,
    input  logic [31:0] msg_in_data,
    input  logic        msg_in_last,
    output logic        msg_in_ready,

    // Message output (to dispatcher)
    output logic        msg_out_valid,
    output logic [31:0] msg_out_data,
    output logic        msg_out_last,
    input  logic        msg_out_ready
);

    // Message receive FSM
    typedef enum logic [2:0] {
        RX_IDLE,
        RX_HEADER,
        RX_DATA0,
        RX_DATA1,
        TX_HEADER,
        TX_DATA
    } rx_state_t;

    rx_state_t state;

    // Decoded fields
    logic [7:0] rx_node_id;
    logic [7:0] rx_opcode;
    logic [31:0] rx_op0, rx_op1;

    // Result
    logic [31:0] result;

    // Result computation (combinational)
    always_comb begin
        unique case (rx_opcode)
            8'h10: result = rx_op0 + rx_op1;                          // ADD
            8'h11: result = rx_op0 - rx_op1;                          // SUB
            8'h12: result = rx_op0 * rx_op1;                          // MUL
            8'h13: result = rx_op1 != 0 ? rx_op0 / rx_op1 : 32'h0;    // DIV
            8'h14: result = rx_op1 != 0 ? rx_op0 % rx_op1 : 32'h0;    // MOD
            8'h15: result = {31'h0, rx_op0 == rx_op1};                // EQ
            8'h16: result = {31'h0, $signed(rx_op0) < $signed(rx_op1)}; // LT
            8'h17: result = {31'h0, $signed(rx_op0) > $signed(rx_op1)}; // GT
            8'h18: result = {31'h0, $signed(rx_op0) <= $signed(rx_op1)}; // LE
            8'h19: result = {31'h0, $signed(rx_op0) >= $signed(rx_op1)}; // GE
            default: result = 32'h0;
        endcase
    end

    // FSM
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= RX_IDLE;
            rx_node_id <= '0;
            rx_opcode  <= '0;
            rx_op0 <= '0;
            rx_op1 <= '0;
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
                        state <= RX_DATA0;
                    end
                end

                RX_DATA0: begin
                    msg_in_ready <= 1'b1;
                    if (msg_in_valid) begin
                        rx_node_id <= msg_in_data[31:24];
                        rx_opcode  <= msg_in_data[23:16];
                        rx_op0     <= {16'h0, msg_in_data[15:0]};
                        state <= RX_DATA1;
                    end
                end

                RX_DATA1: begin
                    msg_in_ready <= 1'b1;
                    if (msg_in_valid) begin
                        rx_op1 <= msg_in_data;
                        state <= TX_HEADER;
                    end
                end

                TX_HEADER: begin
                    msg_out_valid <= 1'b1;
                    msg_out_data <= {8'd0, 8'd1, 8'h31, 8'h00};
                    msg_out_last <= 1'b0;
                    if (msg_out_ready) begin
                        state <= TX_DATA;
                    end
                end

                TX_DATA: begin
                    msg_out_valid <= 1'b1;
                    msg_out_data <= {rx_node_id, result[23:0]};
                    msg_out_last <= 1'b1;
                    if (msg_out_ready) begin
                        state <= RX_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
