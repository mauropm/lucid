`default_nettype none

module graph_scheduler_parallel #(
    parameter int NUM_NODES = 64,
    parameter int Q_DEPTH = NUM_NODES
) (
    input  logic        clk, reset_n,
    input  logic        reg_cyc, reg_stb, reg_we,
    input  logic [31:0] reg_adr, reg_dat_w,
    output logic [31:0] reg_dat_r,
    output logic        reg_ack
);

    localparam int NODE_ID_W = $clog2(NUM_NODES);
    localparam int DEP_W = NUM_NODES;
    localparam int Q_CNT_W = $clog2(Q_DEPTH) + 1;

    typedef enum logic [3:0] { S_IDLE, S_SCAN, S_EXEC, S_BACKUP, S_DIV, S_UPD_SCAN, S_UPD_NEXT, S_DONE } fsm_t;
    fsm_t state;

    logic [31:0] ctrl, status, root_id, node_cnt, done_cnt, perf_conc;
    logic start_pulse;
    logic q_overflow;

    logic [1:0]  node_state  [0:NUM_NODES-1];
    logic [7:0]  node_opcode [0:NUM_NODES-1];
    logic [5:0]  node_numinp [0:NUM_NODES-1];
    logic [5:0]  node_rdyinp [0:NUM_NODES-1];
    logic [31:0] node_result [0:NUM_NODES-1];
    logic [DEP_W-1:0] node_dep [0:NUM_NODES-1];
    logic [31:0] node_op0    [0:NUM_NODES-1];
    logic [31:0] node_op1    [0:NUM_NODES-1];
    logic [31:0] node_imm0   [0:NUM_NODES-1];
    logic [31:0] node_imm1   [0:NUM_NODES-1];
    logic [9:0]  node_flags  [0:NUM_NODES-1];
    logic [NODE_ID_W-1:0] node_src0 [0:NUM_NODES-1];
    logic [NODE_ID_W-1:0] node_src1 [0:NUM_NODES-1];

    assign reg_ack = reg_cyc && reg_stb;

    // C9+H1: Single queue process (no multi-driver)
    logic [NODE_ID_W-1:0] queue [0:Q_DEPTH-1];
    logic [NODE_ID_W-1:0] q_wptr, q_rptr;
    logic [Q_CNT_W-1:0] q_cnt; // M6: proper width
    wire q_empty = (q_cnt == 0);
    wire q_full  = (q_cnt == Q_DEPTH);
    wire [NODE_ID_W-1:0] pop_id = queue[q_rptr];

    logic push_q, pop_q, pop_q2;
    logic [NODE_ID_W-1:0] push_data;

    logic [NODE_ID_W-1:0] backup_id;
    logic backup_valid;

    logic [DEP_W-1:0] upd_mask;
    logic [NODE_ID_W-1:0] upd_src;
    logic [NODE_ID_W-1:0] upd_cur;

    logic [NODE_ID_W-1:0] scan_cnt;
    logic [NODE_ID_W-1:0] exec_id;
    int tmp_nid, tmp_fid;
    logic tmp_found;
    int tmp_rnid, tmp_rfid;

    logic [4:0]  div_cnt;
    logic [31:0] div_rem, div_quo, div_divisor;
    logic [NODE_ID_W-1:0] div_node_id;
    logic        div_is_mod;
    wire [31:0]  div_rem_shifted = {div_rem[30:0], div_quo[31]};
    wire [31:0]  div_sub_result  = div_rem_shifted - div_divisor;
    wire         div_sub_ok      = ~div_sub_result[31];

    // Queue process
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            q_wptr <= '0; q_rptr <= '0; q_cnt <= '0;
        end else begin
            if (push_q && !q_full) begin
                queue[q_wptr] <= push_data;
                q_wptr <= q_wptr + 1'b1;
            end
            if (pop_q && !q_empty) begin
                q_rptr <= q_rptr + 1'b1;
            end
            if (pop_q2 && !q_empty && q_cnt > 1) begin
                q_rptr <= q_rptr + 1'b1;
            end
            q_cnt <= q_cnt
                + (push_q && !q_full ? 1'b1 : '0)
                - (pop_q  && !q_empty ? 1'b1 : '0)
                - (pop_q2 && !q_empty && q_cnt > 1 ? 1'b1 : '0);
        end
    end

    // H1: Single process for all FSM + register state
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ctrl <= '0; root_id <= '0; node_cnt <= '0;
            done_cnt <= '0; start_pulse <= 1'b0;
            status <= 32'd2; perf_conc <= '0; q_overflow <= 1'b0;
            state <= S_IDLE; scan_cnt <= '0;
            push_q <= 1'b0; pop_q <= 1'b0; pop_q2 <= 1'b0;
            push_data <= '0;
            backup_valid <= 1'b0; backup_id <= '0;
            upd_mask <= '0; upd_src <= '0; upd_cur <= '0;
            exec_id <= '0;
            div_cnt <= '0; div_rem <= '0; div_quo <= '0; div_divisor <= '0;
            div_node_id <= '0; div_is_mod <= 1'b0;
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
            push_q <= 1'b0; pop_q <= 1'b0; pop_q2 <= 1'b0;
            start_pulse <= 1'b0;

            if (reg_cyc && reg_stb && reg_we) begin
                // Control registers (only when NOT writing to node fields)
                if (reg_adr[7:0] < 8'h20) begin
                    case (reg_adr[5:2])
                        4'd0: begin ctrl <= reg_dat_w; if (reg_dat_w[0]) start_pulse <= 1'b1; end
                        4'd2: root_id  <= reg_dat_w;
                        4'd3: node_cnt <= reg_dat_w;
                        default: ;
                    endcase
                end
                // Node field write (address >= 0x20, 8-word stride)
                if (reg_adr[11:0] >= 12'h020) begin
                    tmp_nid = (reg_adr[11:0] - 12'h020) >> 5;
                    tmp_fid = reg_adr[4:2];
                    if (tmp_nid < NUM_NODES) begin
                        case (tmp_fid)
                            0: {node_state[tmp_nid], node_opcode[tmp_nid], node_numinp[tmp_nid], node_rdyinp[tmp_nid], node_flags[tmp_nid]} <= reg_dat_w;
                            1: node_imm0[tmp_nid] <= reg_dat_w;
                            2: node_imm1[tmp_nid] <= reg_dat_w;
                            3: node_result[tmp_nid] <= reg_dat_w;
                            4: node_dep[tmp_nid][31:0] <= reg_dat_w;
                            5: begin
                                node_src0[tmp_nid] <= reg_dat_w[7:0];
                                node_src1[tmp_nid] <= reg_dat_w[15:8];
                            end
                            6: node_dep[tmp_nid][63:32] <= reg_dat_w;
                            default: ;
                        endcase
                    end
                end
            end

            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        state <= S_SCAN; scan_cnt <= '0; done_cnt <= '0;
                        backup_valid <= 1'b0; q_overflow <= 1'b0;
                    end
                end

                S_SCAN: begin
                    if (scan_cnt < node_cnt) begin
                        if (node_numinp[scan_cnt] == 0) begin
                            node_state[scan_cnt] <= 2'b10;
                            if (!q_full) begin
                                push_q <= 1'b1; push_data <= scan_cnt;
                            end else q_overflow <= 1'b1;
                        end else begin
                            node_state[scan_cnt] <= 2'b01;
                        end
                        scan_cnt <= scan_cnt + 1'b1;
                    end else state <= S_EXEC;
                end

                S_EXEC: begin
                    if (!q_empty) begin
                        pop_q <= 1'b1;
                        exec_id <= pop_id;
                        div_node_id <= pop_id;
                        case (node_opcode[pop_id])
                            8'h01: node_result[pop_id] <= node_imm0[pop_id];
                            8'h02: node_result[pop_id] <= {31'h0, node_flags[pop_id][0]};
                            8'h10: node_result[pop_id] <= node_op0[pop_id] + node_op1[pop_id];
                            8'h11: node_result[pop_id] <= node_op0[pop_id] - node_op1[pop_id];
                            8'h12: node_result[pop_id] <= node_op0[pop_id] * node_op1[pop_id];
                            8'h13, 8'h14: begin
                                if (node_op1[pop_id] != 0) begin
                                    state <= S_DIV;
                                    div_cnt <= 5'd31;
                                    div_quo <= node_op0[pop_id];
                                    div_rem <= '0;
                                    div_divisor <= node_op1[pop_id];
                                    div_is_mod <= (node_opcode[pop_id] == 8'h14);
                                end else begin
                                    node_result[pop_id] <= 32'd0;
                                end
                            end
                            8'h15: node_result[pop_id] <= {31'h0, node_op0[pop_id] == node_op1[pop_id]};
                            8'h16: node_result[pop_id] <= {31'h0, $signed(node_op0[pop_id]) < $signed(node_op1[pop_id])};
                            8'h17: node_result[pop_id] <= {31'h0, $signed(node_op0[pop_id]) > $signed(node_op1[pop_id])};
                            8'h18: node_result[pop_id] <= {31'h0, $signed(node_op0[pop_id]) <= $signed(node_op1[pop_id])};
                            8'h19: node_result[pop_id] <= {31'h0, $signed(node_op0[pop_id]) >= $signed(node_op1[pop_id])};
                            default: node_result[pop_id] <= node_imm0[pop_id];
                        endcase
                        if (node_opcode[pop_id] != 8'h13 && node_opcode[pop_id] != 8'h14) begin
                            node_state[pop_id] <= 2'b11;
                            done_cnt <= done_cnt + 1'b1;
                        end else if (node_op1[pop_id] == 0) begin
                            node_state[pop_id] <= 2'b11;
                            done_cnt <= done_cnt + 1'b1;
                        end

                        if (q_cnt > 1) begin
                            pop_q2 <= 1'b1;
                            backup_valid <= 1'b1;
                            backup_id <= queue[q_rptr + 1'b1];
                            if (perf_conc < 2) perf_conc <= 2;
                        end else begin
                            if (perf_conc < 1) perf_conc <= 1;
                            backup_valid <= 1'b0;
                        end
                        upd_src <= pop_id;
                        upd_mask <= node_dep[pop_id];
                        if (state != S_DIV)
                            state <= S_UPD_SCAN;
                    end else begin
                        if (node_state[root_id] == 2'b11)
                            state <= S_DONE;
                        else if (done_cnt >= node_cnt)
                            state <= S_DONE;
                        else
                            state <= S_EXEC;
                    end
                end

                S_BACKUP: begin
                    if (backup_valid) begin
                        exec_id <= backup_id;
                        div_node_id <= backup_id;
                        case (node_opcode[backup_id])
                            8'h01: node_result[backup_id] <= node_imm0[backup_id];
                            8'h02: node_result[backup_id] <= {31'h0, node_flags[backup_id][0]};
                            8'h10: node_result[backup_id] <= node_op0[backup_id] + node_op1[backup_id];
                            8'h11: node_result[backup_id] <= node_op0[backup_id] - node_op1[backup_id];
                            8'h12: node_result[backup_id] <= node_op0[backup_id] * node_op1[backup_id];
                            8'h13, 8'h14: begin
                                if (node_op1[backup_id] != 0) begin
                                    state <= S_DIV;
                                    div_cnt <= 5'd31;
                                    div_quo <= node_op0[backup_id];
                                    div_rem <= '0;
                                    div_divisor <= node_op1[backup_id];
                                    div_is_mod <= (node_opcode[backup_id] == 8'h14);
                                end else begin
                                    node_result[backup_id] <= 32'd0;
                                end
                            end
                            8'h15: node_result[backup_id] <= {31'h0, node_op0[backup_id] == node_op1[backup_id]};
                            8'h16: node_result[backup_id] <= {31'h0, $signed(node_op0[backup_id]) < $signed(node_op1[backup_id])};
                            8'h17: node_result[backup_id] <= {31'h0, $signed(node_op0[backup_id]) > $signed(node_op1[backup_id])};
                            8'h18: node_result[backup_id] <= {31'h0, $signed(node_op0[backup_id]) <= $signed(node_op1[backup_id])};
                            8'h19: node_result[backup_id] <= {31'h0, $signed(node_op0[backup_id]) >= $signed(node_op1[backup_id])};
                            default: node_result[backup_id] <= node_imm0[backup_id];
                        endcase
                        if (node_opcode[backup_id] != 8'h13 && node_opcode[backup_id] != 8'h14) begin
                            node_state[backup_id] <= 2'b11;
                            done_cnt <= done_cnt + 1'b1;
                        end else if (node_op1[backup_id] == 0) begin
                            node_state[backup_id] <= 2'b11;
                            done_cnt <= done_cnt + 1'b1;
                        end
                        backup_valid <= 1'b0;
                        upd_src <= backup_id;
                        upd_mask <= node_dep[backup_id];
                        if (state != S_DIV)
                            state <= S_UPD_SCAN;
                    end else begin
                        state <= S_UPD_SCAN;
                    end
                end

                S_UPD_SCAN: begin
                    if (upd_mask != 0) begin
                        tmp_found = 1'b0;
                        for (int b = 0; b < DEP_W; b++) begin
                            if (!tmp_found && upd_mask[b]) begin
                                upd_cur <= b[NODE_ID_W-1:0];
                                tmp_found = 1'b1;
                            end
                        end
                        upd_mask <= upd_mask & (upd_mask - 1);
                        state <= S_UPD_NEXT;
                    end else if (backup_valid) begin
                        state <= S_BACKUP;
                    end else begin
                        if (node_state[root_id] == 2'b11) state <= S_DONE;
                        else state <= S_EXEC;
                    end
                end

                S_DIV: begin
                    if (div_sub_ok) begin
                        div_rem <= div_sub_result;
                        div_quo <= {div_quo[30:0], 1'b1};
                    end else begin
                        div_rem <= div_rem_shifted;
                        div_quo <= {div_quo[30:0], 1'b0};
                    end
                    if (div_cnt == 5'd0) begin
                        if (div_is_mod)
                            node_result[div_node_id] <= div_sub_ok ? div_sub_result : div_rem_shifted;
                        else
                            node_result[div_node_id] <= div_sub_ok ? {div_quo[30:0], 1'b1} : {div_quo[30:0], 1'b0};
                        node_state[div_node_id] <= 2'b11;
                        done_cnt <= done_cnt + 1'b1;
                        upd_mask <= node_dep[div_node_id];
                        upd_src <= div_node_id;
                        state <= S_UPD_SCAN;
                    end else begin
                        div_cnt <= div_cnt - 1'b1;
                    end
                end

                S_UPD_NEXT: begin
                    if (upd_cur < NUM_NODES) begin
                        if (node_src0[upd_cur] == upd_src)
                            node_op0[upd_cur] <= node_result[upd_src];
                        else if (node_src1[upd_cur] == upd_src)
                            node_op1[upd_cur] <= node_result[upd_src];
                        node_rdyinp[upd_cur] <= node_rdyinp[upd_cur] + 1'b1;
                        if (node_rdyinp[upd_cur] + 1 >= node_numinp[upd_cur]) begin
                            node_state[upd_cur] <= 2'b10;
                            if (!q_full) begin
                                push_q <= 1'b1; push_data <= upd_cur;
                            end else q_overflow <= 1'b1;
                        end
                    end
                    state <= S_UPD_SCAN;
                end

                S_DONE: begin end
                default: state <= S_IDLE;
            endcase

            if (start_pulse) status <= {30'h0, q_overflow, 1'b1};
            if (state == S_DONE) status <= {29'h0, q_overflow, 2'b10};
        end
    end

    always_comb begin
        reg_dat_r = '0;
        tmp_rnid = '0;
        tmp_rfid = '0;
        if (reg_cyc && reg_stb) begin
            case (reg_adr[5:2])
                4'd0: reg_dat_r = ctrl;
                4'd1: reg_dat_r = status;
                4'd2: reg_dat_r = root_id;
                4'd3: reg_dat_r = node_cnt;
                4'd4: reg_dat_r = done_cnt;
                4'd5: reg_dat_r = perf_conc;
                default: begin
                    if (reg_adr[11:0] >= 12'h020) begin
                        tmp_rnid = (reg_adr[11:0] - 12'h020) >> 5;
                        tmp_rfid = reg_adr[4:2];
                        if (tmp_rnid < NUM_NODES) begin
                            case (tmp_rfid)
                                0: reg_dat_r = {node_state[tmp_rnid], node_opcode[tmp_rnid], node_numinp[tmp_rnid], node_rdyinp[tmp_rnid], node_flags[tmp_rnid]};
                                1: reg_dat_r = node_imm0[tmp_rnid];
                                2: reg_dat_r = node_imm1[tmp_rnid];
                                3: reg_dat_r = node_result[tmp_rnid];
                                4: reg_dat_r = node_dep[tmp_rnid][31:0];
                                5: reg_dat_r = {16'h0, node_src1[tmp_rnid], node_src0[tmp_rnid]};
                                6: reg_dat_r = node_dep[tmp_rnid][63:32];
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
