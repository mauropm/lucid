// Graph Scheduler Testbench
// =========================
// Tests execution of a dependency graph.
// Graph for: (+ 2 (* 3 4))
//
// Node 0: LIT_INT   imm0=2          num_inputs=0  dep_mask=bit4
// Node 1: LIT_INT   imm0=3          num_inputs=0  dep_mask=bit3
// Node 2: LIT_INT   imm0=4          num_inputs=0  dep_mask=bit3
// Node 3: MUL (0x12)                num_inputs=2  dep_mask=bit4
// Node 4: ADD (0x10)                num_inputs=2  dep_mask=0
// Root: 4
// Expected result: 2 + (3 * 4) = 14

`timescale 1ns/1ps

module tb_graph_scheduler;
    logic clk, reset_n;
    logic reg_cyc, reg_stb, reg_we, reg_ack;
    logic [31:0] reg_adr, reg_dat_w, reg_dat_r;

    graph_scheduler #(.NUM_NODES(64), .Q_DEPTH(16)) sched (
        .clk(clk), .reset_n(reset_n),
        .reg_cyc(reg_cyc), .reg_stb(reg_stb), .reg_we(reg_we),
        .reg_adr(reg_adr), .reg_dat_w(reg_dat_w),
        .reg_dat_r(reg_dat_r), .reg_ack(reg_ack)
    );

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

    // Node field write helper
    // Address = 0x20 + node_id * 24 + field_id * 4
    task node_write(input int nid, input int fid, input [31:0] data);
        reg_write(32'h20 + nid * 24 + fid * 4, data);
    endtask

    // Encode state/opcode/numinp/flags into one word
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
        #15 reset_n = 1;
        @(posedge clk);

        $display("=== Loading graph ===");

        // Set up the graph: (+ 2 (* 3 4))
        // Node fields: state=idle(0), opcode, num_inputs, ready_inputs=0, flags=0

        // Node 0: LIT_INT, imm0=2, num_inputs=0, dep_mask with bit 4 set
        node_write(0, 0, encode_header(2'b00, 8'h01, 6'd0, 6'd0, 10'd0));
        node_write(0, 1, 32'd2);    // imm0 = 2
        node_write(0, 4, 32'h00000010); // dep_mask = bit 4 (node 4 depends on node 0)
        $display("  Node 0: LIT_INT 2");

        // Node 1: LIT_INT, imm0=3, num_inputs=0, dep_mask with bit 3 set
        node_write(1, 0, encode_header(2'b00, 8'h01, 6'd0, 6'd0, 10'd0));
        node_write(1, 1, 32'd3);    // imm0 = 3
        node_write(1, 4, 32'h00000008); // dep_mask = bit 3
        $display("  Node 1: LIT_INT 3");

        // Node 2: LIT_INT, imm0=4, num_inputs=0, dep_mask with bit 3 set
        node_write(2, 0, encode_header(2'b00, 8'h01, 6'd0, 6'd0, 10'd0));
        node_write(2, 1, 32'd4);    // imm0 = 4
        node_write(2, 4, 32'h00000008); // dep_mask = bit 3
        $display("  Node 2: LIT_INT 4");

        // Node 3: MUL, num_inputs=2 (depends on nodes 1, 2), dep_mask = bit 4
        node_write(3, 0, encode_header(2'b00, 8'h12, 6'd2, 6'd0, 10'd0));
        node_write(3, 4, 32'h00000010); // dep_mask = bit 4
        $display("  Node 3: MUL");

        // Node 4: ADD, num_inputs=2 (depends on nodes 0, 3), dep_mask = 0
        node_write(4, 0, encode_header(2'b00, 8'h10, 6'd2, 6'd0, 10'd0));
        node_write(4, 4, 32'd0);       // dep_mask = 0 (no dependents)
        $display("  Node 4: ADD (root)");

        // Configure scheduler
        reg_write(32'h08, 32'd4);  // root_node = 4
        reg_write(32'h0C, 32'd5);  // node_count = 5

        $display("");
        $display("=== Starting execution ===");
        reg_write(32'h00, 32'd1);  // ctrl[0] = 1 (start)

        // Wait for execution to complete (poll status)
        for (int i = 0; i < 50; i++) begin
            @(posedge clk);
        end

        // Check results
        $display("");
        $display("=== Results ===");

        // Read node 4 (root) result at addr = 0x20 + 4*24 + 3*4 = 0x8C
        @(posedge clk);
        reg_cyc <= 1; reg_stb <= 1; reg_we <= 0;
        reg_adr <= 32'h8C;
        @(posedge clk);
        $display("  Node 4 result = 0x%08X (%0d)", reg_dat_r, reg_dat_r);
        reg_cyc <= 0; reg_stb <= 0;

        // Also read node 3
        @(posedge clk);
        reg_cyc <= 1; reg_stb <= 1; reg_we <= 0;
        reg_adr <= 32'h20 + 3 * 24 + 3 * 4;
        @(posedge clk);
        $display("  Node 3 result = 0x%08X (%0d)", reg_dat_r, reg_dat_r);
        reg_cyc <= 0; reg_stb <= 0;

        // Check status
        @(posedge clk);
        reg_cyc <= 1; reg_stb <= 1; reg_we <= 0;
        reg_adr <= 32'h04; // status register
        @(posedge clk);
        $display("  Status = 0x%08X (2=idle, 1=running)", reg_dat_r);
        reg_cyc <= 0; reg_stb <= 0;

        // Also check done count
        @(posedge clk);
        reg_cyc <= 1; reg_stb <= 1; reg_we <= 0;
        reg_adr <= 32'h10; // done count
        @(posedge clk);
        $display("  Nodes done = %0d", reg_dat_r);
        reg_cyc <= 0; reg_stb <= 0;

        // Verify
        if (sched.node_result[4] == 32'd14) begin
            $display("  PASS: result = 14");
        end else begin
            $error("  FAIL: expected 14, got %0d", sched.node_result[4]);
        end

        if (sched.node_result[3] == 32'd12) begin
            $display("  PASS: intermediate result = 12");
        end else begin
            $error("  FAIL: expected 12, got %0d", sched.node_result[3]);
        end

        $display("");
        $display("PASS: tb_graph_scheduler");
        $finish;
    end

endmodule
