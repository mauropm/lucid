# ADR-001: Two-Processor Architecture

**Status:** Accepted
**Date:** 2026-07-17

## Context

The Lucid system must support both conventional system tasks (boot, UART, filesystem, debugging) and functional program execution. These workloads have fundamentally different requirements.

Conventional tasks require:
- Sequential instruction execution
- Interrupt handling
- Familiar C toolchain
- Standard peripheral drivers

Functional execution requires:
- Graph-based dataflow execution
- Heap allocation and garbage collection
- Closure and continuation support
- Non-sequential scheduling

## Decision

Use two independent processors within a single FPGA:

1. **Management CPU:** Standard RV32IM core handling boot, UART, debugger, REPL, filesystem, and compiler frontends.
2. **Lucid FPU:** Custom functional processor handling graph execution, heap, closures, continuations, and GC.

The two processors communicate via shared memory and message FIFOs.

## Consequences

**Benefits:**
- Clear separation of concerns
- Each processor can be developed and verified independently
- Management CPU can use existing RISC-V toolchain
- FPU design is not constrained by conventional CPU pipeline requirements
- Debug interface through management CPU provides visibility into FPU state

**Risks:**
- Two processors consume more FPGA resources than one
- Inter-processor communication adds latency
- Memory coherency must be managed between processors

## Alternatives Considered

1. **Single processor with functional extensions:** Adding functional instructions to RV32IM. Rejected because it would compromise the RISC-V standard compliance and the instruction set would need to be fundamentally different from sequential execution.

2. **Pure FPU with software emulation of system tasks:** Rejected because it would require reimplementing UART, filesystem, and debugger in the functional paradigm, adding unnecessary complexity.

3. **GPU-like accelerator attached to RV32IM:** Rejected because the FPU is not a SIMD accelerator; it is a fundamentally different execution model that needs its own scheduling and memory management.
