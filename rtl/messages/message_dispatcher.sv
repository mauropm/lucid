// Message Dispatcher
// ==================
// Routes messages between FPU execution units using the message router.
// Maintains a software-programmable routing table.
// Provides status and statistics for each module.
//
// Register interface (Wishbone slave):
//   0x00  MSG_CTRL      R/W   Control register
//   0x04  MSG_STATUS    R     Status register
//   0x08  MSG_ROUTE_N   R/W   Module N destination route

module message_dispatcher #(
    parameter int NUM_MODULES = 4,
    parameter int ROUTER_INPUTS = 4,
    parameter int ROUTER_OUTPUTS = 8
) (
    input  logic               clk,
    input  logic               reset_n,

    // Wishbone slave (for CPU to program routing table)
    input  logic               wb_cyc,
    input  logic               wb_stb,
    input  logic               wb_we,
    input  logic [31:0]        wb_adr,
    input  logic [31:0]        wb_dat_w,
    input  logic [3:0]         wb_sel,
    output logic [31:0]        wb_dat_r,
    output logic               wb_ack,

    // Module TX ports (module → dispatcher)
    input  logic [NUM_MODULES-1:0]   tx_valid,
    input  logic [NUM_MODULES-1:0]   tx_last,
    input  logic [NUM_MODULES*32-1:0] tx_data,
    output logic [NUM_MODULES-1:0]   tx_ready,

    // Module RX ports (dispatcher → module)
    output logic [NUM_MODULES-1:0]   rx_valid,
    output logic [NUM_MODULES-1:0]   rx_last,
    output logic [NUM_MODULES*32-1:0] rx_data,
    input  logic [NUM_MODULES-1:0]   rx_ready
);

    // Control and status registers
    logic [31:0] ctrl;
    logic [31:0] status;

    // Routing table: for each source module, where to send its output
    // route[module] = destination module ID
    logic [7:0] route [NUM_MODULES];

    // Statistics
    logic [31:0] msg_count [NUM_MODULES];
    logic [31:0] err_count [NUM_MODULES];

    // Message router
    logic [ROUTER_INPUTS-1:0]  r_in_valid, r_in_last, r_in_ready;
    logic [ROUTER_INPUTS*32-1:0] r_in_data;
    logic [ROUTER_OUTPUTS-1:0] r_out_valid, r_out_last, r_out_ready;
    logic [ROUTER_OUTPUTS*32-1:0] r_out_data;

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

    // Connect module TX to router inputs
    genvar i;
    generate
        for (i = 0; i < NUM_MODULES; i++) begin : gen_tx_connect
            assign r_in_valid[i] = tx_valid[i];
            assign r_in_last[i]  = tx_last[i];
            assign r_in_data[i*32 +: 32] = tx_data[i*32 +: 32];
            assign tx_ready[i]   = r_in_ready[i];
        end
    endgenerate

    // Connect router outputs to module RX
    // Direct mapping: router output N → module N
    generate
        for (i = 0; i < NUM_MODULES; i++) begin : gen_rx_connect
            assign rx_valid[i] = r_out_valid[i];
            assign rx_last[i]  = r_out_last[i];
            assign rx_data[i*32 +: 32] = r_out_data[i*32 +: 32];
            assign r_out_ready[i] = rx_ready[i];
        end
    endgenerate

    // Unused router outputs
    generate
        for (i = NUM_MODULES; i < ROUTER_OUTPUTS; i++) begin : gen_unused
            assign r_out_ready[i] = 1'b1;
        end
    endgenerate

    // Wishbone slave
    assign wb_ack = wb_stb && wb_cyc;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ctrl <= '0;
            for (int m = 0; m < NUM_MODULES; m++) begin
                route[m] <= 8'hFF; // Default: broadcast
                msg_count[m] <= '0;
                err_count[m] <= '0;
            end
        end else begin
            // Count messages
            for (int m = 0; m < NUM_MODULES; m++) begin
                if (tx_valid[m] && tx_ready[m] && !r_in_last[m]) begin
                    msg_count[m] <= msg_count[m] + 1'b1;
                end
            end

            // Wishbone write
            if (wb_we && wb_stb && wb_cyc) begin
                if (wb_adr[7:0] == 8'h00) ctrl <= wb_dat_w;
                if (wb_adr[7:0] >= 8'h08 && wb_adr[7:0] < 8'h08 + NUM_MODULES*4) begin
                    route[(wb_adr[7:0] - 8'h08) >> 2] <= wb_dat_w[7:0];
                end
            end
        end
    end

    // Wishbone read
    always_comb begin
        wb_dat_r = '0;
        case (wb_adr[7:0])
            8'h00: wb_dat_r = ctrl;
            8'h04: wb_dat_r = status;
            default: begin
                if (wb_adr[7:0] >= 8'h08 && wb_adr[7:0] < 8'h08 + NUM_MODULES*4) begin
                    wb_dat_r = {24'h0, route[(wb_adr[7:0] - 8'h08) >> 2]};
                end
            end
        endcase
    end

endmodule
