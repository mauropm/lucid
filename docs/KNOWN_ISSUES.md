# Known Issues

## Graph Scheduler Parallel Dependency Bug (Medium Confidence)

The `graph_scheduler_parallel` module (Phase 7) computes incorrect results for dependency chains. Single-node and independent-node tests pass, but chained computations (e.g., LIT→ADD→MUL) return 0 for intermediate results.

**Root Cause:** The `backup_valid` flag and UPDATE state interaction cause `upd_src` to point to the wrong node when processing the second popped node's dependents.

**Workaround:** Use `graph_scheduler.sv` (Phase 3) for any graph with non-trivial dependencies. `graph_scheduler_parallel` is correct for independent nodes and concurrency counting.

**Files:** `rtl/scheduler/graph_scheduler_parallel.sv`

## Heap BRAM Address Wrapping (High Confidence)

The heap controller's single-port BRAM (`heap_controller.sv`) has 1024 entries. When management RAM at 0x10000 is accessed, the word address wraps at 4 KB boundaries.

**Impact:** Only affects the standalone CPU testbench (tb_platform uses separate BRAM instances per slave, avoiding the issue). The real system has independent boot_rom and mgmt_ram instances.

**Workaround:** Already working — each Wishbone slave has its own BRAM instance.

**Files:** `rtl/heap/heap_controller.sv`

## Icarus SystemVerilion Limitations (High Confidence)

Icarus Verilog 13.0 does not support:

- `automatic` variable declarations inside `always_ff`, `initial`, or task bodies
- String module parameters (`parameter string X = ""`)
- `break` in `for` loops inside `always_comb`
- `unique case` / `priority case` (ignores qualifier)
- Array concatenation in port connections
- Variable-indexed part-selects in `always_comb` (generates incorrect sensitivity lists)

**Workaround:** All RTL is written to avoid these constructs. Use `make sim-icarus` to verify compatibility.

## Yosys Synthesis Limitations (High Confidence)

Yosys 0.67 does not support:

- String parameters (use integer parameters instead)
- `always_comb` with complex assignments
- Some SystemVerilog 2005+ constructs

**Workaround:** Synthesis script re-reads a subset of RTL files, excluding files with unsupported constructs. String parameters were removed from `bram.sv`.

## GC Mark Stack Overflow (Low Confidence)

The GC controller has a 64-entry hardware mark stack. Deeply nested object graphs could overflow.

**Impact:** Objects beyond stack depth are not marked and would be incorrectly collected.

**Files:** `rtl/gc/gc_controller.sv`
**Stack depth:** 64 entries (configurable via parameter)

## No Interrupt Controller (High Confidence)

The UART uses polling. This is acceptable for the management CPU role but prevents efficient I/O.

**Files:** `rtl/peripherals/uart.sv`

## RV32IM Single-Cycle M Extension (Medium Confidence)

The MUL/DIV operations are single-cycle combinational, which may limit timing closure at 100 MHz. A multi-cycle implementation would be more area-efficient.

**Files:** `rtl/cpu/rv32im_core.sv`

## Waveform Viewer Path (High Confidence)

GTKWave on macOS may have a startup delay that causes the environment check to time out. The tool itself works when launched directly.

## Missing Firmware (High Confidence)

The `firmware/` directory exists but contains no code. The Scheme reader/compiler runs on the development host (Python), not on the RV32IM CPU. Self-hosting requires a C port.
