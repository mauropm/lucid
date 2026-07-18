# Lucid Message Protocol Specification

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Overview

All communication between modules within the Lucid FPU uses FIFO-based message passing. No module directly reads or writes another module's internal state. This decouples execution units, enables independent testing, and simplifies verification.

---

## 2. Message Format

### 2.1 Base Message (32 bits)

| Bits | Field | Description |
|------|-------|-------------|
| 31:24 | TYPE | Message type (8 bits, 256 types) |
| 23:16 | FLAGS | Control flags (8 bits) |
| 15:0 | TAG | Correlation tag (16 bits) |

### 2.2 Extended Messages

Many message types have one or more payload words following the header:

#### 2.2.1 Standard Extended Message

| Word | Content |
|------|---------|
| 0 | Header (TYPE | FLAGS | TAG) |
| 1 | Payload word 0 |
| 2 | Payload word 1 |
| ... | ... |

### 2.3 Flags

| Bit | Name | Description |
|-----|------|-------------|
| 0 | RESPONSE_REQUIRED | Sender expects a response message |
| 1 | HIGH_PRIORITY | Message is high priority |
| 2 | ERROR | Message indicates an error condition |
| 3 | BROADCAST | Message is a broadcast to all units |
| 4 | LAST | Last message in a sequence |
| 5-7 | RESERVED | Reserved for future use |

---

## 3. Message Types

### 3.1 System Messages (0x00-0x0F)

| Code | Name | Payload | Description |
|------|------|---------|-------------|
| 0x00 | NOP | None | No operation (heartbeat) |
| 0x01 | RESET | None | Reset receiver to known state |
| 0x02 | HALT | None | Halt execution |
| 0x03 | ACK | TAG | Acknowledge receipt of a message |
| 0x04 | NACK | TAG + ERROR_CODE | Negative acknowledgment |
| 0x05 | STATUS_REQ | None | Request status |
| 0x06 | STATUS_RESP | STATUS_DATA | Status response |

### 3.2 Graph Messages (0x10-0x1F)

| Code | Name | Payload | Description |
|------|------|---------|-------------|
| 0x10 | GRAPH_LOAD | PTR + SIZE | Load graph into graph memory |
| 0x11 | GRAPH_EXECUTE | ROOT_ID | Start execution of a graph |
| 0x12 | GRAPH_ABORT | None | Abort current graph execution |
| 0x13 | NODE_READY | NODE_ID | A node's dependencies are satisfied |
| 0x14 | NODE_SCHEDULE | NODE_ID | Schedule a node for execution |
| 0x15 | NODE_RESULT | NODE_ID + VALUE | Node execution result |
| 0x16 | NODE_ERROR | NODE_ID + ERROR_CODE | Node execution error |
| 0x17 | GRAPH_COMPLETE | ROOT_ID + VALUE | Graph execution complete |

### 3.3 Heap Messages (0x20-0x2F)

| Code | Name | Payload | Description |
|------|------|---------|-------------|
| 0x20 | ALLOCATE | SIZE | Request heap allocation |
| 0x21 | ALLOCATE_RESP | PTR | Allocation result |
| 0x22 | ALLOCATE_FAIL | SIZE | Allocation failed (OOM) |
| 0x23 | WRITE_HEADER | PTR + HEADER | Write object header |
| 0x24 | WRITE_FIELD | PTR + OFFSET + VALUE | Write object field |
| 0x25 | READ_FIELD | PTR + OFFSET | Request object field read |
| 0x26 | READ_FIELD_RESP | VALUE | Field read result |
| 0x27 | HEAP_INFO | None | Request heap statistics |
| 0x28 | HEAP_INFO_RESP | STATS | Heap statistics response |

### 3.4 Execution Messages (0x30-0x3F)

| Code | Name | Payload | Description |
|------|------|---------|-------------|
| 0x30 | EXECUTE_PRIMITIVE | PRIM_ID + ARGS | Execute primitive operation |
| 0x31 | PRIMITIVE_RESULT | PRIM_ID + RESULT | Primitive execution result |
| 0x32 | CREATE_CLOSURE | ARITY + ENV | Create a closure |
| 0x33 | CLOSURE_RESULT | CLOSURE_PTR | Closure created |
| 0x34 | APPLY | CLOSURE_PTR + ARGS | Apply a function |
| 0x35 | APPLY_RESULT | VALUE | Function application result |
| 0x36 | TAIL_CALL | CLOSURE_PTR + ARGS | Perform tail call |
| 0x37 | LOOKUP | ENV_PTR + SYM_PTR | Lookup variable in environment |
| 0x38 | LOOKUP_RESULT | SYM_PTR + VALUE | Variable lookup result |
| 0x39 | ENV_EXTEND | ENV_PTR + BINDINGS | Extend environment |

### 3.5 GC Messages (0x40-0x4F)

