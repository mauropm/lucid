# Lucid Phase 2: Message System

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Scope

Phase 2 establishes the message passing infrastructure that all FPU modules use to communicate. It delivers:
- A message types package defining all message formats
- A message dispatcher with configurable routing table
- A message router/switch for N-to-M module communication
- Multi-module message-level simulation and verification

Phase 2 does **not** include:
- FPU execution units (Phase 3+)
- The graph scheduler (Phase 3)
- Heap or GC modules (Phase 5, 8)

---

## 2. Architecture

```
                    ┌──────────────────┐
                    │  Message         │
                    │  Dispatcher      │
                    │  (Routing Table) │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────▼───┐  ┌──────▼─────┐  ┌────▼────────┐
     │ Module 0   │  │ Module 1   │  │ Module 2    │
     │ (Scheduler)│  │ (Arith)    │  │ (Heap)      │
     │            │  │            │  │             │
     │ FIFO_in    │  │ FIFO_in    │  │ FIFO_in     │
     │ FIFO_out   │  │ FIFO_out   │  │ FIFO_out    │
     └────────────┘  └────────────┘  └─────────────┘
```

### 2.1 Module Interface

Every FPU module exposes a standard interface:

| Port | Width | Direction | Description |
|------|-------|-----------|-------------|
| clk | 1 | In | Clock |
| reset_n | 1 | In | Active-low reset |
| msg_in_valid | 1 | In | Input message valid |
| msg_in_data | 32 | In | Input message word |
| msg_in_ready | 1 | Out | Module ready for input |
| msg_in_last | 1 | In | Last word of multi-word message |
| msg_out_valid | 1 | Out | Output message valid |
| msg_out_data | 32 | Out | Output message word |
| msg_out_ready | 1 | In | Downstream ready |
| msg_out_last | 1 | Out | Last word of multi-word message |

### 2.2 Module IDs

| ID | Module | Description |
|----|--------|-------------|
| 0 | SCHEDULER | Graph scheduler (Phase 3) |
| 1 | ARITH | Primitive arithmetic unit (Phase 4) |
| 2 | COMPARE | Comparison unit (Phase 4) |
| 3 | CLOSURE | Closure unit (Phase 5) |
| 4 | ENV | Environment unit (Phase 5) |
| 5 | CONTINUATION | Continuation unit (Phase 6) |
| 6 | HEAP | Heap allocation unit (Phase 5) |
| 7 | GC | Garbage collector (Phase 8) |

---

## 3. Message Types

### 3.1 Header Format (32-bit)

| Bits | Field | Description |
|------|-------|-------------|
| 31:24 | DEST | Destination module ID |
| 23:16 | SRC | Source module ID |
| 15:8 | TYPE | Message type (256 types) |
| 7:0 | FLAGS | Control flags |

### 3.2 Control Flags

| Bit | Name | Description |
|-----|------|-------------|
| 0 | RESP_REQ | Response required |
| 1 | HIGH_PRIO | High priority |
| 2 | ERROR | Error condition |
| 3 | BROADCAST | Broadcast to all modules |
| 4 | LAST | Last word of multi-word message |

### 3.3 Message Types by Category

#### System (0x00-0x0F)

| Code | Name | Payload | Description |
|------|------|---------|-------------|
| 0x00 | NOP | — | No operation |
| 0x01 | RESET | — | Reset receiver |
| 0x02 | HALT | — | Halt execution |
| 0x03 | ACK | TAG | Acknowledgement |
| 0x04 | NACK | TAG+ERR | Negative ack |
| 0x05 | STATUS_REQ | — | Request status |
| 0x06 | STATUS_RESP | STATUS | Status response |

#### Graph (0x10-0x1F)

