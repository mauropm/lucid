# Lucid Session State

**Session Date:** 2026-07-17 — 2026-07-18
**Repository:** `/Users/mauro/Documents/Code/lucid`
**Last Commit:** `1a4c6ae` (Phase 10 complete)

---

## Project Overview

Lucid is an open hardware Functional Processing Unit (FPU) — a heterogeneous computing architecture for direct execution of functional programming languages. It uses a graph-based intermediate representation (Lucid IR) where nodes are computations and edges are data dependencies. The architecture has two processors: an RV32IM Management CPU (boot, UART, REPL, compiler frontends) and a custom Lucid FPU (graph execution, heap, closures, GC).

### Current Status: All 10 Phases Complete

| Phase | Focus | Status |
|-------|-------|--------|
| 0 | Foundation (docs, CI, tooling) | ✓ |
| 1 | Platform (RV32IM CPU, Wishbone bus, UART) | ✓ |
| 2 | Message system (FIFOs, router, dispatcher) | ✓ |
| 3 | Graph IR execution (scheduler, dependency tracking) | ✓ |
| 4 | Primitive execution (message-based dispatch) | ✓ |
| 5 | Heap, closures, environments | ✓ |
| 6 | Scheme frontend (reader, compiler, end-to-end) | ✓ |
| 7 | Parallel scheduling (dual-issue, concurrency tracking) | ✓ |
| 8 | Garbage collection (mark-sweep engine) | ✓ |
| 9 | Optimization (synthesis, Tang Nano 20K top) | ✓ |
| 10 | Language expansion (Racket, CL, OCaml, Haskell) | ✓ |

### Main Design Philosophy

- Architecture before RTL. Documentation before code. Verification before optimization.
- Everything communicates via messages (FIFOs). No module directly accesses another's state.
- The heart of Lucid is Lucid IR, not any specific language. Scheme is the first frontend, not the only one.
- The Management CPU never evaluates functional programs. The FPU never parses source code.
- Designed for long-term evolution (10-year horizon). Tang Nano 20K is the first target, not the limit.

---

## Current Objective

This session built all 10 phases of the Lucid architecture from scratch. The project evolved through:

1. **Phase 0:** Repository structure, architecture documents, build system, CI, ADRs
2. **Phase 1:** RV32IM CPU, Wishbone bus, UART, boot ROM, management RAM
3. **Phase 2:** FIFO, message router, message dispatcher, protocol
4. **Phase 3:** Graph scheduler with FSM, dependency tracking, ready queue
5. **Phase 4:** Primitive execution unit, message-based dispatch
6. **Phase 5:** Heap controller, closure unit, environment unit
7. **Phase 6:** Scheme reader, compiler to Lucid IR, end-to-end test
8. **Phase 7:** Parallel scheduler with dual-pop queue
9. **Phase 8:** Mark-sweep garbage collector
10. **Phase 9:** Yosys synthesis, timing constraints, Tang Nano top-level
11. **Phase 10:** Racket, Common Lisp, OCaml, Haskell frontends

The session completed all planned phases. What remains is refinement, hardware bringup, and feature additions.

---

## Session Summary

### Files Created

