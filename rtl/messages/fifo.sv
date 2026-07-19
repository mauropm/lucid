`default_nettype none

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
    localparam int PTR_WIDTH = $clog2(DEPTH);

    generate
        if (DEPTH != (1 << $clog2(DEPTH))) begin : gen_depth_check
            wire _depth_must_be_power_of_two = 1'b0;
        end
    endgenerate

    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [CNT_WIDTH-1:0] wr_ptr, rd_ptr;
    logic [WIDTH-1:0] rd_data_q;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            rd_data_q <= '0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr[PTR_WIDTH-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (rd_en && !empty) begin
                rd_data_q <= mem[rd_ptr[PTR_WIDTH-1:0]];
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

    assign rd_data = rd_data_q;
    assign count   = wr_ptr - rd_ptr;
    assign empty   = (wr_ptr == rd_ptr);
    assign full    = (wr_ptr[CNT_WIDTH-2:0] == rd_ptr[CNT_WIDTH-2:0]) &&
                     (wr_ptr[CNT_WIDTH-1]   != rd_ptr[CNT_WIDTH-1]);

`ifdef HAVE_SVA
    assert property (@(posedge clk) disable iff (!reset_n)
        !(wr_en && full))
    else $error("FIFO overflow: write while full");

    assert property (@(posedge clk) disable iff (!reset_n)
        !(rd_en && empty))
    else $error("FIFO underflow: read while empty");

    assert property (@(posedge clk) disable iff (!reset_n)
        count <= DEPTH)
    else $error("FIFO count exceeds DEPTH");
`endif

endmodule

`default_nettype wire
