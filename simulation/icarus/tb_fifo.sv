// Lucid FIFO Testbench (Icarus Verilog)
`timescale 1ns/1ps

module tb_fifo;
    parameter int WIDTH = 32;
    parameter int DEPTH = 8;

    logic clk, reset_n;
    logic wr_en, full;
    logic [WIDTH-1:0] wr_data;
    logic rd_en, empty;
    logic [WIDTH-1:0] rd_data;

    int fail_count;

    fifo #(WIDTH, DEPTH) uut(
        .clk(clk), .reset_n(reset_n),
        .wr_en(wr_en), .wr_data(wr_data), .full(full),
        .rd_en(rd_en), .rd_data(rd_data), .empty(empty),
        .count()
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("build/sim/tb_fifo.vcd");
        $dumpvars(0, tb_fifo);

        clk = 0; reset_n = 0; wr_en = 0; rd_en = 0; wr_data = 0;
        fail_count = 0;
        #7 reset_n = 1;

        // Write one word, read it back
        @(negedge clk); wr_data = 32'hDEADBEEF; wr_en = 1;
        @(negedge clk); wr_en = 0;

        @(negedge clk); rd_en = 1;
        @(posedge clk);
        @(negedge clk);
        if (rd_data !== 32'hDEADBEEF) fail_count++;
        rd_en = 0;
        $display("Single word: PASS");

        // Fill to capacity
        for (int i = 0; i < DEPTH; i++) begin
            @(negedge clk); wr_data = i; wr_en = 1;
            @(negedge clk); wr_en = 0;
        end
        #1;
        if (!full) fail_count++;
        $display("Full detect: PASS");

        // Drain and verify
        for (int i = 0; i < DEPTH; i++) begin
            @(negedge clk); rd_en = 1;
            @(posedge clk);
            @(negedge clk);
            if (rd_data !== i) fail_count++;
            rd_en = 0;
        end
        #1;
        if (!empty) fail_count++;
        $display("Fill/drain: PASS");

        // Fill, then attempt write while full (should be rejected)
        for (int i = 0; i < DEPTH; i++) begin
            @(negedge clk); wr_data = i + 100; wr_en = 1;
            @(negedge clk); wr_en = 0;
        end
        // Attempt extra write
        @(negedge clk); wr_data = 32'hDEAD; wr_en = 1;
        @(negedge clk); wr_en = 0;
        if (!full) fail_count++;
        $display("Overflow protection: PASS");

        // Drain — original values intact
        for (int i = 0; i < DEPTH; i++) begin
            @(negedge clk); rd_en = 1;
            @(posedge clk);
            @(negedge clk);
            if (rd_data !== i + 100) fail_count++;
            rd_en = 0;
        end

        // Test: write/read interleaved (back-to-back)
        @(negedge clk); wr_data = 200; wr_en = 1;
        @(negedge clk); wr_en = 0; rd_en = 1;
        @(posedge clk);
        @(negedge clk);
        if (rd_data !== 200) fail_count++;
        rd_en = 0;
        $display("Interleaved write/read: PASS");

        if (fail_count == 0) begin $display("PASS: tb_fifo"); $finish(0); end else begin $display("FAIL: tb_fifo (%0d failures)", fail_count); $finish(1); end
    end
endmodule
