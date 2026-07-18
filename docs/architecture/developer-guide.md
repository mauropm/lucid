# Lucid Developer Guide

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Introduction

This guide describes how to set up a development environment for Lucid, build and simulate modules, and contribute to the project.

---

## 2. Prerequisites

### 2.1 Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Git | ≥ 2.30 | Version control |
| Make | ≥ 4.0 | Build automation |
| Python 3 | ≥ 3.10 | Scripting, verification |
| Verilator | ≥ 5.0 | RTL simulation |
| Icarus Verilog | ≥ 12.0 | IEEE Verilog simulation |
| GTKWave | ≥ 3.3 | Waveform viewer |

### 2.2 Optional Tools

| Tool | Purpose |
|------|---------|
| Yosys | RTL synthesis |
| OSS CAD Suite | Open-source FPGA toolchain |
| Gowin IDE | Vendor synthesis for Tang Nano |
| nextpnr | Place and route |
| OpenFPGALoader | Board programming |
| Rust/Cargo | Firmware development (future) |

### 2.3 macOS Installation

```bash
# Homebrew
brew install verilator icarus-verilog gtkwave yosys

# Python packages
pip3 install cocotb pytest
```

---

## 3. Repository Structure

```
lucid/
├── docs/               # All documentation
│   ├── adr/            # Architecture Decision Records
│   └── architecture/   # Architecture specifications
├── rtl/                # All RTL source code
│   ├── fpu/            # Lucid FPU modules
│   ├── cpu/            # RV32IM management CPU
│   ├── scheduler/      # Graph scheduler
│   ├── heap/           # Heap controller
│   ├── gc/             # Garbage collector
│   ├── messages/       # Message passing infrastructure
│   ├── primitives/     # Primitive execution units
│   ├── bus/            # Wishbone bus infrastructure
│   └── peripherals/    # UART, GPIO, etc.
├── firmware/           # Management CPU firmware
├── frontend/           # Language frontends
│   ├── scheme/         # Scheme frontend
│   ├── racket/         # Racket frontend (future)
│   ├── common-lisp/    # Common Lisp frontend (future)
│   ├── ocaml/          # OCaml frontend (future)
│   └── haskell/        # Haskell frontend (future)
├── ir/                 # Lucid IR library and tools
├── simulation/         # Simulation testbenches
│   ├── verilator/      # C++ Verilator testbenches
│   └── icarus/         # Icarus Verilog testbenches
├── verification/       # Verification scripts
├── scripts/            # Utility scripts
├── tools/              # Development tools
├── examples/           # Example programs
├── benchmarks/         # Benchmark suite
└── ci/                 # CI configuration
```

---

## 4. Build System

### 4.1 Quick Start

```bash
# Clone and enter the repository
git clone https://github.com/your-org/lucid
cd lucid

# Create project directories
make directories

# Show available targets
make info

# Run all simulations
make sim

# Lint RTL
make lint

# Run verification
make verify
```

### 4.2 Build Targets

| Target | Description |
|--------|-------------|
| `make info` | Show help |
| `make directories` | Create build directories |
| `make docs` | Validate documentation |
| `make sim` | Run all simulations |
| `make sim-verilator` | Run Verilator simulations |
| `make sim-icarus` | Run Icarus simulations |
| `make verify` | Run verification suite |
| `make lint` | Lint RTL sources |
| `make clean` | Remove build artifacts |

### 4.3 CMake (Verilator Testbenches)

For more complex Verilator simulations, CMake is used:

```bash
mkdir -p build && cd build
cmake ..
make
```

---

## 5. Writing RTL

### 5.1 Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Files | snake_case | `graph_scheduler.sv` |
| Modules | snake_case | `graph_scheduler` |
| Signals | snake_case | `data_valid` |
| Parameters | UPPER_SNAKE_CASE | `FIFO_DEPTH` |
| Constants | UPPER_SNAKE_CASE | `MSG_TYPE_EVALUATE` |
| Active-low | _n suffix | `reset_n` |

### 5.2 File Organization

One module per file unless tightly coupled. File name matches module name.

### 5.3 Interface Documentation

Every module must include a header comment documenting:

```
// Module:    <name>
// Purpose:   <brief description>
// Inputs:    <list of input ports>
// Outputs:   <list of output ports>
// Params:    <parameter list>
// Protocol:  <interface protocol description>
// Depends:   <related modules>
```

### 5.4 Coding Standards

- **Synchronous design:** All modules should be synchronous to a single clock domain where possible
- **Registered outputs:** Outputs should be registered to avoid combinational paths
- **Assertions:** Use SystemVerilog assertions for invariants
- **Parameters:** Use parameters for all configurable sizes
- **No latches:** All synthesis targets must be latch-free
- **Reset:** Active-low synchronous or asynchronous reset

### 5.5 Simulation Guidelines

- Every module must have a testbench
- Testbenches should be self-checking
- Generate VCD/FST waveforms for debugging
- Test edge cases: empty, full, overflow, underflow
- Test with randomized inputs when possible

---

## 6. Adding a New Module

1. Write the specification document in `docs/architecture/`
2. Create the RTL file in the appropriate `rtl/` subdirectory
3. Create a testbench in `simulation/verilator/` or `simulation/icarus/`
4. Add assertions to the RTL
5. Run simulation and verify
6. Add verification script if appropriate

---

## 7. Development Workflow

```
1. Create an issue describing the feature or bug
2. Write or update the specification document
3. Implement the RTL
4. Write or update testbenches
5. Run simulation and verify
6. Submit a pull request
7. Code review
8. Merge after CI passes
```

### 7.1 Commit Messages

Follow conventional commits:

```
type(scope): description

type: feat, fix, docs, style, refactor, perf, test, ci, chore
scope: module or area of change
```

Examples:
```
feat(scheduler): add dependency tracking
fix(heap): correct allocation alignment
docs(architecture): update memory map
```

---

## 8. Debugging

### 8.1 Waveform Analysis

```bash
# Run a simulation that generates a VCD file
# Then view with GTKWave
gtkwave build/sim/output.vcd
```

### 8.2 Simulation Debug

Verilator supports tracing:
```bash
verilator --trace --cc module.sv --exe tb_module.cpp
```

---

## 9. Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for detailed contribution guidelines.

---

## 10. Getting Help

- Open an issue on GitHub
- Discuss in project discussions
- Review architecture documents in `docs/architecture/`

---

## Appendix A: Quick Reference

```bash
# Lint a single file
verilator --lint-only -Wall rtl/fpu/my_module.sv

# Simulate with Icarus
iverilog -o build/sim/test.vvp rtl/fpu/my_module.sv simulation/icarus/tb_my_module.sv
vvp build/sim/test.vvp

# Simulate with Verilator
verilator --cc --exe --build rtl/fpu/my_module.sv simulation/verilator/tb_my_module.cpp
./obj_dir/Vmy_module
```

## Appendix B: Tools Checklist

- [ ] Verilator installed (`verilator --version`)
- [ ] Icarus Verilog installed (`iverilog -V`)
- [ ] GTKWave installed (`gtkwave --version`)
- [ ] Python 3 installed (`python3 --version`)
- [ ] Make installed (`make --version`)
