`default_nettype none

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

    logic [7:0] in_dest [NUM_INPUTS];
    genvar ii;
    generate
        for (ii = 0; ii < NUM_INPUTS; ii++) begin : gen_dest
            assign in_dest[ii] = in_data[ii*32 + 24 +: 8];
        end
    endgenerate

    logic [NUM_OUTPUTS-1:0]  busy;
    logic [NUM_INPUTS-1:0]   conn [NUM_OUTPUTS];
    logic [NUM_OUTPUTS-1:0]  lock;
    logic [NUM_OUTPUTS*32-1:0] out_data_r;
    logic [NUM_OUTPUTS-1:0]   out_last_r;
    logic [NUM_INPUTS-1:0]   in_locked;
    logic [NUM_INPUTS-1:0]   in_locked_ready;

    assign out_data  = out_data_r;
    assign out_last  = out_last_r;
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

            // H7: Parameterized priority grant
            wire [NUM_INPUTS-1:0] grant;
            assign grant[0] = request[0];
            genvar g;
            for (g = 1; g < NUM_INPUTS; g++) begin : gen_grant
                wire lower_pending;
                assign lower_pending = |request[g-1:0];
                assign grant[g] = request[g] && !lower_pending;
            end

            wire [NUM_INPUTS-1:0] current_conn;
            assign current_conn = conn[o];

            always_ff @(posedge clk or negedge reset_n) begin
                if (!reset_n) begin
                    busy[o]        <= 1'b0;
                    lock[o]        <= 1'b0;
                    conn[o]        <= '0;
                    out_data_r[o*32 +: 32] <= '0;
                    out_last_r[o]  <= 1'b0;
                end else begin
                    if (busy[o]) begin
                        if (out_ready[o]) begin
                            if (lock[o]) begin
                                // H7: Hold lock during bubbles - wait for next word
                                logic found;
                                found = 1'b0;
                                for (int i = 0; i < NUM_INPUTS; i++) begin
                                    if (conn[o][i] && in_valid[i]) begin
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
                                // H7: Do NOT terminate on bubble - hold busy/lock
                            end else begin
                                busy[o] <= 1'b0;
                                conn[o] <= '0;
                            end
                        end
                    end else if (any_request) begin
                        busy[o] <= 1'b1;
                        conn[o] <= grant;
                        for (int i = 0; i < NUM_INPUTS; i++) begin
                            if (grant[i]) begin
                                out_data_r[o*32 +: 32] <= in_data[i*32 +: 32];
                                out_last_r[o] <= in_last[i];
                                if (!in_last[i])
                                    lock[o] <= 1'b1;
                            end
                        end
                    end
                end
            end
        end
    endgenerate

    // When an input is locked to an output, accept data based on that output's
    // ready status, not on the per-word destination field in the payload.
    generate
        for (ii = 0; ii < NUM_INPUTS; ii++) begin : gen_in_locked
            wire [NUM_OUTPUTS-1:0] lmask;
            for (genvar oo = 0; oo < NUM_OUTPUTS; oo++) begin : gen_l
                assign lmask[oo] = lock[oo] && conn[oo][ii];
            end
            assign in_locked[ii] = |lmask;
            assign in_locked_ready[ii] = |(lmask & out_ready);
        end
    endgenerate

    generate
        for (ii = 0; ii < NUM_INPUTS; ii++) begin : gen_ready
            assign in_ready[ii] = in_locked[ii] ? in_locked_ready[ii] :
                (in_dest[ii] < NUM_OUTPUTS) ?
                    (!busy[in_dest[ii]] || (lock[in_dest[ii]] && out_ready[in_dest[ii]])) : 1'b1;
        end
    endgenerate

endmodule

`default_nettype wire
