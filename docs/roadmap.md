# Lucid Project Roadmap

**Last Updated:** 2026-07-18

---

## Phase 0: Foundation ✓

| Task | Status |
|------|--------|
| Repository structure | ✓ |
| Architecture Guide | ✓ |
| Developer Guide | ✓ |
| Lucid IR Specification | ✓ |
| Memory Map | ✓ |
| Object Model | ✓ |
| Message Protocol | ✓ |
| Scheduler Specification | ✓ |
| Coding Standards | ✓ |
| Contributing Guide | ✓ |
| Roadmap | ✓ |
| Makefile build system | ✓ |
| CI configuration | ✓ |
| ADR records | ✓ |

## Phase 1: Platform ✓

| Task | Status |
|------|--------|
| Wishbone bus matrix | ✓ |
| UART peripheral | ✓ |
| RV32IM management CPU | ✓ |
| Memory subsystem (BRAM) | ✓ |
| Boot ROM and boot flow | ✓ |
| Clock generation (PLL wrapper) | ✓ |
| Top-level integration | ✓ |
| Simulation testbench | ✓ |

## Phase 2: Message System ✓

| Task | Status |
|------|--------|
| FIFO module | ✓ |
| Message dispatcher | ✓ |
| Message format definition | ✓ |
| Message router (crossbar) | ✓ |
| Message-level testbench | ✓ |

## Phase 3: Lucid IR Graph Execution ✓

| Task | Status |
|------|--------|
| Graph memory controller | ✓ |
| Dependency tracker | ✓ |
| Ready queue | ✓ |
| Scheduler core (FSM) | ✓ |
| Node execution (inline) | ✓ |
| Graph execution test | ✓ |

## Phase 4: Primitive Execution ✓

| Task | Status |
|------|--------|
| Primitive arithmetic unit (add, sub, mul) | ✓ |
| Comparison unit (EQ, LT, GT, LE, GE) | ✓ |
| Message-based primitive dispatch | ✓ |
| Execution unit testbench | ✓ |

## Phase 5: Heap and Closures ✓

| Task | Status |
|------|--------|
| Heap controller | ✓ |
| Object allocation | ✓ |
| Closure creation unit | ✓ |
| Environment unit | ✓ |
| Heap testbench | ✓ |

## Phase 6: Scheme Frontend ✓

| Task | Status |
|------|--------|
| Scheme tokenizer/reader | ✓ |
| Scheme parser (s-expressions) | ✓ |
| Lucid IR compiler | ✓ |
| End-to-end testbench | ✓ |
| IR graph loader | ✓ |

## Phase 7: Parallel Scheduling ✓

| Task | Status |
|------|--------|
| Multi-pop ready queue (2-wide) | ✓ |
| Dual-issue dispatch | ✓ |
| Concurrency tracking | ✓ |
| Synchronization testbench | ✓ |

## Phase 8: Garbage Collection ✓

| Task | Status |
|------|--------|
| Mark/sweep GC engine | ✓ |
| Root set management | ✓ |
| GC-heap integration | ✓ |
| GC testbench | ✓ |

## Phase 9: Optimization ✓

| Task | Status |
|------|--------|
| Synthesis script (Yosys) | ✓ |
| Timing constraints (SDC) | ✓ |
| Tang Nano 20K top-level | ✓ |
| Synthesis analysis | ✓ |
| PLL integration | ✓ |

## Phase 10: Language Expansion ✓

| Task | Status |
|------|--------|
| Racket frontend | ✓ |
| Common Lisp frontend | ✓ |
| OCaml frontend | ✓ |
| Haskell frontend | ✓ |
| Multi-language test | ✓ |

---

## Milestone Status

| Milestone | Status | Notes |
|-----------|--------|-------|
| MVP (Phase 4) | ✓ Complete | Single-expression evaluation working |
| Basic Scheme (Phase 6) | ✓ Complete | End-to-end: Scheme → IR → execution |
| Production (Phase 8) | ✓ Complete | GC, heap, closures all working |
| Mature (Phase 9) | ✓ Complete | Synthesis flow and analysis done |
| Expansion (Phase 10) | ✓ Complete | 5 language frontends |

## Next Priorities

1. **Bug fixes**: `graph_scheduler_parallel` chain dependency issue
2. **Verilator testbenches**: Add C++ testbenches for faster simulation
3. **Hardware bringup**: Program Tang Nano 20K, verify UART REPL
4. **C firmware**: Port Scheme reader/compiler to C for RV32IM
5. **Performance analysis**: Benchmark graph execution speed
6. **Continuations**: Hardware support for `call/cc`
7. **Multi-scheduler**: Multiple concurrent graph executions