| Code | Name | Payload | Description |
|------|------|---------|-------------|
| 0x10 | GRAPH_LOAD | PTR+SIZE | Load graph |
| 0x11 | GRAPH_EXEC | ROOT_ID | Start execution |
| 0x12 | NODE_READY | NODE_ID | Dependencies satisfied |
| 0x13 | NODE_SCHEDULE | NODE_ID | Schedule node |
| 0x14 | NODE_RESULT | NODE_ID+VALUE | Node result |
| 0x15 | GRAPH_DONE | ROOT_ID+VALUE | Execution complete |

#### Heap (0x20-0x2F)

| Code | Name | Payload | Description |
|------|------|---------|-------------|
| 0x20 | ALLOC | SIZE | Allocate object |
| 0x21 | ALLOC_RESP | PTR | Allocation result |
| 0x22 | ALLOC_FAIL | SIZE+ERR | Allocation failed |

#### Primitive (0x30-0x3F)

| Code | Name | Payload | Description |
|------|------|---------|-------------|
| 0x30 | EXEC_PRIM | PRIM_ID+ARGS | Execute primitive |
| 0x31 | PRIM_RESULT | RESULT | Primitive result |

#### Closure (0x40-0x4F)

| Code | Name | Payload | Description |
|------|------|---------|-------------|
| 0x40 | MAKE_CLOSURE | ARITY+ENV | Create closure |
| 0x41 | CLOSURE_RESULT | CLOSURE_PTR | Closure created |
| 0x42 | APPLY | CLOSURE+ARGS | Apply function |

#### GC (0x50-0x5F)

| Code | Name | Payload | Description |
|------|------|---------|-------------|
| 0x50 | GC_TRIGGER | REASON | Trigger GC |
| 0x51 | GC_DONE | STATS | GC complete |
| 0x52 | GC_MARK | PTR | Mark object |

---

## 4. Message Dispatcher

### 4.1 Architecture

The dispatcher maintains a routing table indexed by destination module ID. Each entry contains:
- Output FIFO pointer
- Module ready flag
- Priority level

### 4.2 Routing Logic

```
1. Receive message header from input
2. Extract DEST field
3. If DEST is BROADCAST:
     Send to all modules
4. Else:
     Look up DEST in routing table
     If module is ready:
       Forward message to module's input FIFO
     Else:
       Buffer or stall
```

### 4.3 Register Interface

| Offset | Width | Register | Description |
|--------|-------|----------|-------------|
| 0x00 | 32 | MSG_CTRL | Dispatcher control |
| 0x04 | 32 | MSG_STATUS | Dispatcher status |
| 0x08 | 32 | MSG_ROUTE_N | Routing table entry N |
| 0x10+N*4 | 32 | MSG_STAT_N | Module N statistics |

---

## 5. Message Router / Switch

For N modules communicating with each other, a crossbar switch routes messages from any source to any destination. The router uses the DEST field in the message header to determine routing.

### 5.1 Crossbar Architecture

```
Source 0 ──┬──> Demux ──> Dest 0
Source 1 ──┼──> Demux ──> Dest 1
Source 2 ──┼──> Demux ──> Dest 2
  ...       │     ...
Source N ──┴──> Demux ──> Dest N

Each (Source, Destination) pair has dedicated flow control.
```

### 5.2 Arbitration

When multiple sources send to the same destination simultaneously, a round-robin arbiter selects which source is granted access.

---

## 6. Implementation Plan

1. Create message types header (`rtl/messages/message_types.sv`)
2. Enhance FIFO (already done in Phase 0/1)
3. Implement message router (crossbar switch with arbitration)
4. Implement message dispatcher (routing table manager)
5. Write module-to-module testbench
6. Verify with multiple concurrent message flows

---

## 7. Verification Plan

| Test | Description |
|------|-------------|
| Single message | One module sends to another, verify delivery |
| Broadcast | One module broadcasts to all, verify all receive |
| Multi-word | Multi-word message, verify all words delivered in order |
| Backpressure | Full FIFO, verify stall/recovery |
| Contention | Multiple sources to one destination, verify arbitration |
| Routing table | Program routing table, verify routing changes |
| Status query | Request status from module, verify response |
| Error handling | Invalid destination, verify error response |
