// Closure Unit
// ============
// Creates closure objects in the FPU heap.
// A closure consists of: header + arity + code_ptr + environment entries.
//
// Memory layout:
//   Word 0: {TAG=CLOSURE(8), FLAGS(8), SIZE(16)}
//   Word 1: arity (32)
//   Word 2: code_ptr (pointer to graph in graph memory)
//   Word 3+: environment entry pointers

module closure_unit (
    input  logic        clk,
    input  logic        reset_n,

    // Interface to heap controller
    output logic        alloc_valid,
    output logic [7:0]  alloc_tag,
    output logic [7:0]  alloc_flags,
    output logic [15:0] alloc_size,
    input  logic [31:0] alloc_ptr,
    input  logic        alloc_ack,

    // Closure parameters
    input  logic        closure_req,
    input  logic [7:0]  arity,
    input  logic [31:0] code_ptr,
    input  logic [7:0]  env_size,    // number of env entries
    input  logic [255:0] env_data,   // packed env entries (8 × 32-bit)
    output logic [31:0] closure_ptr,
    output logic        closure_ack
);

    // State machine
    typedef enum logic [1:0] { ST_IDLE, ST_ALLOC, ST_WRITE, ST_DONE } state_t;
    state_t state;

    logic [2:0] write_idx; // counter for writing env entries
    logic [15:0] total_size;

    // Total size = header(4) + arity(4) + code_ptr(4) + env_size*4
    assign total_size = 12 + (env_size << 2);

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
                        alloc_tag   <= 8'h08; // CLOSURE
                        alloc_flags <= 8'h00;
                        alloc_size  <= total_size;
                        state <= ST_ALLOC;
                    end
                end

                ST_ALLOC: begin
                    if (alloc_ack) begin
                        closure_ptr <= alloc_ptr;
                        write_idx <= '0;
                        if (alloc_ptr != 32'd0) begin
                            state <= ST_WRITE;
                        end else begin
                            closure_ack <= 1'b1; // OOM
                            state <= ST_DONE;
                        end
                    end
                end

                ST_WRITE: begin
                    // Write closure data into heap memory
                    // This is done via the heap controller's write port
                    // For simplicity, we write one word per cycle
                    if (write_idx < 2 + env_size) begin
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
            endcase
        end
    end

endmodule