```
docs/architecture/platform-design.md
docs/architecture/message-system-design.md
docs/architecture/graph-execution-design.md
docs/architecture/primitive-exec-design.md
docs/architecture/heap-closures-design.md
docs/architecture/scheme-frontend-design.md
docs/architecture/parallel-scheduling-design.md
docs/architecture/gc-design.md
docs/architecture/optimization-design.md
docs/architecture/language-expansion-design.md
docs/PROJECT.md
docs/ARCHITECTURE.md
docs/DECISIONS.md
docs/ROADMAP.md (updated)
docs/SESSION_STATE.md
docs/TODO.md
docs/KNOWN_ISSUES.md

rtl/bus/wishbone_bus.sv (rewritten)
rtl/bus/wishbone_if.sv (deleted)
rtl/cpu/rv32im_core.sv
rtl/cpu/boot_rom.sv
rtl/cpu/mgmt_ram.sv
rtl/messages/fifo.sv
rtl/messages/message_dispatcher.sv
rtl/messages/message_router.sv
rtl/messages/message_types.sv
rtl/peripherals/uart.sv
rtl/peripherals/bram.sv
rtl/peripherals/gowin_pll.sv
rtl/scheduler/graph_scheduler.sv
rtl/scheduler/graph_scheduler_fp.sv
rtl/scheduler/graph_scheduler_parallel.sv
rtl/scheduler/graph_memory.sv
rtl/heap/heap_controller.sv
rtl/heap/heap_controller_gc.sv
rtl/heap/closure_unit.sv
rtl/heap/environment_unit.sv
rtl/gc/gc_controller.sv
rtl/primitives/primitive_exec.sv
rtl/top/lucid_top.sv

frontend/scheme/reader.py
frontend/scheme/compiler.py
frontend/racket/__init__.py
frontend/clisp/__init__.py
frontend/ocaml/__init__.py
frontend/haskell/__init__.py

simulation/icarus/tb_fifo.sv
simulation/icarus/tb_message_dispatcher.sv
simulation/icarus/tb_message_system.sv
simulation/icarus/tb_platform.sv
simulation/icarus/tb_graph_scheduler.sv
simulation/icarus/tb_primitive_exec.sv
simulation/icarus/tb_heap.sv
simulation/icarus/tb_scheme.sv
simulation/icarus/tb_parallel.sv
simulation/icarus/tb_gc.sv
simulation/icarus/boot_rom.hex

tools/graph_viz.py
tools/graph_examples.py
tools/gen_scheme_test.py
tools/test_multilang.py

scripts/check_env.py
scripts/pre-commit.sh
scripts/syn_lucid.tcl
scripts/lucid.sdc

Makefile (updated with synth targets)
CMakeLists.txt
```

### Major Refactors

1. **wishbone_bus.sv** — Replaced `always_comb` with `assign` statements for Icarus compatibility. Changed from parameterized array ports to fixed 3-slave named ports.

2. **fifo.sv** — Added registered read data output (`rd_data_q`). Fixed full/empty detection using extra pointer bit.

3. **message_router.sv** — Iterated through 5+ designs: `always_comb` loops (Icarus internal error) → fixed-priority with generate → combinational crossbar with registered outputs → output register pipeline.

4. **graph_scheduler.sv** — Added IF and comparison opcodes (0x15–0x19, 0x30). Extended operand storage to 3 inputs.

5. **graph_scheduler_fp.sv** — New module (Phase 4). Adds message-based dispatch to primitive execution unit.

6. **graph_scheduler_parallel.sv** — New module (Phase 7). Dual-pop queue, backup register, concurrency tracking.

7. **bram.sv** — Removed string `HEX_FILE` parameter (Yosys compatibility). Initialization via `$readmemh` only in simulation.

### APIs Added

- **Message protocol:** EXEC_PRIM (3-word), PRIM_RESULT (2-word), header format `{DEST(8), SRC(8), TYPE(8), FLAGS(8)}`
- **Register interfaces:** Scheduler control registers, heap status, GC control
- **Python APIs:** `compile_scheme()`, `compile_racket()`, `compile_cl()`, `compile_ocaml()`, `compile_haskell()` — all return `{writes, node_count, root_id}`

### Interfaces Changed

- `wishbone_bus` — from array ports to fixed `s0_*`, `s1_*`, `s2_*` ports
- `message_dispatcher` — from simple `msg_in_data/msg_out_data` to Wishbone slave + module TX/RX ports
- `bram` — removed `HEX_FILE` parameter

---

## Technical Decisions

### 1. Two-Processor Architecture (ADR-001)
- **Decision:** Separate RV32IM CPU + custom Lucid FPU
- **Reason:** Clean separation of system tasks (boot, UART, debug) from functional execution
- **Alternatives:** Single processor with functional extensions, pure FPU with software emulation
- **Tradeoffs:** More FPGA resources, inter-processor communication latency

### 2. Message Passing Between FPU Modules (ADR-002)
- **Decision:** All FPU modules communicate via FIFO-based message passing
- **Reason:** Decoupling, independent verification, natural backpressure
- **Alternatives:** Shared Wishbone bus, register-based MMIO, direct wiring
- **Tradeoffs:** Message serialization latency, FIFO depth sizing

