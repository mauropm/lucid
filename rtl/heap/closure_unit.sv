`default_nettype none

module closure_unit (
    input  logic        clk,
    input  logic        reset_n,

    output logic        alloc_valid,
    output logic [7:0]  alloc_tag,
    output logic [7:0]  alloc_flags,
    output logic [15:0] alloc_size,
    input  logic [31:0] alloc_ptr,
    input  logic        alloc_ack,

    input  logic        closure_req,
    input  logic [7:0]  arity,
    input  logic [31:0] code_ptr,
    input  logic [7:0]  env_size,
    input  logic [255:0] env_data,
    output logic [31:0] closure_ptr,
    output logic        closure_ack
);

    typedef enum logic [1:0] { ST_IDLE, ST_ALLOC, ST_WRITE, ST_DONE } state_t;
    state_t state;

    // H11: Properly sized counter (env_size up to 255, so 2+255=257 needs 9 bits)
    logic [8:0] write_idx;
    logic [15:0] total_size;

    assign total_size = 12 + ({8'h0, env_size} << 2);

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= ST_IDLE;
            alloc_valid <= 1'b0;
            closure_ack <= 1'b0;
            closure_ptr <= '0;
            write_idx <= '0;
        end else begin
            alloc_valid <= 1'b0;
            closure_ack <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (closure_req) begin
                        alloc_valid <= 1'b1;
                        alloc_tag   <= 8'h08;
                        alloc_flags <= 8'h00;
                        alloc_size  <= total_size;
                        state <= ST_ALLOC;
                    end
                end

                ST_ALLOC: begin
                    if (alloc_ack) begin
                        closure_ptr <= alloc_ptr;
                        write_idx <= '0;
                        if (alloc_ptr != 32'd0)
                            state <= ST_WRITE;
                        else begin
                            closure_ack <= 1'b1;
                            state <= ST_DONE;
                        end
                    end
                end

                ST_WRITE: begin
                    // H11: Fixed - properly bounded loop with sized counter
                    if (write_idx < 2 + {8'h0, env_size}) begin
                        write_idx <= write_idx + 1'b1;
                    end else begin
                        closure_ack <= 1'b1;
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    closure_ack <= 1'b0;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
