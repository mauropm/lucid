`default_nettype none

module heap_controller #(
    parameter int HEAP_SIZE = 16384,
    parameter int HEAP_BASE = 32'h00300000
) (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        alloc_valid,
    input  logic [7:0]  alloc_tag,
    input  logic [7:0]  alloc_flags,
    input  logic [15:0] alloc_size,
    output logic [31:0] alloc_ptr,
    output logic        alloc_ack,

    output logic [31:0] heap_free_ptr,
    output logic [31:0] heap_used,
    output logic [31:0] heap_avail
);

    logic [31:0] mem [0:HEAP_SIZE/4 - 1];

    logic [31:0] free_ptr;
    logic alloc_active;
    int tmp_wa;

    logic init_done;

    wire [15:0] alloc_size_aligned = (alloc_size + 15) & ~15;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            free_ptr   <= 32'd256;
            alloc_ack  <= 1'b0;
            alloc_ptr  <= '0;
            alloc_active <= 1'b0;
            init_done  <= 1'b0;
        end else begin
            alloc_ack <= 1'b0;

            if (!init_done) begin
                mem[0] <= 32'h48454150;
                mem[1] <= HEAP_SIZE;
                mem[3] <= 32'd0;
                mem[4] <= 32'd0;
                mem[5] <= 32'd0;
                init_done <= 1'b1;
            end

            if (alloc_valid && !alloc_active) begin
                alloc_active <= 1'b1;
                if (free_ptr + alloc_size_aligned <= HEAP_SIZE) begin
                    tmp_wa = free_ptr >> 2;
                    mem[tmp_wa] <= {alloc_tag, alloc_flags, alloc_size_aligned};
                    alloc_ptr <= HEAP_BASE + free_ptr;
                    alloc_ack <= 1'b1;
                    free_ptr <= free_ptr + alloc_size_aligned;
                end else begin
                    alloc_ptr <= 32'd0;
                    alloc_ack <= 1'b1;
                end
            end
            if (!alloc_valid)
                alloc_active <= 1'b0;
        end
    end

    assign heap_free_ptr = free_ptr;
    assign heap_used     = free_ptr - 32'd256;
    assign heap_avail    = HEAP_SIZE - free_ptr;

endmodule

`default_nettype wire
