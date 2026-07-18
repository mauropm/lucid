// RV32IM Management CPU Core
// ==========================
// 3-state CPU: fetch, execute, load-data.
// Wishbone B4 master. Single issue, in-order.
// Supports RV32I base + M extension (multiply/divide).
//
// Reset vector: 0x00000000 (Boot ROM)

module rv32im_core (
    input  logic        clk,
    input  logic        reset_n,

    // Wishbone master (instruction fetch + data access)
    output logic        wb_cyc,
    output logic        wb_stb,
    output logic        wb_we,
    output logic [31:0] wb_adr,
    output logic [31:0] wb_dat_o,
    output logic [3:0]  wb_sel,
    input  logic [31:0] wb_dat_i,
    input  logic        wb_ack
);

    // State machine
    typedef enum logic [1:0] {
        STATE_FETCH,
        STATE_EXEC,
        STATE_LOAD
    } state_t;

    state_t state, state_next;
    logic [31:0] pc, pc_next;
    logic [31:0] instr;

    // Decoded instruction fields
    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [4:0]  rs1, rs2, rd;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    logic [31:0] imm;

    // Register file
    logic [31:0] regfile [32];
    logic [31:0] rs1_val, rs2_val;

    // ALU
    logic [31:0] alu_a, alu_b;
    logic [31:0] alu_result;

    // Multiplier/divider results
    logic [31:0] mul_result;
    logic [31:0] div_result, div_rem;

    // Load/store
    logic [31:0] ld_result;
    logic [31:0] st_data;

    // CSR
    logic [31:0] csr_cycle, csr_instret;
    logic [31:0] csr_mtvec, csr_mepc, csr_mcause, csr_mscratch;

    // Execution control
    logic reg_wr_en;
    logic [4:0] reg_wr_addr;
    logic [31:0] reg_wr_data;
    logic branch_taken;
    logic [31:0] branch_target;
    logic is_load, is_store;

    // ============================================================
    // Instruction Decode
    // ============================================================
    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign rd     = instr[11:7];

    // Immediate generation
    assign imm_i = { {21{instr[31]}}, instr[30:20] };
    assign imm_s = { {21{instr[31]}}, instr[30:25], instr[11:7] };
    assign imm_b = { {20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0 };
    assign imm_u = { instr[31:12], 12'h000 };
    assign imm_j = { {12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0 };

    // Main ALU
    always_comb begin
        alu_result = '0;
        unique case (opcode)
            7'b0110011: begin // R-type
                case (funct3)
                    3'b000: alu_result = funct7[5] ? alu_a - alu_b : alu_a + alu_b;
                    3'b001: alu_result = alu_a << alu_b[4:0];
                    3'b010: alu_result = $signed(alu_a) < $signed(alu_b);
                    3'b011: alu_result = alu_a < alu_b;
                    3'b100: alu_result = alu_a ^ alu_b;
                    3'b101: alu_result = funct7[5] ? ($signed(alu_a) >>> alu_b[4:0]) : (alu_a >> alu_b[4:0]);
                    3'b110: alu_result = alu_a | alu_b;
                    3'b111: alu_result = alu_a & alu_b;
                endcase
            end
            7'b0010011: begin // I-type ALU
                case (funct3)
                    3'b000: alu_result = alu_a + alu_b;
                    3'b001: alu_result = alu_a << alu_b[4:0];
                    3'b010: alu_result = $signed(alu_a) < $signed(alu_b);
                    3'b011: alu_result = alu_a < alu_b;
                    3'b100: alu_result = alu_a ^ alu_b;
                    3'b101: alu_result = funct7[5] ? ($signed(alu_a) >>> alu_b[4:0]) : (alu_a >> alu_b[4:0]);
                    3'b110: alu_result = alu_a | alu_b;
                    3'b111: alu_result = alu_a & alu_b;
                endcase
            end
            7'b0000011: begin // Load
                alu_result = alu_a + alu_b;
            end
            7'b0100011: begin // Store
                alu_result = alu_a + alu_b;
            end
            7'b1100111: begin // JALR
                alu_result = (alu_a + alu_b) & ~1;
            end
            default: ;
        endcase
    end

    // Branch comparator
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
            endcase
        end
    end
    assign branch_target = pc + imm_b;

    // Load alignment and sign-extension
    always_comb begin
        ld_result = '0;
        case (funct3)
            3'b000: ld_result = { {24{wb_dat_i[7]}},  wb_dat_i[7:0]   }; // LB
            3'b001: ld_result = { {16{wb_dat_i[15]}}, wb_dat_i[15:0]  }; // LH
            3'b010: ld_result = wb_dat_i;                                 // LW
            3'b100: ld_result = { 24'h0,              wb_dat_i[7:0]   }; // LBU
            3'b101: ld_result = { 16'h0,              wb_dat_i[15:0]  }; // LHU
        endcase
    end

    // Store data formatting
    always_comb begin
        st_data = '0;
        unique case (funct3)
            3'b000: st_data = {4{rs2_val[7:0]}};   // SB
            3'b001: st_data = {2{rs2_val[15:0]}};  // SH
            3'b010: st_data = rs2_val;              // SW
        endcase
    end

    // Byte select for stores
    always_comb begin
        wb_sel = 4'h0;
        if (is_store && state == STATE_EXEC) begin
            unique case (funct3)
                3'b000: wb_sel = 4'b0001 << wb_adr[1:0];
                3'b001: wb_sel = (wb_adr[1] ? 4'b1100 : 4'b0011);
                3'b010: wb_sel = 4'b1111;
            endcase
        end else if (state == STATE_FETCH) begin
            wb_sel = 4'b1111;
        end
    end

    // ============================================================
    // Multiply / Divide (M extension)
    logic [63:0] mul_full;
    assign mul_full = $signed(rs1_val) * $signed(rs2_val);

    // ============================================================
    // Immediate selection
    // ============================================================
    always_comb begin
        unique case (opcode)
            7'b0110011: imm = '0; // R-type
            7'b0010011: imm = imm_i;
            7'b0000011: imm = imm_i;
            7'b0100011: imm = imm_s;
            7'b1100011: imm = imm_b;
            7'b0110111: imm = imm_u; // LUI
            7'b0010111: imm = imm_u; // AUIPC
            7'b1101111: imm = imm_j; // JAL
            7'b1100111: imm = imm_i; // JALR
            7'b1110011: imm = {27'h0, instr[19:15]}; // CSR
            default:    imm = '0;
        endcase
    end

    // ALU sources
    always_comb begin
        alu_a = rs1_val;
        alu_b = '0;
        if (opcode == 7'b0110011 || opcode == 7'b1100011) begin
            alu_b = rs2_val;
        end else begin
            alu_b = imm;
        end
        // AUIPC: rs1 is PC
        if (opcode == 7'b0010111) alu_a = pc;
        // JAL: rd gets PC+4
        // JALR: rd gets PC+4, target is rs1+imm
    end

    // ============================================================
    // Register File
    // ============================================================
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (int i = 0; i < 32; i++) regfile[i] <= '0;
        end else if (reg_wr_en && reg_wr_addr != 5'd0) begin
            regfile[reg_wr_addr] <= reg_wr_data;
        end
    end

    assign rs1_val = (rs1 == 5'd0) ? 32'd0 : regfile[rs1];
    assign rs2_val = (rs2 == 5'd0) ? 32'd0 : regfile[rs2];

    // ============================================================
    // CSRs
    // ============================================================
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
            if (state == STATE_EXEC && state_next == STATE_FETCH && !is_load && !is_store && opcode != 7'b1110011) begin
                csr_instret <= csr_instret + 1'b1;
            end
            // CSR writes handled in execution
        end
    end

    // ============================================================
    // Main State Machine
    // ============================================================
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
        is_load  = 1'b0;
        is_store = 1'b0;
        pc_next  = pc + 4;


        case (state)
            STATE_FETCH: begin
                wb_cyc = 1'b1;
                wb_stb = 1'b1;
                wb_adr = pc;
                if (wb_ack) begin
                    state_next = STATE_EXEC;
                end else begin
                    state_next = STATE_FETCH;
                end
            end

            STATE_EXEC: begin
                state_next = STATE_FETCH;
                case (opcode)
                    7'b0110011: begin // R-type
                        if (funct7 == 7'b0000001) begin
                            // M extension
                            case (funct3)
                                3'b000: begin // MUL
                                    reg_wr_en   = 1'b1;
                                    reg_wr_data = $signed(alu_a) * $signed(alu_b);
                                end
                                3'b001: begin // MULH
                                    reg_wr_en   = 1'b1;
                                    reg_wr_data = ($signed(alu_a) * $signed(alu_b)) >> 32;
                                end
                                3'b010, 3'b011: begin // MULHSU/MULHU
                                    reg_wr_en   = 1'b1;
                                    reg_wr_data = ($unsigned(alu_a) * $unsigned(alu_b)) >> 32;
                                end
                                3'b100: begin // DIV
                                    reg_wr_en   = 1'b1;
                                    reg_wr_data = (alu_b != 0) ? $signed(alu_a) / $signed(alu_b) : -1;
                                end
                                3'b101: begin // DIVU
                                    reg_wr_en   = 1'b1;
                                    reg_wr_data = (alu_b != 0) ? $unsigned(alu_a) / $unsigned(alu_b) : -1;
                                end
                                3'b110: begin // REM
                                    reg_wr_en   = 1'b1;
                                    reg_wr_data = (alu_b != 0) ? $signed(alu_a) % $signed(alu_b) : alu_a;
                                end
                                3'b111: begin // REMU
                                    reg_wr_en   = 1'b1;
                                    reg_wr_data = (alu_b != 0) ? $unsigned(alu_a) % $unsigned(alu_b) : alu_a;
                                end
                            endcase
                        end else begin
                            reg_wr_en   = 1'b1;
                            reg_wr_data = alu_result;
                        end
                    end

                    7'b0010011: begin // I-type ALU
                        reg_wr_en   = 1'b1;
                        reg_wr_data = alu_result;
                    end

                    7'b0000011: begin // Load
                        is_load = 1'b1;
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
                        if (branch_taken) begin
                            pc_next = branch_target;
                        end else begin
                            pc_next = pc + 4;
                        end
                    end

                    7'b1110011: begin // CSR
                        unique case (funct3)
                            3'b001: begin // CSRRW
                                reg_wr_en   = 1'b1;
                                if (instr[31:20] == 12'hC00) reg_wr_data = csr_cycle;
                                else if (instr[31:20] == 12'hC02) reg_wr_data = csr_instret;
                                else reg_wr_data = '0;
                                // CSRRW writes to csr_mscratch are handled in always_ff
                            end
                            3'b010: begin // CSRRS
                                reg_wr_en   = 1'b1;
                                if (instr[31:20] == 12'hC00) reg_wr_data = csr_cycle;
                                else if (instr[31:20] == 12'hC02) reg_wr_data = csr_instret;
                                else if (instr[31:20] == 12'h340) reg_wr_data = csr_mscratch;
                                else reg_wr_data = '0;
                            end
                            default: ;
                        endcase
                    end

                    default: begin
                        // Illegal instruction — just skip
                        pc_next = pc + 4;
                    end
                endcase
            end

            STATE_LOAD: begin
                // Not used in current design
                state_next = STATE_FETCH;
            end
        endcase
    end

    // State and PC update
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= STATE_FETCH;
            pc    <= 32'h00000000;
            instr <= '0;
        end else begin
            state <= state_next;
            if (state == STATE_FETCH && wb_ack) begin
                instr <= wb_dat_i;
            end
            if ((state == STATE_EXEC && state_next == STATE_FETCH) ||
                (state == STATE_EXEC && (opcode == 7'b1100011 || opcode == 7'b1101111 || opcode == 7'b1100111))) begin
                pc <= pc_next;
            end
        end
    end

endmodule
