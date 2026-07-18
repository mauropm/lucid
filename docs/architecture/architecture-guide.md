# Lucid Architecture Guide

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Introduction

Lucid is an open hardware Functional Processing Unit (FPU) — a heterogeneous computing architecture dedicated to the direct execution of functional programming languages.

Unlike conventional processors that execute imperative instructions sequentially, Lucid executes graph-based intermediate representations where nodes represent computations and edges represent data dependencies. This enables natural parallelism, transparent laziness, and first-class support for closures, continuations, and garbage collection.

### 1.1 Guiding Principles

- **Architecture before RTL.** Every subsystem is designed and documented before implementation.
- **Hardware for functional semantics.** The hardware directly supports closures, continuations, and graph reduction — not through emulation, but as native operations.
- **Language independence.** The architecture exposes Lucid IR, an intermediate representation that any functional language frontend can target. Scheme is the first frontend, not the only frontend.
- **Modular replaceability.** Every subsystem communicates via message passing. No module directly manipulates another's internal state.
- **Verification before optimization.** Correctness is verified through simulation, formal assertions, and randomized testing before any optimization effort.

### 1.2 System Overview

The FPGA contains two independent processors:

| Processor | Architecture | Role |
|-----------|-------------|------|
| Management CPU | RV32IM | Boot, UART, debugger, REPL, filesystem, compiler frontends |
| Lucid FPU | Custom | Functional execution, heap, closures, continuations, GC, scheduling |

The Management CPU never evaluates functional programs. The Lucid FPU never parses source code. They communicate through a shared memory interface and a message FIFO.

---

## 2. Top-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     FPGA (GW2AR-18)                      │
│                                                         │
│  ┌────────────────────────┐  ┌────────────────────────┐  │
│  │   Management CPU       │  │   Lucid FPU            │  │
│  │   (RV32IM)             │  │   (Functional Proc.)   │  │
│  │                        │  │                        │  │
│  │  • Boot ROM            │  │  • Graph Scheduler     │  │
│  │  • UART                │  │  • Execution Units     │  │
│  │  • Debugger            │  │  • Heap Controller     │  │
│  │  • REPL                │  │  • GC Engine           │  │
│  │  • SD Card             │  │  • Message Dispatcher  │  │
│  │  • Frontend Compiler   │  │                        │  │
│  └────────┬───────────────┘  └────────┬───────────────┘  │
│           │                            │                  │
│           └──────────┬─────────────────┘                  │
│                      │                                    │
│              ┌───────┴───────┐                            │
│              │   Wishbone    │                            │
│              │   Bus Matrix  │                            │
│              └───────┬───────┘                            │
│                      │                                    │
│           ┌──────────┴──────────┐                        │
│           │     Shared SRAM     │                         │
│           │   (Block RAM/SPRAM) │                         │
│           └─────────────────────┘                         │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

### 2.1 Management CPU (RV32IM)

**Role:** System controller and language frontend host.

The Management CPU is a standard RV32IM core responsible for all non-functional tasks:
- Board initialization and boot
- UART serial communication for the REPL
- Debugger and diagnostic interfaces
- SD card and filesystem access
- Running compiler frontends (Scheme → Lucid IR)
- Telemetry and performance monitoring

**Justification:** A standard RISC-V core is chosen because:
- It is well-understood and verifiable
- Open-source implementations exist (e.g., PicoRV32, VexRiscv)
- It cleanly separates the novel FPU from conventional system tasks
- It provides a familiar debugging interface

### 2.2 Lucid FPU

**Role:** Functional program execution engine.

The FPU is a novel processor designed from first principles for functional computation. It does not execute instructions sequentially. Instead, it schedules graph nodes for execution based on data readiness.

The FPU contains:
- **Message Dispatcher:** Routes messages between execution units
- **Graph Scheduler:** Tracks dependencies and dispatches ready nodes
- **Execution Units:** Specialized engines for different operations
- **Heap Controller:** Manages functional object allocation
- **GC Engine:** Hardware garbage collection

---

## 3. Message Passing Architecture

All FPU modules communicate exclusively through FIFO-based message passing.

### 3.1 Design Rationale

Message passing is chosen over shared state for:
- **Decoupling:** Modules can be developed, tested, and replaced independently
- **Deadlock avoidance:** FIFO ordering provides predictable communication
- **Synthesis efficiency:** Point-to-point FIFOs map well to FPGA fabric
- **Scalability:** New execution units can be added without modifying existing ones
- **Verification:** Module interfaces are simple and testable in isolation

