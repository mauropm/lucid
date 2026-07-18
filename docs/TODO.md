# TODO

## High Priority

- [ ] **Fix parallel scheduler chain dependency** — `graph_scheduler_parallel` computes incorrect results when nodes have input dependencies. The backup_valid/UPDATE interaction is wrong. (Confidence: Medium)
- [ ] **Port Scheme frontend to C** — The Python compiler must be ported to C for the RV32IM management CPU firmware. This enables a self-hosted REPL on the FPGA. (Confidence: High)
- [ ] **Create hardware test** — Program Tang Nano 20K, verify UART REPL output. Requires Gowin EDA or nextpnr-gowin + OpenFPGALoader. (Confidence: Medium)

## Medium Priority

- [ ] **Add Verilator C++ testbenches** — Currently only Icarus testbenches exist. Verilator is faster and supports more SystemVerilog. (Confidence: High)
- [ ] **Add proper error handling to Scheme compiler** — Unbound variables, syntax errors, type errors should produce useful messages. (Confidence: High)
- [ ] **Add `let*`, `letrec`, `do`, `map` to Scheme compiler** — These are essential for realistic Scheme programs. (Confidence: Medium)
- [ ] **Complete GC sweep phase** — `gc_controller.sv` sweep phase is a stub (scans but doesn't compact). Implement proper free list compaction. (Confidence: Medium)

## Low Priority

- [ ] **Add interrupt controller** — For non-polled UART I/O. (Confidence: High)
- [ ] **Implement round-robin router arbitration** — Replace fixed priority in `message_router.sv`. (Confidence: Medium)
- [ ] **Add pipelined mode to Wishbone bus** — For burst transfers to graph memory. (Confidence: Low)
- [ ] **Formal verification** — Add SystemVerilog assertions to critical modules. (Confidence: Low)
- [ ] **Cocotb testbenches** — Python-based cosimulation for more complex scenarios. (Confidence: Medium)
- [ ] **Performance benchmarks** — Measure cycles per node, scheduler throughput, heap utilization. (Confidence: High)
