`default_nettype none

module graph_scheduler #(
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
    output logic        reg_ack
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
    logic [DEP_W-1:0] node_dep    [0:NUM_NODES-1];
    logic [31:0] node_op0    [0:NUM_NODES-1];
    logic [31:0] node_op1    [0:NUM_NODES-1];
    logic [31:0] node_op2    [0:NUM_NODES-1];
    // C5: Source tracking - which producer node feeds each operand slot
    logic [NODE_ID_W-1:0] node_src0 [0:NUM_NODES-1];
    logic [NODE_ID_W-1:0] node_src1 [0:NUM_NODES-1];
    logic [NODE_ID_W-1:0] node_src2 [0:NUM_NODES-1];

    // Ready queue
    logic [NODE_ID_W-1:0] queue [0:Q_DEPTH-1];
    logic [NODE_ID_W-1:0] q_wptr, q_rptr;
    logic [Q_CNT_W-1:0] q_cnt;
    logic q_empty, q_full;
    wire [NODE_ID_W-1:0] pop_q_id = queue[q_rptr];

    assign q_empty = (q_cnt == 0);
    assign q_full  = (q_cnt == Q_DEPTH);

    typedef enum logic [3:0] {
        S_IDLE, S_SCAN, S_EXEC, S_RESULT, S_DIV, S_UPD_SCAN, S_UPD_NEXT, S_DONE
    } fsm_t;

    fsm_t state;
    wire done_state = (state == S_DONE);

    logic [NODE_ID_W-1:0] scan_cnt;
    logic [DEP_W-1:0] upd_dep_mask;
    logic [NODE_ID_W-1:0] upd_cur;
    logic [NODE_ID_W-1:0] exec_id;
    logic [7:0]  tmp_nid;
    logic [2:0]  tmp_fid;
    logic tmp_found;
    logic [7:0]  tmp_rnid;
    logic [2:0]  tmp_rfid;

    logic [4:0]  div_cnt;
    logic [31:0] div_rem, div_quo, div_divisor;
    wire [31:0]  div_rem_shifted = {div_rem[30:0], div_quo[31]};
    wire [31:0]  div_sub_result  = div_rem_shifted - div_divisor;
    wire         div_sub_ok      = ~div_sub_result[31];

    // H1: Single process for all state (no multi-driver)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ctrl <= '0; root_id <= '0; node_cnt <= '0;
            done_cnt <= '0; start_pulse <= 1'b0;
            status <= 32'd2;
            q_overflow <= 1'b0;
            state <= S_IDLE;
            scan_cnt <= '0;
            upd_dep_mask <= '0; upd_cur <= '0; exec_id <= '0;
            q_wptr <= '0; q_rptr <= '0; q_cnt <= '0;
            div_cnt <= '0; div_rem <= '0; div_quo <= '0; div_divisor <= '0;
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
                node_op2[i]    <= 32'd0;
                node_src0[i]   <= '0;
                node_src1[i]   <= '0;
                node_src2[i]   <= '0;
            end
        end else begin
            start_pulse <= 1'b0;

            // CPU register writes
            if (reg_cyc && reg_stb && reg_we) begin
                // Control registers (only when NOT writing to node fields)
                if (reg_adr[7:0] < 8'h20) begin
                    case (reg_adr[5:2])
                        4'd0: begin
                            ctrl <= reg_dat_w;
                            if (reg_dat_w[0]) start_pulse <= 1'b1;
                        end
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
                            1: node_imm0[tmp_nid]   <= reg_dat_w;
                            2: node_imm1[tmp_nid]   <= reg_dat_w;
                            3: node_result[tmp_nid]  <= reg_dat_w;
                            4: node_dep[tmp_nid][31:0] <= reg_dat_w;
                            5: begin
                                node_src0[tmp_nid] <= reg_dat_w[7:0];
                                node_src1[tmp_nid] <= reg_dat_w[15:8];
                                node_src2[tmp_nid] <= reg_dat_w[23:16];
                            end
                            6: node_dep[tmp_nid][63:32] <= reg_dat_w;
                            default: ;
                        endcase
                    end
                end
            end

            // FSM
            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        state <= S_SCAN;
                        scan_cnt <= '0;
                        done_cnt <= '0;
                        q_overflow <= 1'b0;
                        q_wptr <= '0; q_rptr <= '0; q_cnt <= '0;
                    end
                end

                S_SCAN: begin
                    if (scan_cnt < node_cnt) begin
                        if (node_numinp[scan_cnt] == 0) begin
                            node_state[scan_cnt] <= 2'b10;
                            if (!q_full) begin
                                queue[q_wptr] <= scan_cnt;
                                q_wptr <= q_wptr + 1'b1;
                                q_cnt <= q_cnt + 1'b1;
                            end else begin
                                q_overflow <= 1'b1;
                            end
                        end else begin
                            node_state[scan_cnt] <= 2'b01;
                        end
                        scan_cnt <= scan_cnt + 1'b1;
                    end else begin
                        state <= S_EXEC;
                    end
                end

                S_EXEC: begin
                    if (!q_empty) begin
                        exec_id <= pop_q_id;
                        q_rptr <= q_rptr + 1'b1;
                        q_cnt <= q_cnt - 1'b1;
                        state <= S_RESULT;
                    end else begin
                        state <= S_DONE;
                        // M10: Check if root is done
                        if (node_state[root_id] != 2'b11)
                            status <= {28'h0, 3'b100}; // Error: incomplete
                    end
                end

                S_RESULT: begin
                    case (node_opcode[exec_id])
                        8'h01: node_result[exec_id] <= node_imm0[exec_id];
                        8'h02: node_result[exec_id] <= {31'h0, node_flags[exec_id][0]};
                        8'h10: node_result[exec_id] <= node_op0[exec_id] + node_op1[exec_id];
                        8'h11: node_result[exec_id] <= node_op0[exec_id] - node_op1[exec_id];
                        8'h12: node_result[exec_id] <= node_op0[exec_id] * node_op1[exec_id];
                        8'h13: begin
                            if (node_op1[exec_id] == 0) begin
                                node_result[exec_id] <= 32'd0;
                            end else begin
                                state <= S_DIV;
                                div_cnt <= 5'd31;
                                div_quo <= node_op0[exec_id];
                                div_rem <= '0;
                                div_divisor <= node_op1[exec_id];
                            end
                        end
                        8'h14: begin
                            if (node_op1[exec_id] == 0) begin
                                node_result[exec_id] <= 32'd0;
                            end else begin
                                state <= S_DIV;
                                div_cnt <= 5'd31;
                                div_quo <= node_op0[exec_id];
                                div_rem <= '0;
                                div_divisor <= node_op1[exec_id];
                            end
                        end
                        8'h15: node_result[exec_id] <= {31'h0, node_op0[exec_id] == node_op1[exec_id]};
                        8'h16: node_result[exec_id] <= {31'h0, $signed(node_op0[exec_id]) < $signed(node_op1[exec_id])};
                        8'h17: node_result[exec_id] <= {31'h0, $signed(node_op0[exec_id]) > $signed(node_op1[exec_id])};
                        8'h18: node_result[exec_id] <= {31'h0, $signed(node_op0[exec_id]) <= $signed(node_op1[exec_id])};
                        8'h19: node_result[exec_id] <= {31'h0, $signed(node_op0[exec_id]) >= $signed(node_op1[exec_id])};
                        8'h30: node_result[exec_id] <= node_op0[exec_id] != 0 ? node_op1[exec_id] : node_op2[exec_id];
                        default: node_result[exec_id] <= node_imm0[exec_id];
                    endcase
                    if (node_opcode[exec_id] != 8'h13 && node_opcode[exec_id] != 8'h14) begin
                        node_state[exec_id] <= 2'b11;
                        done_cnt <= done_cnt + 1'b1;
                        upd_dep_mask <= node_dep[exec_id];
                        state <= S_UPD_SCAN;
                    end else if (node_op1[exec_id] == 0) begin
                        node_state[exec_id] <= 2'b11;
                        done_cnt <= done_cnt + 1'b1;
                        upd_dep_mask <= node_dep[exec_id];
                        state <= S_UPD_SCAN;
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
                        if (node_opcode[exec_id] == 8'h14)
                            node_result[exec_id] <= div_sub_ok ? div_sub_result : div_rem_shifted;
                        else
                            node_result[exec_id] <= div_sub_ok ? {div_quo[30:0], 1'b1} : {div_quo[30:0], 1'b0};
                        node_state[exec_id] <= 2'b11;
                        done_cnt <= done_cnt + 1'b1;
                        upd_dep_mask <= node_dep[exec_id];
                        state <= S_UPD_SCAN;
                    end else begin
                        div_cnt <= div_cnt - 1'b1;
                    end
                end

                S_UPD_SCAN: begin
                    if (upd_dep_mask != 0) begin
                        // H2: Generated priority encoder
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
                        if (node_state[root_id] == 2'b11)
                            state <= S_DONE;
                        else
                            state <= S_EXEC;
                    end
                end

                S_UPD_NEXT: begin
                    if (upd_cur < NUM_NODES) begin
                        // C5: Source-based slot assignment
                        if (node_src0[upd_cur] == exec_id)
                            node_op0[upd_cur] <= node_result[exec_id];
                        else if (node_src1[upd_cur] == exec_id)
                            node_op1[upd_cur] <= node_result[exec_id];
                        else if (node_src2[upd_cur] == exec_id)
                            node_op2[upd_cur] <= node_result[exec_id];
                        node_rdyinp[upd_cur] <= node_rdyinp[upd_cur] + 1'b1;
                        if (node_rdyinp[upd_cur] + 1 >= node_numinp[upd_cur]) begin
                            node_state[upd_cur] <= 2'b10;
                            if (!q_full) begin
                                queue[q_wptr] <= upd_cur;
                                q_wptr <= q_wptr + 1'b1;
                                q_cnt <= q_cnt + 1'b1;
                            end else begin
                                q_overflow <= 1'b1;
                            end
                        end
                    end
                    state <= S_UPD_SCAN;
                end

                S_DONE: begin
                    // Wait for next start
                end

                default: state <= S_IDLE;
            endcase

            // Status
            if (start_pulse) status <= {30'h0, q_overflow, 1'b1}; // running
            if (done_state)  status <= {29'h0, q_overflow, 2'b10}; // done + overflow flag
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
                                5: reg_dat_r = {8'h0, node_src2[tmp_rnid], node_src1[tmp_rnid], node_src0[tmp_rnid]};
                                6: reg_dat_r = node_dep[tmp_rnid][63:32];
                                default: reg_dat_r = '0;
                            endcase
                        end
                    end
                end
            endcase
        end
    end

`ifdef HAVE_SVA
    assert property (@(posedge clk) disable iff (!reset_n)
        q_cnt <= Q_DEPTH)
    else $error("Scheduler queue count exceeds Q_DEPTH");

    assert property (@(posedge clk) disable iff (!reset_n)
        done_cnt <= node_cnt)
    else $warning("done_cnt exceeds node_cnt");
`endif

endmodule

`default_nettype wire