### 3. Graph-Based IR (ADR-003)
- **Decision:** Lucid IR is a dependency graph, not bytecode or AST
- **Reason:** Exposes parallelism naturally, maps directly to scheduler
- **Alternatives:** Bytecode VM, AST tree-walking, SSA form, combinators
- **Tradeoffs:** Graph size limits on small FPGAs, debugging visualization needed

### 4. Assign-Only Wishbone Bus
- **Decision:** Bus uses only `assign` statements, no `always_comb`
- **Reason:** Icarus Verilog doesn't support `always_comb` with certain array indexing
- **Alternatives:** Keep `always_comb` and use Verilator only
- **Tradeoffs:** More verbose but compatible with all simulators

### 5. Fixed-Priority Router Arbitration
- **Decision:** Message router uses fixed priority (lower input index wins)
- **Reason:** Icarus doesn't support `for` loops with `break` in `always_comb`
- **Alternatives:** Round-robin with rotate-and-priority-encode
- **Tradeoffs:** Less fair, but simpler and correct for verification

### 6. Inline Primitive Computation (Phase 3) vs Message Dispatch (Phase 4+)
- **Decision:** Phase 3 computes inline; Phase 4+ dispatches via messages
- **Reason:** Phase 3 needed to establish correctness. Phase 4 added the message protocol.
- **Alternatives:** Only message dispatch from the start
- **Tradeoffs:** Two scheduler versions to maintain, but allows performance comparison

### 7. Sequential Heap Allocation with GC-Aware Mode
- **Decision:** Simple bump allocator with GC integration (block during GC, OOM auto-triggers)
- **Reason:** Minimal hardware for Phase 5; GC integration doesn't complicate the allocator
- **Alternatives:** Free-list allocator, slab allocator
- **Tradeoffs:** Fragmentation possible with mark-sweep, but acceptable for Phase 8

### 8. Python Frontends (not C/assembly)
- **Decision:** Language frontends in Python, not C for the RV32IM
- **Reason:** Faster prototyping, readable code, no cross-compilation needed
- **Alternatives:** C firmware running on the RV32IM CPU
- **Tradeoffs:** Frontends run on the development host, not on the FPGA itself.
  Port to C is a future task.

### 9. Yosys for Synthesis (not Gowin EDA)
- **Decision:** Use Yosys + nextpnr-gowin for open-source synthesis flow
- **Reason:** Reproducible builds, macOS compatibility, open-source philosophy
- **Alternatives:** Gowin EDA (Windows only)
- **Tradeoffs:** Yosys has limited Gowin support; Gowin EDA needed for bitstream

### 10. No `automatic int` Inside `always_ff`
- **Decision:** Declare temporary variables at module level, not automatic inside blocks
- **Reason:** Icarus Verilog doesn't support automatic variables in procedural blocks
- **Alternatives:** Use Verilator instead of Icarus
- **Tradeoffs:** Module-level variables persist between clock cycles. Must be assigned before use.

---

## Important Context

### Architectural Constraints

- **Tang Nano 20K limits:** 20,736 LUT4, 72 BRAM (9K each), 32 DSP. All RTL must fit.
- **100 MHz target:** PLL from 27 MHz external oscillator.
- **Two clock domains:** sys_clk (100 MHz) and UART baud clock (derived).
- **Synthesis estimate:** ~500 cells (Yosys generic), ~3,000–4,000 LUT4 estimated after ABC mapping.

### Hardware Limitations

- **No cache or MMU:** The Management CPU doesn't need them (control-only, low performance).
- **No interrupt controller:** Simple polling for UART.
- **Single-port BRAM:** Graph memory and heap are single-port (no simultaneous read/write).
- **No external DRAM:** Tang Nano 20K has optional 64 MB SDRAM; currently only on-chip BRAM is used.

### Compiler Assumptions

