// Platform Integration Testbench
// ==============================
`timescale 1ns/1ps

module tb_platform;
    logic clk, reset_n;

    // Wishbone master (from CPU)
    logic        wb_cyc, wb_stb, wb_we;
    logic [31:0] wb_adr, wb_dat_o, wb_dat_i;
    logic [3:0]  wb_sel;
    logic        wb_ack;

    // UART serial
    logic uart_tx;

    // CPU
    rv32im_core cpu (
        .clk(clk),
        .reset_n(reset_n),
        .wb_cyc(wb_cyc),
        .wb_stb(wb_stb),
        .wb_we(wb_we),
        .wb_adr(wb_adr),
        .wb_dat_o(wb_dat_o),
        .wb_sel(wb_sel),
        .wb_dat_i(wb_dat_i),
        .wb_ack(wb_ack)
    );

    // Bus slave signals
    logic        s0_cyc, s0_stb, s0_ack;
    logic [31:0] s0_adr, s0_dat_r;
    logic        s1_cyc, s1_stb, s1_we, s1_ack;
    logic [31:0] s1_adr, s1_dat_w, s1_dat_r;
    logic [3:0]  s1_sel;
    logic        s2_cyc, s2_stb, s2_we, s2_ack;
    logic [31:0] s2_adr, s2_dat_w, s2_dat_r;
    logic [3:0]  s2_sel;

    // Wishbone bus
    wishbone_bus bus (
        .m_cyc(wb_cyc),
        .m_stb(wb_stb),
        .m_we(wb_we),
        .m_adr(wb_adr),
        .m_dat_w(wb_dat_o),
        .m_sel(wb_sel),
        .m_dat_r(wb_dat_i),
        .m_ack(wb_ack),
        .s0_cyc(s0_cyc),
        .s0_stb(s0_stb),
        .s0_adr(s0_adr),
        .s0_dat_r(s0_dat_r),
        .s0_ack(s0_ack),
        .s1_cyc(s1_cyc),
        .s1_stb(s1_stb),
        .s1_we(s1_we),
        .s1_adr(s1_adr),
        .s1_dat_w(s1_dat_w),
        .s1_sel(s1_sel),
        .s1_dat_r(s1_dat_r),
        .s1_ack(s1_ack),
        .s2_cyc(s2_cyc),
        .s2_stb(s2_stb),
        .s2_we(s2_we),
        .s2_adr(s2_adr),
        .s2_dat_w(s2_dat_w),
        .s2_sel(s2_sel),
        .s2_dat_r(s2_dat_r),
        .s2_ack(s2_ack)
    );

    // Boot ROM
    boot_rom rom (
        .clk(clk),
        .reset_n(reset_n),
        .wb_cyc(s0_cyc),
        .wb_stb(s0_stb),
        .wb_adr(s0_adr),
        .wb_dat_r(s0_dat_r),
        .wb_ack(s0_ack),
        .wb_we(1'b0),
        .wb_dat_w(32'h0),
        .wb_sel(4'h0)
    );

    // Management RAM
    mgmt_ram ram (
        .clk(clk),
        .reset_n(reset_n),
        .wb_cyc(s1_cyc),
        .wb_stb(s1_stb),
        .wb_we(s1_we),
        .wb_adr(s1_adr),
        .wb_dat_w(s1_dat_w),
        .wb_sel(s1_sel),
        .wb_dat_r(s1_dat_r),
        .wb_ack(s1_ack)
    );

    // UART
    uart #(.FIFO_DEPTH(8)) uart_inst (
        .clk(clk),
        .reset_n(reset_n),
        .wb_cyc(s2_cyc),
        .wb_stb(s2_stb),
        .wb_we(s2_we),
        .wb_adr(s2_adr),
        .wb_dat_w(s2_dat_w),
        .wb_sel(s2_sel),
        .wb_dat_r(s2_dat_r),
        .wb_ack(s2_ack),
        .rx(1'b1),
        .tx(uart_tx)
    );

    // Clock
    always #5 clk = ~clk;

    int fail_count;

    // Test
    initial begin
        $dumpfile("build/sim/tb_platform.vcd");
        $dumpvars(0, tb_platform);

        clk = 0; reset_n = 0;
        fail_count = 0;
        #15 reset_n = 1;

        // Wait for 12-instruction test program to execute (~50 cycles)
        repeat (70) @(posedge clk);

        // Register checks
        $display("=== Register Check ===");
        if (cpu.regfile[1] !== 32'd42) fail_count++;
        else $display("x1 = 42: PASS");

        if (cpu.regfile[2] !== 32'd43) fail_count++;
        else $display("x2 = 43: PASS");

        if (cpu.regfile[3] !== 32'h00010000) fail_count++;
        else $display("x3 = 0x00010000: PASS");

        if (cpu.regfile[4] !== 32'd42) fail_count++;
        else $display("x4 = 42: PASS");

        if (cpu.regfile[5] !== 32'd100) fail_count++;
        else $display("x5 = 100: PASS");

        if (cpu.regfile[6] !== 32'h00020000) fail_count++;
        else $display("x6 = 0x00020000: PASS");

        if (cpu.regfile[7] !== 32'd1) fail_count++;
        else $display("x7 = 1: PASS");

        // Memory check
        if (ram.ram.mem[0] !== 32'd42) fail_count++;
        else $display("RAM store/load: PASS");

        // UART TX check: the transmitter should be busy sending the byte
        if (!uart_inst.tx_busy) fail_count++;
        else $display("UART TX write: PASS");

        $display("");
        if (fail_count == 0) begin $display("PASS: tb_platform"); $finish(0); end else begin $display("FAIL: tb_platform (%0d failures)", fail_count); $finish(1); end
    end

endmodule
