// Message Dispatcher Testbench
`timescale 1ns/1ps

module tb_message_dispatcher;
    parameter int NUM_MODULES = 4;

    logic clk, reset_n;

    // Wishbone (program routing table — not tested here)
    logic wb_cyc, wb_stb, wb_we, wb_ack;
    logic [31:0] wb_adr, wb_dat_w, wb_dat_r;

    // Module TX/RX
    logic [NUM_MODULES-1:0] tx_valid, tx_last, tx_ready;
    logic [NUM_MODULES*32-1:0] tx_data;
    logic [NUM_MODULES-1:0] rx_valid, rx_last, rx_ready;
    logic [NUM_MODULES*32-1:0] rx_data;

    int fail_count;

    message_dispatcher #(
        .NUM_MODULES(NUM_MODULES),
        .ROUTER_INPUTS(NUM_MODULES),
        .ROUTER_OUTPUTS(8)
    ) uut (
        .clk(clk), .reset_n(reset_n),
        .wb_cyc(wb_cyc), .wb_stb(wb_stb), .wb_we(wb_we),
        .wb_adr(wb_adr), .wb_dat_w(wb_dat_w), .wb_sel(4'h0),
        .wb_dat_r(wb_dat_r), .wb_ack(wb_ack),
        .tx_valid(tx_valid), .tx_last(tx_last),
        .tx_data(tx_data), .tx_ready(tx_ready),
        .rx_valid(rx_valid), .rx_last(rx_last),
        .rx_data(rx_data), .rx_ready(rx_ready)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("build/sim/tb_message_dispatcher.vcd");
        $dumpvars(0, tb_message_dispatcher);

        clk = 0; reset_n = 0;
        for (int i = 0; i < NUM_MODULES; i++) begin
            tx_valid[i] = 0; tx_last[i] = 0;
            tx_data[i*32 +: 32] = 0; rx_ready[i] = 0;
        end
        fail_count = 0;
        #10 reset_n = 1;
        @(posedge clk);

        // Test: Send from module 0 to module 1
        @(posedge clk);
        tx_valid[0] <= 1;
        tx_data[0*32 +: 32] <= {8'd1, 8'd0, 8'h03, 8'h00}; // dest=1, src=0, type=ACK
        tx_last[0] <= 1;
        @(posedge clk);
        while (!tx_ready[0]) @(posedge clk);
        tx_valid[0] <= 0;
        @(posedge clk);

        // Module 1 should receive
        @(posedge clk);
        @(posedge clk);
        if (rx_valid[1]) begin
            $display("Module 1 received: header=0x%08X", rx_data[1*32 +: 32]);
            rx_ready[1] <= 1;
            @(posedge clk);
            rx_ready[1] <= 0;
        end else begin
            fail_count++;
        end

        // Test: Send from module 2 to module 0
        @(posedge clk);
        tx_valid[2] <= 1;
        tx_data[2*32 +: 32] <= {8'd0, 8'd2, 8'h05, 8'h00}; // dest=0, src=2, type=STATUS_REQ
        tx_last[2] <= 1;
        @(posedge clk);
        while (!tx_ready[2]) @(posedge clk);
        tx_valid[2] <= 0;
        @(posedge clk);

        @(posedge clk);
        if (rx_valid[0]) begin
            $display("Module 0 received: header=0x%08X", rx_data[0*32 +: 32]);
            rx_ready[0] <= 1;
            @(posedge clk);
            rx_ready[0] <= 0;
        end else begin
            fail_count++;
        end

        if (fail_count == 0) begin $display("PASS: tb_message_dispatcher"); $finish(0); end else begin $display("FAIL: tb_message_dispatcher (%0d failures)", fail_count); $finish(1); end
    end
endmodule
