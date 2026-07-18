// Graph Scheduler
// ===============
// Executes Lucid IR dependency graphs.
// Three-phase execution: scan, execute, update.
// For Phase 3: all computations happen inline.

module graph_scheduler #(
    parameter int NUM_NODES = 64,
    parameter int Q_DEPTH = 16
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

    // ============================================================
    // Register file
    // ============================================================
    logic [31:0] ctrl, status, root_id, node_cnt, done_cnt;
    logic start_pulse;

    assign reg_ack = reg_cyc && reg_stb;

    // ============================================================
    // Node state arrays
    // ============================================================
    logic [1:0]  node_state  [0:NUM_NODES-1];
    logic [7:0]  node_opcode [0:NUM_NODES-1];
    logic [5:0]  node_numinp [0:NUM_NODES-1];
    logic [5:0]  node_rdyinp [0:NUM_NODES-1];
    logic [9:0]  node_flags  [0:NUM_NODES-1];
    logic [31:0] node_imm0   [0:NUM_NODES-1];
    logic [31:0] node_imm1   [0:NUM_NODES-1];
    logic [31:0] node_result [0:NUM_NODES-1];
    logic [31:0] node_dep    [0:NUM_NODES-1];
    logic [31:0] node_op0    [0:NUM_NODES-1]; // operand values from inputs
    logic [31:0] node_op1    [0:NUM_NODES-1];

    // ============================================================
    // Ready queue (FIFO of node IDs)
    // ============================================================
    logic [$clog2(NUM_NODES)-1:0] queue [0:Q_DEPTH-1];
    logic [$clog2(Q_DEPTH)-1:0] q_wptr, q_rptr;
    logic [$clog2(Q_DEPTH):0] q_cnt;
    logic q_empty, q_full;
    wire [$clog2(NUM_NODES)-1:0] pop_q_id = queue[q_rptr];

    assign q_empty = (q_cnt == 0);
    assign q_full  = (q_cnt == Q_DEPTH);

    // ============================================================
    // FSM
    // ============================================================
    typedef enum logic [2:0] {
        S_IDLE, S_SCAN, S_EXEC, S_RESULT, S_UPD_SCAN, S_UPD_NEXT, S_DONE
    } fsm_t;

    fsm_t state;
    wire done_state = (state == S_DONE);

    // Scan pointer
    logic [$clog2(NUM_NODES)-1:0] scan_cnt;

    // Update state
    logic [31:0] upd_dep_mask;
    logic [$clog2(NUM_NODES)-1:0] upd_cur;

    // Control signals
    logic push_q, pop_q;
    logic [$clog2(NUM_NODES)-1:0] push_q_id;
    logic [$clog2(NUM_NODES)-1:0] exec_id;

    // Temporary computation variables
    int tmp_nid, tmp_fid, tmp_d;

    // ============================================================
    // Register write logic
    // ============================================================
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ctrl <= '0; root_id <= '0; node_cnt <= '0;
            done_cnt <= '0; start_pulse <= 1'b0;
            status <= 32'd2;
            for (int i = 0; i < NUM_NODES; i++) begin
                node_state[i] <= 2'b00;
                node_opcode[i] <= 8'h00;
                node_numinp[i] <= 6'd0;
                node_rdyinp[i] <= 6'd0;
                node_flags[i]  <= 10'd0;
                node_imm0[i]   <= 32'd0;
                node_imm1[i]   <= 32'd0;
                node_result[i] <= 32'd0;
                node_dep[i]    <= 32'd0;
                node_op0[i]    <= 32'd0;
                node_op1[i]    <= 32'd0;
            end
        end else begin
            start_pulse <= 1'b0;
            if (reg_cyc && reg_stb && reg_we) begin
                case (reg_adr[5:2])
                    0: begin
                        ctrl <= reg_dat_w;
                        if (reg_dat_w[0]) start_pulse <= 1'b1;
                    end
                    2: root_id <= reg_dat_w;
                    3: node_cnt <= reg_dat_w;
                endcase
                // Node field write (address >= 0x20)
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
            if (done_state)   status <= 32'd2;
        end
    end

    // ============================================================
    // Register read
    // ============================================================
    always_comb begin
        reg_dat_r = '0;
        if (reg_cyc && reg_stb) begin
            case (reg_adr[5:2])
                0: reg_dat_r = ctrl;
                1: reg_dat_r = status;
                2: reg_dat_r = root_id;
                3: reg_dat_r = node_cnt;
                4: reg_dat_r = done_cnt;
                default: reg_dat_r = '0;
            endcase
        end
    end

    // ============================================================
    // Ready queue logic
    // ============================================================
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            q_wptr <= '0; q_rptr <= '0; q_cnt <= '0;
        end else begin
            if (push_q && !q_full) begin
                queue[q_wptr] <= push_q_id;
                q_wptr <= q_wptr + 1'b1;
                q_cnt <= q_cnt + 1'b1;
            end
            if (pop_q && !q_empty) begin
                q_rptr <= q_rptr + 1'b1;
                q_cnt <= q_cnt - 1'b1;
            end
            if (push_q && !q_full && pop_q && !q_empty) begin
                q_cnt <= q_cnt;
            end
        end
    end

    // ============================================================
    // Main FSM
    // ============================================================
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            scan_cnt <= '0;
            pop_q <= 1'b0;
            push_q <= 1'b0;
            upd_dep_mask <= '0;
            upd_cur <= '0;
            exec_id <= '0;
        end else begin
            pop_q <= 1'b0;
            push_q <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        state <= S_SCAN;
                        scan_cnt <= '0;
                        done_cnt <= '0;
                    end
                end

                S_SCAN: begin
                    if (scan_cnt < node_cnt) begin
                        if (node_numinp[scan_cnt] == 0) begin
                            node_state[scan_cnt] <= 2'b10; // READY
                            push_q <= 1'b1;
                            push_q_id <= scan_cnt;
                        end else begin
                            node_state[scan_cnt] <= 2'b01; // WAITING
                        end
                        scan_cnt <= scan_cnt + 1'b1;
                    end else begin
                        state <= S_EXEC;
                    end
                end

                S_EXEC: begin
                    if (!q_empty) begin
                        exec_id <= pop_q_id;
                        pop_q <= 1'b1;
                        state <= S_RESULT;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_RESULT: begin
                    tmp_nid = exec_id;
                    case (node_opcode[tmp_nid])
                        8'h01: node_result[tmp_nid] <= node_imm0[tmp_nid];           // LIT_INT
                        8'h02: node_result[tmp_nid] <= node_flags[tmp_nid][0];       // LIT_BOOL
                        8'h10: node_result[tmp_nid] <= node_op0[tmp_nid] + node_op1[tmp_nid]; // ADD
                        8'h11: node_result[tmp_nid] <= node_op0[tmp_nid] - node_op1[tmp_nid]; // SUB
                        8'h12: node_result[tmp_nid] <= node_op0[tmp_nid] * node_op1[tmp_nid]; // MUL
                        default: node_result[tmp_nid] <= node_imm0[tmp_nid];
                    endcase
                    node_state[tmp_nid] <= 2'b11; // DONE
                    done_cnt <= done_cnt + 1'b1;
                    upd_dep_mask <= node_dep[tmp_nid];
                    state <= S_UPD_SCAN;
                end

                S_UPD_SCAN: begin
                    if (upd_dep_mask != 0) begin
                        if (upd_dep_mask[0]) upd_cur <= 0;
                        else if (upd_dep_mask[1]) upd_cur <= 1;
                        else if (upd_dep_mask[2]) upd_cur <= 2;
                        else if (upd_dep_mask[3]) upd_cur <= 3;
                        else if (upd_dep_mask[4]) upd_cur <= 4;
                        else if (upd_dep_mask[5]) upd_cur <= 5;
                        else if (upd_dep_mask[6]) upd_cur <= 6;
                        else if (upd_dep_mask[7]) upd_cur <= 7;
                        else if (upd_dep_mask[8]) upd_cur <= 8;
                        else if (upd_dep_mask[9]) upd_cur <= 9;
                        else if (upd_dep_mask[10]) upd_cur <= 10;
                        else if (upd_dep_mask[11]) upd_cur <= 11;
                        else if (upd_dep_mask[12]) upd_cur <= 12;
                        else if (upd_dep_mask[13]) upd_cur <= 13;
                        else if (upd_dep_mask[14]) upd_cur <= 14;
                        else if (upd_dep_mask[15]) upd_cur <= 15;
                        else if (upd_dep_mask[16]) upd_cur <= 16;
                        else if (upd_dep_mask[17]) upd_cur <= 17;
                        else if (upd_dep_mask[18]) upd_cur <= 18;
                        else if (upd_dep_mask[19]) upd_cur <= 19;
                        else if (upd_dep_mask[20]) upd_cur <= 20;
                        else if (upd_dep_mask[21]) upd_cur <= 21;
                        else if (upd_dep_mask[22]) upd_cur <= 22;
                        else if (upd_dep_mask[23]) upd_cur <= 23;
                        else if (upd_dep_mask[24]) upd_cur <= 24;
                        else if (upd_dep_mask[25]) upd_cur <= 25;
                        else if (upd_dep_mask[26]) upd_cur <= 26;
                        else if (upd_dep_mask[27]) upd_cur <= 27;
                        else if (upd_dep_mask[28]) upd_cur <= 28;
                        else if (upd_dep_mask[29]) upd_cur <= 29;
                        else if (upd_dep_mask[30]) upd_cur <= 30;
                        else upd_cur <= 31;
                        upd_dep_mask <= upd_dep_mask & (upd_dep_mask - 1);
                        state <= S_UPD_NEXT;
                    end else begin
                        if (node_state[root_id] == 2'b11) begin
                            state <= S_DONE;
                        end else begin
                            state <= S_EXEC;
                        end
                    end
                end

                S_UPD_NEXT: begin
                    tmp_d = upd_cur;
                    if (tmp_d < NUM_NODES) begin
                        // Store the result of the completed node as an operand
                        if (node_rdyinp[tmp_d] == 0) begin
                            node_op0[tmp_d] <= node_result[exec_id];
                        end else if (node_rdyinp[tmp_d] == 1) begin
                            node_op1[tmp_d] <= node_result[exec_id];
                        end
                        node_rdyinp[tmp_d] <= node_rdyinp[tmp_d] + 1'b1;
                        if (node_rdyinp[tmp_d] + 1 >= node_numinp[tmp_d]) begin
                            node_state[tmp_d] <= 2'b10; // READY
                            push_q <= 1'b1;
                            push_q_id <= tmp_d;
                        end
                    end
                    state <= S_UPD_SCAN;
                end

                S_DONE: begin
                    // Wait for next start
                end
            endcase
        end
    end

endmodule