- All frontends produce the same node format: `{STATE, OPCODE, NUM_INPUTS, READY_INPUTS, FLAGS}` header, imm0, imm1, result, dep_mask.
- Node IDs are integers 0..N-1. dep_mask is a bitmask of dependent nodes (up to 32).
- Literals (LIT_INT, LIT_BOOL) have `num_inputs=0` and are immediately ready.
- Non-literals wait until `ready_inputs >= num_inputs`.

### FPGA Tools

- **Verilator 5.050** and **Icarus 13.0** both work (some SystemVerilog limitations in Icarus).
- **Yosys 0.67** works with `-sv` flag. Avoid string parameters, `automatic` in procedural blocks, and complex array concatenation.
- **Gowin rPLL** needs a blackbox module for Yosys; actual primitive is in the Gowin library.

### Language Semantics

- The Scheme reader produces Python-native AST (lists, ints, bools, `Symbol` for identifiers).
- Python booleans must be checked before Python ints (`isinstance(True, int)` is True).
- The IRCompiler maintains an environment stack for lexical scoping.
- The `Symbol` class extends `str` for backward compatibility with string-based operations.

---

## Current Problems

### Known Issues

| # | Issue | File | Severity | Status |
|---|-------|------|----------|--------|
| 1 | Parallel scheduler chain dependency fails | `graph_scheduler_parallel.sv` | Medium | Investigated |
| 2 | Icarus `automatic int` in procedural blocks | Various | Low | Workaround applied |
| 3 | Yosys string parameters unsupported | Various | Low | Workaround applied |
| 4 | Message router arbitration needs round-robin | `message_router.sv` | Low | Fixed-priority works |
| 5 | Heap BRAM address wraps at 4 KB boundary | `heap_controller.sv` | Medium | Documented |
| 6 | No interrupt support for UART | `uart.sv` | Low | Phase 1 limitation |
| 7 | RV32IM MUL/DIV multi-cycle | `rv32im_core.sv` | Low | Single-cycle now |
| 8 | Scheme reader strings not fully tested | `reader.py` | Low | Basic tests pass |
| 9 | GC mark stack depth limited to 64 | `gc_controller.sv` | Low | Adequate for now |
| 10 | No C frontend firmware for RV32IM | `firmware/` | High | Future work |

### Issue Details

**Issue 1: Parallel scheduler chain dependency fails**
- **Description:** The `graph_scheduler_parallel` module's S_EXEC → S_BACKUP → S_UPD → S_EXEC loop works for independent literals (perf_conc=2) but fails for dependency chains (ADD result = 0).
- **Root cause:** Interaction between the backup_valid flag and the UPDATE state causes incorrect operand propagation. The second popped node's dependents are processed using the wrong `upd_src` value.
- **Workaround:** Use Phase 3 scheduler (`graph_scheduler`) for chain dependencies. The parallel scheduler is correct for independent subgraphs.
- **Confidence:** Medium

**Issue 5: Heap BRAM address wraps at 4 KB boundary**
- **Description:** The heap controller's BRAM has 1024 entries (10-bit address). The management RAM is at 0x10000, which maps to word address 0x4000 — out of bounds. In simulation, this silently wraps.
- **Workaround:** Each BRAM instance is independent. Boot ROM and mgmt RAM use separate BRAM instances, so they don't interfere. The issue only affects the CPU standalone testbench.
- **Confidence:** High

### TODOs

- [ ] Port Scheme reader/compiler from Python to C for RV32IM firmware
- [ ] Add Verilator C++ testbenches for faster simulation
- [ ] Run full Yosys synthesis with ABC mapping to get LUT counts
- [ ] Create Gowin EDA project for bitstream generation
- [ ] Add hardware UART loopback test on Tang Nano 20K
- [ ] Implement proper error handling in Scheme compiler
- [ ] Add interrupt controller for UART
- [ ] Implement heap compaction in sweep phase
- [ ] Add `let*`, `letrec`, `do`, `map` to Scheme compiler
- [ ] Write comprehensive documentation for the benchmark suite

---

## Next Steps

