`default_nettype none

module environment_unit (
    input  logic        clk,
    input  logic        reset_n,

    output logic        alloc_valid,
    output logic [7:0]  alloc_tag,
    output logic [7:0]  alloc_flags,
    output logic [15:0] alloc_size,
    input  logic [31:0] alloc_ptr,
    input  logic        alloc_ack,

    input  logic        env_create_req,
    input  logic [7:0]  binding_count,
    input  logic [255:0] binding_data,
    output logic [31:0] env_ptr,
    output logic        env_ack,

    input  logic        env_extend_req,
    input  logic [31:0] parent_env_ptr,
    input  logic [7:0]  new_bindings,
    output logic [31:0] child_env_ptr,
    output logic        extend_ack,

    input  logic        lookup_req,
    input  logic [31:0] lookup_env,
    input  logic [31:0] lookup_sym,
    output logic [31:0] lookup_value,
    output logic        lookup_found,
    output logic        lookup_ack
);

    typedef enum logic [1:0] { ST_IDLE, ST_ALLOC, ST_DONE } state_t;
    state_t state;

    // H10: Register request type at acceptance
    logic req_is_create;
    logic req_is_extend;
    logic req_is_lookup;
    logic [7:0] saved_binding_count;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= ST_IDLE;
            alloc_valid <= 1'b0;
            env_ack <= 1'b0;
            extend_ack <= 1'b0;
            lookup_ack <= 1'b0;
            lookup_found <= 1'b0;
            lookup_value <= '0;
            env_ptr <= '0;
            child_env_ptr <= '0;
            req_is_create <= 1'b0;
            req_is_extend <= 1'b0;
            req_is_lookup <= 1'b0;
            saved_binding_count <= '0;
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
                        req_is_create <= 1'b1;
                        req_is_extend <= 1'b0;
                        req_is_lookup <= 1'b0;
                        saved_binding_count <= binding_count;
                        alloc_valid <= 1'b1;
                        alloc_tag   <= 8'h09;
                        alloc_flags <= 8'h04;
                        alloc_size  <= 8 + ({8'h0, binding_count} << 3);
                        state <= ST_ALLOC;
                    end else if (env_extend_req) begin
                        req_is_create <= 1'b0;
                        req_is_extend <= 1'b1;
                        req_is_lookup <= 1'b0;
                        saved_binding_count <= binding_count;
                        alloc_valid <= 1'b1;
                        alloc_tag   <= 8'h09;
                        alloc_flags <= 8'h04;
                        alloc_size  <= 8 + (({8'h0, binding_count} + {8'h0, new_bindings}) << 3);
                        state <= ST_ALLOC;
                    end else if (lookup_req) begin
                        // H10: Lookup stub - acknowledge immediately with not-found
                        lookup_ack <= 1'b1;
                        lookup_found <= 1'b0;
                    end
                end

                ST_ALLOC: begin
                    if (alloc_ack) begin
                        if (req_is_create) begin
                            env_ptr <= alloc_ptr;
                            env_ack <= 1'b1;
                        end else if (req_is_extend) begin
                            child_env_ptr <= alloc_ptr;
                            extend_ack <= 1'b1;
                        end
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    req_is_create <= 1'b0;
                    req_is_extend <= 1'b0;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
