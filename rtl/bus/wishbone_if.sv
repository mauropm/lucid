// Wishbone B4 Interface Definition

interface wishbone_interface #(
    parameter int AW = 32,
    parameter int DW = 32
) ();
    // Master signals
    logic        cyc;
    logic        stb;
    logic        we;
    logic [AW-1:0] adr;
    logic [DW-1:0] dat_o;  // master → slave
    logic [DW/8-1:0] sel;

    // Slave signals
    logic [DW-1:0] dat_i;  // slave → master
    logic        ack;
    logic        err;

    modport master (
        output cyc, stb, we, adr, dat_o, sel,
        input  dat_i, ack, err
    );

    modport slave (
        input  cyc, stb, we, adr, dat_i, sel,
        output dat_o, ack, err
    );

endinterface