### Priority 1: Hardware Bringup (High)
- **Objective:** Program Tang Nano 20K, verify UART output
- **Files:** `rtl/top/lucid_top.sv`, `scripts/syn_lucid.tcl`
- **Complexity:** Medium
- **Dependencies:** Gowin EDA or nextpnr-gowin, OpenFPGALoader

### Priority 2: Fix Parallel Scheduler (High)
- **Objective:** Fix chain dependency computation in `graph_scheduler_parallel`
- **Files:** `rtl/scheduler/graph_scheduler_parallel.sv`
- **Complexity:** Medium
- **Dependencies:** None (debugging only)

### Priority 3: C Firmware Port (High)
- **Objective:** Port Scheme reader/compiler to C for RV32IM
- **Files:** `firmware/` (new directory)
- **Complexity:** Very High
- **Dependencies:** RISC-V GCC toolchain

### Priority 4: Verilator Testbenches (Medium)
- **Objective:** Add C++ testbenches for faster simulation
- **Files:** `simulation/verilator/`
- **Complexity:** Medium
- **Dependencies:** Verilator (installed)

### Priority 5: Performance Analysis (Medium)
- **Objective:** Benchmark graph execution speed, identify bottlenecks
- **Files:** `benchmarks/` (new), `rtl/scheduler/graph_scheduler.sv`
- **Complexity:** Low
- **Dependencies:** Working simulation

### Priority 6: VCD-Based Debugging (Medium)
- **Objective:** Create GTKWave save files for common test cases
- **Files:** `tools/` (new scripts)
- **Complexity:** Low
- **Dependencies:** GTKWave (installed)

### Priority 7: Continuation Support (Low)
- **Objective:** Add `call/cc` support to the FPU
- **Files:** `rtl/scheduler/`, `rtl/heap/`
- **Complexity:** Very High
- **Dependencies:** Phase 6 (Scheme frontend) complete

### Priority 8: Documentation (Ongoing)
- **Objective:** Keep docs in sync with implementation
- **Files:** `docs/`
- **Complexity:** Low
- **Dependencies:** None

---

## Testing Status

### Passing Tests (10/10)

| Testbench | Command | Tests | Runtime |
|-----------|---------|-------|---------|
| tb_fifo | `make sim-icarus` | 5 | Fast |
| tb_message_dispatcher | `make sim-icarus` | 2 | Fast |
| tb_message_system | `make sim-icarus` | 5 | Moderate |
| tb_platform | `make sim-icarus` | 7 register checks | Moderate |
| tb_graph_scheduler | `make sim-icarus` | Result verification | Moderate |
| tb_primitive_exec | `make sim-icarus` | 3 operations | Slow |
| tb_heap | `make sim-icarus` | 6 tests | Moderate |
| tb_scheme | `make sim-icarus` | 4 expressions | Moderate |
| tb_parallel | `make sim-icarus` | 2+ tests (concurrency) | Moderate |
| tb_gc | `make sim-icarus` | 6 tests | Slow |

### Failing Tests

None. All 10 testbenches pass.

### Missing Tests

- **Verilator C++ testbenches:** Only Icarus testbenches exist. Verilator testbenches would be faster.
- **Randomized testing:** No fuzzing or random instruction sequences.
- **Formal verification:** No assertions beyond basic `assert` in testbenches.
- **Hardware-in-loop:** No Tang Nano 20K tests (no board available?).
- **Multi-cycle MUL/DIV:** No tests for multi-cycle M extension operations.
- **GC mark/sweep correctness:** No test for complex object graphs with cycles.

### Manual Verification

- Python multi-language test: `python3 tools/test_multilang.py` — verifies all 5 frontends produce consistent IR
- Environment check: `python3 scripts/check_env.py` — Verilator, Icarus, Make, Python3 all found (optional tools: GTKWave, Yosys)

---

## Build Instructions

### Prerequisites

```bash
# Install tools (macOS)
brew install verilator icarus-verilog gtkwave yosys

# Python packages
pip3 install cocotb pytest

# Verify environment
python3 scripts/check_env.py
```

### Build and Run

