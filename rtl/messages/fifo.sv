// Lucid FIFO Module
// =================
// Standard FIFO used for message passing between FPU modules.
//
// Inputs:
//   clk          (1)    Clock
//   reset_n      (1)    Active-low reset
//   wr_en        (1)    Write enable
//   wr_data      (WIDTH) Write data
//   rd_en        (1)    Read enable
//
// Outputs:
//   full         (1)    FIFO is full
//   empty        (1)    FIFO is empty
//   rd_data      (WIDTH) Read data
//   count        (log2(DEPTH)) Number of entries
//
// Parameters:
//   WIDTH        (32)   Data width in bits
//   DEPTH        (8)    Number of entries
//
// Protocol:
//   Standard ready/valid handshake.
//   wr_en && !full  → data written
//   rd_en && !empty → data read

module fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 8
) (
    input  logic              clk,
    input  logic              reset_n,

    input  logic              wr_en,
    input  logic [WIDTH-1:0]  wr_data,
    output logic              full,

    input  logic              rd_en,
    output logic [WIDTH-1:0]  rd_data,
    output logic              empty,

    output logic [$clog2(DEPTH):0] count
);

    localparam int CNT_WIDTH = $clog2(DEPTH) + 1;

    logic [WIDTH-1:0] mem [DEPTH];
    logic [CNT_WIDTH-1:0] wr_ptr, rd_ptr;
    logic [WIDTH-1:0] rd_data_q;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            rd_data_q <= '0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr[$clog2(DEPTH)-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (rd_en && !empty) begin
                rd_data_q <= mem[rd_ptr[$clog2(DEPTH)-1:0]];
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

    assign rd_data = rd_data_q;
    assign count   = wr_ptr - rd_ptr;
    assign empty   = (wr_ptr == rd_ptr);
    assign full    = (wr_ptr[CNT_WIDTH-2:0] == rd_ptr[CNT_WIDTH-2:0]) &&
                     (wr_ptr[CNT_WIDTH-1]   != rd_ptr[CNT_WIDTH-1]);

endmodule
