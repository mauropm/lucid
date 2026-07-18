# Lucid Phase 1: Platform

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Scope

Phase 1 establishes the hardware platform that supports all later phases. It delivers:
- A functional Wishbone B4 bus matrix connecting CPU, memory, and peripherals
- A UART peripheral for serial communication (REPL, debug)
- An RV32IM management CPU capable of running compiled C code
- On-chip memory (boot ROM, management RAM)
- Clock generation (PLL wrapper)
- A top-level integration for the Tang Nano 20K reference board

Phase 1 does **not** include:
- The Lucid FPU (Phase 2+)
- Caches or MMU (not needed for management CPU)
- Interrupt controller (simple polling initially)
- SD card or SPI (future phase)

---

## 2. Architecture

```
                ┌──────────────────────────────────────┐
                │            Top Level                  │
                │  (Tang Nano 20K)                      │
                │                                       │
                │  ┌──────┐    ┌──────────────────┐     │
                │  │ PLL  │    │  Wishbone Bus     │     │
                │  │27→100│───>│  Matrix           │     │
                │  └──────┘    │  (2 masters,      │     │
                │              │   6 slaves)       │     │
                │              └──┬──┬──┬──┬──┬──┬─┘     │
                │                 │  │  │  │  │  │       │
                │  ┌────────┐    │  │  │  │  │  │       │
                │  │RV32IM  │<───┘  │  │  │  │  │       │
                │  │CPU     │       │  │  │  │  │       │
                │  └────────┘       │  │  │  │  │       │
                │          ┌────────┘  │  │  │  │       │
                │          │  ┌────────┘  │  │  │       │
                │          │  │  ┌────────┘  │  │       │
                │          │  │  │  ┌────────┘  │       │
                │          │  │  │  │  ┌────────┘       │
                │          │  │  │  │  │                │
                │     ┌────┘  │  │  │  └──────┐         │
                │     │   ┌───┘  │  └─────┐    │        │
                │     ▼   ▼      ▼        ▼    ▼        │
                │  ┌────┐┌────┐┌────┐┌────┐┌────┐      │
                │  │Boot││Mgmt││UART││Debug││FPU │      │
                │  │ROM ││RAM ││    ││ Int││Ctrl│      │
                │  └────┘└────┘└────┘└────┘└────┘      │
                │                                       │
                └───────────────────────────────────────┘
```

### 2.1 Bus Architecture

The Wishbone B4 bus matrix connects:

| Slave | Address Range | Size | Type |
|-------|--------------|------|------|
| Boot ROM | 0x00000000 - 0x00000FFF | 4 KB | ROM (preloaded) |
| Management RAM | 0x00010000 - 0x00010FFF | 4 KB | RAM |
| UART | 0x00020000 - 0x0002001F | 32 B | Peripheral |
| Debug | 0x00030000 - 0x000300FF | 256 B | Peripheral |
| FPU Control | 0x00100000 - 0x001000FF | 256 B | Control |
| Graph Memory | 0x00200000 - 0x00203FFF | 16 KB | RAM |

Arbitration: fixed priority (CPU has highest priority). Only one master in Phase 1.

### 2.2 Clock Domains

| Domain | Frequency | Source | Used By |
|--------|-----------|--------|---------|
| sys_clk | 100 MHz | PLL (27 MHz → 100 MHz) | CPU, Bus, UART, Memory |
| uart_clk | 1.8432 MHz | Derived from sys_clk | UART baud rate |

---

## 3. UART Peripheral

### 3.1 Specifications

| Parameter | Value |
|-----------|-------|
| Protocol | 8N1 (8 data bits, no parity, 1 stop bit) |
| Baud rate | 115200 (default, configurable) |
| RX FIFO | 8 bytes |
| TX FIFO | 8 bytes |
| Interface | Wishbone B4 slave |

### 3.2 Register Map