```bash
# Show all targets
make info

# Run all Icarus Verilog simulations
make sim-icarus

# Run a specific testbench
mkdir -p build/sim
iverilog -g2012 -o build/sim/tb_fifo.vvp rtl/messages/fifo.sv simulation/icarus/tb_fifo.sv
vvp build/sim/tb_fifo.vvp

# View waveforms
gtkwave build/sim/tb_fifo.vcd

# Run synthesis (Yosys required)
make synth
make synth-stats

# Python multi-language test
python3 tools/test_multilang.py

# Generate IR for a Scheme expression
echo '(+ 2 (* 3 4))' | python3 frontend/scheme/compiler.py

# Generate Verilog test data from Scheme
python3 tools/gen_scheme_test.py '(+ 2 (* 3 4))'
```

### Important Build Notes

- Icarus needs `-g2012` flag for SystemVerilog support
- Verilator is installed but no C++ testbenches are written yet
- The Makefile's `sim-icarus` target passes all RTL files to each testbench (may compile unused modules)
- VCD files are written to `build/sim/`
- Yosys synthesis excludes some RTL files (heap, GC, message-only modules that are not in the top-level integration)

---

## Repository Map

```
lucid/
├── docs/                      # All documentation
│   ├── adr/                   # Architecture Decision Records
│   ├── architecture/          # Phase design documents
│   ├── PROJECT.md             # Vision and goals
│   ├── ARCHITECTURE.md        # System overview
│   ├── DECISIONS.md           # ADR index
│   ├── ROADMAP.md             # Implementation status
│   ├── SESSION_STATE.md       # This file
│   ├── TODO.md                # Actionable tasks
│   ├── KNOWN_ISSUES.md        # Bugs and limitations
│   ├── CONTRIBUTING.md        # Contribution guide
│   └── roadmap.md             # Original roadmap (deprecated by ROADMAP.md)
│
├── rtl/                       # All RTL source code
│   ├── bus/wishbone_bus.sv    # Wishbone bus matrix
│   ├── cpu/
│   │   ├── rv32im_core.sv     # RV32IM CPU
│   │   ├── boot_rom.sv        # Boot ROM
│   │   └── mgmt_ram.sv        # Management RAM
│   ├── messages/
│   │   ├── fifo.sv            # Parameterized FIFO
│   │   ├── message_dispatcher.sv
│   │   ├── message_router.sv   # Crossbar switch
│   │   └── message_types.sv   # Type definitions
│   ├── peripherals/
│   │   ├── uart.sv            # UART (8N1, 115200)
│   │   ├── bram.sv            # Generic BRAM
│   │   └── gowin_pll.sv      # Gowin PLL blackbox
│   ├── scheduler/
│   │   ├── graph_scheduler.sv         # Phase 3 (inline)
│   │   ├── graph_scheduler_fp.sv      # Phase 4 (message dispatch)
│   │   ├── graph_scheduler_parallel.sv # Phase 7 (dual-issue)
│   │   └── graph_memory.sv            # Node storage
│   ├── heap/
│   │   ├── heap_controller.sv         # Basic allocator
│   │   ├── heap_controller_gc.sv      # GC-aware allocator
│   │   ├── closure_unit.sv            # Closure creation
│   │   └── environment_unit.sv        # Environment management
│   ├── gc/gc_controller.sv   # Mark-sweep GC
│   ├── primitives/primitive_exec.sv   # Execution unit
│   └── top/lucid_top.sv      # Tang Nano 20K top-level
│
├── frontend/                  # Language frontends (Python)
│   ├── scheme/reader.py       # Tokenizer + s-expression parser
│   ├── scheme/compiler.py     # Scheme → Lucid IR compiler
│   ├── racket/__init__.py     # Racket frontend
│   ├── clisp/__init__.py      # Common Lisp frontend
│   ├── ocaml/__init__.py      # OCaml-like frontend
│   └── haskell/__init__.py    # Haskell-like frontend
│
├── simulation/icarus/         # Icarus Verilog testbenches
│   ├── tb_fifo.sv
│   ├── tb_message_dispatcher.sv
│   ├── tb_message_system.sv
│   ├── tb_platform.sv
│   ├── tb_graph_scheduler.sv
│   ├── tb_primitive_exec.sv
│   ├── tb_heap.sv
│   ├── tb_scheme.sv
│   ├── tb_parallel.sv
│   ├── tb_gc.sv
│   └── boot_rom.hex           # Test program for CPU
│
├── simulation/verilator/      # Verilator C++ testbenches (placeholders)
│   └── tb_fifo.cpp
│
├── tools/                     # Development tools
│   ├── graph_viz.py           # IR graph → DOT
│   ├── graph_examples.py      # Example IR graphs
│   ├── gen_scheme_test.py     # Scheme → Verilog test data
│   └── test_multilang.py     # Multi-language test
│
├── scripts/                   # Build and utility scripts
│   ├── check_env.py           # Environment verification
│   ├── pre-commit.sh          # Git pre-commit hook
│   ├── syn_lucid.tcl          # Yosys synthesis script
│   └── lucid.sdc              # Timing constraints
│
├── firmware/                  # Future: RV32IM firmware in C
├── examples/                  # Example programs
├── benchmarks/                # Benchmarks
├── verification/              # Verification scripts
│
├── Makefile                   # Build system
├── CMakeLists.txt             # CMake (for Verilator)
└── .github/workflows/ci.yml  # CI configuration
```

