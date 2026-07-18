`default_nettype none

module wishbone_bus #(
    parameter int NUM_SLAVES = 3
) (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        m_cyc,
    input  logic        m_stb,
    input  logic        m_we,
    input  logic [31:0] m_adr,
    input  logic [31:0] m_dat_w,
    input  logic [3:0]  m_sel,
    output logic [31:0] m_dat_r,
    output logic        m_ack,

    output logic        s0_cyc, s0_stb,
    output logic [31:0] s0_adr,
    input  logic [31:0] s0_dat_r,
    input  logic        s0_ack,

    output logic        s1_cyc, s1_stb, s1_we,
    output logic [31:0] s1_adr, s1_dat_w,
    output logic [3:0]  s1_sel,
    input  logic [31:0] s1_dat_r,
    input  logic        s1_ack,

    output logic        s2_cyc, s2_stb, s2_we,
    output logic [31:0] s2_adr, s2_dat_w,
    output logic [3:0]  s2_sel,
    input  logic [31:0] s2_dat_r,
    input  logic        s2_ack
);

    wire [2:0] slave_sel;
    assign slave_sel[0] = (m_adr[31:16] == 16'h0000);
    assign slave_sel[1] = (m_adr[31:16] == 16'h0001);
    assign slave_sel[2] = (m_adr[31:16] == 16'h0002);

    wire any_sel = |slave_sel;

    assign s0_cyc = m_cyc && slave_sel[0];
    assign s0_stb = m_stb && slave_sel[0];
    assign s0_adr = m_adr;

    assign s1_cyc   = m_cyc && slave_sel[1];
    assign s1_stb   = m_stb && slave_sel[1];
    assign s1_we    = m_we;
    assign s1_adr   = m_adr;
    assign s1_dat_w = m_dat_w;
    assign s1_sel   = m_sel;

    assign s2_cyc   = m_cyc && slave_sel[2];
    assign s2_stb   = m_stb && slave_sel[2];
    assign s2_we    = m_we;
    assign s2_adr   = m_adr;
    assign s2_dat_w = m_dat_w;
    assign s2_sel   = m_sel;

    // H5: Default slave returns all-ones data and immediate ack for unmapped addresses
    assign m_dat_r = slave_sel[0] ? s0_dat_r :
                     slave_sel[1] ? s1_dat_r :
                     slave_sel[2] ? s2_dat_r : 32'hFFFF_FFFF;
    assign m_ack   = any_sel ? (slave_sel[0] ? s0_ack :
                                slave_sel[1] ? s1_ack :
                                               s2_ack) :
                               (m_stb && m_cyc);

endmodule

`default_nettype wire
