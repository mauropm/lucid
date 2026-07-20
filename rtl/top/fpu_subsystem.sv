`default_nettype none

// FPU Subsystem Integration
// =========================
// Wires the canonical dataflow scheduler (graph_scheduler_fp) to the message
// router and the primitive execution unit. Arithmetic/compare primitives are
// dispatched by the scheduler as MSG_EXEC_PRIM messages, routed to
// primitive_exec, and the result is routed back to the scheduler as
// MSG_PRIM_RESULT.
//
// This is the reusable integration block instantiated by lucid_top and by the
// scheduler/integration testbenches, so the SAME hierarchy is exercised in
// simulation and in hardware.
//
// Message routing (by header destination byte):
//   scheduler tx  -> router in[0]  (dest = MODULE_ARITH) -> router out[1] -> primitive_exec rx
//   primitive rx  -> router in[1]  (dest = MODULE_SCHEDULER) -> router out[0] -> scheduler rx
//
// Future FPU modules (heap, gc, closure, env) attach at higher router inputs
// without changing the scheduler or primitive_exec.

module fpu_subsystem #(
    parameter int NUM_NODES = 64,
    parameter int Q_DEPTH   = NUM_NODES,
    parameter int ROUTER_OUTPUTS = 2
) (
    input  logic        clk,
    input  logic        reset_n,

    // CPU / host register interface to the scheduler
    input  logic        reg_cyc,
    input  logic        reg_stb,
    input  logic        reg_we,
    input  logic [31:0] reg_adr,
    input  logic [31:0] reg_dat_w,
    output logic [31:0] reg_dat_r,
    output logic        reg_ack,

    // Debug passthroughs (used by integration testbenches to inspect results)
    output logic [31:0] dbg_node_result [0:NUM_NODES-1],
    output logic [31:0] dbg_root_id
);

    // Scheduler <-> router message wires
    logic sched_tx_valid, sched_tx_last, sched_tx_ready;
    logic [31:0] sched_tx_data;
    logic sched_rx_valid, sched_rx_last, sched_rx_ready;
    logic [31:0] sched_rx_data;

    logic pe_tx_valid, pe_tx_last, pe_tx_ready;
    logic [31:0] pe_tx_data;
    logic pe_rx_valid, pe_rx_last, pe_rx_ready;
    logic [31:0] pe_rx_data;

    localparam int ROUTER_INPUTS = 2;

    graph_scheduler_fp #(.NUM_NODES(NUM_NODES), .Q_DEPTH(Q_DEPTH)) sched (
        .clk(clk), .reset_n(reset_n),
        .reg_cyc(reg_cyc), .reg_stb(reg_stb), .reg_we(reg_we),
        .reg_adr(reg_adr), .reg_dat_w(reg_dat_w),
        .reg_dat_r(reg_dat_r), .reg_ack(reg_ack),
        .msg_tx_valid(sched_tx_valid), .msg_tx_last(sched_tx_last),
        .msg_tx_data(sched_tx_data),   .msg_tx_ready(sched_tx_ready),
        .msg_rx_valid(sched_rx_valid), .msg_rx_last(sched_rx_last),
        .msg_rx_data(sched_rx_data),   .msg_rx_ready(sched_rx_ready)
    );

    primitive_exec pe (
        .clk(clk), .reset_n(reset_n),
        .msg_in_valid(pe_rx_valid), .msg_in_data(pe_rx_data),
        .msg_in_last(pe_rx_last),   .msg_in_ready(pe_rx_ready),
        .msg_out_valid(pe_tx_valid), .msg_out_data(pe_tx_data),
        .msg_out_last(pe_tx_last),   .msg_out_ready(pe_tx_ready)
    );

    // Router output index == destination module id:
    //   out[0] = MODULE_SCHEDULER -> scheduler rx
    //   out[1] = MODULE_ARITH     -> primitive_exec rx
    message_router #(.NUM_INPUTS(ROUTER_INPUTS), .NUM_OUTPUTS(ROUTER_OUTPUTS)) router (
        .clk(clk), .reset_n(reset_n),
        .in_valid({pe_tx_valid,  sched_tx_valid}),   // in[1]=pe, in[0]=sched
        .in_last ({pe_tx_last,   sched_tx_last}),
        .in_data ({pe_tx_data,   sched_tx_data}),
        .in_ready({pe_tx_ready,  sched_tx_ready}),
        .out_valid({pe_rx_valid,  sched_rx_valid}),   // out[1]=pe, out[0]=sched
        .out_last ({pe_rx_last,   sched_rx_last}),
        .out_data ({pe_rx_data,   sched_rx_data}),
        .out_ready({pe_rx_ready,  sched_rx_ready})
    );

    assign dbg_node_result = sched.dbg_node_result;
    assign dbg_root_id     = sched.dbg_root_id;

endmodule

`default_nettype wire
