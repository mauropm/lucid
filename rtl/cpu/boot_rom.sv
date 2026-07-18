`default_nettype none

module boot_rom (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        wb_cyc,
    input  logic        wb_stb,
    input  logic        wb_we,
    input  logic [31:0] wb_adr,
    input  logic [31:0] wb_dat_w,
    input  logic [3:0]  wb_sel,
    output logic [31:0] wb_dat_r,
    output logic        wb_ack
);

    localparam int ADDR_WIDTH = 10;
    logic [ADDR_WIDTH-1:0] rom_addr;

    assign rom_addr = wb_adr[ADDR_WIDTH+1:2];

    bram #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(32),
        .HEX_FILE("boot_rom.hex")
    ) rom (
        .clk(clk),
        .en(wb_cyc && wb_stb),
        .we(1'b0),
        .addr(rom_addr),
        .din('0),
        .sel(4'h0),
        .dout(wb_dat_r)
    );

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            wb_ack <= 1'b0;
        else
            wb_ack <= wb_cyc && wb_stb;
    end

endmodule

`default_nettype wire
