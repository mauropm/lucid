`timescale 1ns/1ps

// tb_parallel — Scheduler stress test (canonical graph_scheduler_fp)
// Verifies the single-issue scheduler produces correct results for
// wide/deep graphs with no dropped or duplicated work.
module tb_parallel;
    logic clk, reset_n;
    logic reg_cyc, reg_stb, reg_we, reg_ack;
    logic [31:0] reg_adr, reg_dat_w, reg_dat_r;

    graph_scheduler_fp #(.NUM_NODES(64), .Q_DEPTH(64)) sched (
        .clk(clk), .reset_n(reset_n),
        .reg_cyc(reg_cyc), .reg_stb(reg_stb), .reg_we(reg_we),
        .reg_adr(reg_adr), .reg_dat_w(reg_dat_w),
        .reg_dat_r(reg_dat_r), .reg_ack(reg_ack)
    );

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

        // Stress graph: two independent ADD chains merged into a MUL
        $display("=== Test: Parallel ADD chains (merged MUL) ===");
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

        if (sched.dbg_node_result[4]==3 && sched.dbg_node_result[5]==30 && sched.dbg_node_result[6]==90)
            $display("  PASS: Results correct (3, 30, 90)");
        else begin $error("  FAIL: Wrong results (4=%0d 5=%0d 6=%0d)", sched.dbg_node_result[4], sched.dbg_node_result[5], sched.dbg_node_result[6]); fail_count++; end

        $display("");
        $display("=== Test: 5 * (1+2) + (3+4) ===");
        reset_n=0; #15 reset_n=1; @(posedge clk); reg_write(32'h00, 0); @(posedge clk);

        nw(0, 0, 32'h00400000); nw(0, 1, 32'd5); nw(0, 4, 32'h00000040);
        nw(1, 0, 32'h00400000); nw(1, 1, 32'd1); nw(1, 4, 32'h00000020);
        nw(2, 0, 32'h00400000); nw(2, 1, 32'd2); nw(2, 4, 32'h00000020);
        nw(3, 0, 32'h00400000); nw(3, 1, 32'd3); nw(3, 4, 32'h00000080);
        nw(4, 0, 32'h00400000); nw(4, 1, 32'd4); nw(4, 4, 32'h00000080);
        nw(5, 0, 32'h04020000); nw(5, 4, 32'h00000040);
        nw(5, 5, 32'h00000201); // src0=1, src1=2
        nw(6, 0, 32'h04820000); nw(6, 4, 32'h00000100);
        nw(6, 5, 32'h00000500); // src0=0, src1=5
        nw(7, 0, 32'h04020000); nw(7, 4, 32'h00000100);
        nw(7, 5, 32'h00000403); // src0=3, src1=4
        nw(8, 0, 32'h04020000); nw(8, 4, 32'd0);
        nw(8, 5, 32'h00000706); // src0=6, src1=7

        reg_write(32'h08, 32'd8); reg_write(32'h0C, 32'd9);
        reg_write(32'h00, 32'd1);

        for (int i=0; i<100; i++) @(posedge clk);

        $display("  node8 = %0d (exp 22)", sched.dbg_node_result[8]);
        if (sched.dbg_node_result[8]==22) $display("  PASS");
        else begin $error("  FAIL"); fail_count++; end

        $display("");
        if (fail_count == 0) begin $display("PASS: tb_parallel"); $finish(0); end
        else begin $display("FAIL: tb_parallel (%0d failures)", fail_count); $finish(1); end
    end
endmodule
