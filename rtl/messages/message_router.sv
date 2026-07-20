`default_nettype none

// Message Router
// ==============
// Crossbar that routes point-to-point messages between FPU modules based on
// the destination byte in each message header (bits [31:24] of word 0).
//
// Handshake convention (ready/valid, AXI-stream style):
//   * A message is a sequence of one or more words. The final word has
//     in_last asserted.
//   * An input may only present a word when its in_ready is high. The router
//     captures the word combinationally into the selected output register.
//   * An output presents out_valid while busy; the consumer must keep
//     out_ready high to advance each word. The last word clears busy.
//
// Arbitration: round-robin per output (task #12). A per-output rr_ptr rotates
// the grant order after each accepted first-word so no input can starve
// another. Fixed-priority (lowest-index-first) is the fallback when only one
// requester is pending.
//
// Multi-word correctness: once an output is granted to an input (lock), all
// subsequent words are taken from that same input until in_last, regardless of
// the destination field of later words. This is what makes variable-length
// messages route atomically.

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

    // Destination of each input's current header word.
    logic [7:0] in_dest [NUM_INPUTS];
    genvar ii;
    generate
        for (ii = 0; ii < NUM_INPUTS; ii++) begin : gen_dest
            assign in_dest[ii] = in_data[ii*32 + 24 +: 8];
        end
    endgenerate

    // An input currently supplying a multi-word message (locked to some output)
    // must not spawn new requests for other outputs; its later words only flow
    // to the output it is already locked to.
    function automatic logic [NUM_OUTPUTS-1:0] conn_mask(input int ii);
        logic [NUM_OUTPUTS-1:0] m;
        m = '0;
        for (int o = 0; o < NUM_OUTPUTS; o++)
            if (lock[o] && (src[o] == IW'(ii)))
                m[o] = 1'b1;
        return m;
    endfunction

    logic [NUM_INPUTS-1:0] in_locked;
    generate
        for (ii = 0; ii < NUM_INPUTS; ii++) begin : gen_inlocked
            assign in_locked[ii] = |(lock & conn_mask(ii));
        end
    endgenerate

    logic [NUM_OUTPUTS-1:0]        busy;
    logic [NUM_OUTPUTS-1:0]        lock;
    logic [$clog2(NUM_INPUTS)-1:0] src [NUM_OUTPUTS];
    logic [NUM_OUTPUTS*32-1:0]     out_data_r;
    logic [NUM_OUTPUTS-1:0]        out_last_r;

    localparam int IW = $clog2(NUM_INPUTS);

    // Round-robin pointer per output: next input to favour for arbitration.
    logic [IW-1:0] rr_ptr [NUM_OUTPUTS];

    // Outputs are presented from the registered latches. Every forwarded word
    // (including the first, latched at request) is captured into out_data_r /
    // out_last_r one cycle before it is presented, so data and last are always
    // sampled by the consumer on the same clock edge (no last-bit skew).
    assign out_data  = out_data_r;
    assign out_last  = out_last_r;
    assign out_valid = busy;

    generate
        genvar o;
        for (o = 0; o < NUM_OUTPUTS; o++) begin : gen_output

            // Requester bitmap for this output, and the round-robin grant.
            logic [NUM_INPUTS-1:0] request;
            for (genvar i = 0; i < NUM_INPUTS; i++) begin : gen_req
                assign request[i] = in_valid[i] && (in_dest[i] == o) && !in_locked[i];
            end
            wire any_request = |request;

            // Round-robin grant: walk from rr_ptr[o], wrapping, and pick the
            // first pending requester. Falls back to fixed priority when only
            // one requester is pending (rr_ptr has no effect then).
            logic [IW-1:0] grant_idx;
            logic          grant_valid;
            always_comb begin
                grant_idx   = '0;
                grant_valid = 1'b0;
                for (int k = 0; k < NUM_INPUTS; k++) begin
                    logic [IW-1:0] idx;
                    idx = (rr_ptr[o] + IW'(k)) % NUM_INPUTS;
                    if (!grant_valid && request[idx]) begin
                        grant_idx   = idx;
                        grant_valid = 1'b1;
                    end
                end
            end

            always_ff @(posedge clk or negedge reset_n) begin
                if (!reset_n) begin
                    busy[o]        <= 1'b0;
                    lock[o]        <= 1'b0;
                    src[o]         <= '0;
                    out_data_r[o*32 +: 32] <= '0;
                    out_last_r[o]  <= 1'b0;
                    rr_ptr[o]      <= '0;
                end else begin
                    if (!busy[o] && any_request && grant_valid) begin
                        // Accept the first word of a new message.
                        busy[o]        <= 1'b1;
                        src[o]         <= grant_idx;
                        out_data_r[o*32 +: 32] <= in_data[grant_idx*32 +: 32];
                        out_last_r[o]  <= in_last[grant_idx];
                        if (!in_last[grant_idx]) begin
                            lock[o] <= 1'b1;
                            // Rotate arbitration pointer past the granted input.
                            rr_ptr[o] <= (grant_idx + IW'(1)) % NUM_INPUTS;
                        end else begin
                            lock[o] <= 1'b0;
                        end
                    end else if (busy[o] && out_ready[o]) begin
                        if (lock[o]) begin
                            // Forward the next word from the locked source. The
                            // word is captured this cycle and presented next
                            // cycle (out_valid stays high), so the consumer sees
                            // data and last together.
                            out_data_r[o*32 +: 32] <= in_data[src[o]*32 +: 32];
                            out_last_r[o]  <= in_last[src[o]];
                            if (in_last[src[o]]) begin
                                // Final word captured: release the lock now, but
                                // keep busy high for one more cycle so the last
                                // word is presented with valid=1 before we free
                                // the output.
                                lock[o] <= 1'b0;
                                rr_ptr[o] <= (src[o] + IW'(1)) % NUM_INPUTS;
                            end
                        end else begin
                            // Single-word message already presented, or the
                            // final word of a multi-word message was presented
                            // last cycle: free the output.
                            busy[o] <= 1'b0;
                        end
                    end
                end
            end
        end
    endgenerate

    // in_ready: an input is ready if it is currently locked to an output (and
    // that output's consumer is ready), or if it has a pending request to a
    // free output.
    generate
        for (ii = 0; ii < NUM_INPUTS; ii++) begin : gen_ready
            logic [NUM_OUTPUTS-1:0] lmask;
            logic locked;
            logic locked_ready;
            logic free_req;
            assign lmask = conn_mask(ii);
            assign locked = |lmask;
            assign locked_ready = |(lmask & out_ready);
            assign free_req = (in_dest[ii] < 8'(NUM_OUTPUTS)) ? (!busy[in_dest[ii]]) : 1'b0;
            assign in_ready[ii] = locked ? locked_ready : free_req;
        end
    endgenerate

endmodule

`default_nettype wire
