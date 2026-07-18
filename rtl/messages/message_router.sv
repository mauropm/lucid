// Message Router
// ==============
// Combinational crossbar with registered outputs.
// Input is routed to output in one cycle.
// Output register holds data until the receiver acknowledges.
// Multi-word: output register advances on each acknowledge.

module message_router #(
    parameter int NUM_INPUTS  = 4,
    parameter int NUM_OUTPUTS = 8
) (
    input  logic               clk,
    input  logic               reset_n,

    input  logic [NUM_INPUTS-1:0]   in_valid,
    input  logic [NUM_INPUTS-1:0]   in_last,
    input  logic [NUM_INPUTS*32-1:0] in_data,
    output logic [NUM_INPUTS-1:0]   in_ready,

    output logic [NUM_OUTPUTS-1:0]  out_valid,
    output logic [NUM_OUTPUTS-1:0]  out_last,
    output logic [NUM_OUTPUTS*32-1:0] out_data,
    input  logic [NUM_OUTPUTS-1:0]  out_ready
);

    // Destinations for each input (DEST is in bits [31:24] of the header)
    logic [7:0] in_dest [NUM_INPUTS];
    genvar ii;
    generate
        for (ii = 0; ii < NUM_INPUTS; ii++) begin : gen_dest
            assign in_dest[ii] = in_data[ii*32 + 24 +: 8];
        end
    endgenerate

    // Per-output state
    logic [NUM_OUTPUTS-1:0]  busy; // 1 = output holding data, not yet accepted
    logic [NUM_INPUTS-1:0]   conn [NUM_OUTPUTS]; // which input is connected
    logic [NUM_OUTPUTS-1:0]  lock; // 1 = multi-word in progress
    logic [NUM_OUTPUTS*32-1:0] out_data_r;
    logic [NUM_OUTPUTS-1:0]   out_last_r;

    // Output data (registered)
    assign out_data = out_data_r;
    assign out_last = out_last_r;
    assign out_valid = busy;

    genvar o;
    generate
        for (o = 0; o < NUM_OUTPUTS; o++) begin : gen_output

            wire [NUM_INPUTS-1:0] request;
            wire any_request;
            for (genvar i = 0; i < NUM_INPUTS; i++) begin : gen_req
                assign request[i] = in_valid[i] && (in_dest[i] == o);
            end
            assign any_request = |request;

            // Priority grant
            wire [NUM_INPUTS-1:0] grant;
            assign grant[0] = request[0];
            assign grant[1] = request[1] && !request[0];
            assign grant[2] = request[2] && !(request[0] || request[1]);
            assign grant[3] = request[3] && !(request[0] || request[1] || request[2]);

            // Current connection (for multi-word): use stored grant
            wire [NUM_INPUTS-1:0] current_conn;
            assign current_conn = conn[o];

            // Output register update
            always_ff @(posedge clk or negedge reset_n) begin
                if (!reset_n) begin
                    busy[o]        <= 1'b0;
                    lock[o]        <= 1'b0;
                    conn[o]        <= '0;
                    out_data_r[o*32 +: 32] <= '0;
                    out_last_r[o]  <= 1'b0;
                end else begin
                    if (busy[o]) begin
                        // Output busy: accept if receiver is ready
                        if (out_ready[o]) begin
                            if (lock[o]) begin
                                // Multi-word: advance to next word
                                logic found;
                                found = 1'b0;
                                for (int i = 0; i < NUM_INPUTS; i++) begin
                                    if (conn[o][i] && in_valid[i] && in_dest[i] == o) begin
                                        out_data_r[o*32 +: 32] <= in_data[i*32 +: 32];
                                        out_last_r[o] <= in_last[i];
                                        if (in_last[i]) begin
                                            lock[o] <= 1'b0;
                                            busy[o] <= 1'b0;
                                            conn[o] <= '0;
                                        end
                                        found = 1'b1;
                                    end
                                end
                                // If no word available, output becomes idle
                                if (!found) begin
                                    busy[o] <= 1'b0;
                                    lock[o] <= 1'b0;
                                    conn[o] <= '0;
                                end
                            end else begin
                                // Single-word: output accepted
                                busy[o] <= 1'b0;
                                conn[o] <= '0;
                            end
                        end
                    end else if (any_request) begin
                        // Output free: accept new transaction
                        busy[o] <= 1'b1;
                        conn[o] <= grant;
                        for (int i = 0; i < NUM_INPUTS; i++) begin
                            if (grant[i]) begin
                                out_data_r[o*32 +: 32] <= in_data[i*32 +: 32];
                                out_last_r[o] <= in_last[i];
                                if (!in_last[i]) begin
                                    lock[o] <= 1'b1;
                                end
                            end
                        end
                    end
                end
            end
        end
    endgenerate

    // in_ready: an input is ready only when its destination output register
    // is free (not busy). This ensures single-register outputs hold data
    // until the receiver acknowledges, and no data is lost between messages.
    generate
        for (ii = 0; ii < NUM_INPUTS; ii++) begin : gen_ready
            assign in_ready[ii] = (in_dest[ii] < NUM_OUTPUTS) ?
                !busy[in_dest[ii]] : 1'b1;
        end
    endgenerate

endmodule