| Offset | Access | Name | Description |
|--------|--------|------|-------------|
| 0x00 | R/W | UART_CTRL | Control (enable, tx_en, rx_en, interrupt enable) |
| 0x04 | R/W | UART_BAUD | Baud rate divisor (default: 868 = 100MHz / 115200) |
| 0x08 | R | UART_STATUS | Status (tx_busy, rx_ready, tx_full, rx_empty, error) |
| 0x0C | W | UART_TX_DATA | Transmit data (write-only) |
| 0x10 | R | UART_RX_DATA | Receive data (read-only) |
| 0x14 | R | UART_RX_LEVEL | Number of bytes in RX FIFO |

### 3.3 Operation

**Transmit:**
1. Read STATUS to check TX is not busy
2. Write byte to TX_DATA
3. UART serializes and transmits

**Receive:**
1. Read STATUS to check RX_READY
2. Read byte from RX_DATA
3. Byte is removed from RX FIFO

---

## 4. Boot ROM

### 4.1 Layout (4 KB)

| Offset | Content |
|--------|---------|
| 0x0000 | Reset vector (jump to 0x0100) |
| 0x0004 | Exception vector (jump to 0x0200) |
| 0x0100 | Boot code: initialize stack pointer, copy .data, clear .bss, jump to main |
| 0x0200 | Exception handler stub |
| 0x0300 - 0x0FFF | Application code / REPL |

### 4.2 Initial Program

The boot ROM contains a minimal program that:
1. Sets the stack pointer to top of Management RAM
2. Initializes the UART
3. Prints a welcome message
4. Enters a REPL loop waiting for serial commands

---

## 5. Management CPU (RV32IM)

### 5.1 Specification

| Feature | Support |
|---------|---------|
| Base ISA | RV32I |
| Multiply | M extension (mul, mulh, mulhsu, mulhu, div, divu, rem, remu) |
| Privilege | Machine mode only |
| CSR | Minimal: cycle, cycleh, instret, instreth, mepc, mcause, mtvec, mscratch |
| Interrupts | External interrupt (MEI) via UART |
| Bus | Wishbone B4 master |

### 5.2 Pipeline

A minimal 3-stage pipeline:

```
Fetch → Decode → Execute/Memory/Writeback
```

Stage 1: Fetch instruction from Wishbone
Stage 2: Decode instruction, read register file
Stage 3: ALU operation, memory access, writeback

Hazards:
- Data hazards: forwarding from EX/WB to ID
- Control hazards: branch not-taken prediction (1-cycle mispredict penalty)
- Load-use: 1-cycle stall

### 5.3 Implementation Approach

The CPU is implemented as a single-cycle design initially (one instruction per clock cycle). This is simpler to verify and sufficient for a management processor. Multi-cycle or pipelined versions can be introduced later if performance requires it.

Actually, let me reconsider. For a management CPU that just boots, runs UART I/O, and runs a REPL, a single-cycle implementation at 100 MHz should provide ~100 MIPS, which is more than adequate. The CPU is not the performance bottleneck.

---

## 6. Memory Subsystem

### 6.1 Boot ROM

- 4 KB initialized ROM
- Contents preloaded during FPGA configuration
- Mapped at 0x00000000

### 6.2 Management RAM

- 4 KB dual-port BRAM
- Mapped at 0x00010000
- Stack and data segment for firmware

---

## 7. Verification Plan

| Test | Description |
|------|-------------|
| Wishbone address decode | Verify each slave is selected at correct address range |
| Wishbone arbitration | Verify two masters get bus access |
| UART TX | Transmit byte, verify serial output waveform |
| UART RX | Feed serial input, verify received byte |
| UART loopback | Connect TX to RX, verify data integrity |
| CPU instruction test | Execute known instruction sequence, verify register state |
| CPU load/store | Write to memory, read back, verify |
| CPU UART interaction | CPU reads/writes UART registers |
| Boot ROM execution | CPU boots from ROM, executes code |
| Top-level integration | All modules connected, clock running |

---

## 8. Implementation Plan

1. Fix Wishbone bus (plain ports for Icarus compatibility)
2. Implement UART (transmitter, receiver, Wishbone interface)
3. Implement RV32IM CPU (single-cycle, minimal)
4. Implement boot ROM (with initial program)
5. Implement BRAM for management RAM
6. Implement PLL wrapper
7. Create top-level integration
8. Write testbench for each module
9. Write integration testbench
10. Simulate and verify

Each module is developed independently with its own testbench, then integrated.
