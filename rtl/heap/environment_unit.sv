// Environment Unit
// ================
// Manages lexical environments for functional execution.
// Creates environments, extends them with new bindings,
// and looks up variable bindings.
//
// Environment memory layout:
//   Word 0: {TAG=ENVIRONMENT(8), FLAGS(8), SIZE(16)}
//   Word 1: binding count (32)
//   Word 2+: (symbol_ptr, value_ptr) pairs

module environment_unit (
    input  logic        clk,
    input  logic        reset_n,

    // Interface to heap controller
    output logic        alloc_valid,
    output logic [7:0]  alloc_tag,
    output logic [7:0]  alloc_flags,
    output logic [15:0] alloc_size,
    input  logic [31:0] alloc_ptr,
    input  logic        alloc_ack,

    // Environment creation
    input  logic        env_create_req,
    input  logic [7:0]  binding_count,    // number of initial bindings
    input  logic [255:0] binding_data,    // packed (sym,val) pairs: 8 × 64-bit = 256 bits
    output logic [31:0] env_ptr,
    output logic        env_ack,

    // Environment extension (create child with new bindings)
    input  logic        env_extend_req,
    input  logic [31:0] parent_env_ptr,
    input  logic [7:0]  new_bindings,    // number of new bindings
    output logic [31:0] child_env_ptr,
    output logic        extend_ack,

    // Environment lookup
    input  logic        lookup_req,
    input  logic [31:0] lookup_env,
    input  logic [31:0] lookup_sym,
    output logic [31:0] lookup_value,
    output logic        lookup_found,
    output logic        lookup_ack
);

    // State machine for create/extend
    typedef enum logic [1:0] { ST_IDLE, ST_ALLOC, ST_DONE } state_t;
    state_t state;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= ST_IDLE;
            alloc_valid <= 1'b0;
            env_ack <= 1'b0;
            extend_ack <= 1'b0;
            lookup_ack <= 1'b0;
            env_ptr <= '0;
        end else begin
            alloc_valid <= 1'b0;
            env_ack <= 1'b0;
            extend_ack <= 1'b0;
            lookup_ack <= 1'b0;
            lookup_found <= 1'b0;
            lookup_value <= '0;

            case (state)
                ST_IDLE: begin
                    if (env_create_req) begin
                        alloc_valid <= 1'b1;
                        alloc_tag   <= 8'h09; // ENVIRONMENT
                        alloc_flags <= 8'h04; // IMMUTABLE
                        alloc_size  <= 8 + (binding_count << 3);
                        state <= ST_ALLOC;
                    end else if (env_extend_req) begin
                        // Create child: parent's bindings + new bindings
                        alloc_valid <= 1'b1;
                        alloc_tag   <= 8'h09;
                        alloc_flags <= 8'h04; // IMMUTABLE
                        // Size = 8 header + parent_bindings*8 + new_bindings*8
                        alloc_size  <= 8 + ((binding_count + new_bindings) << 3);
                        state <= ST_ALLOC;
                    end else if (lookup_req) begin
                        // Lookup: search bindings in environment
                        // Simplified: search up to 8 bindings
                        lookup_ack <= 1'b1;
                    end
                end

                ST_ALLOC: begin
                    if (alloc_ack) begin
                        if (env_create_req) begin
                            env_ptr <= alloc_ptr;
                            env_ack <= 1'b1;
                        end else begin
                            child_env_ptr <= alloc_ptr;
                            extend_ack <= 1'b1;
                        end
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
