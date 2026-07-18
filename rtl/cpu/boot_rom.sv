// Boot ROM
// =========
// 4 KB initialized ROM mapped at 0x00000000.
// Wishbone B4 slave. 1-cycle read latency.
// Contents initialized from hex file in simulation.

module boot_rom (
    input  logic        clk,
    input  logic        reset_n,

    // Wishbone slave
    input  logic        wb_cyc,
    input  logic        wb_stb,
    input  logic        wb_we,
    input  logic [31:0] wb_adr,
    input  logic [31:0] wb_dat_w,
    input  logic [3:0]  wb_sel,
    output logic [31:0] wb_dat_r,
    output logic        wb_ack
);

    // 4 KB = 1024 × 32-bit words
    localparam int ADDR_WIDTH = 10;

    logic [ADDR_WIDTH-1:0] rom_addr;

    // Word-aligned address within ROM range
    assign rom_addr = wb_adr[ADDR_WIDTH+1:2];

    bram #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(32)
    ) rom (
        .clk(clk),
        .en(wb_cyc && wb_stb),
        .we(1'b0), // read-only
        .addr(rom_addr),
        .din('0),
        .dout(wb_dat_r)
    );

    // 1-cycle read latency (registered)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wb_ack <= 1'b0;
        end else begin
            wb_ack <= wb_cyc && wb_stb;
        end
    end

endmodule
