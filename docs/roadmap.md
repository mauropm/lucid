# Lucid Project Roadmap

**Last Updated:** 2026-07-17

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

## Phase 1: Platform

| Task | Status | Dependencies |
|------|--------|-------------|
| Wishbone bus matrix | ⬜ | None |
| UART peripheral | ⬜ | Wishbone |
| RV32IM management CPU | ⬜ | Wishbone |
| Memory subsystem | ⬜ | Wishbone |
| Boot ROM and boot flow | ⬜ | CPU, UART |
| Clock generation (PLL) | ⬜ | None |
| Top-level integration | ⬜ | All Phase 1 |
| Simulation testbench | ⬜ | All Phase 1 |

## Phase 2: Message System

| Task | Status | Dependencies |
|------|--------|-------------|
| FIFO module | ⬜ | None |
| Message dispatcher | ⬜ | FIFO |
| Message format definition | ⬜ | None |
| Module-to-module messaging | ⬜ | Dispatcher |
| Message-level testbench | ⬜ | All Phase 2 |

## Phase 3: Lucid IR Graph Execution

| Task | Status | Dependencies |
|------|--------|-------------|
| Graph memory controller | ⬜ | Wishbone |
| Dependency tracker | ⬜ | Graph memory |
| Ready queue | ⬜ | FIFO |
| Scheduler core | ⬜ | Dep tracker, ready queue |
| Node execution FSM | ⬜ | Scheduler |
| Single-node graph execution test | ⬜ | All Phase 3 |

## Phase 4: Primitive Execution

| Task | Status | Dependencies |
|------|--------|-------------|
| Primitive arithmetic unit (add, sub) | ⬜ | Scheduler |
| Primitive arithmetic unit (mul) | ⬜ | Scheduler |
| Comparison unit | ⬜ | Scheduler |
| Primitive dispatch | ⬜ | Scheduler |
| Primitive execution testbench | ⬜ | All Phase 4 |

## Phase 5: Heap and Closures

| Task | Status | Dependencies |
|------|--------|-------------|
| Heap controller | ⬜ | Wishbone |
| Object allocation | ⬜ | Heap controller |
| Closure creation unit | ⬜ | Heap controller |
| Environment unit | ⬜ | Heap controller |
| Pair/vector allocation | ⬜ | Heap controller |
| Heap testbench | ⬜ | All Phase 5 |

## Phase 6: Scheme Frontend

| Task | Status | Dependencies |
|------|--------|-------------|
| Scheme reader (on CPU) | ⬜ | UART |
| Scheme parser | ⬜ | Reader |
| Lucid IR generator | ⬜ | Parser, IR spec |
| REPL loop | ⬜ | UART, parser, IR gen, FPU |
| Integration test | ⬜ | All Phase 6 |

## Phase 7: Parallel Scheduling

| Task | Status | Dependencies |
|------|--------|-------------|
| Multi-unit dispatch | ⬜ | Scheduler |
| Concurrent graph execution | ⬜ | Multi-unit dispatch |
| Hazard detection | ⬜ | Scheduler |
| Performance counters | ⬜ | Scheduler |

## Phase 8: Garbage Collection

| Task | Status | Dependencies |
|------|--------|-------------|
| Mark/sweep GC engine | ⬜ | Heap controller |
| Root set management | ⬜ | GC engine |
| GC integration with scheduler | ⬜ | GC, scheduler |
| GC testbench | ⬜ | All Phase 8 |

## Phase 9: Optimization

| Task | Status | Dependencies |
|------|--------|-------------|
| Timing closure (100 MHz) | ⬜ | All RTL |
| Area optimization | ⬜ | All RTL |
| Pipeline optimization | ⬜ | All RTL |
| FPGA bitstream | ⬜ | All RTL |
| Board bringup (Tang Nano) | ⬜ | Bitstream |

## Phase 10+: Language Expansion

| Task | Status | Dependencies |
|------|--------|-------------|
| Racket frontend | ⬜ | Phase 6 |
| Common Lisp frontend | ⬜ | Phase 6 |
| OCaml frontend | ⬜ | Phase 6 |
| Haskell frontend | ⬜ | Phase 6 |

---

## Milestone Timeline

| Milestone | Target | Deliverable |
|-----------|--------|-------------|
| MVP | Phase 4 complete | Single-expression evaluation on FPGA |
| Basic Scheme | Phase 6 complete | REPL running on Tang Nano |
| Production | Phase 8 complete | Self-hosting Scheme with GC |
| Mature | Phase 9 complete | Optimized, synthesized bitstream |
| Expansion | Phase 10+ | Multi-language support |
