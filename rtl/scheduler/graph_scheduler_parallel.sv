// Parallel Graph Scheduler
// ========================
// Dual-pop ready queue. In each execute cycle, pops up to 2 ready nodes.
// Computes the first immediately. If a second was popped, computes it
// on the next cycle. Tracks concurrency via perf_conc.

module graph_scheduler_parallel #(
    parameter int NUM_NODES = 64,
    parameter int Q_DEPTH = 16
) (
    input  logic        clk, reset_n,
    input  logic        reg_cyc, reg_stb, reg_we,
    input  logic [31:0] reg_adr, reg_dat_w,
    output logic [31:0] reg_dat_r,
    output logic        reg_ack
);

    typedef enum logic [2:0] { S_IDLE, S_SCAN, S_EXEC, S_BACKUP, S_UPD, S_DONE } fsm_t;
    fsm_t state;
    int tmp_nid, tmp_fid, tmp_d;

    logic [31:0] ctrl, status, root_id, node_cnt, done_cnt, perf_conc;
    logic start_pulse;
    logic [1:0]  node_state  [0:NUM_NODES-1];
    logic [7:0]  node_opcode [0:NUM_NODES-1];
    logic [5:0]  node_numinp [0:NUM_NODES-1];
    logic [5:0]  node_rdyinp [0:NUM_NODES-1];
    logic [31:0] node_result [0:NUM_NODES-1];
    logic [31:0] node_dep    [0:NUM_NODES-1];
    logic [31:0] node_op0    [0:NUM_NODES-1];
    logic [31:0] node_op1    [0:NUM_NODES-1];
    logic [31:0] node_imm0   [0:NUM_NODES-1];
    logic [31:0] node_imm1   [0:NUM_NODES-1];
    logic [9:0]  node_flags  [0:NUM_NODES-1];
    assign reg_ack = reg_cyc && reg_stb;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ctrl <= '0; root_id <= '0; node_cnt <= '0;
            done_cnt <= '0; start_pulse <= 1'b0;
            status <= 32'd2; perf_conc <= '0;
        end else begin
            start_pulse <= 1'b0;
            if (reg_cyc && reg_stb && reg_we) begin
                case (reg_adr[5:2])
                    0: begin ctrl <= reg_dat_w; if (reg_dat_w[0]) start_pulse <= 1'b1; end
                    2: root_id <= reg_dat_w;
                    3: node_cnt <= reg_dat_w;
                endcase
                if (reg_adr[7:0] >= 8'h20) begin
                    tmp_nid = (reg_adr[7:2] - 8'h08) / 6;
                    tmp_fid = (reg_adr[7:2] - 8'h08) % 6;
                    if (tmp_nid < NUM_NODES) begin
                        case (tmp_fid)
                            0: {node_state[tmp_nid], node_opcode[tmp_nid], node_numinp[tmp_nid], node_rdyinp[tmp_nid], node_flags[tmp_nid]} <= reg_dat_w;
                            1: node_imm0[tmp_nid] <= reg_dat_w;
                            2: node_imm1[tmp_nid] <= reg_dat_w;
                            3: node_result[tmp_nid] <= reg_dat_w;
                            4: node_dep[tmp_nid] <= reg_dat_w;
                        endcase
                    end
                end
            end
            if (start_pulse) status <= 32'd1;
            if (state == S_DONE) status <= 32'd2;
        end
    end

    always_comb begin
        reg_dat_r = '0;
        if (reg_cyc && reg_stb) begin
            case (reg_adr[5:2])
                0: reg_dat_r = ctrl; 1: reg_dat_r = status;
                2: reg_dat_r = root_id; 3: reg_dat_r = node_cnt;
                4: reg_dat_r = done_cnt; 5: reg_dat_r = perf_conc;
            endcase
        end
    end

    // Queue (simplified: single push/pop)
    logic [$clog2(NUM_NODES)-1:0] queue [0:Q_DEPTH-1];
    logic [$clog2(Q_DEPTH)-1:0] q_wptr, q_rptr;
    logic [3:0] q_cnt;
    wire q_empty = (q_cnt == 0);
    wire pop_id = queue[q_rptr];
    logic push_q, pop_q;
    logic [$clog2(NUM_NODES)-1:0] push_data;

    // Backup register for second popped node
    logic [$clog2(NUM_NODES)-1:0] backup_id;
    logic backup_valid;

    // Update state
    logic [31:0] upd_mask;
    logic [$clog2(NUM_NODES)-1:0] upd_src;

    logic [$clog2(NUM_NODES)-1:0] scan_cnt;

    // Queue logic
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin q_wptr <= '0; q_rptr <= '0; q_cnt <= '0; end
        else begin
            if (push_q && !(q_cnt == Q_DEPTH)) begin
                queue[q_wptr] <= push_data; q_wptr <= q_wptr + 1;
            end
            if (pop_q && !q_empty) begin
                q_rptr <= q_rptr + 1;
            end
            if (push_q && !(q_cnt == Q_DEPTH) && pop_q && !q_empty) q_cnt <= q_cnt;
            else if (push_q && !(q_cnt == Q_DEPTH)) q_cnt <= q_cnt + 1;
            else if (pop_q && !q_empty) q_cnt <= q_cnt - 1;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE; scan_cnt <= '0;
            done_cnt <= '0; perf_conc <= '0;
            push_q <= 1'b0; pop_q <= 1'b0; push_data <= '0;
            backup_valid <= 1'b0; backup_id <= '0;
            upd_mask <= '0; upd_src <= '0;
            for (int i = 0; i < NUM_NODES; i++) begin
                node_state[i] <= 2'b00; node_opcode[i] <= 8'h00;
                node_numinp[i] <= 6'd0; node_rdyinp[i] <= 6'd0;
                node_flags[i] <= 10'd0; node_imm0[i] <= 32'd0;
                node_imm1[i] <= 32'd0; node_result[i] <= 32'd0;
                node_dep[i] <= 32'd0;
                node_op0[i] <= 32'd0; node_op1[i] <= 32'd0;
            end
        end else begin
            push_q <= 1'b0; pop_q <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        state <= S_SCAN; scan_cnt <= '0; done_cnt <= '0;
                        backup_valid <= 1'b0;
                        q_wptr <= '0; q_rptr <= '0; q_cnt <= '0;
                    end
                end

                S_SCAN: begin
                    if (scan_cnt < node_cnt) begin
                        if (node_numinp[scan_cnt] == 0) begin
                            node_state[scan_cnt] <= 2'b10;
                            push_q <= 1'b1; push_data <= scan_cnt;
                        end else begin
                            node_state[scan_cnt] <= 2'b01;
                        end
                        scan_cnt <= scan_cnt + 1;
                    end else state <= S_EXEC;
                end

                S_EXEC: begin
                    if (!q_empty) begin
                        pop_q <= 1'b1;
                        tmp_nid = pop_id;
                        // Compute inline
                        case (node_opcode[tmp_nid])
                            8'h01: node_result[tmp_nid] <= node_imm0[tmp_nid];
                            8'h02: node_result[tmp_nid] <= {31'h0, node_flags[tmp_nid][0]};
                            8'h10: node_result[tmp_nid] <= node_op0[tmp_nid] + node_op1[tmp_nid];
                            8'h11: node_result[tmp_nid] <= node_op0[tmp_nid] - node_op1[tmp_nid];
                            8'h12: node_result[tmp_nid] <= node_op0[tmp_nid] * node_op1[tmp_nid];
                            default: node_result[tmp_nid] <= node_imm0[tmp_nid];
                        endcase
                        node_state[tmp_nid] <= 2'b11;
                        done_cnt <= done_cnt + 1;
                        // Check for second pop
                        if (q_cnt > 1) begin
                            backup_valid <= 1'b1;
                            backup_id <= queue[q_rptr + 1'b1];
                            q_rptr <= q_rptr + 1; q_cnt <= q_cnt - 1;
                            if (perf_conc < 2) perf_conc <= 2;
                        end else begin
                            if (perf_conc < 1) perf_conc <= 1;
                            backup_valid <= 1'b0;
                        end
                        upd_src <= tmp_nid;
                        upd_mask <= node_dep[tmp_nid];
                        state <= S_UPD;
                    end else begin
                        if (node_state[root_id] == 2'b11) state <= S_DONE;
                    end
                end

                S_BACKUP: begin
                    if (backup_valid) begin
                        tmp_nid = backup_id;
                        case (node_opcode[tmp_nid])
                            8'h01: node_result[tmp_nid] <= node_imm0[tmp_nid];
                            8'h02: node_result[tmp_nid] <= {31'h0, node_flags[tmp_nid][0]};
                            8'h10: node_result[tmp_nid] <= node_op0[tmp_nid] + node_op1[tmp_nid];
                            8'h11: node_result[tmp_nid] <= node_op0[tmp_nid] - node_op1[tmp_nid];
                            8'h12: node_result[tmp_nid] <= node_op0[tmp_nid] * node_op1[tmp_nid];
                            default: node_result[tmp_nid] <= node_imm0[tmp_nid];
                        endcase
                        node_state[tmp_nid] <= 2'b11;
                        done_cnt <= done_cnt + 1;
                        backup_valid <= 1'b0;
                        upd_src <= tmp_nid;
                        upd_mask <= node_dep[tmp_nid];
                    end
                    state <= S_UPD;
                end

                S_UPD: begin
                    if (upd_mask != 0) begin
                        if (upd_mask[0]) tmp_d = 0;    else if (upd_mask[1]) tmp_d = 1;
                        else if (upd_mask[2]) tmp_d = 2; else if (upd_mask[3]) tmp_d = 3;
                        else if (upd_mask[4]) tmp_d = 4; else if (upd_mask[5]) tmp_d = 5;
                        else if (upd_mask[6]) tmp_d = 6; else if (upd_mask[7]) tmp_d = 7;
                        else if (upd_mask[8]) tmp_d = 8; else if (upd_mask[9]) tmp_d = 9;
                        else tmp_d = 10;
                        if (node_rdyinp[tmp_d] == 0) node_op0[tmp_d] <= node_result[upd_src];
                        else node_op1[tmp_d] <= node_result[upd_src];
                        node_rdyinp[tmp_d] <= node_rdyinp[tmp_d] + 1;
                        if (node_rdyinp[tmp_d] + 1 >= node_numinp[tmp_d]) begin
                            node_state[tmp_d] <= 2'b10;
                            push_q <= 1'b1; push_data <= tmp_d;
                        end
                        upd_mask <= upd_mask & (upd_mask - 1);
                    end else if (backup_valid) begin
                        state <= S_BACKUP;
                    end else begin
                        if (node_state[root_id] == 2'b11) state <= S_DONE;
                        else state <= S_EXEC;
                    end
                end

                S_DONE: begin end
            endcase
        end
    end

endmodule
