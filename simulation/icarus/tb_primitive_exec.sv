// Primitive Execution Integration Testbench
// =========================================
// Tests: graph_scheduler_fp + message_router + primitive_exec.
//
// Graph: (+ 2 3) = 5
// Node 0: LIT_INT imm0=2  num_inputs=0  dep_mask=bit2
// Node 1: LIT_INT imm0=3  num_inputs=0  dep_mask=bit2
// Node 2: ADD (opcode=0x10) num_inputs=2  dep_mask=0
// Root: 2

`timescale 1ns/1ps

module tb_primitive_exec;
    logic clk, reset_n;

    // Scheduler register interface
    logic reg_cyc, reg_stb, reg_we, reg_ack;
    logic [31:0] reg_adr, reg_dat_w, reg_dat_r;

    // Message signals between scheduler and primitive exec
    logic sched_tx_valid, sched_tx_last, sched_tx_ready;
    logic [31:0] sched_tx_data;
    logic sched_rx_valid, sched_rx_last, sched_rx_ready;
    logic [31:0] sched_rx_data;

    logic exec_tx_valid, exec_tx_last, exec_tx_ready;
    logic [31:0] exec_tx_data;
    logic exec_rx_valid, exec_rx_last, exec_rx_ready;
    logic [31:0] exec_rx_data;

    // Scheduler with message dispatch
    int fail_count;

    graph_scheduler_fp #(.NUM_NODES(64), .Q_DEPTH(64)) sched (
        .clk(clk), .reset_n(reset_n),
        .reg_cyc(reg_cyc), .reg_stb(reg_stb), .reg_we(reg_we),
        .reg_adr(reg_adr), .reg_dat_w(reg_dat_w),
        .reg_dat_r(reg_dat_r), .reg_ack(reg_ack),
        .msg_tx_valid(sched_tx_valid), .msg_tx_last(sched_tx_last),
        .msg_tx_data(sched_tx_data), .msg_tx_ready(sched_tx_ready),
        .msg_rx_valid(sched_rx_valid), .msg_rx_last(sched_rx_last),
        .msg_rx_data(sched_rx_data), .msg_rx_ready(sched_rx_ready)
    );

    // Primitive execution unit
    primitive_exec exec (
        .clk(clk), .reset_n(reset_n),
        .msg_in_valid(exec_rx_valid), .msg_in_data(exec_rx_data),
        .msg_in_last(exec_rx_last), .msg_in_ready(exec_rx_ready),
        .msg_out_valid(exec_tx_valid), .msg_out_data(exec_tx_data),
        .msg_out_last(exec_tx_last), .msg_out_ready(exec_tx_ready)
    );

    // Direct connection: scheduler TX → exec RX, exec TX → scheduler RX
    assign exec_rx_valid  = sched_tx_valid;
    assign exec_rx_data   = sched_tx_data;
    assign exec_rx_last   = sched_tx_last;
    assign sched_tx_ready = exec_rx_ready;

    assign sched_rx_valid  = exec_tx_valid;
    assign sched_rx_data   = exec_tx_data;
    assign sched_rx_last   = exec_tx_last;
    assign exec_tx_ready   = sched_rx_ready;

    always #5 clk = ~clk;

    // Register write helper
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
        input [1:0] state, input [7:0] opcode,
        input [5:0] num_inputs, input [5:0] ready_inputs,
        input [9:0] flags
    );
        return {state, opcode, num_inputs, ready_inputs, flags};
    endfunction

    initial begin
        $dumpfile("build/sim/tb_primitive_exec.vcd");
        $dumpvars(0, tb_primitive_exec);

        clk = 0; reset_n = 0;
        reg_cyc = 0; reg_stb = 0; reg_we = 0; reg_adr = 0; reg_dat_w = 0;
        fail_count = 0;
        #15 reset_n = 1;
        @(posedge clk);

        $display("=== Loading graph: (+ 2 3) ===");

        // Node 0: LIT_INT, imm0=2, dep_mask=bit2
        node_write(0, 0, encode_header(2'b00, 8'h01, 6'd0, 6'd0, 10'd0));
        node_write(0, 1, 32'd2);
        node_write(0, 4, 32'h00000004);
        $display("  Node 0: LIT_INT 2");

        // Node 1: LIT_INT, imm0=3, dep_mask=bit2
        node_write(1, 0, encode_header(2'b00, 8'h01, 6'd0, 6'd0, 10'd0));
        node_write(1, 1, 32'd3);
        node_write(1, 4, 32'h00000004);
        $display("  Node 1: LIT_INT 3");

        // Node 2: ADD, num_inputs=2, no dependents (root)
        node_write(2, 0, encode_header(2'b00, 8'h10, 6'd2, 6'd0, 10'd0));
        node_write(2, 4, 32'd0);
        node_write(2, 5, 32'h00000001);
        $display("  Node 2: ADD (root)");

        reg_write(32'h08, 32'd2);  // root = 2
        reg_write(32'h0C, 32'd3);  // node_count = 3

        $display("");
        $display("=== Starting execution ===");
        reg_write(32'h00, 32'd1);  // start

        // Wait for completion
        for (int i = 0; i < 80; i++) @(posedge clk);

        $display("");
        $display("=== Results ===");

        if (sched.node_result[2] == 32'd5) begin
            $display("  Node 2 (ADD) = %0d: PASS", sched.node_result[2]);
        end else begin
            fail_count++;
        end

        // Test 2: MUL 3 × 4 = 12
        $display("");
        $display("=== Loading graph: (* 3 4) ===");

        // Reset everything
        reset_n = 0;
        #15 reset_n = 1;
        @(posedge clk);
        reg_write(32'h00, 32'd0);
        @(posedge clk);

        // Node 0: LIT_INT 3, dep_mask=bit2
        node_write(0, 0, encode_header(2'b00, 8'h01, 6'd0, 6'd0, 10'd0));
        node_write(0, 1, 32'd3);
        node_write(0, 4, 32'h00000004);
        // Node 1: LIT_INT 4, dep_mask=bit2
        node_write(1, 0, encode_header(2'b00, 8'h01, 6'd0, 6'd0, 10'd0));
        node_write(1, 1, 32'd4);
        node_write(1, 4, 32'h00000004);
        // Node 2: MUL (0x12), num_inputs=2
        node_write(2, 0, encode_header(2'b00, 8'h12, 6'd2, 6'd0, 10'd0));
        node_write(2, 4, 32'd0);
        node_write(2, 5, 32'h00000001);

        reg_write(32'h08, 32'd2);  // root = 2
        reg_write(32'h0C, 32'd3);  // node_count = 3
        reg_write(32'h00, 32'd1);  // start

        for (int i = 0; i < 80; i++) @(posedge clk);

        if (sched.node_result[2] == 32'd12) begin
            $display("  Node 2 (MUL) = %0d: PASS", sched.node_result[2]);
        end else begin
            fail_count++;
        end

        // Test 3: LT comparison (3 < 5)
        $display("");
        $display("=== Loading graph: (< 3 5) ===");

        // Reset again
        reset_n = 0;
        #15 reset_n = 1;
        @(posedge clk);
        reg_write(32'h00, 32'd0);
        @(posedge clk);

        node_write(0, 0, encode_header(2'b00, 8'h01, 6'd0, 6'd0, 10'd0));
        node_write(0, 1, 32'd3);
        node_write(0, 4, 32'h00000004);
        node_write(1, 0, encode_header(2'b00, 8'h01, 6'd0, 6'd0, 10'd0));
        node_write(1, 1, 32'd5);
        node_write(1, 4, 32'h00000004);
        node_write(2, 0, encode_header(2'b00, 8'h16, 6'd2, 6'd0, 10'd0)); // LT
        node_write(2, 4, 32'd0);
        node_write(2, 5, 32'h00000001);

        reg_write(32'h08, 32'd2);
        reg_write(32'h0C, 32'd3);
        reg_write(32'h00, 32'd1);

        for (int i = 0; i < 80; i++) @(posedge clk);

        if (sched.node_result[2] == 32'd1) begin
            $display("  Node 2 (LT) = true (1): PASS");
        end else begin
            fail_count++;
        end

        $display("");
        if (fail_count == 0) begin $display("PASS: tb_primitive_exec"); $finish(0); end else begin $display("FAIL: tb_primitive_exec (%0d failures)", fail_count); $finish(1); end
    end

endmodule
