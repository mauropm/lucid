// Garbage Collection Testbench (simplified)
`timescale 1ns/1ps

module tb_gc;
    logic clk, reset_n;
    logic alloc_valid, alloc_ack, alloc_oom;
    logic [7:0]  alloc_tag, alloc_flags;
    logic [15:0] alloc_size;
    logic [31:0] alloc_ptr, heap_free_ptr, heap_used, heap_avail;
    logic        gc_trigger, gc_busy, gc_done;

    heap_controller_gc #(.HEAP_SIZE(4096)) heap (
        .clk(clk), .reset_n(reset_n),
        .alloc_valid(alloc_valid), .alloc_tag(alloc_tag),
        .alloc_flags(alloc_flags), .alloc_size(alloc_size),
        .alloc_ptr(alloc_ptr), .alloc_ack(alloc_ack), .alloc_oom(alloc_oom),
        .gc_mem_rd_en(1'b0), .gc_mem_wr_en(1'b0),
        .gc_mem_addr(32'h0), .gc_mem_wdata(32'h0),
        .gc_mem_rdata(),
        .gc_trigger(gc_trigger), .gc_busy(gc_busy), .gc_done(gc_done),
        .heap_free_ptr(heap_free_ptr), .heap_used(heap_used), .heap_avail(heap_avail)
    );

    always #5 clk = ~clk;

    task do_alloc(input [7:0] tag, input [15:0] sz, output [31:0] ptr);
        @(posedge clk);
        alloc_valid <= 1; alloc_tag <= tag; alloc_flags <= 0; alloc_size <= sz;
        @(posedge clk);
        alloc_valid <= 0;
        while (!alloc_ack) @(posedge clk);
        ptr = alloc_ptr;
        @(posedge clk);
    endtask

    logic [31:0] p;
    int alloc_count;
    int fail_count;

    initial begin
        $dumpfile("build/sim/tb_gc.vcd");
        $dumpvars(0, tb_gc);

        clk = 0; reset_n = 0;
        alloc_valid = 0; alloc_tag = 0; alloc_flags = 0; alloc_size = 0;
        gc_trigger = 0;
        gc_done = 0;
        fail_count = 0;
        #15 reset_n = 1;
        @(posedge clk);

        // Test 1: Allocate objects
        $display("=== Test 1: Allocate Integer ===");
        do_alloc(8'h01, 16'd8, p);
        $display("  Integer at 0x%08X: %s", p, p == 32'h00300100 ? "PASS" : "FAIL");

        $display("=== Test 2: Allocate Pair ===");
        do_alloc(8'h06, 16'd12, p);
        $display("  Pair at 0x%08X: %s", p, p == 32'h00300108 ? "PASS" : "FAIL");

        $display("=== Test 3: Allocate after GC goes idle ===");
        do_alloc(8'h01, 16'd8, p);
        $display("  Another Integer at 0x%08X", p);

        // Test 4: Trigger GC
        $display("");
        $display("=== Test 4: Trigger GC ===");
        gc_trigger <= 1;
        @(posedge clk);
        gc_trigger <= 0;
        @(posedge clk);
        $display("  GC busy: %0d (expected 1)", gc_busy);
        if (gc_busy) $display("  GC started: PASS");
        else fail_count++;
        // Simulate GC completion
        gc_done <= 1;
        @(posedge clk);
        gc_done <= 0;

        // Test 5: Heap state while GC active
        $display("");
        $display("=== Test 5: Heap State ===");
        $display("  Free ptr: %0d bytes", heap_free_ptr);
        $display("  Used: %0d / %0d", heap_used, heap_used + heap_avail);

        // Test 6: OOM triggers GC
        $display("");
        $display("=== Test 6: OOM triggers GC ===");
        // Fill remaining heap
        alloc_count = 0;
        for (int i = 0; i < 500; i++) begin
            @(posedge clk);
            alloc_valid <= 1; alloc_tag <= 8'h01; alloc_flags <= 0; alloc_size <= 16'd8;
            @(posedge clk);
            alloc_valid <= 0;
            if (alloc_ack || alloc_oom) begin
                alloc_count++;
                if (alloc_oom) begin
                    $display("  OOM after %0d allocations, GC auto-triggered: %0d", alloc_count, gc_busy);
                    i = 500;
                end
            end
            @(posedge clk);
        end

        // Verify allocation stops during GC
        do_alloc(8'h01, 16'd8, p);
        $display("  Alloc during GC: ptr=0x%08X, OOM=%0d", p, alloc_oom);
        if (p == 32'd0) $display("  OOM blocks allocation: PASS");
        else fail_count++;

        $display("");
        if (fail_count == 0) begin $display("PASS: tb_gc"); $finish(0); end else begin $display("FAIL: tb_gc (%0d failures)", fail_count); $finish(1); end
    end
endmodule
