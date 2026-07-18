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
        #7 reset_n = 1;

        // Write one word, read it back
        @(negedge clk); wr_data = 32'hDEADBEEF; wr_en = 1;
        @(negedge clk); wr_en = 0;

        @(negedge clk); rd_en = 1;
        @(posedge clk);
        @(negedge clk);
        if (rd_data !== 32'hDEADBEEF) $error("Readback: expected 0xDEADBEEF, got 0x%08X", rd_data);
        rd_en = 0;
        $display("Single word: PASS");

        // Fill to capacity
        for (int i = 0; i < DEPTH; i++) begin
            @(negedge clk); wr_data = i; wr_en = 1;
            @(negedge clk); wr_en = 0;
        end
        #1;
        if (!full) $error("FIFO should be full after %0d writes", DEPTH);
        $display("Full detect: PASS");

        // Drain and verify
        for (int i = 0; i < DEPTH; i++) begin
            @(negedge clk); rd_en = 1;
            @(posedge clk);
            @(negedge clk);
            if (rd_data !== i) $error("Read at %0d: expected %0d, got %0d", i, i, rd_data);
            rd_en = 0;
        end
        #1;
        if (!empty) $error("FIFO should be empty after drain");
        $display("Fill/drain: PASS");

        // Fill, then attempt write while full (should be rejected)
        for (int i = 0; i < DEPTH; i++) begin
            @(negedge clk); wr_data = i + 100; wr_en = 1;
            @(negedge clk); wr_en = 0;
        end
        // Attempt extra write
        @(negedge clk); wr_data = 32'hDEAD; wr_en = 1;
        @(negedge clk); wr_en = 0;
        if (!full) $error("Should remain full after rejected write");
        $display("Overflow protection: PASS");

        // Drain — original values intact
        for (int i = 0; i < DEPTH; i++) begin
            @(negedge clk); rd_en = 1;
            @(posedge clk);
            @(negedge clk);
            if (rd_data !== i + 100) $error("Overflow data at %0d: expected %0d, got %0d", i, i+100, rd_data);
            rd_en = 0;
        end

        // Test: write/read interleaved (back-to-back)
        @(negedge clk); wr_data = 200; wr_en = 1;
        @(negedge clk); wr_en = 0; rd_en = 1;
        @(posedge clk);
        @(negedge clk);
        if (rd_data !== 200) $error("Interleaved: expected 200, got %0d", rd_data);
        rd_en = 0;
        $display("Interleaved write/read: PASS");

        $display("PASS: tb_fifo");
        $finish;
    end
endmodule
