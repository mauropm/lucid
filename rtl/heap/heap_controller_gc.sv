// Heap Controller with GC Support
// ================================
// Manages the FPU heap with integration for the mark-sweep GC.
// Has two ports: allocator port (for allocation) and GC port (for marking/sweeping).

module heap_controller_gc #(
    parameter int HEAP_SIZE = 4096,
    parameter int HEAP_BASE = 32'h00300000
) (
    input  logic        clk,
    input  logic        reset_n,

    // Allocation port
    input  logic        alloc_valid,
    input  logic [7:0]  alloc_tag,
    input  logic [7:0]  alloc_flags,
    input  logic [15:0] alloc_size,
    output logic [31:0] alloc_ptr,
    output logic        alloc_ack,
    output logic        alloc_oom,  // out of memory

    // GC port
    input  logic        gc_mem_rd_en,
    input  logic        gc_mem_wr_en,
    input  logic [31:0] gc_mem_addr,   // word address
    input  logic [31:0] gc_mem_wdata,
    output logic [31:0] gc_mem_rdata,

    // GC control
    input  logic        gc_trigger,
    output logic        gc_busy,
    input  logic        gc_done,

    // Heap status
    output logic [31:0] heap_free_ptr,
    output logic [31:0] heap_used,
    output logic [31:0] heap_avail
);

    // Internal BRAM
    logic [31:0] mem [0:HEAP_SIZE/4 - 1];

    // Free pointer
    logic [31:0] free_ptr;
    int tmp_wa;

    // GC state
    logic gc_active;
    logic [31:0] gc_saved_free;  // free pointer saved before GC

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            free_ptr <= 32'd256;
            alloc_ack <= 1'b0;
            alloc_ptr <= '0;
            alloc_oom <= 1'b0;
            gc_active <= 1'b0;
            gc_busy <= 1'b0;
            gc_saved_free <= '0;
            mem[0] <= 32'h48454150;
            mem[1] <= HEAP_SIZE;
            mem[2] <= 32'd256;
            mem[3] <= 32'd0;
            mem[4] <= 32'd0;
        end else begin
            alloc_ack <= 1'b0;
            alloc_oom <= 1'b0;

            // GC memory read (combinational read with registered output)
            if (gc_mem_rd_en) begin
                gc_mem_rdata <= mem[gc_mem_addr];
            end

            // GC memory write
            if (gc_mem_wr_en) begin
                mem[gc_mem_addr] <= gc_mem_wdata;
            end

            // GC trigger
            if (gc_trigger && !gc_active) begin
                gc_active <= 1'b1;
                gc_busy <= 1'b1;
                gc_saved_free <= free_ptr;
            end

            // GC completion (external module sets gc_done)
            if (gc_done && gc_active) begin
                gc_active <= 1'b0;
                gc_busy <= 1'b0;
                // Update free pointer from GC
                // (In a full implementation, GC writes the new free pointer)
            end

            // Allocation
            if (alloc_valid && !alloc_ack) begin
                if (gc_active) begin
                    // Block allocation during GC, return OOM
                    alloc_ptr <= 32'd0;
                    alloc_ack <= 1'b1;
                    alloc_oom <= 1'b1;
                end else if (free_ptr + alloc_size <= HEAP_SIZE) begin
                    tmp_wa = free_ptr >> 2;
                    mem[tmp_wa] <= {alloc_tag, alloc_flags, alloc_size};
                    alloc_ptr <= HEAP_BASE + free_ptr;
                    alloc_ack <= 1'b1;
                    free_ptr <= free_ptr + alloc_size;
                end else begin
                    alloc_ptr <= 32'd0;
                    alloc_ack <= 1'b1;
                    alloc_oom <= 1'b1;
                    // Auto-trigger GC on OOM
                    gc_active <= 1'b1;
                    gc_busy <= 1'b1;
                    gc_saved_free <= free_ptr;
                end
            end

            // Update heap header
            mem[2] <= free_ptr;
        end
    end

    assign heap_free_ptr = free_ptr;
    assign heap_used     = free_ptr;
    assign heap_avail    = HEAP_SIZE - free_ptr;

endmodule
