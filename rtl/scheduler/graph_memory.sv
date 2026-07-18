// Graph Memory
// ============
// BRAM-based storage for Lucid IR graph nodes.
// Each node is 6 × 32-bit words (24 bytes).
// Wishbone slave for host CPU to load/read the graph.
// Internal port for the scheduler to read/write nodes.

module graph_memory #(
    parameter int NUM_NODES = 256
) (
    input  logic        clk,
    input  logic        reset_n,

    // Wishbone slave (host CPU loads graph)
    input  logic        wb_cyc,
    input  logic        wb_stb,
    input  logic        wb_we,
    input  logic [31:0] wb_adr,
    input  logic [31:0] wb_dat_w,
    input  logic [3:0]  wb_sel,
    output logic [31:0] wb_dat_r,
    output logic        wb_ack,

    // Scheduler port: read/write full nodes
    input  logic [7:0]  sched_node_id,
    input  logic        sched_rd_en,
    output logic [191:0] sched_rd_data,
    output logic        sched_rd_valid,
    input  logic        sched_wr_en,
    input  logic [191:0] sched_wr_data
);

    // Each node occupies 6 × 32-bit words
    // Word layout:
    //   w0: {STATE(2), OPCODE(8), NUM_INPUTS(6), READY_INPUTS(6), FLAGS(10)}
    //   w1: IMM0
    //   w2: IMM1
    //   w3: RESULT
    //   w4: DEP_MASK
    //   w5: INPUTS

    localparam int WORDS_PER_NODE = 6;
    localparam int TOTAL_WORDS = NUM_NODES * WORDS_PER_NODE;
    localparam int ADDR_WIDTH = $clog2(TOTAL_WORDS);

    logic [31:0] mem [TOTAL_WORDS];

    // Wishbone address → word index
    wire [ADDR_WIDTH-1:0] wb_word_addr;
    assign wb_word_addr = wb_adr[ADDR_WIDTH+1:2];

    // Wishbone write
    always_ff @(posedge clk) begin
        if (wb_cyc && wb_stb && wb_we) begin
            mem[wb_word_addr] <= wb_dat_w;
        end
    end

    // Wishbone read (1-cycle)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wb_ack <= 1'b0;
        end else begin
            wb_ack <= wb_cyc && wb_stb;
            if (wb_cyc && wb_stb && !wb_we) begin
                wb_dat_r <= mem[wb_word_addr];
            end
        end
    end

    // Scheduler port: read
    wire [ADDR_WIDTH-1:0] sched_base;
    assign sched_base = sched_node_id * WORDS_PER_NODE;

    always_ff @(posedge clk) begin
        if (sched_rd_en) begin
            sched_rd_data <= {
                mem[sched_base + 5],
                mem[sched_base + 4],
                mem[sched_base + 3],
                mem[sched_base + 2],
                mem[sched_base + 1],
                mem[sched_base + 0]
            };
            sched_rd_valid <= 1'b1;
        end else begin
            sched_rd_valid <= 1'b0;
        end
    end

    // Scheduler port: write
    always_ff @(posedge clk) begin
        if (sched_wr_en) begin
            {mem[sched_base + 5],
             mem[sched_base + 4],
             mem[sched_base + 3],
             mem[sched_base + 2],
             mem[sched_base + 1],
             mem[sched_base + 0]} <= sched_wr_data;
        end
    end

endmodule
