`timescale 1ns/1ps

module tb_scheme;
    logic clk, reset_n;
    logic reg_cyc, reg_stb, reg_we, reg_ack;
    logic [31:0] reg_adr, reg_dat_w, reg_dat_r;

    graph_scheduler #(.NUM_NODES(64), .Q_DEPTH(64)) sched (
        .clk(clk), .reset_n(reset_n),
        .reg_cyc(reg_cyc), .reg_stb(reg_stb), .reg_we(reg_we),
        .reg_adr(reg_adr), .reg_dat_w(reg_dat_w),
        .reg_dat_r(reg_dat_r), .reg_ack(reg_ack)
    );

    always #5 clk = ~clk;

    int fail_count;

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
        reg_write(32'h00, 32'd1);
        for (int i = 0; i < 60; i++) @(posedge clk);
        if (sched.node_result[sched.root_id] == expected)
            $display("  Result = %0d: PASS", sched.node_result[sched.root_id]);
        else begin
            $error("  Result = %0d, expected %0d", sched.node_result[sched.root_id], expected);
            fail_count++;
        end
    endtask

    initial begin
        $dumpfile("build/sim/tb_scheme.vcd");
        $dumpvars(0, tb_scheme);

        clk = 0; reset_n = 0;
        reg_cyc = 0; reg_stb = 0; reg_we = 0;
        reg_adr = 0; reg_dat_w = 0;
        fail_count = 0;
        #15 reset_n = 1;
        @(posedge clk);

        // Test 1: (+ 2 (* 3 4)) = 14
        $display("=== Test 1: (+ 2 (* 3 4)) ===");
        node_write(0, 0, 32'h00400000); node_write(0, 1, 32'h00000002); node_write(0, 4, 32'h00000010);
        node_write(1, 0, 32'h00400000); node_write(1, 1, 32'h00000003); node_write(1, 4, 32'h00000008);
        node_write(2, 0, 32'h00400000); node_write(2, 1, 32'h00000004); node_write(2, 4, 32'h00000008);
        node_write(3, 0, 32'h04820000); node_write(3, 4, 32'h00000010);
        node_write(3, 5, 32'h00000201); // src0=1, src1=2
        node_write(4, 0, 32'h04020000); node_write(4, 4, 32'h00000000);
        node_write(4, 5, 32'h00000300); // src0=0, src1=3
        reg_write(32'h08, 32'd4); reg_write(32'h0C, 32'd5);
        run_scheme("(+ 2 (* 3 4))", 14);

        // Test 2: (* (+ 2 3) 4) = 20
        $display("=== Test 2: (* (+ 2 3) 4) ===");
        reset_n = 0; #15 reset_n = 1; @(posedge clk); reg_write(32'h00, 32'd0); @(posedge clk);
        node_write(0, 0, 32'h00400000); node_write(0, 1, 32'h00000002); node_write(0, 4, 32'h00000008);
        node_write(1, 0, 32'h00400000); node_write(1, 1, 32'h00000003); node_write(1, 4, 32'h00000008);
        node_write(2, 0, 32'h00400000); node_write(2, 1, 32'h00000004); node_write(2, 4, 32'h00000010);
        node_write(3, 0, 32'h04020000); node_write(3, 4, 32'h00000010);
        node_write(3, 5, 32'h00000001); // src0=0, src1=1
        node_write(4, 0, 32'h04820000); node_write(4, 4, 32'h00000000);
        node_write(4, 5, 32'h00000203); // src0=3, src1=2
        reg_write(32'h08, 32'd4); reg_write(32'h0C, 32'd5);
        run_scheme("(* (+ 2 3) 4)", 20);

        // Test 3: (if #t 1 2) = 1
        $display("=== Test 3: (if #t 1 2) ===");
        reset_n = 0; #15 reset_n = 1; @(posedge clk); reg_write(32'h00, 32'd0); @(posedge clk);
        node_write(0, 0, 32'h00800001); node_write(0, 4, 32'h00000008);
        node_write(1, 0, 32'h00400000); node_write(1, 1, 32'h00000001); node_write(1, 4, 32'h00000008);
        node_write(2, 0, 32'h00400000); node_write(2, 1, 32'h00000002); node_write(2, 4, 32'h00000008);
        node_write(3, 0, 32'h0C030000); node_write(3, 4, 32'h00000000);
        node_write(3, 5, 32'h00000201); // src0=0, src1=1, src2=2
        reg_write(32'h08, 32'd3); reg_write(32'h0C, 32'd4);
        run_scheme("(if #t 1 2)", 1);

        // Test 4: (< 3 5) = 1
        $display("=== Test 4: (< 3 5) ===");
        reset_n = 0; #15 reset_n = 1; @(posedge clk); reg_write(32'h00, 32'd0); @(posedge clk);
        node_write(0, 0, 32'h00400000); node_write(0, 1, 32'h00000003); node_write(0, 4, 32'h00000004);
        node_write(1, 0, 32'h00400000); node_write(1, 1, 32'h00000005); node_write(1, 4, 32'h00000004);
        node_write(2, 0, 32'h05820000); node_write(2, 4, 32'h00000000);
        node_write(2, 5, 32'h00000001); // src0=0, src1=1
        reg_write(32'h08, 32'd2); reg_write(32'h0C, 32'd3);
        run_scheme("(< 3 5)", 1);

        $display("");
        if (fail_count == 0) begin $display("PASS: tb_scheme"); $finish(0); end
        else begin $display("FAIL: tb_scheme (%0d failures)", fail_count); $finish(1); end
    end

endmodule
