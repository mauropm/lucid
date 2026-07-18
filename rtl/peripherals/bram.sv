`default_nettype none

module bram #(
    parameter int ADDR_WIDTH = 10,
    parameter int DATA_WIDTH = 32,
    parameter string HEX_FILE = ""
) (
    input  logic                    clk,
    input  logic                    en,
    input  logic                    we,
    input  logic [ADDR_WIDTH-1:0]   addr,
    input  logic [DATA_WIDTH-1:0]   din,
    input  logic [DATA_WIDTH/8-1:0] sel,
    output logic [DATA_WIDTH-1:0]   dout
);

    localparam int DEPTH = 2 ** ADDR_WIDTH;
    localparam int NUM_BYTES = DATA_WIDTH / 8;

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        if (HEX_FILE != "") begin
            $readmemh(HEX_FILE, mem);
        end
    end

    always_ff @(posedge clk) begin
        if (en) begin
            if (we) begin
                for (int b = 0; b < NUM_BYTES; b++) begin
                    if (sel[b])
                        mem[addr][b*8 +: 8] <= din[b*8 +: 8];
                end
            end
            dout <= mem[addr];
        end
    end

endmodule

`default_nettype wire
