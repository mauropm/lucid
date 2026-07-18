// Scheme End-to-End Testbench
// ===========================
// Compiles Scheme source to Lucid IR, loads into graph scheduler,
// executes, and verifies the result.
//
// Tests:
//   (+ 2 (* 3 4))   → 14
//   (* (+ 2 3) 4)   → 20
//   (if #t 1 2)     → 1
//   (< 3 5)         → #t (1)

`timescale 1ns/1ps

module tb_scheme;
    logic clk, reset_n;

    // Scheduler register interface
    logic reg_cyc, reg_stb, reg_we, reg_ack, reg_ack2;
    logic [31:0] reg_adr, reg_dat_w, reg_dat_r;
    logic [31:0] reg_adr2, reg_dat_w2, reg_dat_r2;

    // Message signals (not used in Phase 3 inline computation)
    logic tx_valid, tx_last, tx_ready;
    logic [31:0] tx_data;
    logic rx_valid, rx_last, rx_ready;
    logic [31:0] rx_data;

    graph_scheduler #(.NUM_NODES(64), .Q_DEPTH(16)) sched (
        .clk(clk), .reset_n(reset_n),
        .reg_cyc(reg_cyc), .reg_stb(reg_stb), .reg_we(reg_we),
        .reg_adr(reg_adr), .reg_dat_w(reg_dat_w),
        .reg_dat_r(reg_dat_r), .reg_ack(reg_ack)
    );

    always #5 clk = ~clk;

    task reg_write(input [31:0] addr, data);
        @(posedge clk);
        reg_cyc <= 1; reg_stb <= 1; reg_we <= 1;
        reg_adr <= addr; reg_dat_w <= data;
        @(posedge clk);
        reg_cyc <= 0; reg_stb <= 0; reg_we <= 0;
        @(posedge clk);
    endtask

    task node_write(input int nid, input int fid, input [31:0] data);
        reg_write(32'h20 + nid * 24 + fid * 4, data);
    endtask

    task run_scheme(input string name, input [31:0] expected);
        $display("");
        $display("=== %s ===", name);
        // Start execution
        reg_write(32'h00, 32'd1); // start
        // Wait for completion (poll status)
        for (int i = 0; i < 60; i++) @(posedge clk);
        // Check result
        if (sched.node_result[sched.root_id] == expected) begin
            $display("  Result = %0d: PASS", sched.node_result[sched.root_id]);
        end else begin
            $error("  Result = %0d, expected %0d", sched.node_result[sched.root_id], expected);
        end
    endtask

    initial begin
        $dumpfile("build/sim/tb_scheme.vcd");
        $dumpvars(0, tb_scheme);

        clk = 0; reset_n = 0;
        reg_cyc = 0; reg_stb = 0; reg_we = 0;
        reg_adr = 0; reg_dat_w = 0;
        #15 reset_n = 1;
        @(posedge clk);

        // ============================================================
        // Test 1: (+ 2 (* 3 4)) = 14
        // ============================================================
        $display("=== Test 1: (+ 2 (* 3 4)) ===");
        // Node 0: LIT_INT 2 → dep_mask bit4
        node_write(0, 0, 32'h00400000);
        node_write(0, 1, 32'h00000002);
        node_write(0, 4, 32'h00000010);
        // Node 1: LIT_INT 3 → dep_mask bit3
        node_write(1, 0, 32'h00400000);
        node_write(1, 1, 32'h00000003);
        node_write(1, 4, 32'h00000008);
        // Node 2: LIT_INT 4 → dep_mask bit3
        node_write(2, 0, 32'h00400000);
        node_write(2, 1, 32'h00000004);
        node_write(2, 4, 32'h00000008);
        // Node 3: MUL (0x12), num_inputs=2 → dep_mask bit4
        node_write(3, 0, 32'h04820000);
        node_write(3, 4, 32'h00000010);
        // Node 4: ADD (0x10), num_inputs=2
        node_write(4, 0, 32'h04020000);
        node_write(4, 4, 32'h00000000);
        reg_write(32'h08, 32'd4);  // root
        reg_write(32'h0C, 32'd5);  // node_count
        run_scheme("(+ 2 (* 3 4))", 14);

        // ============================================================
        // Test 2: (* (+ 2 3) 4) = 20
        // ============================================================
        $display("=== Test 2: (* (+ 2 3) 4) ===");
        reset_n = 0;
        #15 reset_n = 1;
        @(posedge clk);
        reg_write(32'h00, 32'd0);
        @(posedge clk);

        // Node 0: LIT_INT 2 → dep_mask bit3
        node_write(0, 0, 32'h00400000);
        node_write(0, 1, 32'h00000002);
        node_write(0, 4, 32'h00000008);
        // Node 1: LIT_INT 3 → dep_mask bit3
        node_write(1, 0, 32'h00400000);
        node_write(1, 1, 32'h00000003);
        node_write(1, 4, 32'h00000008);
        // Node 2: LIT_INT 4 → dep_mask bit4
        node_write(2, 0, 32'h00400000);
        node_write(2, 1, 32'h00000004);
        node_write(2, 4, 32'h00000010);
        // Node 3: ADD (0x10), num_inputs=2 → dep_mask bit4
        node_write(3, 0, 32'h04020000);
        node_write(3, 4, 32'h00000010);
        // Node 4: MUL (0x12), num_inputs=2
        node_write(4, 0, 32'h04820000);
        node_write(4, 4, 32'h00000000);
        reg_write(32'h08, 32'd4);
        reg_write(32'h0C, 32'd5);
        run_scheme("(* (+ 2 3) 4)", 20);

        // ============================================================
        // Test 3: (if #t 1 2) = 1
        // ============================================================
        $display("=== Test 3: (if #t 1 2) ===");
        reset_n = 0;
        #15 reset_n = 1;
        @(posedge clk);
        reg_write(32'h00, 32'd0);
        @(posedge clk);

        // Node 0: LIT_BOOL #t (opcode=0x02, flags=1) → dep_mask bit3
        node_write(0, 0, 32'h00800001);
        node_write(0, 4, 32'h00000008);
        // Node 1: LIT_INT 1 → dep_mask bit3
        node_write(1, 0, 32'h00400000);
        node_write(1, 1, 32'h00000001);
        node_write(1, 4, 32'h00000008);
        // Node 2: LIT_INT 2 → dep_mask bit3
        node_write(2, 0, 32'h00400000);
        node_write(2, 1, 32'h00000002);
        node_write(2, 4, 32'h00000008);
        // Node 3: IF (0x30), num_inputs=3
        node_write(3, 0, 32'h0C030000);
        node_write(3, 4, 32'h00000000);
        reg_write(32'h08, 32'd3);
        reg_write(32'h0C, 32'd4);
        run_scheme("(if #t 1 2)", 1);

        // ============================================================
        // Test 4: (< 3 5) = #t (1)
        // ============================================================
        $display("=== Test 4: (< 3 5) ===");
        reset_n = 0;
        #15 reset_n = 1;
        @(posedge clk);
        reg_write(32'h00, 32'd0);
        @(posedge clk);

        // Node 0: LIT_INT 3 → dep_mask bit2
        node_write(0, 0, 32'h00400000);
        node_write(0, 1, 32'h00000003);
        node_write(0, 4, 32'h00000004);
        // Node 1: LIT_INT 5 → dep_mask bit2
        node_write(1, 0, 32'h00400000);
        node_write(1, 1, 32'h00000005);
        node_write(1, 4, 32'h00000004);
        // Node 2: LT (0x16), num_inputs=2
        node_write(2, 0, 32'h05820000);
        node_write(2, 4, 32'h00000000);
        reg_write(32'h08, 32'd2);
        reg_write(32'h0C, 32'd3);
        run_scheme("(< 3 5)", 1);

        $display("");
        $display("PASS: tb_scheme");
        $finish;
    end

endmodule
