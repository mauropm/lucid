`default_nettype none

module mgmt_ram (
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
    logic [ADDR_WIDTH-1:0] ram_addr;

    assign ram_addr = wb_adr[ADDR_WIDTH+1:2];

    bram #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(32)
    ) ram (
        .clk(clk),
        .en(wb_cyc && wb_stb),
        .we(wb_we),
        .addr(ram_addr),
        .din(wb_dat_w),
        .sel(wb_sel),
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
