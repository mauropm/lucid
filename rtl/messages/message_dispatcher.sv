// Lucid Message Dispatcher
// ========================
// Routes messages between FPU execution units.
// Maintains a routing table: module_id → output FIFO.
//
// Inputs:
//   clk              (1)    Clock
//   reset_n          (1)    Active-low reset
//   msg_in_data      (32)   Input message data
//   msg_in_valid     (1)    Input message valid
//   msg_in_ready     (1)    Input message ready (backpressure)
//
// Outputs: (for each destination)
//   msg_out_data[N]  (32)   Output message data to unit N
//   msg_out_valid[N] (1)    Output message valid to unit N
//   msg_out_ready[N] (1)    Output message ready from unit N
//
// Parameters:
//   NUM_UNITS       (4)     Number of execution units

module message_dispatcher #(
    parameter int NUM_UNITS = 4
) (
    input  logic              clk,
    input  logic              reset_n,

    input  logic [31:0]       msg_in_data,
    input  logic              msg_in_valid,
    output logic              msg_in_ready,

    output logic [31:0]       msg_out_data [NUM_UNITS],
    output logic              msg_out_valid [NUM_UNITS],
    input  logic              msg_out_ready [NUM_UNITS]
);

    // Message header: TYPE[31:24], FLAGS[23:16], TAG[15:0]
    // TYPE[7:4] = destination unit ID
    // TYPE[3:0] = opcode within destination unit

    logic [3:0] dest_unit;

    assign dest_unit = msg_in_data[31:28];
    assign msg_in_ready = msg_out_ready[dest_unit];

    // Broadcast: if FLAGS[3] (BROADCAST) is set, send to all units
    logic broadcast;
    assign broadcast = msg_in_data[19];

    genvar i;
    generate
        for (i = 0; i < NUM_UNITS; i++) begin : gen_output
            assign msg_out_data[i]  = msg_in_data;
            assign msg_out_valid[i] = msg_in_valid && (broadcast || (dest_unit == i));
        end
    endgenerate

endmodule
