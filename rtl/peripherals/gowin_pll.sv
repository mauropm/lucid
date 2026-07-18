// Gowin rPLL Primitive (blackbox for Yosys)
// Actual instantiation provided by Gowin EDA tool.

(* blackbox *)
module rPLL (
    input  logic clkin,
    output logic clkout,
    output logic lock
);
    parameter FCLKIN = "27";
    parameter DIV_F = "100";
    parameter DIV_Q = "5";
    parameter FILTER = "1";
endmodule
