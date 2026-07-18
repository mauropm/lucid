# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the Lucid project. Each ADR documents a significant architectural decision including context, options considered, and the chosen approach.

## Index

| ADR | Title | Status | Date | Description |
|-----|-------|--------|------|-------------|
| 001 | Two-Processor Architecture | Accepted | 2026-07-17 | RV32IM management CPU + custom Lucid FPU |
| 002 | Message Passing Between FPU Modules | Accepted | 2026-07-17 | FIFO-based message passing instead of shared state |
| 003 | Graph-Based Intermediate Representation | Accepted | 2026-07-17 | Dependency graph IR instead of bytecode or AST |

## Location

Full ADRs are in `docs/adr/`:

- `docs/adr/001-two-processor-architecture.md`
- `docs/adr/002-message-passing.md`
- `docs/adr/003-graph-based-ir.md`