### 3.2 Message Format

Every message has a 32-bit header followed by optional payload words.

| Field | Width | Description |
|-------|-------|-------------|
| Type  | 8     | Message type identifier |
| Flags | 8     | Control flags (priority, response-required, etc.) |
| Tag   | 16    | Correlation tag for request/response matching |

Payload width and semantics are type-dependent.

### 3.3 Message Types

| Type | Code | Description |
|------|------|-------------|
| NOP | 0x00 | No operation |
| ALLOCATE | 0x01 | Allocate heap object |
| EVALUATE | 0x02 | Evaluate a graph node |
| EXECUTE_PRIMITIVE | 0x03 | Execute a primitive operation |
| CREATE_CLOSURE | 0x04 | Create a closure object |
| APPLY | 0x05 | Apply a function |
| TAIL_CALL | 0x06 | Perform a tail call |
| LOOKUP_ENV | 0x07 | Look up a variable in an environment |
| GC_REQUEST | 0x08 | Request garbage collection |
| GC_COMPLETE | 0x09 | Garbage collection complete |
| CONTINUATION_SAVE | 0x0A | Save a continuation |
| CONTINUATION_RESTORE | 0x0B | Restore a continuation |
| NODE_RESULT | 0x0C | Graph node execution result |
| READY_NODE | 0x0D | Node is ready for execution |
| SCHEDULE | 0x0E | Schedule a graph node |
| HALT | 0xFF | Halt execution |

---

## 4. Graph Execution Model

Lucid does not execute imperative instructions. It executes a dependency graph.

### 4.1 Graph Structure

