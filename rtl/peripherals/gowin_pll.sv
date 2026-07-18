`default_nettype none

// H14: Gowin rPLL primitive blackbox with correct parameters
// For 27 MHz → 100 MHz: VCO = 27 * FBDIV / IDIV = 540 MHz, ODIV = 540/100 ≈ 5.4
// Legal Gowin config: IDIV_SEL=2, FBDIV_SEL=40, ODIV_SEL=5 → VCO=540 MHz, OUT=108 MHz
// Or: IDIV_SEL=3, FBDIV_SEL=44, ODIV_SEL=4 → VCO=396 MHz, OUT=99 MHz
// Closest practical: IDIV=1, FB=15, ODIV=4 → VCO=405, OUT=101.25

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
endmodule

`default_nettype wire
