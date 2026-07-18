`default_nettype none

module graph_scheduler_fp #(
    parameter int NUM_NODES = 64,
    parameter int Q_DEPTH = NUM_NODES
) (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        reg_cyc,
    input  logic        reg_stb,
    input  logic        reg_we,
    input  logic [31:0] reg_adr,
    input  logic [31:0] reg_dat_w,
    output logic [31:0] reg_dat_r,
    output logic        reg_ack,

    // H3: Extended message protocol (4-word EXEC_PRIM, 3-word PRIM_RESULT)
    output logic        msg_tx_valid,
    output logic        msg_tx_last,
    output logic [31:0] msg_tx_data,
    input  logic        msg_tx_ready,

    input  logic        msg_rx_valid,
    input  logic        msg_rx_last,
    input  logic [31:0] msg_rx_data,
    output logic        msg_rx_ready
);

    localparam int NODE_ID_W = $clog2(NUM_NODES);
    localparam int DEP_W = NUM_NODES;
    localparam int Q_CNT_W = $clog2(Q_DEPTH) + 1;

    logic [31:0] ctrl, status, root_id, node_cnt, done_cnt;
    logic start_pulse;
    logic q_overflow;
    assign reg_ack = reg_cyc && reg_stb;

    logic [1:0]  node_state  [0:NUM_NODES-1];
    logic [7:0]  node_opcode [0:NUM_NODES-1];
    logic [5:0]  node_numinp [0:NUM_NODES-1];
    logic [5:0]  node_rdyinp [0:NUM_NODES-1];
    logic [9:0]  node_flags  [0:NUM_NODES-1];
    logic [31:0] node_imm0   [0:NUM_NODES-1];
    logic [31:0] node_imm1   [0:NUM_NODES-1];
    logic [31:0] node_result [0:NUM_NODES-1];
    logic [DEP_W-1:0] node_dep [0:NUM_NODES-1];
    logic [31:0] node_op0    [0:NUM_NODES-1];
    logic [31:0] node_op1    [0:NUM_NODES-1];
    logic [NODE_ID_W-1:0] node_src0 [0:NUM_NODES-1];
    logic [NODE_ID_W-1:0] node_src1 [0:NUM_NODES-1];

    logic [NODE_ID_W-1:0] queue [0:Q_DEPTH-1];
    logic [NODE_ID_W-1:0] q_wptr, q_rptr;
    logic [Q_CNT_W-1:0] q_cnt;
    logic q_empty, q_full;
    wire [NODE_ID_W-1:0] pop_q_id = queue[q_rptr];
    assign q_empty = (q_cnt == 0);
    assign q_full  = (q_cnt == Q_DEPTH);

    typedef enum logic [3:0] {
        S_IDLE, S_SCAN, S_EXEC, S_DISPATCH, S_DISP_D0, S_DISP_D1, S_DISP_D2,
        S_WAIT_MSG, S_WAIT_RES, S_UPD_SCAN, S_UPD_NEXT, S_DONE
    } fsm_t;

    fsm_t state;
    wire done_state = (state == S_DONE);

    logic [NODE_ID_W-1:0] scan_cnt;
    logic [DEP_W-1:0] upd_dep_mask;
    logic [NODE_ID_W-1:0] upd_cur;
    logic push_q, pop_q;
    logic [NODE_ID_W-1:0] push_q_id;
    logic [NODE_ID_W-1:0] exec_id;
    int tmp_nid, tmp_fid;
    logic tmp_found;
    logic [NODE_ID_W-1:0] tmp_res_nid;
    int tmp_rnid, tmp_rfid;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ctrl <= '0; root_id <= '0; node_cnt <= '0;
            done_cnt <= '0; start_pulse <= 1'b0;
            status <= 32'd2; q_overflow <= 1'b0;
            state <= S_IDLE; scan_cnt <= '0;
            pop_q <= 1'b0; push_q <= 1'b0;
            upd_dep_mask <= '0; upd_cur <= '0; exec_id <= '0;
            q_wptr <= '0; q_rptr <= '0; q_cnt <= '0;
            msg_tx_valid <= 1'b0; msg_tx_last <= 1'b0; msg_tx_data <= '0;
            msg_rx_ready <= 1'b0;
            for (int i = 0; i < NUM_NODES; i++) begin
                node_state[i]  <= 2'b00;
                node_opcode[i] <= 8'h00;
                node_numinp[i] <= 6'd0;
                node_rdyinp[i] <= 6'd0;
                node_flags[i]  <= 10'd0;
                node_imm0[i]   <= 32'd0;
                node_imm1[i]   <= 32'd0;
                node_result[i] <= 32'd0;
                node_dep[i]    <= '0;
                node_op0[i]    <= 32'd0;
                node_op1[i]    <= 32'd0;
                node_src0[i]   <= '0;
                node_src1[i]   <= '0;
            end
        end else begin
            start_pulse <= 1'b0;
            pop_q <= 1'b0; push_q <= 1'b0;
            msg_tx_valid <= 1'b0;

            if (reg_cyc && reg_stb && reg_we) begin
                case (reg_adr[5:2])
                    4'd0: begin ctrl <= reg_dat_w; if (reg_dat_w[0]) start_pulse <= 1'b1; end
                    4'd2: root_id  <= reg_dat_w;
                    4'd3: node_cnt <= reg_dat_w;
                    default: ;
                endcase
                if (reg_adr[7:0] >= 8'h20) begin
                    tmp_nid = (reg_adr[7:2] - 6'd8) / 6;
                    tmp_fid = (reg_adr[7:2] - 6'd8) % 6;
                    if (tmp_nid < NUM_NODES) begin
                        case (tmp_fid)
                            0: {node_state[tmp_nid], node_opcode[tmp_nid], node_numinp[tmp_nid], node_rdyinp[tmp_nid], node_flags[tmp_nid]} <= reg_dat_w;
                            1: node_imm0[tmp_nid] <= reg_dat_w;
                            2: node_imm1[tmp_nid] <= reg_dat_w;
                            3: node_result[tmp_nid] <= reg_dat_w;
                            4: node_dep[tmp_nid] <= reg_dat_w[DEP_W-1:0];
                            5: begin
                                node_src0[tmp_nid] <= reg_dat_w[7:0];
                                node_src1[tmp_nid] <= reg_dat_w[15:8];
                            end
                            default: ;
                        endcase
                    end
                end
            end

            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        state <= S_SCAN; scan_cnt <= '0; done_cnt <= '0;
                        q_overflow <= 1'b0;
                        q_wptr <= '0; q_rptr <= '0; q_cnt <= '0;
                    end
                end

                S_SCAN: begin
                    if (scan_cnt < node_cnt) begin
                        if (node_numinp[scan_cnt] == 0) begin
                            node_state[scan_cnt] <= 2'b10;
                            if (!q_full) begin
                                push_q <= 1'b1; push_q_id <= scan_cnt;
                                queue[q_wptr] <= scan_cnt;
                                q_wptr <= q_wptr + 1'b1;
                                q_cnt <= q_cnt + 1'b1;
                            end else q_overflow <= 1'b1;
                        end else begin
                            node_state[scan_cnt] <= 2'b01;
                        end
                        scan_cnt <= scan_cnt + 1'b1;
                    end else state <= S_EXEC;
                end

                S_EXEC: begin
                    if (!q_empty) begin
                        exec_id <= pop_q_id;
                        pop_q <= 1'b1;
                        q_rptr <= q_rptr + 1'b1;
                        q_cnt <= q_cnt - 1'b1;
                        state <= S_DISPATCH;
                    end else begin
                        state <= S_DONE;
                        if (node_state[root_id] != 2'b11)
                            status <= {28'h0, 3'b100};
                    end
                end

                S_DISPATCH: begin
                    if (node_opcode[exec_id] == 8'h01 || node_opcode[exec_id] == 8'h02) begin
                        node_result[exec_id] <= (node_opcode[exec_id] == 8'h01) ?
                            node_imm0[exec_id] : {31'h0, node_flags[exec_id][0]};
                        node_state[exec_id] <= 2'b11;
                        done_cnt <= done_cnt + 1'b1;
                        upd_dep_mask <= node_dep[exec_id];
                        state <= S_UPD_SCAN;
                    end else begin
                        // H3: 4-word EXEC_PRIM: header, {node_id, opcode, rsvd}, op0, op1
                        msg_tx_valid <= 1'b1;
                        msg_tx_data <= {8'd1, 8'd0, 8'h30, 8'h00};
                        msg_tx_last <= 1'b0;
                        if (msg_tx_ready) state <= S_DISP_D0;
                    end
                end

                S_DISP_D0: begin
                    msg_tx_valid <= 1'b1;
                    msg_tx_data <= {exec_id, node_opcode[exec_id], 8'h00, 8'h00};
                    msg_tx_last <= 1'b0;
                    if (msg_tx_ready) state <= S_DISP_D1;
                end

                S_DISP_D1: begin
                    msg_tx_valid <= 1'b1;
                    msg_tx_data <= node_op0[exec_id]; // H3: full 32-bit op0
                    msg_tx_last <= 1'b0;
                    if (msg_tx_ready) state <= S_DISP_D2;
                end

                S_DISP_D2: begin
                    msg_tx_valid <= 1'b1;
                    msg_tx_data <= node_op1[exec_id]; // H3: full 32-bit op1
                    msg_tx_last <= 1'b1;
                    if (msg_tx_ready) state <= S_WAIT_MSG;
                end

                S_WAIT_MSG: begin
                    msg_rx_ready <= 1'b1;
                    if (msg_rx_valid) begin
                        msg_rx_ready <= 1'b0;
                        state <= S_WAIT_RES;
                    end
                end

                S_WAIT_RES: begin
                    msg_rx_ready <= 1'b1;
                    if (msg_rx_valid && msg_rx_last) begin
                        tmp_res_nid = msg_rx_data[NODE_ID_W-1+24:24];
                        node_result[tmp_res_nid] <= msg_rx_data;
                        node_state[tmp_res_nid] <= 2'b11;
                        done_cnt <= done_cnt + 1'b1;
                        msg_rx_ready <= 1'b0;
                        upd_dep_mask <= node_dep[tmp_res_nid];
                        exec_id <= tmp_res_nid;
                        state <= S_UPD_SCAN;
                    end
                end

                S_UPD_SCAN: begin
                    if (upd_dep_mask != 0) begin
                        tmp_found = 1'b0;
                        for (int b = 0; b < DEP_W; b++) begin
                            if (!tmp_found && upd_dep_mask[b]) begin
                                upd_cur <= b[NODE_ID_W-1:0];
                                tmp_found = 1'b1;
                            end
                        end
                        upd_dep_mask <= upd_dep_mask & (upd_dep_mask - 1);
                        state <= S_UPD_NEXT;
                    end else begin
                        if (node_state[root_id] == 2'b11) state <= S_DONE;
                        else state <= S_EXEC;
                    end
                end

                S_UPD_NEXT: begin
                    if (upd_cur < NUM_NODES) begin
                        // C5: Source-based slot assignment
                        if (node_src0[upd_cur] == exec_id)
                            node_op0[upd_cur] <= node_result[exec_id];
                        else if (node_src1[upd_cur] == exec_id)
                            node_op1[upd_cur] <= node_result[exec_id];
                        node_rdyinp[upd_cur] <= node_rdyinp[upd_cur] + 1'b1;
                        if (node_rdyinp[upd_cur] + 1 >= node_numinp[upd_cur]) begin
                            node_state[upd_cur] <= 2'b10;
                            if (!q_full) begin
                                push_q <= 1'b1; push_q_id <= upd_cur;
                                queue[q_wptr] <= upd_cur;
                                q_wptr <= q_wptr + 1'b1;
                                q_cnt <= q_cnt + 1'b1;
                            end else q_overflow <= 1'b1;
                        end
                    end
                    state <= S_UPD_SCAN;
                end

                S_DONE: begin end
                default: state <= S_IDLE;
            endcase

            if (start_pulse) status <= {30'h0, q_overflow, 1'b1};
            if (done_state)  status <= {29'h0, q_overflow, 2'b10};
        end
    end

    always_comb begin
        reg_dat_r = '0;
        if (reg_cyc && reg_stb) begin
            case (reg_adr[5:2])
                4'd0: reg_dat_r = ctrl;
                4'd1: reg_dat_r = status;
                4'd2: reg_dat_r = root_id;
                4'd3: reg_dat_r = node_cnt;
                4'd4: reg_dat_r = done_cnt;
                default: begin
                    if (reg_adr[7:0] >= 8'h20) begin
                        tmp_rnid = (reg_adr[7:2] - 6'd8) / 6;
                        tmp_rfid = (reg_adr[7:2] - 6'd8) % 6;
                        if (tmp_rnid < NUM_NODES) begin
                            case (tmp_rfid)
                                0: reg_dat_r = {node_state[tmp_rnid], node_opcode[tmp_rnid], node_numinp[tmp_rnid], node_rdyinp[tmp_rnid], node_flags[tmp_rnid]};
                                1: reg_dat_r = node_imm0[tmp_rnid];
                                2: reg_dat_r = node_imm1[tmp_rnid];
                                3: reg_dat_r = node_result[tmp_rnid];
                                4: reg_dat_r = node_dep[tmp_rnid][31:0];
                                default: reg_dat_r = '0;
                            endcase
                        end
                    end
                end
            endcase
        end
    end

endmodule

`default_nettype wire
