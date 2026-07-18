# Lucid Coding Standards

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Language

### 1.1 RTL

- Primary: SystemVerilog (IEEE 1800-2017)
- Use only synthesizable subset for RTL
- Testbenches may use non-synthesizable constructs
- `.sv` extension for SystemVerilog files

### 1.2 Firmware

- C11 or C++17 for bare-metal firmware
- Rust is acceptable for future firmware components

### 1.3 Scripts

- Python 3.10+ for verification and tooling
- Shell (zsh) for build scripts (macOS compatibility)

---

## 2. Naming

| Element | Convention | Example |
|---------|-----------|---------|
| Files | snake_case | `graph_scheduler.sv` |
| Modules | snake_case | `graph_scheduler` |
| Interfaces | snake_case | `wishbone_interface` |
| Signals | snake_case | `data_valid`, `addr_out` |
| Parameters | UPPER_SNAKE_CASE | `FIFO_DEPTH` |
| Localparams | UPPER_SNAKE_CASE | `STATE_IDLE` |
| Constants (Python) | UPPER_SNAKE_CASE | `MSG_TYPE_EVALUATE` |
| Functions | snake_case | `get_heap_usage()` |

Active-low signals: suffix with `_n` (e.g., `reset_n`)
Clock signals: suffix with `_clk` (e.g., `sys_clk`)

---

## 3. File Organization

### 3.1 Module Header

Every RTL file must begin with:

```systemverilog
// Module:    <module_name>
// Purpose:   <one-line description>
// Inputs:    <list of input ports with widths>
// Outputs:   <list of output ports with widths>
// Params:    <parameter list with defaults>
// Protocol:  <interface protocol summary>
// Depends:   <other modules required>
// Clock:     <clock domain>
// Reset:     <reset type and polarity>
```

### 3.2 File Structure

```
// License header (if applicable)
// Module header comment
`timescale / `default_nettype
module declaration
  parameter declarations
  localparam declarations
  port declarations
  signal declarations
  logic body (assign, always blocks)
  module instantiations
endmodule
```

---

## 4. RTL Style

### 4.1 Synchronous Design

- All modules synchronous to a single clock domain
- Use only posedge clock
- Registered outputs preferred over combinational

```systemverilog
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        output_data <= '0;
    end else begin
        output_data <= next_output_data;
    end
end
```

### 4.2 Always Blocks

- Use `always_comb` for combinational logic
- Use `always_ff` for sequential logic
- Use `always_latch` only when explicitly intended (avoid if possible)

### 4.3 No Latches

All combinational blocks must assign every signal in every path.

### 4.4 Parameters

Use parameters for all configurable sizes. No hard-coded widths.

```systemverilog
parameter int FIFO_DEPTH = 8;
parameter int DATA_WIDTH = 32;
```

### 4.5 Interfaces

Use SystemVerilog `interface` for standard protocols (Wishbone, FIFO handshake).

### 4.6 Assertions

Use SystemVerilog assertions for module invariants:

```systemverilog
assert property (@(posedge clk) !(full && wr_en));
assert property (@(posedge clk) !(empty && rd_en));
```

---

## 5. Verification

- Every module must have a self-checking testbench
- Testbenches should generate VCD/FST waveforms
- Test edge cases: boundary conditions, overflow, full/empty queues
- Use randomization for stress testing
- All tests must pass before merge

---

## 6. Documentation

- All public interfaces documented in header comments
- Architecture decisions documented in `docs/adr/`
- Module behavior documented in `docs/architecture/`
- README files for subdirectories with multiple modules

---

## 7. Testing

```bash
# Before submitting a PR
make lint            # No lint warnings
make sim-verilator   # All Verilator tests pass
make sim-icarus      # All Icarus tests pass
make verify          # All verification passes
```
