// Lucid Wishbone Bus (Wishbone B4)
// ================================
// Shared bus connecting Management CPU, FPU, and peripherals.
//
// Implements Wishbone B4 pipelined mode.

module wishbone_bus #(
    parameter int NUM_MASTERS = 2,
    parameter int NUM_SLAVES  = 8
) (
    input  logic clk,
    input  logic reset_n,

    // Master interfaces
    wishbone_interface.master masters [NUM_MASTERS],

    // Slave interfaces
    wishbone_interface.slave  slaves [NUM_SLAVES]
);

    // Address decoding
    logic [NUM_SLAVES-1:0] slave_select;

    // Simplified arbitration: fixed priority (master 0 > master 1)
    logic [NUM_MASTERS-1:0] grant;
    logic [NUM_MASTERS-1:0] request;

    genvar i;
    generate
        for (i = 0; i < NUM_MASTERS; i++) begin : gen_arb
            assign request[i] = masters[i].cyc && masters[i].stb;
        end
    endgenerate

    // Fixed priority arbiter
    always_comb begin
        grant = '0;
        if (request[0]) grant[0] = 1'b1;
        else if (request[1]) grant[1] = 1'b1;
    end

    // Address decoding (simple example)
    // Slave 0: 0x00000000 - 0x000FFFFF (Boot ROM, Management RAM, peripherals)
    // Slave 1: 0x00100000 - 0x001FFFFF (FPU control)
    // Slave 2: 0x00200000 - 0x002FFFFF (Graph memory)
    // Slave 3: 0x00300000 - 0x003FFFFF (FPU Heap)
    // Slave 4: 0x00400000 - 0x004FFFFF (GC Scratch)
    // etc.

    wire [31:0] active_addr;
    assign active_addr = grant[0] ? masters[0].adr : masters[1].adr;

    always_comb begin
        slave_select = '0;
        if (active_addr[31:20] == 12'h000) slave_select[0] = 1'b1;
        else if (active_addr[31:20] == 12'h001) slave_select[1] = 1'b1;
        else if (active_addr[31:20] == 12'h002) slave_select[2] = 1'b1;
        else if (active_addr[31:20] == 12'h003) slave_select[3] = 1'b1;
        else if (active_addr[31:20] == 12'h004) slave_select[4] = 1'b1;
    end

    // Bus signal routing
    generate
        for (i = 0; i < NUM_SLAVES; i++) begin : gen_slave_mux
            assign slaves[i].cyc = |grant && slave_select[i];
            assign slaves[i].stb = |grant && slave_select[i];
            assign slaves[i].adr = active_addr;
            assign slaves[i].dat_i = grant[0] ? masters[0].dat_o : masters[1].dat_o;
            assign slaves[i].we = grant[0] ? masters[0].we : masters[1].we;
            assign slaves[i].sel = grant[0] ? masters[0].sel : masters[1].sel;
        end
    endgenerate

    // Master read data mux
    generate
        for (i = 0; i < NUM_MASTERS; i++) begin : gen_master_dat
            always_comb begin
                masters[i].dat_i = '0;
                masters[i].ack = 1'b0;
                masters[i].err = 1'b0;
                for (int j = 0; j < NUM_SLAVES; j++) begin
                    if (slave_select[j] && grant[i]) begin
                        masters[i].dat_i = slaves[j].dat_o;
                        masters[i].ack = slaves[j].ack;
                        masters[i].err = slaves[j].err;
                    end
                end
            end
        end
    endgenerate

endmodule
