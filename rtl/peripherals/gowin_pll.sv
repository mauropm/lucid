`default_nettype none

(* blackbox *)
module rPLL (
    input  logic clkin,
    output logic clkout,
    output logic lock
);
    parameter FCLKIN     = "27";
    parameter IDIV_SEL   = 2;
    parameter FBDIV_SEL  = 40;
    parameter ODIV_SEL   = 5;
    parameter DYN_SDIV_SEL = 2;
    parameter FILTER     = "1";

`ifndef SYNTHESIS
    real half_period_ns;

    initial begin
        half_period_ns = (1000.0 / 27.0) * IDIV_SEL * ODIV_SEL / (2.0 * FBDIV_SEL);
        clkout = 1'b0;
        lock = 1'b0;
        #100;
        lock = 1'b1;
        forever #(half_period_ns) clkout = ~clkout;
    end
`endif

endmodule

`default_nettype wire
