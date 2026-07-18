# Lucid

**An Open Hardware Functional Processing Unit (FPU)**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> **Note:** In Lucid, *FPU* stands for **Functional Processing Unit** — *not* Floating Point Unit.

---

## What is Lucid?

Lucid is an open hardware computer architecture dedicated to the **direct execution of functional programming languages** in hardware. It is not a soft CPU, not a Scheme interpreter, and not an FPGA demo — it is a heterogeneous computing architecture designed from first principles for functional computation.

Conventional processors execute imperative instructions sequentially. Lucid instead executes a **graph-based intermediate representation (Lucid IR)**, where nodes represent computations and edges represent data dependencies. Execution is driven by *readiness*, not instruction order — the hardware scheduler behaves more like a GPU scheduler than a traditional CPU.

The long-term goal is to become the equivalent of **LLVM for functional hardware**:

```
Scheme ────┐
Racket ────┤
Common Lisp┤    ┌──────────┐     ┌───────────┐     ┌─────────────────────┐
OCaml ─────┼──▶ │ Lucid    │ ──▶ │ Lucid IR  │ ──▶ │ Functional          │
Haskell ───┤    │ Frontends│     │ (graph)   │     │ Processing Unit     │
Future DSLs┘    └──────────┘     └───────────┘     └─────────────────────┘
```

Only the frontends change. The hardware does not. Scheme is the first supported frontend — never a dependency of the architecture.

## Architectural Highlights

- **Two-processor design.** An RV32IM *Management CPU* (boot, UART, REPL, debugger, filesystem, compiler frontends) runs alongside the novel *Lucid FPU* (graph execution, heap, closures, continuations, GC, scheduling). The Management CPU never evaluates functional programs; the FPU never parses source code.
- **Lucid IR.** A dependency graph — not an AST, not bytecode. Inspired by the STG machine, SSA, Sea-of-Nodes, and graph reduction machines. Independent nodes may execute concurrently.
- **Message-passing internals.** All FPU modules communicate exclusively through FIFO-based messages. No module touches another's internal state, so every subsystem is independently testable and replaceable.
- **Specialized execution units.** Heap allocation, primitive arithmetic, comparison, closure, environment, continuation, and pattern matching units — each independently synthesizable.
- **Hardware-managed memory.** The functional heap (pairs, closures, thunks, continuations, ...) belongs exclusively to the FPU, with a dedicated hardware GC subsystem on the roadmap.

### Graph Execution Example

```scheme
(+ 2 (* 3 4))
```

becomes a dependency graph:

```
  MUL(3, 4) ──▶ 12 ─┐
                    ├──▶ ADD(2, ·) ──▶ 14
  2 ────────────────┘
```

The scheduler detects that the `MUL` node has no unsatisfied dependencies and executes it immediately; `ADD` waits for readiness. The hardware pipeline is:

```
Graph Fetch → Dependency Decode → Ready Queue → Scheduler → Execute → Commit → Graph Update
```

## Target Hardware

The reference platform is the **Sipeed Tang Nano 20K** (Gowin GW2AR-18 FPGA):

| Component | Specification |
|-----------|---------------|
| FPGA | Gowin GW2AR-18 (Tang Nano 20K) |
| Logic cells | 20,736 LUT4 |
| Block RAM | 828 Kbits |
| Clock | 27 MHz external → 100 MHz internal (PLL) |

All RTL must realistically fit this FPGA. Simulation is the primary validation method; hardware is secondary. Larger targets (Tang Mega 60K, Artix-7, and beyond) are supported for simulation and future scaling.

## Repository Layout

```
lucid/
├── docs/               # All documentation
│   ├── adr/            # Architecture Decision Records
│   └── architecture/   # Architecture specifications
├── rtl/                # SystemVerilog RTL
│   ├── cpu/            # RV32IM management CPU, boot ROM, RAM
│   ├── scheduler/      # Graph scheduler and graph memory
│   ├── messages/       # FIFOs, message dispatcher/router
│   ├── primitives/     # Primitive execution units
│   ├── bus/            # Wishbone bus infrastructure
│   └── peripherals/    # UART, BRAM
├── firmware/           # Management CPU firmware
├── frontend/           # Language frontends (scheme, racket, ...)
├── ir/                 # Lucid IR library and tools
├── simulation/         # Testbenches (icarus/, verilator/)
├── verification/       # Verification scripts
├── tools/              # Development tools (graph visualizer, examples)
├── scripts/            # Utility scripts (env check, git hooks)
├── examples/           # Example programs
├── benchmarks/         # Benchmark suite
└── ci/                 # CI configuration
```

