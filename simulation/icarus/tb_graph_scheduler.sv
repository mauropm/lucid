`timescale 1ns/1ps

module tb_graph_scheduler;
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

    function [31:0] encode_header(
        input [1:0] state,
        input [7:0] opcode,
        input [5:0] num_inputs,
        input [5:0] ready_inputs,
        input [9:0] flags
    );
        return {state, opcode, num_inputs, ready_inputs, flags};
    endfunction

    initial begin
        $dumpfile("build/sim/tb_graph_scheduler.vcd");
        $dumpvars(0, tb_graph_scheduler);

        clk = 0; reset_n = 0;
        reg_cyc = 0; reg_stb = 0; reg_we = 0;
        reg_adr = 0; reg_dat_w = 0;
        fail_count = 0;
        #15 reset_n = 1;
        @(posedge clk);

        // Graph: (+ 2 (* 3 4)) = 14
        // Node 0: LIT_INT 2, dep=bit4
        node_write(0, 0, encode_header(2'b00, 8'h01, 6'd0, 6'd0, 10'd0));
        node_write(0, 1, 32'd2);
        node_write(0, 4, 32'h00000010);
        // Node 1: LIT_INT 3, dep=bit3
        node_write(1, 0, encode_header(2'b00, 8'h01, 6'd0, 6'd0, 10'd0));
        node_write(1, 1, 32'd3);
        node_write(1, 4, 32'h00000008);
        // Node 2: LIT_INT 4, dep=bit3
        node_write(2, 0, encode_header(2'b00, 8'h01, 6'd0, 6'd0, 10'd0));
        node_write(2, 1, 32'd4);
        node_write(2, 4, 32'h00000008);
        // Node 3: MUL, numinp=2, dep=bit4, src0=1, src1=2
        node_write(3, 0, encode_header(2'b00, 8'h12, 6'd2, 6'd0, 10'd0));
        node_write(3, 4, 32'h00000010);
        node_write(3, 5, 32'h00000201); // src0=1, src1=2
        // Node 4: ADD, numinp=2, src0=0, src1=3
        node_write(4, 0, encode_header(2'b00, 8'h10, 6'd2, 6'd0, 10'd0));
        node_write(4, 4, 32'd0);
        node_write(4, 5, 32'h00000300); // src0=0, src1=3

        reg_write(32'h08, 32'd4);
        reg_write(32'h0C, 32'd5);

        reg_write(32'h00, 32'd1);

        for (int i = 0; i < 50; i++) @(posedge clk);

        $display("=== Results ===");
        if (sched.node_result[4] == 32'd14)
            $display("  Node 4 = 14: PASS");
        else begin $error("  Node 4 = %0d, expected 14", sched.node_result[4]); fail_count++; end

        if (sched.node_result[3] == 32'd12)
            $display("  Node 3 = 12: PASS");
        else begin $error("  Node 3 = %0d, expected 12", sched.node_result[3]); fail_count++; end

        $display("");
        if (fail_count == 0) begin $display("PASS: tb_graph_scheduler"); $finish(0); end
        else begin $display("FAIL: tb_graph_scheduler (%0d failures)", fail_count); $finish(1); end
    end

endmodule
