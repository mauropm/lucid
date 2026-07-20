`default_nettype none

// BRAM primitive.
// NOTE (T2): Gowin synthesis does not accept a `string` parameter for the
// initialization file, so no HEX_FILE parameter exists. Initialization is
// performed in simulation only (guarded by `ifndef SYNTHESIS`) using the file
// provided by the BOOT_ROM_HEX macro. Hardware synthesis relies on the vendor
// IP / bitstream ROM contents instead.
module bram #(
    parameter int ADDR_WIDTH = 10,
    parameter int DATA_WIDTH = 32
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

`ifndef SYNTHESIS
  `ifdef BOOT_ROM_HEX
    initial begin
        $readmemh(`BOOT_ROM_HEX, mem);
    end
  `endif
`endif

    // Canonical BRAM: register the read address so the read data is decoupled
    // from the live `addr` net. This is both the recommended inference pattern
    // and avoids simulator-specific event-scheduling issues when `en` is held.
    logic [ADDR_WIDTH-1:0] rd_addr;
    always_ff @(posedge clk) begin
        if (en) rd_addr <= addr;
    end

    always_ff @(posedge clk) begin
        if (en && we) begin
            for (int b = 0; b < NUM_BYTES; b++) begin
                if (sel[b])
                    mem[addr][b*8 +: 8] <= din[b*8 +: 8];
            end
        end
        if (en) dout <= mem[rd_addr];
    end

endmodule

`default_nettype wire