A Lucid IR graph consists of:
- **Nodes:** Each node represents a unit of computation (primitive operation, function application, closure creation, etc.)
- **Edges:** Each edge represents a data dependency from producer to consumer
- **Roots:** Entry points into the graph (the program's top-level expressions)

### 4.2 Execution Pipeline

```
Graph Fetch → Dependency Decode → Ready Queue → Scheduler → Execute → Commit → Graph Update
```

1. **Graph Fetch:** The scheduler fetches the next graph from graph memory
2. **Dependency Decode:** Each node's dependencies are decoded and tracked
3. **Ready Queue:** Nodes whose dependencies are all satisfied enter the ready queue
4. **Scheduler:** Ready nodes are dispatched to execution units
5. **Execute:** Execution units perform the actual computation
6. **Commit:** Results are written back
7. **Graph Update:** Downstream nodes are notified of completed dependencies

### 4.3 Execution Units

| Unit | Operations |
|------|------------|
| Primitive Arithmetic | Integer add, sub, mul, div, mod |
| Comparison | eq?, <, >, <=, >= |
| Closure | Closure creation, application |
| Environment | Variable lookup, environment extension |
| Continuation | Call/cc, continuation capture/restore |
| Pattern Matching | Pattern match compilation and execution |
| Heap Allocation | Object allocation in functional heap |

---

## 5. Memory Architecture

### 5.1 Memory Map

| Address Range | Region | Access | Description |
|--------------|--------|--------|-------------|
| 0x00000000 - 0x0000FFFF | Boot ROM | R | Bootloader and reset vectors |
| 0x00010000 - 0x0001FFFF | Management Stack | R/W | CPU stack and scratch |
| 0x00020000 - 0x0002FFFF | UART | R/W | Serial communication |
| 0x00030000 - 0x0003FFFF | Debug | R/W | Debug interface |
| 0x00100000 - 0x001FFFFF | FPU Control | R/W | Scheduler control registers |
| 0x00200000 - 0x002FFFFF | Graph Memory | R/W | Lucid IR graph storage |
| 0x00300000 - 0x003FFFFF | FPU Heap | R/W | Functional object heap |
| 0x00400000 - 0x004FFFFF | GC Scratch | R/W | Garbage collector workspace |
| 0x80000000 - 0x8FFFFFFF | External DRAM | R/W | External memory (future) |

### 5.2 Heap Layout

The FPU heap is a contiguous region of memory managed by the hardware heap controller and GC engine.

| Section | Size | Description |
|---------|------|-------------|
| Heap Header | 64 bytes | Heap metadata (free pointer, GC status, etc.) |
| Object Space | (configurable) | Active heap objects |
| GC Space | (configurable) | GC work area (copying/compaction) |
| Free List | (configurable) | Free block tracking |

---

## 6. Object Model

Every heap object shares a common header:

| Offset | Width | Field | Description |
|--------|-------|-------|-------------|
| 0 | 8 | Type tag | Object type identifier |
| 1 | 8 | Flags | GC mark, immutability, etc. |
| 2 | 16 | Size | Object size in words (including header) |
| 4 | 32 | Payload start | Object-specific data |

### 6.1 Object Types

| Tag | Type | Description |
|-----|------|-------------|
| 0x01 | Integer | 31-bit signed integer (tagged) |
| 0x02 | Boolean | #t or #f |
| 0x03 | Character | Unicode code point |
| 0x04 | String | Character string |
| 0x05 | Symbol | Interned symbol |
| 0x06 | Pair | Cons cell (car, cdr) |
| 0x07 | Vector | Fixed-length array |
| 0x08 | Closure | Function + environment |
| 0x09 | Environment | Variable bindings |
| 0x0A | Primitive | Built-in operation |
| 0x0B | Continuation | Saved execution state |
| 0x0C | Thunk | Delayed computation |
| 0x0D | Promise | Future result |

---

## 7. Reference Hardware

| Component | Specification |
|-----------|-------------|
| FPGA | Gowin GW2AR-18 (Tang Nano 20K) |
| Logic cells | 20,736 LUT4 |
| Block RAM | 828 Kbits (72 blocks of 9K) |
| DSP | 32 multipliers (18×18) |
| PLL | 27 MHz → 100 MHz internal |
| External flash | 16 MB (boot/config) |
| External DRAM | 64 MB SDRAM (optional) |

All RTL must fit within these constraints. Simulation on larger targets (Artix-7, etc.) is permitted, but the Tang Nano 20K is the minimum supported target.

---

## 8. Language Frontend Architecture

```
Source Code (Scheme, Racket, OCaml, Haskell, ...)
        │
        ▼
    Frontend Parser
        │
        ▼
    Frontend Analyzer
        │
        ▼
    Lucid IR Generator
        │
        ▼
    Lucid IR Graph
        │
        ▼
    [Serialization / Load into FPU Graph Memory]
        │
        ▼
    FPU Execution
```

### 8.1 Frontend Responsibilities
- Parse source language
- Perform language-specific analysis and optimization
- Emit Lucid IR graph
- Handle I/O through the Management CPU

### 8.2 FPU Responsibilities
- Load graph from graph memory
- Schedule and execute nodes
- Manage heap and GC
- Return results through the message interface

---

## 9. Verification Strategy

### 9.1 Levels of Verification

| Level | Method | Scope |
|-------|--------|-------|
| Unit | Module-level testbenches | Verilator, Icarus |
| Integration | Cross-module communication | Message-level tests |
| System | Full FPU execution | Graph execution tests |
| Hardware | FPGA bitstream | Physical board tests |

### 9.2 Verification Tools

| Tool | Purpose |
|------|---------|
| Verilator | High-performance RTL simulation |
| Icarus Verilog | IEEE-compliant Verilog simulation |
| GTKWave | Waveform viewing and analysis |
| Python/Cocotb | Cosimulation and test generation |

---

## 10. Roadmap

| Phase | Focus | Key Deliverables |
|-------|-------|-----------------|
| 0 | Foundation | Docs, CI, Makefiles, simulation scaffolding |
| 1 | Platform | Wishbone bus, UART, RV32IM core, memory |
| 2 | Messaging | Message system, FIFOs, dispatcher |
| 3 | Graph | Lucid IR graph builder and executor |
| 4 | Primitives | Primitive arithmetic and comparison units |
| 5 | Heap | Heap controller, closures, environments |
| 6 | Scheme | Reader, parser, compiler to Lucid IR, REPL |
| 7 | Scheduler | Parallel graph execution |
| 8 | GC | Hardware garbage collector |
| 9 | Optimization | Timing closure, area reduction, pipelining |
| 10+ | Language expansion | Racket, OCaml, Haskell frontends |

---

## 11. References

- MIT CADR Machine Architecture
- Symbolics 3600 Architecture
- SECD Machine (Landin)
- CEK Machine (Felleisen)
- Krivine Machine
- STG Machine (Peyton Jones)
- LLVM Language Reference
- RISC-V Unprivileged Specification v2.2
- Wishbone B4 Bus Specification
- Gowin GW2A-18 Datasheet
