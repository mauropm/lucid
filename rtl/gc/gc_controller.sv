`default_nettype none

// C8: GC Controller - Marked as STUB
// This module is non-functional. The mark-sweep algorithm is incomplete:
// - Child pushing is not implemented (only roots are marked)
// - Sweep does not reclaim memory or clear mark bits
// - updated_free_ptr is not connected back to the heap
// Do not use in production. A full implementation is pending.

module gc_controller #(
    parameter int HEAP_SIZE = 4096,
    parameter int HEAP_BASE = 32'h00300000,
    parameter int HEADER_SIZE = 256,
    parameter int MAX_ROOTS = 8
) (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        gc_start,
    output logic        gc_busy,
    output logic        gc_done,
    output logic [31:0] gc_freed_bytes,

    input  logic [7:0]  root_count,
    input  logic [255:0] root_ptrs,

    output logic [31:0] mem_addr,
    input  logic [31:0] mem_rdata,
    output logic        mem_rd_en,
    output logic        mem_wr_en,
    output logic [31:0] mem_wdata,

    input  logic [31:0] heap_free_ptr,
    output logic [31:0] updated_free_ptr
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_MARK_ROOT,
        ST_MARK_STACK,
        ST_MARK_CHILDREN,
        ST_SWEEP_SCAN,
        ST_DONE
    } state_t;

    state_t state;

    logic [31:0] mark_stack [0:63];
    logic [5:0]  stack_ptr;
    logic [31:0] scan_ptr;
    logic [31:0] freed_bytes;
    logic [31:0] root_array [0:7];
    logic [2:0]  root_idx;

    always_comb begin
        for (int i = 0; i < 8; i++)
            root_array[i] = root_ptrs[i*32 +: 32];
    end

    logic [31:0] obj_addr;
    logic [31:0] obj_header;
    logic [7:0]  obj_tag;
    logic [7:0]  obj_flags;
    logic [15:0] obj_size;
    logic [3:0]  child_idx;
    logic [5:0]  child_offset;
    logic [3:0]  max_children;

    assign obj_header = mem_rdata;
    assign obj_tag    = obj_header[31:24];
    assign obj_flags  = obj_header[23:16];
    assign obj_size   = obj_header[15:0];

    always_comb begin
        if (obj_tag == 8'h06 || obj_tag == 8'h08)
            max_children = 4'd2;
        else if (obj_tag == 8'h07)
            max_children = 4'd8;
        else
            max_children = 4'd0;
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
            mem_addr <= '0;
            mem_wdata <= '0;
            obj_addr <= '0;
            child_idx <= '0;
            child_offset <= '0;
            root_idx <= '0;
            updated_free_ptr <= '0;
        end else begin
            mem_rd_en <= 1'b0;
            mem_wr_en <= 1'b0;

            case (state)
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

                ST_MARK_ROOT: begin
                    if (root_idx < (root_count < 8 ? root_count : 8)) begin
                        obj_addr <= root_array[root_idx];
                        mem_addr <= (root_array[root_idx] - HEAP_BASE) >> 2;
                        mem_rd_en <= 1'b1;
                        root_idx <= root_idx + 1;
                        state <= ST_MARK_STACK;
                    end else begin
                        scan_ptr <= HEADER_SIZE;
                        state <= ST_SWEEP_SCAN;
                    end
                end

                ST_MARK_STACK: begin
                    if (!obj_flags[0]) begin
                        mem_addr <= (obj_addr - HEAP_BASE) >> 2;
                        mem_wr_en <= 1'b1;
                        mem_wdata <= {obj_tag, obj_flags | 8'h01, obj_size};
                        child_idx <= '0;
                        child_offset <= 6'd4;
                        state <= ST_MARK_CHILDREN;
                    end else begin
                        if (stack_ptr > 0) begin
                            stack_ptr <= stack_ptr - 1;
                            obj_addr <= mark_stack[stack_ptr - 1];
                            mem_addr <= (mark_stack[stack_ptr - 1] - HEAP_BASE) >> 2;
                            mem_rd_en <= 1'b1;
                        end else begin
                            state <= ST_MARK_ROOT;
                        end
                    end
                end

                ST_MARK_CHILDREN: begin
                    if (child_idx < max_children) begin
                        mem_addr <= ((obj_addr + {1'b0, child_offset} - HEAP_BASE) >> 2);
                        mem_rd_en <= 1'b1;
                        child_offset <= child_offset + 4;
                        child_idx <= child_idx + 1;
                        // C8 STUB: child pointer push not implemented
                    end else begin
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

                ST_SWEEP_SCAN: begin
                    if (scan_ptr < heap_free_ptr) begin
                        mem_addr <= scan_ptr >> 2;
                        mem_rd_en <= 1'b1;
                        // C8 STUB: sweep does not reclaim or clear marks
                        scan_ptr <= scan_ptr + (obj_size > 0 ? {16'h0, obj_size} : 8);
                    end else begin
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

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
