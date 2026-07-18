# Lucid Architecture

**Version:** 0.1.0
**Status:** Active Development

---

## System Overview

Lucid uses two independent processors within a single FPGA:

| Processor | Role | Architecture |
|-----------|------|-------------|
| Management CPU | Boot, UART, debugger, REPL, compiler frontends | RV32IM |
| Lucid FPU | Graph execution, heap, closures, GC, scheduling | Custom (Lucid IR) |

The Management CPU never evaluates functional programs. The FPU never parses source code.

## Block Diagram

```
┌─────────────────────────────────────────────────────┐
│                     FPGA                             │
│  ┌────────────────────────┐  ┌────────────────────┐  │
│  │   Management CPU       │  │   Lucid FPU        │  │
│  │   (RV32IM)             │  │                    │  │
│  │  • Boot ROM            │  │  • Graph Scheduler │  │
│  │  • UART                │  │  • Execution Units │  │
│  │  • Debugger            │  │  • Heap Controller │  │
│  │  • REPL                │  │  • GC Engine       │  │
│  │  • Frontend Compiler   │  │  • Message System  │  │
│  └────────┬───────────────┘  └────────┬───────────┘  │
│           │                            │              │
│           └──────────┬─────────────────┘              │
│                      │                                │
│              ┌───────┴───────┐                        │
│              │   Wishbone    │                        │
│              │   Bus Matrix  │                        │
│              └───────┬───────┘                        │
│                      │                                │
│           ┌──────────┴──────────┐                    │
│           │     Shared SRAM     │                     │
│           └─────────────────────┘                     │
└───────────────────────────────────────────────────────┘
```

## Key Subsystems

### RV32IM CPU (`rtl/cpu/`)
- 3-state FSM (fetch, execute, load-data)
- Wishbone B4 master
- Full RV32I + M extension, minimal CSR
- 1-cycle Wishbone read latency from BRAM

### Wishbone Bus (`rtl/bus/`)
- 1 master, 3 slaves (boot ROM, mgmt RAM, UART)
- Assign-only (no `always_comb` for Icarus compatibility)
- Address decoding: 16-bit region select

### UART (`rtl/peripherals/uart.sv`)
- 8N1, 115200 baud (configurable divisor)
- 8-byte TX and RX FIFOs
- Wishbone B4 slave

### Message System (`rtl/messages/`)
- **FIFO:** Parameterized (width, depth), registered read data
- **Router:** N×M combinational crossbar, output registers, fixed-priority arbitration
- **Dispatcher:** Wraps router with Wishbone control
- **Types:** Module IDs, message type codes, flags, header helpers

### Graph Scheduler (`rtl/scheduler/`)
- **graph_scheduler.sv:** Single-threaded, inline computation, 5-states (Phase 3)
- **graph_scheduler_fp.sv:** Message-based dispatch to execution units (Phase 4)
- **graph_scheduler_parallel.sv:** Dual-issue, multi-pop queue, concurrency tracking (Phase 7)
- **graph_memory.sv:** BRAM-based node storage (6 words/node)

### Primitive Execution (`rtl/primitives/`)
- Receives EXEC_PRIM messages, returns PRIM_RESULT
- ADD, SUB, MUL, DIV, MOD, EQ, LT, GT, LE, GE, IF
- 3-word input, 2-word output message protocol

### Heap (`rtl/heap/`)
- **heap_controller.sv:** Basic sequential allocator
- **heap_controller_gc.sv:** GC-aware allocator (blocks during GC, auto-triggers on OOM)
- **closure_unit.sv:** Creates closure objects with arity, code ptr, env entries
- **environment_unit.sv:** Create/extend environments, lookup bindings

### GC (`rtl/gc/`)
- Mark-sweep engine, 6-state FSM
- 64-entry hardware mark stack
- BRAM read/write access for object headers
- Integrates with heap_controller_gc via gc_trigger/busy/done handshake

### Lucid IR Execution Model
```
Source → Frontend → Lucid IR Graph → Scheduler → Execution Units → Result
```

Graph nodes represent computation; edges represent data dependencies. The scheduler dispatches ready nodes (all inputs available) to execution units. Results propagate through the dependency graph.

## Reference Hardware

| Component | Specification |
|-----------|-------------|
| FPGA | Gowin GW2AR-18 (Tang Nano 20K) |
| Logic | 20,736 LUT4 |
| BRAM | 828 Kbits (72 × 9K blocks) |
| DSP | 32 × 18×18 multipliers |
| Clock | 100 MHz (PLL from 27 MHz) |
| Synthesis estimate | ~500 cells, 2–4 BRAMs |

## Frontends

| Language | Directory | Status |
|----------|-----------|--------|
| Scheme | `frontend/scheme/` | Full: reader + compiler + end-to-end test |
| Racket | `frontend/racket/` | Reader + compiler (shares Scheme backend) |
| Common Lisp | `frontend/clisp/` | Reader + compiler with CL-specific preprocessing |
| OCaml | `frontend/ocaml/` | Tokenizer + parser + compiler |
| Haskell | `frontend/haskell/` | Tokenizer + parser + compiler |

All frontends compile to the same Lucid IR node format and share the `IRCompiler` backend.

## Verification

10 Icarus Verilog testbenches covering all subsystems:

| Testbench | Area | Tests |
|-----------|------|-------|
| tb_fifo | FIFO | 5 |
| tb_message_dispatcher | Message dispatcher | 2 |
| tb_message_system | Router + dispatcher | 5 |
| tb_platform | CPU + bus + UART | 7 register checks |
| tb_graph_scheduler | Graph execution | Result verification |
| tb_primitive_exec | Message dispatch | 3 operations |
| tb_heap | Heap controller | 6 tests |
| tb_scheme | End-to-end Scheme | 4 expressions |
| tb_parallel | Parallel scheduling | 2 tests |
| tb_gc | Garbage collection | 6 tests |