## Getting Started

### Prerequisites

Development targets **macOS** (all commands must work on macOS; no Linux-only tooling).

| Tool | Purpose |
|------|---------|
| Verilator ≥ 5.0 | High-performance RTL simulation |
| Icarus Verilog ≥ 12 | IEEE Verilog simulation |
| GTKWave | Waveform viewing |
| Python 3 ≥ 3.10 | Scripts and verification |
| Make, CMake | Build automation |
| Yosys, OSS CAD Suite (optional) | Open-source synthesis |
| Gowin IDE, OpenFPGALoader (optional) | Vendor toolchain, board programming |

```bash
brew install verilator icarus-verilog gtkwave yosys
```

Verify your environment:

```bash
python3 scripts/check_env.py
```

### Build and Simulate

The root `Makefile` is the single entry point:

```bash
make info           # Show all targets
make sim            # Run all simulations
make sim-icarus     # Run Icarus Verilog testbenches
make lint           # Lint RTL with Verilator
make verify         # Run verification scripts
make clean          # Remove build artifacts
```

Verilator C++ testbenches can also be driven via CMake:

```bash
mkdir -p build && cd build
cmake ..
make
```

### Tools

`tools/graph_examples.py` prints sample Lucid IR graphs, and `tools/graph_viz.py` converts a single graph description to DOT format for visualization:

```bash
cat <<'EOF' | python3 tools/graph_viz.py > graph.dot
# (+ 2 (* 3 4))
0 LIT_INT imm=2
1 LIT_INT imm=3
2 LIT_INT imm=4
3 MUL input=1,2
4 ADD input=0,3
EOF
dot -Tpng graph.dot -o graph.png
```

## Documentation

Architecture comes before RTL in this project — every subsystem is specified before it is implemented.

- [Architecture Guide](docs/architecture/architecture-guide.md) — system overview, execution model, memory, verification strategy
- [Developer Guide](docs/architecture/developer-guide.md) — environment setup, build system, coding conventions
- [Lucid IR Specification](docs/architecture/lucid-ir-spec.md)
- [Graph Execution Design](docs/architecture/graph-execution-design.md)
- [Scheduler Specification](docs/architecture/scheduler-spec.md)
- [Message Protocol](docs/architecture/message-protocol.md) and [Message System Design](docs/architecture/message-system-design.md)
- [Memory Map](docs/architecture/memory-map.md) and [Object Model](docs/architecture/object-model.md)
- [Platform Design](docs/architecture/platform-design.md) and [Primitive Execution Design](docs/architecture/primitive-exec-design.md)
- [Coding Standards](docs/architecture/coding-standards.md)
- [Architecture Decision Records](docs/adr/) — why the architecture is the way it is
- [Roadmap](docs/roadmap.md)

## Project Status

Lucid is in early development. The foundation (documentation, build system, CI) is complete, and initial RTL for the platform, message system, and graph scheduler exists with Icarus/Verilator testbenches. See the [roadmap](docs/roadmap.md) for the full phased plan:

| Phase | Focus |
|-------|-------|
| 0 | Foundation: docs, CI, build system |
| 1 | Platform: Wishbone, UART, RV32IM, memory |
| 2 | Message system: FIFOs, dispatcher |
| 3 | Lucid IR graph execution |
| 4 | Primitive execution units |
| 5 | Heap, closures, environments |
| 6 | Scheme frontend and REPL |
| 7 | Parallel scheduling |
| 8 | Hardware garbage collection |
| 9 | Optimization and board bring-up |
| 10+ | Racket, Common Lisp, OCaml, Haskell frontends |

## Contributing

Contributions of all kinds are welcome — documentation, RTL, verification, and tooling. Please read the [Contributing Guide](docs/CONTRIBUTING.md) and the [Architecture Guide](docs/architecture/architecture-guide.md) first. The project philosophy:

- Architecture before RTL
- Documentation before code
- Verification before optimization

## License

Lucid is released under the [MIT License](LICENSE).

Copyright (c) 2026 Mauro Parra-Miranda
