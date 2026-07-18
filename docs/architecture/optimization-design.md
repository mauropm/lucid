# Lucid Phase 9: Optimization

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Scope

Phase 9 optimizes the Lucid RTL for the Tang Nano 20K reference board (Gowin GW2AR-18 FPGA). It delivers:
- A top-level module integrating all subsystems with PLL, I/O, and reset
- Yosys synthesis scripts and Makefile targets
- Timing constraints for 100 MHz operation
- Synthesis and timing analysis results
- Optimizations for area and critical paths

---

## 2. Target Constraints

| Parameter | Value | Notes |
|-----------|-------|-------|
| FPGA | GW2AR-18 (Tang Nano 20K) | 20,736 LUT4, 72 BRAM (9K), 32 DSP |
| Clock | 100 MHz | PLL from 27 MHz external |
| LUT budget | ~15,000 | Leave margin for routing |
| BRAM budget | ~60 of 72 | For node memory, heap, buffers |
| DSP budget | 8 of 32 | Multipliers for M extension |

---

## 3. Top-Level Architecture

```
┌───────────────────── Tang Nano 20K ─────────────────────┐
│                                                          │
│  27 MHz ──→ PLL ──→ 100 MHz ──→ System Clock            │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │                  lucid_top                         │  │
│  │                                                    │  │
│  │  ┌─────────┐  ┌─────────┐  ┌──────────────────┐   │  │
│  │  │ RV32IM  │  │ Wishbone│  │ Graph Scheduler  │   │  │
│  │  │ CPU     │←─→│ Bus     │←─→(Phase 3/7)      │   │  │
│  │  └─────────┘  └──┬──────┘  └──────────────────┘   │  │
│  │                  │                                  │  │
│  │  ┌──────────┐    │    ┌──────────┐                 │  │
│  │  │ Boot ROM │◄───┤    │ Mgmt RAM│◄───┤            │  │
│  │  └──────────┘    │    └──────────┘                 │  │
│  │                  │                                  │  │
│  │  ┌──────────┐    │    ┌──────────┐                 │  │
│  │  │ UART     │◄───┤    │ Graph    │◄───┤            │  │
│  │  └──────────┘    │    │ Memory   │                 │  │
│  │                  │    └──────────┘                 │  │
│  │  ┌──────────┐    │    ┌──────────┐                 │  │
│  │  │ Debug    │◄───┤    │ FPU      │◄───┤            │  │
│  │  └──────────┘    │    │ Control  │                 │  │
│  │                  └────└──────────┘                 │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  UART_TX ──→ GPIO                                        │
│  UART_RX ──→ GPIO                                        │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## 4. Pipeline Optimizations

### 4.1 CPU Pipeline

The RV32IM CPU uses a 3-state FSM (fetch, execute, load). For 100 MHz:
- Add pipeline registers between fetch and decode
- Register Wishbone inputs to break long paths
- Use registered BRAM outputs (1-cycle latency)

### 4.2 Scheduler Pipeline

The graph scheduler processes nodes sequentially. For timing:
- Register all node memory outputs
- Pipeline the result computation
- Break the dependency chain into 2-cycle updates

### 4.3 Bus Pipeline

The Wishbone bus:
- Registered address decoding
- Registered read data mux
- Add pipeline stage for long routes

---

## 5. Area Optimization

### 5.1 BRAM Utilization

| Module | BRAM | Notes |
|--------|------|-------|
| Boot ROM | 1 | 4 KB initialized ROM |
| Management RAM | 1 | 4 KB |
| Graph Memory | 4 | 512 × 6-word nodes |
| FPU Heap | 8 | 16 KB object heap |
| Scheduler State | 1 | Node tracking arrays |
| Total | 15 | Well within 72 BRAM budget |

### 5.2 LUT Optimization

- Remove unused opcodes from the CPU decoder
- Share ALU between CPU and scheduler (if feasible)
- Minimize priority encoders (use binary encoding)
- Remove debug counters in production builds

---

## 6. Synthesis Flow

```
                        ┌──────────┐
                        │  RTL     │
                        │  (.sv)   │
                        └────┬─────┘
                             │
                        ┌────▼─────┐
                        │  Yosys   │
                        │  synth   │
                        └────┬─────┘
                             │
                    ┌────────▼────────┐
                    │  nextpnr-gowin  │
                    │  place & route  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Gowin P&R      │
                    │  (optional)     │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Bitstream      │
                    │  (.fs)          │
                    └─────────────────┘
```

---

## 7. Verification Plan

| Test | Description |
|------|-------------|
| Yosys syntax check | All RTL files pass Yosys parsing |
| Synthesis report | LUT, FF, BRAM, DSP counts |
| Timing report | Critical path, slack at 100 MHz |
| Post-synth sim | Functional equivalence check |
