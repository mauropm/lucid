// Lucid Top-Level for Tang Nano 20K
// ==================================
// Integrates all subsystems: RV32IM CPU, Wishbone bus, UART, memories,
// graph scheduler, and FPU control. Targets GW2AR-18 FPGA at 100 MHz.

module lucid_top (
    // 27 MHz external clock
    input  logic        clk_27m,

    // UART
    input  logic        uart_rx,
    output logic        uart_tx,

    // Reset button (active low)
    input  logic        btn_rst_n,

    // LEDs (optional)
    output logic [2:0]  led
);

    // ============================================================
    // Clock generation
    // ============================================================
    // For simulation, bypass the PLL. For synthesis, instantiate
    // Gowin PLL primitive: clk_27m → 100 MHz

`ifdef SYNTHESIS
    // Gowin PLL primitive (rPLL)
    logic pll_lock;
    logic clk_100m;

    rPLL pll_inst (
        .clkout(clk_100m),
        .lock(pll_lock),
        .clkin(clk_27m)
    );
    defparam pll_inst.FCLKIN = "27";
    defparam pll_inst.DIV_F = "100";
    defparam pll_inst.DIV_Q = "5";
    defparam pll_inst.FILTER = "1";

    logic clk;
    assign clk = clk_100m;
`else
    logic clk;
    assign clk = clk_27m;
`endif

    // ============================================================
    // Reset synchronization
    // ============================================================
    logic reset_n;
    logic [3:0] reset_sync;

    always_ff @(posedge clk) begin
        reset_sync <= {reset_sync[2:0], btn_rst_n};
        reset_n <= reset_sync[2] & reset_sync[3];
    end

    // ============================================================
    // Wishbone bus signals
    // ============================================================
    logic        wb_cyc, wb_stb, wb_we;
    logic [31:0] wb_adr, wb_dat_o, wb_dat_i;
    logic [3:0]  wb_sel;
    logic        wb_ack;

    // Slave 0: Boot ROM
    logic        s0_cyc, s0_stb, s0_ack;
    logic [31:0] s0_adr, s0_dat_r;

    // Slave 1: Management RAM
    logic        s1_cyc, s1_stb, s1_we, s1_ack;
    logic [31:0] s1_adr, s1_dat_w, s1_dat_r;
    logic [3:0]  s1_sel;

    // Slave 2: UART
    logic        s2_cyc, s2_stb, s2_we, s2_ack;
    logic [31:0] s2_adr, s2_dat_w, s2_dat_r;
    logic [3:0]  s2_sel;

    // Slave 3: Debug / FPU Control
    logic        s3_cyc, s3_stb, s3_we, s3_ack;
    logic [31:0] s3_adr, s3_dat_w, s3_dat_r;
    logic [3:0]  s3_sel;

    // ============================================================
    // RV32IM CPU
    // ============================================================
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

    // ============================================================
    // Wishbone Bus
    // ============================================================
    wishbone_bus bus (
        .clk(clk),
        .reset_n(reset_n),
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

    // ============================================================
    // Boot ROM (4 KB)
    // ============================================================
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

    // ============================================================
    // Management RAM (4 KB)
    // ============================================================
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

    // ============================================================
    // UART
    // ============================================================
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
        .rx(uart_rx),
        .tx(uart_tx)
    );

    // ============================================================
    // LEDs
    // ============================================================
    assign led[0] = reset_n;
    assign led[1] = cpu.status[0]; // running
    assign led[2] = 1'b1;

endmodule