---

## Developer Notes

### Why Certain Implementations Were Chosen

1. **3-state CPU:** The RV32IM uses a 3-state FSM (fetch, execute, load) instead of a pipeline. This was chosen for simplicity and correctness. The CPU is not a performance bottleneck for the management role. A pipeline can be added later if needed.

2. **Assign-only Wishbone bus:** Icarus Verilog has poor support for `always_comb` with variable-indexed array access and `unique case`. The bus was rewritten from `always_comb` to pure `assign` statements, which eliminated simulation hangs.

3. **Fixed-priority arbitration:** The message router originally attempted round-robin arbitration using rotate-and-priority-encode. Icarus doesn't support `for` loops with `break` in `always_comb`. Fixed priority was chosen for correctness. Round-robin can be added later with a different implementation strategy.

4. **Registered FIFO read data:** The FIFO uses a registered `rd_data_q` output. This avoids combinational read timing issues and simplifies the interface. It adds 1 cycle of read latency, which is fine for the message passing use case.

5. **No default assignments for handshake signals:** A subtle but critical fix: default assignments like `msg_rx_ready <= 1'b0;` cause 1-cycle delays in handshake protocols because the NB default competes with the state-specific NB assignment. Removing the default and only assigning in specific states fixed protocol timing.

6. **Python frontends over C:** The Scheme reader/compiler is in Python for prototyping speed. The Racket, CL, OCaml, and Haskell frontends reuse the same IRCompiler backend, demonstrating language independence. Porting to C for the RV32IM is a separate task.

### Failed Experiments

1. **Round-robin in always_comb:** `for` loop with `break` inside `always_comb` → "NetProc::nex_input not implemented" in Icarus. The rotate-and-priority-encode approach also failed due to `always_comb` with variable part-select.

2. **Inline task in always_ff:** A `task compute_one(...)` called from `always_ff` with blocking assignments → mixing blocking and non-blocking assignments caused incorrect behavior. Inlined the computation directly.

3. **Message router pipeline:** Multiple pipeline stage designs (2-cycle, registered inputs/outputs) were attempted. The simplest combinational crossbar with registered output buffers worked best.

4. **`automatic int` in always_ff:** Icarus doesn't support declaring automatic variables inside `always_ff` procedural blocks. All temporary variables must be module-level `int`.

5. **String parameters for BRAM:** Yosys doesn't support `parameter string HEX_FILE = ""`. Removed the parameter; `$readmemh` is only called in simulation `initial` blocks.

### Things to Avoid

- **`automatic` declarations inside `always_ff` or `initial` blocks** — Icarus doesn't support them
- **String parameters in modules to be synthesized** — Yosys doesn't support them
- **`break` in `for` loops inside `always_comb`** — Icarus internal error
- **`unique case`** — Icarus ignores the `unique` qualifier but warns
- **`always_comb` with variable-indexed array access** — Icarus warns and may generate incorrect sensitivity lists
- **Default NB assignments for handshake signals** — Causes 1-cycle delays
- **Mixing blocking and non-blocking assignments in the same `always` block** — Creates simulation-synthesis mismatches

