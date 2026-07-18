// Message System Testbench
// ========================
`timescale 1ns/1ps

module tb_message_system;
    parameter int NUM_MODULES = 4;

    logic clk, reset_n;
    logic [NUM_MODULES-1:0] tx_valid, tx_last, tx_ready;
    logic [NUM_MODULES*32-1:0] tx_data;
    logic [NUM_MODULES-1:0] rx_valid, rx_last, rx_ready;
    logic [NUM_MODULES*32-1:0] rx_data;

    logic wb_cyc, wb_stb, wb_we, wb_ack;
    logic [31:0] wb_adr, wb_dat_w, wb_dat_r;

    message_dispatcher #(
        .NUM_MODULES(NUM_MODULES),
        .ROUTER_INPUTS(NUM_MODULES),
        .ROUTER_OUTPUTS(8)
    ) disp (
        .clk(clk), .reset_n(reset_n),
        .wb_cyc(1'b0), .wb_stb(1'b0), .wb_we(1'b0),
        .wb_adr('0), .wb_dat_w('0), .wb_sel(4'h0),
        .wb_dat_r(), .wb_ack(),
        .tx_valid(tx_valid), .tx_last(tx_last),
        .tx_data(tx_data), .tx_ready(tx_ready),
        .rx_valid(rx_valid), .rx_last(rx_last),
        .rx_data(rx_data), .rx_ready(rx_ready)
    );

    always #5 clk = ~clk;

    logic [31:0] hdr;
    int fail_count;

    task automatic send_single(input int src, input logic [7:0] dest,
                               input logic [7:0] msg_type, input logic [31:0] payload);
        logic [31:0] header = {dest, 8'(src), msg_type, 8'h00};
        // Wait for tx_ready
        while (!tx_ready[src]) @(posedge clk);
        // Present data
        tx_valid[src] <= 1; tx_data[src*32 +: 32] <= header; tx_last[src] <= 1;
        @(posedge clk);
        // Hold until accepted
        while (!tx_ready[src]) @(posedge clk);
        tx_valid[src] <= 0;
        @(posedge clk);
    endtask

    task automatic expect_single(input int mod, output logic [31:0] head);
        // Wait for data to arrive
        while (!rx_valid[mod]) @(posedge clk);
        // Read data
        head = rx_data[mod*32 +: 32];
        // Acknowledge: set rx_ready for one cycle
        rx_ready[mod] <= 1;
        @(posedge clk);
        rx_ready[mod] <= 0;
        @(posedge clk);
    endtask

    initial begin
        $dumpfile("build/sim/tb_message_system.vcd");
        $dumpvars(0, tb_message_system);

        clk = 0; reset_n = 0;
        for (int i = 0; i < NUM_MODULES; i++) begin
            tx_valid[i] = 0; tx_last[i] = 0;
            tx_data[i*32 +: 32] = 0; rx_ready[i] = 0;
        end
        fail_count = 0;
        #15 reset_n = 1;
        @(posedge clk);

        // Test 1: Module 0 → Module 1
        $display("=== Test 1: 0→1 ===");
        send_single(0, 8'd1, MSG_NOP, 32'hCAFEBABE);
        expect_single(1, hdr);
        if (get_dest(hdr) != 8'd1) fail_count++;
        if (get_src(hdr) != 8'd0) fail_count++;
        if (get_type(hdr) != MSG_NOP) fail_count++;
        $display("  PASS: header=0x%08X", hdr);

        // Test 2: Module 1 → Module 2
        $display("=== Test 2: 1→2 ===");
        send_single(1, 8'd2, MSG_ALLOC, 32'h00000040);
        expect_single(2, hdr);
        if (get_dest(hdr) != 8'd2) fail_count++;
        if (get_src(hdr) != 8'd1) fail_count++;
        if (get_type(hdr) != MSG_ALLOC) fail_count++;
        $display("  PASS: header=0x%08X", hdr);

        // Test 3: Module 3 → Module 0 (wrap-around)
        $display("=== Test 3: 3→0 ===");
        send_single(3, 8'd0, MSG_EXEC_PRIM, 32'h12345678);
        expect_single(0, hdr);
        if (get_src(hdr) != 8'd3) fail_count++;
        if (get_dest(hdr) != 8'd0) fail_count++;
        $display("  PASS: header=0x%08X", hdr);

        // Test 4: Sequential send/receive same path 0→1
        $display("=== Test 4: Sequential 0→1 ===");
        send_single(0, 8'd1, MSG_NOP, 32'h10000000);
        expect_single(1, hdr);
        if (get_src(hdr) != 0) fail_count++;
        send_single(0, 8'd1, MSG_NOP, 32'h20000000);
        expect_single(1, hdr);
        if (get_src(hdr) != 0) fail_count++;
        $display("  PASS: two messages");

        // Test 5: Cross traffic 0→1 and 2→3
        $display("=== Test 5: Cross traffic ===");
        send_single(0, 8'd1, MSG_EXEC_PRIM, 32'hA0000000);
        expect_single(1, hdr);
        send_single(2, 8'd3, MSG_EXEC_PRIM, 32'hB0000000);
        expect_single(3, hdr);
        $display("  PASS");

        $display("");
        if (fail_count == 0) begin $display("PASS: tb_message_system"); $finish(0); end else begin $display("FAIL: tb_message_system (%0d failures)", fail_count); $finish(1); end
    end

endmodule
