// Heap Controller
// ===============
// Manages the FPU's functional object heap.
// Handles allocation requests and returns object pointers.
// Supports all object types with common header format.
//
// Header format (32-bit):
//   [31:24] TAG     Object type
//   [23:16] FLAGS   GC flags
//   [15:0]  SIZE    Object size in bytes

module heap_controller #(
    parameter int HEAP_SIZE = 16384,  // 16 KB for simulation
    parameter int HEAP_BASE = 32'h00300000
) (
    input  logic        clk,
    input  logic        reset_n,

    // Allocation request
    input  logic        alloc_valid,
    input  logic [7:0]  alloc_tag,
    input  logic [7:0]  alloc_flags,
    input  logic [15:0] alloc_size,  // total object size in bytes
    output logic [31:0] alloc_ptr,   // pointer to allocated object (0 = OOM)
    output logic        alloc_ack,

    // Heap state (read-only for debug/monitoring)
    output logic [31:0] heap_free_ptr,
    output logic [31:0] heap_used,
    output logic [31:0] heap_avail
);

    // Internal memory for heap (BRAM)
    logic [31:0] mem [0:HEAP_SIZE/4 - 1];

    // Free pointer (byte offset from HEAP_BASE)
    logic [31:0] free_ptr;
    int tmp_wa;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            free_ptr   <= 32'd256; // Skip header area
            alloc_ack  <= 1'b0;
            alloc_ptr  <= '0;
            // Initialize heap header
            mem[0] <= 32'h48454150; // MAGIC "HEAP"
            mem[1] <= HEAP_SIZE;    // HEAP_SIZE
            mem[2] <= 32'd256;      // FREE_PTR
            mem[3] <= 32'd0;        // OBJECT_COUNT
            mem[4] <= 32'd0;        // GC_COUNT
            mem[5] <= 32'd0;        // FLAGS
        end else begin
            alloc_ack <= 1'b0;

            if (alloc_valid && !alloc_ack) begin
                // Check if enough space
                if (free_ptr + alloc_size <= HEAP_SIZE) begin
                    // Write object header at free_ptr
                    tmp_wa = free_ptr >> 2;
                    mem[tmp_wa] <= {alloc_tag, alloc_flags, alloc_size};

                    // Return object pointer (absolute address)
                    alloc_ptr <= HEAP_BASE + free_ptr;
                    alloc_ack <= 1'b1;

                    // Update free pointer
                    free_ptr <= free_ptr + alloc_size;
                end else begin
                    // Out of memory
                    alloc_ptr <= 32'd0;
                    alloc_ack <= 1'b1;
                end
            end

            // Update heap header
            mem[2] <= free_ptr; // FREE_PTR
        end
    end

    // Heap state outputs
    assign heap_free_ptr = free_ptr;
    assign heap_used     = free_ptr;
    assign heap_avail    = HEAP_SIZE - free_ptr;

endmodule
