`default_nettype none

module wishbone_bus (
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
    assign slave_sel[0] = (m_adr[31:12] == 20'h00000);
    assign slave_sel[1] = (m_adr[31:12] == 20'h00001);
    assign slave_sel[2] = (m_adr[31:12] == 20'h00002);

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

    // H5: Default slave returns all-ones data and registered ack for unmapped addresses
    logic default_ack;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            default_ack <= 1'b0;
        else
            default_ack <= m_stb && m_cyc && !any_sel;
    end

    assign m_dat_r = slave_sel[0] ? s0_dat_r :
                     slave_sel[1] ? s1_dat_r :
                     slave_sel[2] ? s2_dat_r : 32'hFFFF_FFFF;
    assign m_ack   = any_sel ? (slave_sel[0] ? s0_ack :
                                slave_sel[1] ? s1_ack :
                                               s2_ack) :
                               default_ack;

endmodule

`default_nettype wire
