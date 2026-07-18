# Lucid Project

**Version:** 0.1.0
**Status:** Active Development

---

## Vision

Lucid is an open hardware Functional Processing Unit (FPU) — a heterogeneous computing architecture dedicated to the direct execution of functional programming languages. It is the hardware equivalent of LLVM for functional languages.

## Goals

1. **Language Independence:** The architecture exposes Lucid IR, a graph-based intermediate representation. Any functional language (Scheme, Racket, OCaml, Haskell, ...) can compile to it. The hardware never changes — only frontends do.

2. **Direct Hardware Support for Functional Semantics:** Closures, continuations, garbage collection, and graph reduction are hardware-native operations, not software emulation.

3. **Natural Parallelism:** Graph execution is driven by data readiness, not instruction order. Independent subgraphs execute concurrently without explicit parallelism annotations.

4. **Long-Term Evolution:** Designed to scale from the Tang Nano 20K (20K LUTs) to larger FPGAs and ASICs without architectural changes.

## Non-Goals

- Not a Scheme interpreter
- Not another soft CPU
- Not a Lisp emulator
- Not an FPGA demo

## Ten-Year Architecture

Lucid should evolve like RISC-V or LLVM — a stable architectural interface (Lucid IR) with evolving implementations. The hardware is the "backend" — only frontends change.

## Success Criteria

- Scheme REPL running on Tang Nano 20K FPGA
- Multi-language compilation to Lucid IR
- Hardware garbage collection and parallel scheduling
- Open-source ecosystem of frontends and tools
