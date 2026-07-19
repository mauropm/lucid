`timescale 1ns/1ps

module tb_parallel;
    logic clk, reset_n;
    logic reg_cyc, reg_stb, reg_we, reg_ack;
    logic [31:0] reg_adr, reg_dat_w, reg_dat_r;

    graph_scheduler_parallel #(.NUM_NODES(64), .Q_DEPTH(64)) sched (.*);

    always #5 clk = ~clk;

    int fail_count;

    task reg_write(input [31:0] a, d);
        @(posedge clk); reg_cyc=1; reg_stb=1; reg_we=1; reg_adr=a; reg_dat_w=d;
        @(posedge clk); reg_cyc=0; reg_stb=0; reg_we=0; @(posedge clk);
    endtask

    task nw(input int n, f, [31:0] d);
        reg_write(32'h20 + n*32 + f*4, d);
    endtask

    initial begin
        $dumpfile("build/sim/tb_parallel.vcd");
        $dumpvars(0, tb_parallel);
        clk=0; reset_n=0; reg_cyc=0; reg_stb=0; reg_we=0; reg_adr=0; reg_dat_w=0;
        fail_count = 0;
        #15 reset_n=1; @(posedge clk);

        $display("=== Test: Parallel ADD chains ===");
        nw(0, 0, 32'h00400000); nw(0, 1, 32'd1); nw(0, 4, 32'h00000010);
        nw(1, 0, 32'h00400000); nw(1, 1, 32'd10); nw(1, 4, 32'h00000020);
        nw(2, 0, 32'h00400000); nw(2, 1, 32'd2); nw(2, 4, 32'h00000010);
        nw(3, 0, 32'h00400000); nw(3, 1, 32'd20); nw(3, 4, 32'h00000020);
        nw(4, 0, 32'h04020000); nw(4, 4, 32'h00000040);
        nw(4, 5, 32'h00000002); // src0=0, src1=2
        nw(5, 0, 32'h04020000); nw(5, 4, 32'h00000040);
        nw(5, 5, 32'h00000301); // src0=1, src1=3
        nw(6, 0, 32'h04820000); nw(6, 4, 32'd0);
        nw(6, 5, 32'h00000504); // src0=4, src1=5
        reg_write(32'h08, 32'd6); reg_write(32'h0C, 32'd7);
        reg_write(32'h00, 32'd1);

        for (int i=0; i<80; i++) @(posedge clk);

        $display("  node4 (1+2) = %0d (exp 3)", sched.node_result[4]);
        $display("  node5 (10+20) = %0d (exp 30)", sched.node_result[5]);
        $display("  node6 (3*30) = %0d (exp 90)", sched.node_result[6]);

        if (sched.node_result[4]==3 && sched.node_result[5]==30 && sched.node_result[6]==90)
            $display("  PASS: Results correct");
        else begin $error("  FAIL: Wrong results"); fail_count++; end

        // Test 2: Serial chain
        $display("");
        $display("=== Test: Serial chain ===");
        reset_n=0; #15 reset_n=1; @(posedge clk); reg_write(32'h00, 0); @(posedge clk);

        nw(0, 0, 32'h00400000); nw(0, 1, 32'd5); nw(0, 4, 32'h00000002);
        nw(1, 0, 32'h04010000); nw(1, 2, 32'd3); nw(1, 4, 32'h00000004);
        nw(1, 5, 32'h00000000); // src0=0
        nw(2, 0, 32'h04810000); nw(2, 2, 32'd2); nw(2, 4, 32'd0);
        nw(2, 5, 32'h00000001); // src0=1
        reg_write(32'h08, 32'd2); reg_write(32'h0C, 32'd3);
        reg_write(32'h00, 32'd1);

        for (int i=0; i<60; i++) @(posedge clk);

        $display("  node2 (5+3)*2 = %0d (exp 16)", sched.node_result[2]);
        if (sched.node_result[2]==16) $display("  PASS");
        else begin $error("  FAIL"); fail_count++; end

        // Test 3: 5 * (1+2) + (3+4) = 22
        $display("");
        $display("=== Test: 5 * (1+2) + (3+4) ===");
        reset_n=0; #15 reset_n=1; @(posedge clk); reg_write(32'h00, 0); @(posedge clk);

        nw(0, 0, 32'h00400000); nw(0, 1, 32'd5); nw(0, 4, 32'h00000040);
        nw(1, 0, 32'h00400000); nw(1, 1, 32'd1); nw(1, 4, 32'h00000010);
        nw(2, 0, 32'h00400000); nw(2, 1, 32'd2); nw(2, 4, 32'h00000010);
        nw(3, 0, 32'h00400000); nw(3, 1, 32'd3); nw(3, 4, 32'h00000100);
        nw(4, 0, 32'h00400000); nw(4, 1, 32'd4); nw(4, 4, 32'h00000100);
        nw(5, 0, 32'h04020000); nw(5, 4, 32'h00000040);
        nw(5, 5, 32'h00000201); // src0=1, src1=2
        nw(6, 0, 32'h04820000); nw(6, 4, 32'h00000200);
        nw(6, 5, 32'h00000500); // src0=0, src1=5
        nw(7, 0, 32'h04020000); nw(7, 4, 32'h00000200);
        nw(7, 5, 32'h00000403); // src0=3, src1=4
        nw(8, 0, 32'h04020000); nw(8, 4, 32'd0);
        nw(8, 5, 32'h00000706); // src0=6, src1=7

        reg_write(32'h08, 32'd8); reg_write(32'h0C, 32'd9);
        reg_write(32'h00, 32'd1);

        for (int i=0; i<100; i++) @(posedge clk);

        $display("  node8 = %0d (exp 22)", sched.node_result[8]);
        if (sched.node_result[8]==22) $display("  PASS");
        else begin $error("  FAIL"); fail_count++; end

        $display("");
        if (fail_count == 0) begin $display("PASS: tb_parallel"); $finish(0); end
        else begin $display("FAIL: tb_parallel (%0d failures)", fail_count); $finish(1); end
    end
endmodule