| Code | Name | Payload | Description |
|------|------|---------|-------------|
| 0x40 | GC_REQUEST | REASON | Request garbage collection |
| 0x41 | GC_START | None | GC cycle started |
| 0x42 | GC_MARK | PTR | Mark an object as reachable |
| 0x43 | GC_SWEEP | None | Start sweep phase |
| 0x44 | GC_EVACUATE | PTR | Evacuate object (copying GC) |
| 0x45 | GC_COMPLETE | STATS | GC cycle complete |
| 0x46 | GC_ROOT_ADD | PTR | Add a GC root |
| 0x47 | GC_ROOT_REMOVE | PTR | Remove a GC root |

### 3.6 Continuation Messages (0x50-0x5F)

| Code | Name | Payload | Description |
|------|------|---------|-------------|
| 0x50 | CONTINUATION_SAVE | STATE | Save current continuation |
| 0x51 | CONTINUATION_SAVED | CONT_PTR | Continuation saved |
| 0x52 | CONTINUATION_RESTORE | CONT_PTR | Restore a continuation |
| 0x53 | CONTINUATION_RESTORED | None | Continuation restored |

### 3.7 Debug Messages (0xF0-0xFF)

| Code | Name | Payload | Description |
|------|------|---------|-------------|
| 0xF0 | DEBUG_BREAK | None | Breakpoint hit |
| 0xF1 | DEBUG_STEP | None | Single step |
| 0xF2 | DEBUG_PEEK | ADDR | Read memory at address |
| 0xF3 | DEBUG_PEEK_RESP | ADDR + DATA | Memory read response |
| 0xF4 | DEBUG_POKE | ADDR + DATA | Write memory at address |
| 0xF5 | DEBUG_LOG | MESSAGE | Log message |
| 0xFF | ERROR | ERROR_CODE | Unrecoverable error |

---

## 4. Message Flow Patterns

### 4.1 Request-Response

```
Sender                    Receiver
  │                          │
  │────── REQUEST ──────────>│
  │    (RESPONSE_REQUIRED)   │
  │                          │
  │<───── RESPONSE ──────────│
  │    (matching TAG)        │
```

### 4.2 Fire-and-Forget

```
Sender                    Receiver
  │                          │
  │────── MESSAGE ──────────>│
  │    (no RESPONSE_REQUIRED)│
```

### 4.3 Broadcast

```
Sender                    All Receivers
  │                          │
  │────── BROADCAST ────────>│ (to each)
  │    (BROADCAST flag set)  │
```

### 4.4 Allocation Flow

```
Execution Unit         Heap Controller
     │                       │
     │──── ALLOCATE ────────>│
     │                       │── update free_ptr
     │                       │── write header
     │<── ALLOCATE_RESP ─────│
     │                       │
     │── use allocated ptr ─>│
```

---

## 5. FIFO Interface

### 5.1 FIFO Signals

Each message FIFO uses a standard ready/valid handshake:

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| clk | 1 | In | Clock |
| reset_n | 1 | In | Active-low reset |
| wr_en | 1 | In | Write enable |
| wr_data | 32 | In | Write data |
| full | 1 | Out | FIFO is full |
| rd_en | 1 | In | Read enable |
| rd_data | 32 | Out | Read data |
| empty | 1 | Out | FIFO is empty |
| count | log2(DEPTH) | Out | Number of entries |

### 5.2 FIFO Width

Standard FIFO width is 32 bits. Multi-word messages are sent as consecutive writes/reads.

### 5.3 FIFO Depth

| Connection | Default Depth | Rationale |
|------------|--------------|-----------|
| Scheduler → Execution Units | 8 | Short pipeline of ready nodes |
| Execution Units → Scheduler | 16 | Results may batch up |
| Heap Controller → Scheduler | 4 | Allocation requests are infrequent |
| GC → Scheduler | 4 | GC messages are rare |
| Message Dispatcher → Units | 8 | General messaging |

---

## 6. Module Interface Contract

Every module that communicates via messages must implement:

```
Input:  message_fifo_in   (32-bit, with handshake)
Output: message_fifo_out  (32-bit, with handshake)
```

### 6.1 Processing Model

1. Read message from input FIFO
2. Decode TYPE field
3. If multi-word, read additional payload words
4. Process message
5. If RESPONSE_REQUIRED, send response
6. Update status registers

### 6.2 Error Handling

- Unrecognized message type: send NACK with ERROR_UNKNOWN_TYPE
- Cannot process now: send NACK with ERROR_BUSY
- Fatal error: send ERROR and enter halted state

---

## 7. Implementation Notes

### 7.1 Message Dispatcher

The message dispatcher routes messages between modules. It maintains a routing table:

```
Module ID → FIFO Output
```

When a message arrives with a BROADCAST flag, it is sent to all registered modules.

### 7.2 Flow Control

Backpressure is handled by the FIFO full/empty signals. If a destination FIFO is full, the sender must wait. Deadlock avoidance:
- Allocate response FIFOs with sufficient depth
- Never wait for a response while holding a lock
- Use timeouts or watchdog timers

### 7.3 Message Ordering

Messages on the same FIFO are ordered. Messages on different FIFOs have no guaranteed order. If ordering is required, use the TAG field for reassembly.
