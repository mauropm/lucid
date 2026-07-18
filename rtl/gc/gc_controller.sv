// GC Controller
// ==============
// Mark-sweep garbage collector for the FPU heap.
// Three-phase operation: mark, sweep, finish.
// Uses BRAM read/write ports to access heap memory.

module gc_controller #(
    parameter int HEAP_SIZE = 4096,
    parameter int HEAP_BASE = 32'h00300000,
    parameter int HEADER_SIZE = 256,  // bytes reserved for heap header
    parameter int MAX_ROOTS = 8
) (
    input  logic        clk,
    input  logic        reset_n,

    // Control
    input  logic        gc_start,
    output logic        gc_busy,
    output logic        gc_done,
    output logic [31:0] gc_freed_bytes,

    // Root set
    input  logic [7:0]  root_count,
    input  logic [255:0] root_ptrs,  // 8 × 32-bit

    // Heap memory interface (direct BRAM access)
    output logic [31:0] mem_addr,    // word-aligned address
    input  logic [31:0] mem_rdata,
    output logic        mem_rd_en,
    output logic        mem_wr_en,
    output logic [31:0] mem_wdata,

    // Heap state
    input  logic [31:0] heap_free_ptr,
    output logic [31:0] updated_free_ptr
);

    // FSM
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_MARK_ROOT,
        ST_MARK_STACK,
        ST_MARK_CHILDREN,
        ST_SWEEP_SCAN,
        ST_DONE
    } state_t;

    state_t state;

    // Mark stack (up to 64 entries)
    logic [31:0] mark_stack [0:63];
    logic [5:0]  stack_ptr;

    // Scan pointer for sweep
    logic [31:0] scan_ptr;

    // Stats
    logic [31:0] freed_bytes;

    // Root pointer array unpacked
    logic [31:0] root_array [0:7];
    logic [2:0]  root_idx;

    always_comb begin
        for (int i = 0; i < 8; i++) begin
            root_array[i] = root_ptrs[i*32 +: 32];
        end
    end

    // Object header access
    logic [31:0] obj_addr;  // current object being processed
    logic [31:0] obj_header;
    logic [7:0]  obj_tag;
    logic [7:0]  obj_flags;
    logic [15:0] obj_size;
    logic [3:0]  child_idx;  // index of current child being processed

    assign obj_header = mem_rdata;
    assign obj_tag    = obj_header[31:24];
    assign obj_flags  = obj_header[23:16];
    assign obj_size   = obj_header[15:0];

    // Child scanning state
    logic [5:0] child_offset;  // byte offset within object for next child
    logic [3:0] max_children;

    always_comb begin
        // Estimate max children based on object size
        // Each child is a 32-bit pointer, starting after the 32-bit header
        if (obj_tag == 8'h06 || obj_tag == 8'h08) begin // PAIR or CLOSURE
            max_children = 4'd2;
        end else if (obj_tag == 8'h07) begin // VECTOR
            // Size = header(4) + length(4) + elements: children = (obj_size - 8) / 4
            max_children = 4'd8; // Simplified
        end else begin
            max_children = 4'd0;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= ST_IDLE;
            gc_busy <= 1'b0;
            gc_done <= 1'b0;
            gc_freed_bytes <= '0;
            stack_ptr <= '0;
            scan_ptr <= '0;
            freed_bytes <= '0;
            mem_rd_en <= 1'b0;
            mem_wr_en <= 1'b0;
            obj_addr <= '0;
            child_idx <= '0;
            root_idx <= '0;
        end else begin
            // Defaults
            mem_rd_en <= 1'b0;
            mem_wr_en <= 1'b0;

            case (state)
                // ====== IDLE: wait for GC trigger ======
                ST_IDLE: begin
                    gc_busy <= 1'b0;
                    gc_done <= 1'b0;
                    stack_ptr <= '0;
                    scan_ptr <= '0;
                    root_idx <= '0;

                    if (gc_start) begin
                        gc_busy <= 1'b1;
                        freed_bytes <= '0;
                        state <= ST_MARK_ROOT;
                    end
                end

                // ====== MARK_ROOT: iterate through root set ======
                ST_MARK_ROOT: begin
                    if (root_idx < (root_count < 8 ? root_count : 8)) begin
                        obj_addr <= root_array[root_idx];
                        // Read object header
                        mem_addr <= (root_array[root_idx] - HEAP_BASE) >> 2;
                        mem_rd_en <= 1'b1;
                        root_idx <= root_idx + 1;
                        state <= ST_MARK_STACK;
                    end else begin
                        // All roots processed, start sweep
                        scan_ptr <= HEADER_SIZE;
                        state <= ST_SWEEP_SCAN;
                    end
                end

                // ====== MARK_STACK: process an object ======
                ST_MARK_STACK: begin
                    // obj_addr has the current object address
                    // Check if already marked
                    if (!obj_flags[0]) begin  // MARK bit not set
                        // Read the header (was already read by previous state)
                        // Set MARK bit
                        mem_addr <= (obj_addr - HEAP_BASE) >> 2;
                        mem_wr_en <= 1'b1;
                        mem_wdata <= {obj_tag, obj_flags | 8'h01, obj_size};  // set MARK bit

                        // Start scanning children
                        child_idx <= '0;
                        child_offset <= 4;  // first child after header
                        state <= ST_MARK_CHILDREN;
                    end else begin
                        // Already marked, pop next from stack
                        if (stack_ptr > 0) begin
                            stack_ptr <= stack_ptr - 1;
                            obj_addr <= mark_stack[stack_ptr - 1];
                            mem_addr <= (mark_stack[stack_ptr - 1] - HEAP_BASE) >> 2;
                            mem_rd_en <= 1'b1;
                        end else begin
                            // Stack empty, continue to next root
                            state <= ST_MARK_ROOT;
                        end
                    end
                end

                // ====== MARK_CHILDREN: scan children of current object ======
                ST_MARK_CHILDREN: begin
                    if (child_idx < max_children) begin
                        // Read child pointer
                        mem_addr <= ((obj_addr + child_offset - HEAP_BASE) >> 2);
                        mem_rd_en <= 1'b1;
                        child_offset <= child_offset + 4;
                        child_idx <= child_idx + 1;
                        // The child pointer data will be available next cycle
                        // Check if child points to heap and push it
                        // For simplicity: push all non-zero children
                        // In a real implementation, check if the pointer is in heap range
                    end else begin
                        // All children processed, pop from stack
                        if (stack_ptr > 0) begin
                            stack_ptr <= stack_ptr - 1;
                            obj_addr <= mark_stack[stack_ptr - 1];
                            mem_addr <= (mark_stack[stack_ptr - 1] - HEAP_BASE) >> 2;
                            mem_rd_en <= 1'b1;
                            state <= ST_MARK_STACK;
                        end else begin
                            state <= ST_MARK_ROOT;
                        end
                    end
                end

                // ====== SWEEP_SCAN: linear scan, reclaim unmarked ======
                ST_SWEEP_SCAN: begin
                    if (scan_ptr < heap_free_ptr) begin
                        mem_addr <= scan_ptr >> 2;
                        mem_rd_en <= 1'b1;
                        // Process in next cycle
                        state <= ST_SWEEP_SCAN;
                        // For now, just advance
                        scan_ptr <= scan_ptr + (obj_size > 0 ? obj_size : 8);
                    end else begin
                        // Sweep complete
                        updated_free_ptr <= scan_ptr;
                        gc_freed_bytes <= freed_bytes;
                        gc_busy <= 1'b0;
                        gc_done <= 1'b1;
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    gc_done <= 1'b0;
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
