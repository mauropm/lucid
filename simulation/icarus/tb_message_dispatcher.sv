// Lucid Message Dispatcher Testbench (Icarus Verilog)
`timescale 1ns/1ps

module tb_message_dispatcher;
    parameter int NUM_UNITS = 4;

    logic clk, reset_n;
    logic [31:0] msg_in_data;
    logic msg_in_valid, msg_in_ready;

    logic [31:0] msg_out_data [NUM_UNITS];
    logic msg_out_valid [NUM_UNITS];
    logic msg_out_ready [NUM_UNITS];

    message_dispatcher #(
        .NUM_UNITS(NUM_UNITS)
    ) uut (
        .clk(clk),
        .reset_n(reset_n),
        .msg_in_data(msg_in_data),
        .msg_in_valid(msg_in_valid),
        .msg_in_ready(msg_in_ready),
        .msg_out_data(msg_out_data),
        .msg_out_valid(msg_out_valid),
        .msg_out_ready(msg_out_ready)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("build/sim/tb_message_dispatcher.vcd");
        $dumpvars(0, tb_message_dispatcher);

        clk = 0;
        reset_n = 0;
        msg_in_data = 0;
        msg_in_valid = 0;
        for (int i = 0; i < NUM_UNITS; i++) msg_out_ready[i] = 1;

        #10 reset_n = 1;

        // Test: Send message to unit 0
        #10;
        msg_in_data = 32'h00_00_0001;  // TYPE=0x00 (unit 0), TAG=0x0001
        msg_in_valid = 1;
        #10 msg_in_valid = 0;

        assert(msg_out_valid[0]) else $error("Unit 0 should receive message");
        assert(!msg_out_valid[1]) else $error("Unit 1 should not receive message");

        // Test: Send message to unit 2
        #10;
        msg_in_data = 32'h20_00_0002;  // TYPE=0x20 (unit 2), TAG=0x0002
        msg_in_valid = 1;
        #10 msg_in_valid = 0;

        assert(msg_out_valid[2]) else $error("Unit 2 should receive message");
        assert(!msg_out_valid[0]) else $error("Unit 0 should not receive message");

        // Test: Broadcast
        #10;
        msg_in_data = 32'h00_08_0003;  // TYPE=0x00, FLAGS=0x08 (BROADCAST), TAG=0x0003
        msg_in_valid = 1;
        #10 msg_in_valid = 0;

        for (int i = 0; i < NUM_UNITS; i++) begin
            assert(msg_out_valid[i]) else $error("Unit %0d should receive broadcast", i);
        end

        $display("PASS: tb_message_dispatcher");
        $finish;
    end
endmodule
