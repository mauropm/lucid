// Generic Single-Port BRAM
// ========================
// 1-cycle read latency. Initialize from hex file via $readmemh.

module bram #(
    parameter ADDR_WIDTH = 10,  // 2^ADDR_WIDTH words
    parameter DATA_WIDTH = 32
) (
    input  logic                clk,
    input  logic                en,
    input  logic                we,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] din,
    output logic [DATA_WIDTH-1:0] dout
);

    localparam DEPTH = 2 ** ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (en) begin
            if (we) begin
                mem[addr] <= din;
            end
            dout <= mem[addr];
        end
    end

endmodule