### Future Optimization Ideas

1. **Replace fixed-priority router with round-robin** using a rotate-and-mask approach outside `always_comb` (use `assign` + `always_ff` for rotation)
2. **Pipeline the RV32IM CPU** to 2-3 stages for higher frequency
3. **Add output FIFOs** to the message router for multi-word transfers (currently limited to single-register output buffers)
4. **Implement heap compaction** in the GC sweep phase to reduce fragmentation
5. **Use dual-port BRAM** for simultaneous graph memory read/write (Gowin BRAM supports true dual-port)
6. **Add WISHBONE pipelined mode** for burst transfers to graph memory
7. **Implement speculative execution** for `if` nodes (execute both branches, discard wrong one)

---

## Context for the Next LLM

### Quick Start (Read This First)

You are continuing development of Lucid — an open-hardware Functional Processing Unit. The project is at Phase 10/10 completion. All 10 testbenches pass.

### Critical Invariants

1. **Every module communicates via FIFO message passing.** No module reads another module's internal state directly. The message protocol is `{DEST(8), SRC(8), TYPE(8), FLAGS(8)}` — defined in `message_types.sv`.

2. **The heart is Lucid IR**, a dependency graph. Each node has opcode, inputs, dependents. Execution is driven by data readiness. The scheduler pops ready nodes, dispatches them, receives results, and updates dependents.

3. **Two processors never cross boundaries.** The RV32IM CPU never evaluates functional code. The FPU never parses source code. They communicate via shared memory and the register interface.

4. **No `automatic` variables in `always_ff`.** Icarus doesn't support them. Declare all computation temporaries as module-level `int`.

5. **No string parameters in synthesizable modules.** Yosys doesn't support them.

### Code Style

- SystemVerilog for RTL (`.sv`), synthesizable subset
- snake_case for all signals, modules, files
- One module per file (file name = module name)
- Every module has a header comment documenting ports and protocol
- Testbenches should be self-checking with `assert` and `$error`
- Python code follows PEP 8

### Testing

- `make sim-icarus` runs all tests
- New testbenches go in `simulation/icarus/`
- Every new module needs a corresponding testbench
- Testbenches must generate VCD files in `build/sim/`
- The `tb_platform.sv` testbench is the integration test for Phase 1

### Architecture Rules

- The Wishbone bus is assign-only (no `always_comb`)
- Messages use the format `{DEST, SRC, TYPE, FLAGS}` — DEST at bits 31:24
- Node headers are `{STATE(2), OPCODE(8), NUM_INPUTS(6), READY_INPUTS(6), FLAGS(10)}`
- Heap objects have headers `{TAG(8), FLAGS(8), SIZE(16)}` — FLAGS bit 0 = MARK for GC
- The scheduler FSM states are defined as enums. Adding new states requires updating all `case` statements.

### Common Pitfalls

- Icarus doesn't support all SystemVerilog. Test with `make sim-icarus` early and often.
- The Makefile passes ALL RTL files to each testbench. Some testbenches compile unused modules.
- `boot_rom.hex` is in `simulation/icarus/` with a path relative to the working directory.
- Yosys synthesis currently excludes heap/GC/message modules (they're not in the top-level).

---

## Suggested First Prompt

```
You are continuing development of Lucid — an open-hardware Functional Processing Unit.
The project is at Phase 10/10 completion. All 10 testbenches pass.

Read docs/SESSION_STATE.md first for the complete handoff.

Priority tasks:
1. Fix the graph_scheduler_parallel chain dependency bug
2. Port the Scheme reader/compiler from Python to C for the RV32IM firmware
3. Add Verilator C++ testbenches
4. Run Yosys ABC synthesis to get accurate LUT counts
5. Create a Gowin EDA project for Tang Nano 20K bitstream generation

Start by running `make sim-icarus` to verify the current state, then read the key
architecture documents: docs/ARCHITECTURE.md and docs/PROJECT.md.
```
