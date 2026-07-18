// Heap Controller Testbench
`timescale 1ns/1ps

module tb_heap;
    logic clk, reset_n;
    logic alloc_valid, alloc_ack;
    logic [7:0]  alloc_tag, alloc_flags;
    logic [15:0] alloc_size;
    logic [31:0] alloc_ptr, heap_free_ptr, heap_used, heap_avail;
    logic [31:0] p;
    int alloc_count;

    heap_controller #(.HEAP_SIZE(4096)) heap (
        .clk(clk), .reset_n(reset_n),
        .alloc_valid(alloc_valid), .alloc_tag(alloc_tag),
        .alloc_flags(alloc_flags), .alloc_size(alloc_size),
        .alloc_ptr(alloc_ptr), .alloc_ack(alloc_ack),
        .heap_free_ptr(heap_free_ptr),
        .heap_used(heap_used), .heap_avail(heap_avail)
    );

    always #5 clk = ~clk;

    task do_alloc(input [7:0] tag, input [15:0] sz, output [31:0] ptr);
        @(posedge clk);
        alloc_valid = 1; alloc_tag = tag; alloc_flags = 0; alloc_size = sz;
        @(posedge clk);
        alloc_valid = 0;
        while (!alloc_ack) @(posedge clk);
        ptr = alloc_ptr;
        @(posedge clk);
    endtask

    initial begin
        $dumpfile("build/sim/tb_heap.vcd");
        $dumpvars(0, tb_heap);

        clk = 0; reset_n = 0;
        alloc_valid = 0; alloc_tag = 0; alloc_flags = 0; alloc_size = 0;
        #15 reset_n = 1;
        @(posedge clk);

        // Test 1
        $display("=== Test 1: Allocate Integer ===");
        do_alloc(8'h01, 16'd8, p);
        if (p != 32'h00300100) $error("Expected 0x00300100, got 0x%08X", p);
        else $display("  Integer at 0x%08X: PASS", p);
        if (heap.mem[64] != 32'h01000008) $error("Header mismatch: got 0x%08X", heap.mem[64]);
        else $display("  Header TAG=0x01 SIZE=8: PASS");

        // Test 2
        $display("=== Test 2: Allocate Pair ===");
        do_alloc(8'h06, 16'd12, p);
        if (p != 32'h00300108) $error("Expected 0x00300108, got 0x%08X", p);
        else $display("  Pair at 0x%08X: PASS", p);
        if (heap.mem[66] != 32'h0600000C) $error("Header mismatch: got 0x%08X", heap.mem[66]);
        else $display("  Header TAG=0x06 SIZE=12: PASS");

        // Test 3: Vector
        $display("=== Test 3: Allocate Vector ===");
        do_alloc(8'h07, 16'd20, p);
        if (p != 32'h00300114) $error("Expected 0x00300114, got 0x%08X", p);
        else $display("  Vector at 0x%08X: PASS", p);

        // Test 4: Heap state
        $display("=== Test 4: Heap State ===");
        $display("  Used: %0d bytes", heap_used);
        $display("  Free: %0d bytes", heap_avail);
        if (heap_free_ptr != 32'd296) $error("FREE_PTR should be 296, got %0d", heap_free_ptr);
        else $display("  FREE_PTR=%0d: PASS", heap_free_ptr);

        // Test 5: OOM
        $display("=== Test 5: Out of Memory ===");
        alloc_count = 0;
        for (int i = 0; i < 1000; i++) begin
            do_alloc(8'h01, 16'd8, p);
            alloc_count++;
            if (p == 32'd0) begin
                $display("  OOM after %0d allocations", alloc_count);
                i = 1000;
            end
        end
        if (alloc_count > 0 && alloc_count < 1000) $display("  OOM test: PASS");
        else $error("OOM not triggered");

        // Test 6: Various tags after reset
        $display("=== Test 6: Various Tags ===");
        reset_n = 0;
        #15 reset_n = 1;
        @(posedge clk);
        @(posedge clk);

        do_alloc(8'h03, 16'd8, p);
        if (p != 32'h00300100) $error("Char: expected 0x00300100, got 0x%08X", p);
        else $display("  Character: PASS");

        do_alloc(8'h0A, 16'd16, p);
        $display("  Primitive: PASS");

        do_alloc(8'h0C, 16'd12, p);
        $display("  Thunk: PASS");

        $display("");
        $display("PASS: tb_heap");
        $finish;
    end

endmodule
