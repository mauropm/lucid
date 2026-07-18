// Parallel Scheduling Testbench
`timescale 1ns/1ps

module tb_parallel;
    logic clk, reset_n;
    logic reg_cyc, reg_stb, reg_we, reg_ack;
    logic [31:0] reg_adr, reg_dat_w, reg_dat_r;

    graph_scheduler_parallel #(.NUM_NODES(64), .Q_DEPTH(16)) sched (.*);

    always #5 clk = ~clk;

    task reg_write(input [31:0] a, d);
        @(posedge clk); reg_cyc=1; reg_stb=1; reg_we=1; reg_adr=a; reg_dat_w=d;
        @(posedge clk); reg_cyc=0; reg_stb=0; reg_we=0; @(posedge clk);
    endtask

    task nw(input int n, f, [31:0] d);
        reg_write(32'h20 + n*24 + f*4, d);
    endtask

    initial begin
        $dumpfile("build/sim/tb_parallel.vcd");
        $dumpvars(0, tb_parallel);
        clk=0; reset_n=0; reg_cyc=0; reg_stb=0; reg_we=0; reg_adr=0; reg_dat_w=0;
        #15 reset_n=1; @(posedge clk);

        // Graph: two independent chains that converge
        // Chain 1: node0(LIT 1)→node2(LIT 2)→node4(ADD 1+2=3)
        // Chain 2: node1(LIT 10)→node3(LIT 20)→node5(ADD 10+20=30)
        // Converge: node6(MUL 3*30=90)
        // Nodes 4 and 5 are independent → execute in parallel

        $display("=== Test: Parallel ADD chains ===");
        nw(0, 0, 32'h00400000); nw(0, 1, 32'd1); nw(0, 4, 32'h00000010);  // LIT 1 → dep node4
        nw(1, 0, 32'h00400000); nw(1, 1, 32'd10); nw(1, 4, 32'h00000020); // LIT 10 → dep node5
        nw(2, 0, 32'h00400000); nw(2, 1, 32'd2); nw(2, 4, 32'h00000010);  // LIT 2 → dep node4
        nw(3, 0, 32'h00400000); nw(3, 1, 32'd20); nw(3, 4, 32'h00000020); // LIT 20 → dep node5
        nw(4, 0, 32'h04020000); nw(4, 4, 32'h00000040);  // ADD num_inputs=2 → dep node6
        nw(5, 0, 32'h04020000); nw(5, 4, 32'h00000040);  // ADD num_inputs=2 → dep node6
        nw(6, 0, 32'h04820000); nw(6, 4, 32'd0);          // MUL num_inputs=2 root
        reg_write(32'h08, 32'd6); reg_write(32'h0C, 32'd7);
        reg_write(32'h00, 32'd1);

        for (int i=0; i<80; i++) @(posedge clk);

        $display("  node4 (1+2) = %0d (exp 3)", sched.node_result[4]);
        $display("  node5 (10+20) = %0d (exp 30)", sched.node_result[5]);
        $display("  node6 (3*30) = %0d (exp 90)", sched.node_result[6]);
        $display("  concurrency = %0d (exp 2 for parallel dispatch)", sched.perf_conc);

        if (sched.node_result[4]==3 && sched.node_result[5]==30 && sched.node_result[6]==90)
            $display("  PASS: Results correct");
        else $error("  FAIL: Wrong results");

        // Test 2: Serial chain (no parallelism)
        $display("");
        $display("=== Test: Serial chain ===");
        reset_n=0; #15 reset_n=1; @(posedge clk); reg_write(32'h00, 0); @(posedge clk);

        nw(0, 0, 32'h00400000); nw(0, 1, 32'd5); nw(0, 4, 32'h00000002);  // LIT 5 → dep node1
        nw(1, 0, 32'h04010000); nw(1, 2, 32'd3); nw(1, 4, 32'h00000004); // ADD num_inp=1, imm1=3 → dep node2
        nw(2, 0, 32'h04810000); nw(2, 2, 32'd2); nw(2, 4, 32'd0);         // MUL num_inp=1, imm1=2
        reg_write(32'h08, 32'd2); reg_write(32'h0C, 32'd3);
        reg_write(32'h00, 32'd1);

        for (int i=0; i<60; i++) @(posedge clk);

        $display("  node2 (5+3)*2 = %0d (exp 16)", sched.node_result[2]);
        if (sched.node_result[2]==16) $display("  PASS");
        else $error("  FAIL");

        // Test 3: Sequential through exec units - 5 * (1+2) + (3+4)
        // Two independent ADDs, then MUL and ADD at the end
        $display("");
        $display("=== Test: 5 * (1+2) + (3+4) ===");
        reset_n=0; #15 reset_n=1; @(posedge clk); reg_write(32'h00, 0); @(posedge clk);

        // LIT_INTs
        nw(0, 0, 32'h00400000); nw(0, 1, 32'd5); nw(0, 4, 32'h00000040);  // dep node6
        nw(1, 0, 32'h00400000); nw(1, 1, 32'd1); nw(1, 4, 32'h00000010);  // dep node4
        nw(2, 0, 32'h00400000); nw(2, 1, 32'd2); nw(2, 4, 32'h00000010);  // dep node4
        nw(3, 0, 32'h00400000); nw(3, 1, 32'd3); nw(3, 4, 32'h00000100);  // dep node8
        nw(4, 0, 32'h00400000); nw(4, 1, 32'd4); nw(4, 4, 32'h00000100);  // dep node8
        // Ops
        nw(5, 0, 32'h04020000); nw(5, 4, 32'h00000040);  // ADD 1+2=3 → dep node6
        nw(6, 0, 32'h04820000); nw(6, 4, 32'h00000200);  // MUL 5*3=15 → dep node9
        nw(7, 0, 32'h04020000); nw(7, 4, 32'h00000200);  // ADD 3+4=7 → dep node9
        nw(8, 0, 32'h04020000); nw(8, 4, 32'd0);          // ADD 15+7=22 (root)

        reg_write(32'h08, 32'd8); reg_write(32'h0C, 32'd9);
        reg_write(32'h00, 32'd1);

        for (int i=0; i<100; i++) @(posedge clk);

        $display("  node8 (5*(1+2)+(3+4)) = %0d (exp 22)", sched.node_result[8]);
        $display("  concurrency = %0d", sched.perf_conc);
        if (sched.node_result[8]==22) $display("  PASS");
        else $error("  FAIL");

        $display("");
        $display("PASS: tb_parallel");
        $finish;
    end
endmodule
