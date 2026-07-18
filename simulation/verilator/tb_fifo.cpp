// Lucid FIFO Testbench (Verilator C++)

#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vfifo.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vfifo* dut = new Vfifo;

    VerilatedVcdC* trace = new VerilatedVcdC;
    dut->trace(trace, 99);
    trace->open("build/sim/tb_fifo_verilator.vcd");

    // Reset
    dut->reset_n = 0;
    dut->clk = 0;
    dut->wr_en = 0;
    dut->rd_en = 0;
    dut->eval();
    dut->clk = 1;
    dut->eval();
    dut->reset_n = 1;

    // Write one word
    dut->clk = 0;
    dut->wr_data = 0xCAFEBABE;
    dut->wr_en = 1;
    dut->eval();
    dut->clk = 1;
    dut->eval();

    dut->clk = 0;
    dut->wr_en = 0;
    dut->eval();
    dut->clk = 1;
    dut->eval();

    // Read one word
    dut->clk = 0;
    dut->rd_en = 1;
    dut->eval();
    dut->clk = 1;
    dut->eval();

    dut->clk = 0;
    dut->rd_en = 0;
    dut->eval();

    // Check result
    if (dut->rd_data == 0xCAFEBABE) {
        printf("PASS: FIFO readback correct\n");
    } else {
        printf("FAIL: expected 0xCAFEBABE, got 0x%08X\n", dut->rd_data);
        return 1;
    }

    trace->close();
    delete dut;
    return 0;
}
