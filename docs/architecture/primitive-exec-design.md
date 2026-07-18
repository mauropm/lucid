# Lucid Phase 4: Primitive Execution

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Scope

Phase 4 implements the primitive execution units that perform arithmetic, comparison, and other basic operations. These units communicate with the scheduler via the message system: they receive work messages, compute results, and send response messages.

Phase 4 delivers:
- A generic primitive execution unit (arithmetic + comparison)
- Message protocol for scheduler ↔ execution unit communication
- Integration of the execution unit with the existing message router
- Testbench for dispatch and execution

---

## 2. Architecture

```
┌──────────────┐     Message System     ┌──────────────────┐
│  Scheduler   │────────────────────────→│ Primitive Exec   │
│  (Phase 3)   │  EXEC_PRIM msg         │ Unit             │
│              │←────────────────────────│                  │
│              │  PRIM_RESULT msg        │ ADD, SUB, MUL,   │
└──────────────┘                         │ DIV, CMP, ...    │
                                         └──────────────────┘
```

### 2.1 Message Flow

1. Scheduler pops a ready node from the queue
2. Scheduler sends an EXEC_PRIM message to the primitive execution unit
3. Message contains: node_id, opcode, operand0, operand1
4. Execution unit decodes the opcode and computes the result
5. Execution unit sends a PRIM_RESULT message back to the scheduler
6. Message contains: node_id, result
7. Scheduler receives the result and updates the node's result field
8. Scheduler processes dependents

---

## 3. Message Protocol

### 3.1 EXEC_PRIM (Scheduler → Execution Unit)

Multi-word message (3 words):

| Word | Content | Description |
|------|---------|-------------|
| 0 | Header | DEST=ARITH(1), SRC=SCHED(0), TYPE=EXEC_PRIM(0x30), LAST=0 |
| 1 | Data 0 | {node_id[7:0], opcode[7:0], operand0[15:0]} (packed) |
| 2 | Data 1 | operand1[31:0], LAST=1 |

### 3.2 PRIM_RESULT (Execution Unit → Scheduler)

Multi-word message (2 words):

| Word | Content | Description |
|------|---------|-------------|
| 0 | Header | DEST=SCHED(0), SRC=ARITH(1), TYPE=PRIM_RESULT(0x31), LAST=0 |
| 1 | Data | {node_id[7:0], result[23:0]}, LAST=1 |

---

## 4. Primitive Execution Unit

### 4.1 Supported Operations

| Opcode | Name | Formula |
|--------|------|---------|
| 0x10 | ADD | a + b |
| 0x11 | SUB | a - b |
| 0x12 | MUL | a × b |
| 0x13 | DIV | a ÷ b (integer) |
| 0x14 | MOD | a mod b |
| 0x15 | EQ | a == b |
| 0x16 | LT | a < b (signed) |
| 0x17 | GT | a > b (signed) |
| 0x18 | LE | a ≤ b (signed) |
| 0x19 | GE | a ≥ b (signed) |

### 4.2 Interface

| Port | Width | Direction | Description |
|------|-------|-----------|-------------|
| clk | 1 | In | Clock |
| reset_n | 1 | In | Reset |
| msg_in_valid | 1 | In | Message valid |
| msg_in_data | 32 | In | Message data |
| msg_in_last | 1 | In | Last word |
| msg_in_ready | 1 | Out | Ready for message |
| msg_out_valid | 1 | Out | Response valid |
| msg_out_data | 32 | Out | Response data |
| msg_out_last | 1 | Out | Last word of response |
| msg_out_ready | 1 | In | Response accepted |

### 4.3 Implementation

The execution unit:
1. Receives a 3-word EXEC_PRIM message
2. Extracts node_id, opcode, op0, op1
3. Computes the result in 1 cycle (combinational)
4. Sends a 2-word PRIM_RESULT message back

---

## 5. Scheduler Message Integration

The Phase 3 scheduler computed results inline. For Phase 4, it dispatches to the external execution unit:

1. In S_EXEC state: instead of computing inline, send an EXEC_PRIM message
2. Wait in S_WAIT_RESULT state for the response
3. Receive PRIM_RESULT, extract node_id and result
4. Proceed to S_RESULT state (write result, update deps)

---

## 6. Verification Plan

| Test | Description |
|------|-------------|
| Single ADD | Execute 2 + 3 = 5 via message dispatch |
| Single MUL | Execute 3 × 4 = 12 via message dispatch |
| Chain | Execute (2 + 3) × 4 = 20 in the scheduler, with primitives dispatched |
| Comparison | Execute 5 < 3 = false |
| Multiple units | (future) Dispatch to different units concurrently |
