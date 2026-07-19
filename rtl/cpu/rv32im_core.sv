`default_nettype none

module rv32im_core (
    input  logic        clk,
    input  logic        reset_n,

    output logic        wb_cyc,
    output logic        wb_stb,
    output logic        wb_we,
    output logic [31:0] wb_adr,
    output logic [31:0] wb_dat_o,
    output logic [3:0]  wb_sel,
    input  logic [31:0] wb_dat_i,
    input  logic        wb_ack,

    output logic        running
);

    typedef enum logic [1:0] {
        STATE_FETCH,
        STATE_EXEC,
        STATE_DIV
    } state_t;

    state_t state, state_next;
    logic [31:0] pc, pc_next;
    logic [31:0] instr;

    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [4:0]  rs1, rs2, rd;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    logic [31:0] imm;

    logic [31:0] regfile [32];
    logic [31:0] rs1_val, rs2_val;

    logic [31:0] alu_a, alu_b;
    logic [31:0] alu_result;

    logic [31:0] ld_result;
    logic [31:0] st_data;

    logic [31:0] csr_cycle, csr_instret;
    logic [31:0] csr_mtvec, csr_mepc, csr_mcause, csr_mscratch;

    logic reg_wr_en;
    logic [4:0]  reg_wr_addr;
    logic [31:0] reg_wr_data;
    logic branch_taken;
    logic [31:0] branch_target;
    logic is_store;

    logic [4:0]  div_cnt;
    logic [31:0] div_rem;
    logic [31:0] div_quo;
    logic [31:0] div_divisor;
    logic [4:0]  div_rd;
    logic        div_is_signed;
    logic        div_is_rem;
    logic        div_neg_q;
    logic        div_neg_r;

    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign rd     = instr[11:7];

    assign imm_i = { {21{instr[31]}}, instr[30:20] };
    assign imm_s = { {21{instr[31]}}, instr[30:25], instr[11:7] };
    assign imm_b = { {20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0 };
    assign imm_u = { instr[31:12], 12'h000 };
    assign imm_j = { {12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0 };

    always_comb begin
        alu_result = '0;
        case (opcode)
            7'b0110011: begin
                case (funct3)
                    3'b000: alu_result = funct7[5] ? alu_a - alu_b : alu_a + alu_b;
                    3'b001: alu_result = alu_a << alu_b[4:0];
                    3'b010: alu_result = {31'h0, $signed(alu_a) < $signed(alu_b)};
                    3'b011: alu_result = {31'h0, alu_a < alu_b};
                    3'b100: alu_result = alu_a ^ alu_b;
                    3'b101: alu_result = funct7[5] ? ($signed(alu_a) >>> alu_b[4:0]) : (alu_a >> alu_b[4:0]);
                    3'b110: alu_result = alu_a | alu_b;
                    3'b111: alu_result = alu_a & alu_b;
                    default: alu_result = '0;
                endcase
            end
            7'b0010011: begin
                case (funct3)
                    3'b000: alu_result = alu_a + alu_b;
                    3'b001: alu_result = alu_a << alu_b[4:0];
                    3'b010: alu_result = {31'h0, $signed(alu_a) < $signed(alu_b)};
                    3'b011: alu_result = {31'h0, alu_a < alu_b};
                    3'b100: alu_result = alu_a ^ alu_b;
                    3'b101: alu_result = funct7[5] ? ($signed(alu_a) >>> alu_b[4:0]) : (alu_a >> alu_b[4:0]);
                    3'b110: alu_result = alu_a | alu_b;
                    3'b111: alu_result = alu_a & alu_b;
                    default: alu_result = '0;
                endcase
            end
            7'b0000011: alu_result = alu_a + alu_b;
            7'b0100011: alu_result = alu_a + alu_b;
            7'b1100111: alu_result = (alu_a + alu_b) & ~1;
            default: alu_result = '0;
        endcase
    end

    always_comb begin
        branch_taken = 1'b0;
        if (opcode == 7'b1100011) begin
            case (funct3)
                3'b000: branch_taken = (alu_a == alu_b);
                3'b001: branch_taken = (alu_a != alu_b);
                3'b100: branch_taken = ($signed(alu_a) < $signed(alu_b));
                3'b101: branch_taken = ($signed(alu_a) >= $signed(alu_b));
                3'b110: branch_taken = (alu_a < alu_b);
                3'b111: branch_taken = (alu_a >= alu_b);
                default: branch_taken = 1'b0;
            endcase
        end
    end
    assign branch_target = pc + imm_b;

    // C4: Load alignment - select correct byte/halfword lane based on address
    always_comb begin
        ld_result = '0;
        case (funct3)
            3'b000: begin // LB
                case (wb_adr[1:0])
                    2'b00: ld_result = { {24{wb_dat_i[7]}},  wb_dat_i[7:0]   };
                    2'b01: ld_result = { {24{wb_dat_i[15]}}, wb_dat_i[15:8]  };
                    2'b10: ld_result = { {24{wb_dat_i[23]}}, wb_dat_i[23:16] };
                    2'b11: ld_result = { {24{wb_dat_i[31]}}, wb_dat_i[31:24] };
                    default: ld_result = '0;
                endcase
            end
            3'b001: begin // LH
                case (wb_adr[1])
                    1'b0: ld_result = { {16{wb_dat_i[15]}}, wb_dat_i[15:0]  };
                    1'b1: ld_result = { {16{wb_dat_i[31]}}, wb_dat_i[31:16] };
                    default: ld_result = '0;
                endcase
            end
            3'b010: ld_result = wb_dat_i; // LW
            3'b100: begin // LBU
                case (wb_adr[1:0])
                    2'b00: ld_result = { 24'h0, wb_dat_i[7:0]   };
                    2'b01: ld_result = { 24'h0, wb_dat_i[15:8]  };
                    2'b10: ld_result = { 24'h0, wb_dat_i[23:16] };
                    2'b11: ld_result = { 24'h0, wb_dat_i[31:24] };
                    default: ld_result = '0;
                endcase
            end
            3'b101: begin // LHU
                case (wb_adr[1])
                    1'b0: ld_result = { 16'h0, wb_dat_i[15:0]  };
                    1'b1: ld_result = { 16'h0, wb_dat_i[31:16] };
                    default: ld_result = '0;
                endcase
            end
            default: ld_result = '0;
        endcase
    end

    always_comb begin
        st_data = '0;
        case (funct3)
            3'b000: st_data = {4{rs2_val[7:0]}};
            3'b001: st_data = {2{rs2_val[15:0]}};
            3'b010: st_data = rs2_val;
            default: st_data = '0;
        endcase
    end

    always_comb begin
        wb_sel = 4'h0;
        if (is_store && state == STATE_EXEC) begin
            case (funct3)
                3'b000: wb_sel = 4'b0001 << wb_adr[1:0];
                3'b001: wb_sel = (wb_adr[1] ? 4'b1100 : 4'b0011);
                3'b010: wb_sel = 4'b1111;
                default: wb_sel = 4'h0;
            endcase
        end else if (state == STATE_FETCH) begin
            wb_sel = 4'b1111;
        end
    end

    logic signed [63:0] mulh_ss;
    logic signed [63:0] mulh_su;
    logic [63:0]        mulh_uu;

    assign mulh_ss = $signed({{32{rs1_val[31]}}, rs1_val}) * $signed({{32{rs2_val[31]}}, rs2_val});
    assign mulh_su = $signed({{32{rs1_val[31]}}, rs1_val}) * $signed({1'b0, rs2_val});
    assign mulh_uu = {1'b0, rs1_val} * {1'b0, rs2_val};

    always_comb begin
        case (opcode)
            7'b0110011: imm = '0;
            7'b0010011: imm = imm_i;
            7'b0000011: imm = imm_i;
            7'b0100011: imm = imm_s;
            7'b1100011: imm = imm_b;
            7'b0110111: imm = imm_u;
            7'b0010111: imm = imm_u;
            7'b1101111: imm = imm_j;
            7'b1100111: imm = imm_i;
            7'b1110011: imm = {27'h0, instr[19:15]};
            default:    imm = '0;
        endcase
    end

    always_comb begin
        alu_a = rs1_val;
        alu_b = '0;
        if (opcode == 7'b0110011 || opcode == 7'b1100011)
            alu_b = rs2_val;
        else
            alu_b = imm;
        if (opcode == 7'b0010111) alu_a = pc;
    end

    always_ff @(posedge clk) begin
        if (reg_wr_en && reg_wr_addr != 5'd0) begin
            regfile[reg_wr_addr] <= reg_wr_data;
        end
    end

    assign rs1_val = (rs1 == 5'd0) ? 32'd0 : regfile[rs1];
    assign rs2_val = (rs2 == 5'd0) ? 32'd0 : regfile[rs2];

    // M1: CSR implementation with proper write support
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            csr_cycle    <= '0;
            csr_instret  <= '0;
            csr_mtvec    <= 32'h00000000;
            csr_mepc     <= '0;
            csr_mcause   <= '0;
            csr_mscratch <= '0;
        end else begin
            csr_cycle <= csr_cycle + 1'b1;
            // M1: Count every completed instruction
            if ((state == STATE_EXEC && state_next == STATE_FETCH) ||
                (state == STATE_EXEC && (opcode == 7'b1100011 || opcode == 7'b1101111 || opcode == 7'b1100111)) ||
                (state == STATE_DIV && state_next == STATE_FETCH)) begin
                csr_instret <= csr_instret + 1'b1;
            end
            // M1: CSR writes
            if (state == STATE_EXEC && opcode == 7'b1110011) begin
                case (funct3)
                    3'b001: begin // CSRRW
                        case (instr[31:20])
                            12'h340: csr_mscratch <= rs1_val;
                            12'h305: csr_mtvec    <= rs1_val;
                            12'h341: csr_mepc     <= rs1_val;
                            12'h342: csr_mcause   <= rs1_val;
                            default: ;
                        endcase
                    end
                    3'b010: begin // CSRRS
                        if (rs1 != 5'd0) begin
                            case (instr[31:20])
                                12'h340: csr_mscratch <= csr_mscratch | rs1_val;
                                12'h305: csr_mtvec    <= csr_mtvec | rs1_val;
                                12'h341: csr_mepc     <= csr_mepc | rs1_val;
                                12'h342: csr_mcause   <= csr_mcause | rs1_val;
                                default: ;
                            endcase
                        end
                    end
                    3'b011: begin // CSRRC
                        if (rs1 != 5'd0) begin
                            case (instr[31:20])
                                12'h340: csr_mscratch <= csr_mscratch & ~rs1_val;
                                12'h305: csr_mtvec    <= csr_mtvec & ~rs1_val;
                                12'h341: csr_mepc     <= csr_mepc & ~rs1_val;
                                12'h342: csr_mcause   <= csr_mcause & ~rs1_val;
                                default: ;
                            endcase
                        end
                    end
                    default: ;
                endcase
            end
        end
    end

    always_comb begin
        state_next = STATE_FETCH;
        wb_cyc   = 1'b0;
        wb_stb   = 1'b0;
        wb_we    = 1'b0;
        wb_adr   = pc;
        wb_dat_o = st_data;
        reg_wr_en   = 1'b0;
        reg_wr_addr = rd;
        reg_wr_data = '0;
        is_store = 1'b0;
        pc_next  = pc + 4;

        case (state)
            STATE_FETCH: begin
                wb_cyc = 1'b1;
                wb_stb = 1'b1;
                wb_adr = pc;
                if (wb_ack)
                    state_next = STATE_EXEC;
                else
                    state_next = STATE_FETCH;
            end

            STATE_EXEC: begin
                state_next = STATE_FETCH;
                case (opcode)
                    7'b0110011: begin // R-type
                        if (funct7 == 7'b0000001) begin
                            case (funct3)
                                3'b000: begin // MUL
                                    reg_wr_en   = 1'b1;
                                    reg_wr_data = rs1_val * rs2_val;
                                end
                                3'b001: begin // MULH
                                    reg_wr_en   = 1'b1;
                                    reg_wr_data = mulh_ss[63:32];
                                end
                                3'b010: begin // MULHSU
                                    reg_wr_en   = 1'b1;
                                    reg_wr_data = mulh_su[63:32];
                                end
                                3'b011: begin // MULHU
                                    reg_wr_en   = 1'b1;
                                    reg_wr_data = mulh_uu[63:32];
                                end
                                3'b100: begin // DIV
                                    if (rs2_val == 0) begin
                                        reg_wr_en   = 1'b1;
                                        reg_wr_data = 32'hFFFF_FFFF;
                                    end else begin
                                        state_next = STATE_DIV;
                                    end
                                end
                                3'b101: begin // DIVU
                                    if (rs2_val == 0) begin
                                        reg_wr_en   = 1'b1;
                                        reg_wr_data = 32'hFFFF_FFFF;
                                    end else begin
                                        state_next = STATE_DIV;
                                    end
                                end
                                3'b110: begin // REM
                                    if (rs2_val == 0) begin
                                        reg_wr_en   = 1'b1;
                                        reg_wr_data = rs1_val;
                                    end else begin
                                        state_next = STATE_DIV;
                                    end
                                end
                                3'b111: begin // REMU
                                    if (rs2_val == 0) begin
                                        reg_wr_en   = 1'b1;
                                        reg_wr_data = rs1_val;
                                    end else begin
                                        state_next = STATE_DIV;
                                    end
                                end
                                default: begin
                                    reg_wr_en   = 1'b1;
                                    reg_wr_data = '0;
                                end
                            endcase
                        end else begin
                            reg_wr_en   = 1'b1;
                            reg_wr_data = alu_result;
                        end
                    end

                    7'b0010011: begin
                        reg_wr_en   = 1'b1;
                        reg_wr_data = alu_result;
                    end

                    7'b0000011: begin // Load
                        wb_cyc  = 1'b1;
                        wb_stb  = 1'b1;
                        wb_adr  = alu_result;
                        if (wb_ack) begin
                            reg_wr_en   = 1'b1;
                            reg_wr_data = ld_result;
                            state_next  = STATE_FETCH;
                        end else begin
                            state_next = STATE_EXEC;
                        end
                    end

                    7'b0100011: begin // Store
                        is_store = 1'b1;
                        wb_cyc   = 1'b1;
                        wb_stb   = 1'b1;
                        wb_we    = 1'b1;
                        wb_adr   = alu_result;
                        wb_dat_o = st_data;
                        if (wb_ack) begin
                            state_next = STATE_FETCH;
                        end else begin
                            state_next = STATE_EXEC;
                        end
                    end

                    7'b0110111: begin // LUI
                        reg_wr_en   = 1'b1;
                        reg_wr_data = imm_u;
                    end

                    7'b0010111: begin // AUIPC
                        reg_wr_en   = 1'b1;
                        reg_wr_data = pc + imm_u;
                    end

                    7'b1101111: begin // JAL
                        reg_wr_en   = 1'b1;
                        reg_wr_data = pc + 4;
                        pc_next     = pc + imm_j;
                    end

                    7'b1100111: begin // JALR
                        reg_wr_en   = 1'b1;
                        reg_wr_data = pc + 4;
                        pc_next     = (rs1_val + imm_i) & ~1;
                    end

                    7'b1100011: begin // Branch
                        if (branch_taken)
                            pc_next = branch_target;
                        else
                            pc_next = pc + 4;
                    end

                    7'b1110011: begin // CSR
                        reg_wr_en = 1'b1;
                        case (funct3)
                            3'b001: begin // CSRRW
                                case (instr[31:20])
                                    12'hC00: reg_wr_data = csr_cycle;
                                    12'hC02: reg_wr_data = csr_instret;
                                    12'h340: reg_wr_data = csr_mscratch;
                                    12'h305: reg_wr_data = csr_mtvec;
                                    12'h341: reg_wr_data = csr_mepc;
                                    12'h342: reg_wr_data = csr_mcause;
                                    default: reg_wr_data = '0;
                                endcase
                            end
                            3'b010: begin // CSRRS
                                case (instr[31:20])
                                    12'hC00: reg_wr_data = csr_cycle;
                                    12'hC02: reg_wr_data = csr_instret;
                                    12'h340: reg_wr_data = csr_mscratch;
                                    12'h305: reg_wr_data = csr_mtvec;
                                    12'h341: reg_wr_data = csr_mepc;
                                    12'h342: reg_wr_data = csr_mcause;
                                    default: reg_wr_data = '0;
                                endcase
                            end
                            3'b011: begin // CSRRC
                                case (instr[31:20])
                                    12'hC00: reg_wr_data = csr_cycle;
                                    12'hC02: reg_wr_data = csr_instret;
                                    12'h340: reg_wr_data = csr_mscratch;
                                    12'h305: reg_wr_data = csr_mtvec;
                                    12'h341: reg_wr_data = csr_mepc;
                                    12'h342: reg_wr_data = csr_mcause;
                                    default: reg_wr_data = '0;
                                endcase
                            end
                            default: reg_wr_data = '0;
                        endcase
                    end

                    default: begin
                        pc_next = pc + 4;
                    end
                endcase
            end

            default: begin
                state_next = STATE_FETCH;
            end

            STATE_DIV: begin
                if (div_cnt == 5'd0) begin
                    state_next = STATE_FETCH;
                    reg_wr_en  = 1'b1;
                    reg_wr_addr = div_rd;
                    if (div_is_rem)
                        reg_wr_data = div_neg_r ? (32'd0 - div_rem) : div_rem;
                    else
                        reg_wr_data = div_neg_q ? (32'd0 - div_quo) : div_quo;
                end else begin
                    state_next = STATE_DIV;
                end
            end
        endcase
    end

    logic [31:0] div_rem_shifted;
    logic [31:0] div_sub_result;
    logic        div_sub_ok;

    assign div_rem_shifted = {div_rem[30:0], div_quo[31]};
    assign div_sub_result  = div_rem_shifted - div_divisor;
    assign div_sub_ok      = ~div_sub_result[31];

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            div_cnt       <= '0;
            div_rem       <= '0;
            div_quo       <= '0;
            div_divisor   <= '0;
            div_rd        <= '0;
            div_is_signed <= 1'b0;
            div_is_rem    <= 1'b0;
            div_neg_q     <= 1'b0;
            div_neg_r     <= 1'b0;
        end else begin
            if (state == STATE_EXEC && state_next == STATE_DIV) begin
                div_cnt     <= 5'd31;
                div_rd      <= rd;

                case (funct3)
                    3'b100: begin // DIV (signed)
                        div_is_signed <= 1'b1;
                        div_is_rem    <= 1'b0;
                        div_neg_q     <= rs1_val[31] ^ rs2_val[31];
                        div_neg_r     <= rs1_val[31];
                        div_quo       <= rs1_val[31] ? (32'd0 - rs1_val) : rs1_val;
                        div_rem       <= '0;
                        div_divisor   <= rs2_val[31] ? (32'd0 - rs2_val) : rs2_val;
                    end
                    3'b101: begin // DIVU (unsigned)
                        div_is_signed <= 1'b0;
                        div_is_rem    <= 1'b0;
                        div_neg_q     <= 1'b0;
                        div_neg_r     <= 1'b0;
                        div_quo       <= rs1_val;
                        div_rem       <= '0;
                        div_divisor   <= rs2_val;
                    end
                    3'b110: begin // REM (signed)
                        div_is_signed <= 1'b1;
                        div_is_rem    <= 1'b1;
                        div_neg_q     <= rs1_val[31] ^ rs2_val[31];
                        div_neg_r     <= rs1_val[31];
                        div_quo       <= rs1_val[31] ? (32'd0 - rs1_val) : rs1_val;
                        div_rem       <= '0;
                        div_divisor   <= rs2_val[31] ? (32'd0 - rs2_val) : rs2_val;
                    end
                    3'b111: begin // REMU (unsigned)
                        div_is_signed <= 1'b0;
                        div_is_rem    <= 1'b1;
                        div_neg_q     <= 1'b0;
                        div_neg_r     <= 1'b0;
                        div_quo       <= rs1_val;
                        div_rem       <= '0;
                        div_divisor   <= rs2_val;
                    end
                    default: ;
                endcase
            end

            if (state == STATE_DIV) begin
                if (div_sub_ok) begin
                    div_rem <= div_sub_result;
                    div_quo <= {div_quo[30:0], 1'b1};
                end else begin
                    div_rem <= div_rem_shifted;
                    div_quo <= {div_quo[30:0], 1'b0};
                end
                if (div_cnt != 5'd0)
                    div_cnt <= div_cnt - 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= STATE_FETCH;
            pc    <= 32'h00000000;
            instr <= '0;
        end else begin
            state <= state_next;
            if (state == STATE_FETCH && wb_ack)
                instr <= wb_dat_i;
            if ((state == STATE_EXEC && state_next == STATE_FETCH) ||
                (state == STATE_EXEC && state_next == STATE_DIV) ||
                (state == STATE_EXEC && (opcode == 7'b1100011 || opcode == 7'b1101111 || opcode == 7'b1100111)))
                pc <= pc_next;
        end
    end

    assign running = (state != STATE_FETCH) || (state == STATE_FETCH && !wb_ack);

endmodule

`default_nettype wire
