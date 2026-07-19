`default_nettype none

module message_dispatcher #(
    parameter int NUM_MODULES = 4,
    parameter int ROUTER_INPUTS = 4,
    parameter int ROUTER_OUTPUTS = 8
) (
    input  logic               clk,
    input  logic               reset_n,

    input  logic               wb_cyc,
    input  logic               wb_stb,
    input  logic               wb_we,
    input  logic [31:0]        wb_adr,
    input  logic [31:0]        wb_dat_w,
    input  logic [3:0]         wb_sel,
    output logic [31:0]        wb_dat_r,
    output logic               wb_ack,

    input  logic [NUM_MODULES-1:0]   tx_valid,
    input  logic [NUM_MODULES-1:0]   tx_last,
    input  logic [NUM_MODULES*32-1:0] tx_data,
    output logic [NUM_MODULES-1:0]   tx_ready,

    output logic [NUM_MODULES-1:0]   rx_valid,
    output logic [NUM_MODULES-1:0]   rx_last,
    output logic [NUM_MODULES*32-1:0] rx_data,
    input  logic [NUM_MODULES-1:0]   rx_ready
);

    logic [31:0] ctrl;
    logic [31:0] status;

    logic [31:0] msg_count [NUM_MODULES];
    logic [31:0] err_count [NUM_MODULES];

    logic [ROUTER_INPUTS-1:0]  r_in_valid, r_in_last, r_in_ready;
    logic [ROUTER_INPUTS*32-1:0] r_in_data;
    logic [ROUTER_OUTPUTS-1:0] r_out_valid, r_out_last, r_out_ready;
    logic [ROUTER_OUTPUTS*32-1:0] r_out_data;

    logic any_err;

    message_router #(
        .NUM_INPUTS(ROUTER_INPUTS),
        .NUM_OUTPUTS(ROUTER_OUTPUTS)
    ) router (
        .clk(clk),
        .reset_n(reset_n),
        .in_valid(r_in_valid),
        .in_last(r_in_last),
        .in_data(r_in_data),
        .in_ready(r_in_ready),
        .out_valid(r_out_valid),
        .out_last(r_out_last),
        .out_data(r_out_data),
        .out_ready(r_out_ready)
    );

    genvar i;
    generate
        for (i = 0; i < NUM_MODULES; i++) begin : gen_tx_connect
            assign r_in_valid[i] = tx_valid[i];
            assign r_in_last[i]  = tx_last[i];
            assign r_in_data[i*32 +: 32] = tx_data[i*32 +: 32];
            assign tx_ready[i]   = r_in_ready[i];
        end
    endgenerate

    generate
        for (i = 0; i < NUM_MODULES; i++) begin : gen_rx_connect
            assign rx_valid[i] = r_out_valid[i];
            assign rx_last[i]  = r_out_last[i];
            assign rx_data[i*32 +: 32] = r_out_data[i*32 +: 32];
            assign r_out_ready[i] = rx_ready[i];
        end
    endgenerate

    generate
        for (i = NUM_MODULES; i < ROUTER_OUTPUTS; i++) begin : gen_unused
            assign r_out_ready[i] = 1'b1;
        end
    endgenerate

    always_comb begin
        any_err = 1'b0;
        for (int m = 0; m < NUM_MODULES; m++) begin
            if (|err_count[m]) any_err = 1'b1;
        end
    end

    assign wb_ack = wb_stb && wb_cyc;

    assign status = {24'h0, |r_out_valid, |r_in_valid, any_err, 1'b0};

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ctrl <= '0;
            for (int m = 0; m < NUM_MODULES; m++) begin
                msg_count[m] <= '0;
                err_count[m] <= '0;
            end
        end else begin
            // H8: Count complete messages (on last word transfer)
            for (int m = 0; m < NUM_MODULES; m++) begin
                if (tx_valid[m] && tx_ready[m] && r_in_last[m])
                    msg_count[m] <= msg_count[m] + 1'b1;
            end

            if (wb_we && wb_stb && wb_cyc) begin
                if (wb_adr[7:0] == 8'h00) ctrl <= wb_dat_w;
            end
        end
    end

    always_comb begin
        wb_dat_r = '0;
        case (wb_adr[7:0])
            8'h00: wb_dat_r = ctrl;
            8'h04: wb_dat_r = status;
            default: begin
                if (wb_adr[7:0] >= 8'h10 && wb_adr[7:0] < 8'h10 + NUM_MODULES*4)
                    wb_dat_r = msg_count[(wb_adr[7:0] - 8'h10) >> 2];
                else if (wb_adr[7:0] >= 8'h20 && wb_adr[7:0] < 8'h20 + NUM_MODULES*4)
                    wb_dat_r = err_count[(wb_adr[7:0] - 8'h20) >> 2];
                else
                    wb_dat_r = '0;
            end
        endcase
    end

endmodule

`default_nettype wire
