# Lucid Phase 3: Graph IR Execution

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Scope

Phase 3 implements the graph execution engine for Lucid IR. It delivers:
- Graph memory controller for storing and accessing Lucid IR nodes
- Dependency tracker that monitors node inputs and detects readiness
- Ready queue for scheduling nodes whose dependencies are satisfied
- Scheduler core state machine that orchestrates execution
- Node execution FSM that dispatches nodes to execution units via the message system
- Single-node and multi-node graph execution testbench

Phase 3 does **not** include:
- Primitive execution units (Phase 4)
- Heap allocation (Phase 5)
- Closures or environments (Phase 5)
- Garbage collection (Phase 8)
- Parallel execution (Phase 7)

---

## 2. Graph Execution Pipeline

```
                     ┌──────────────────────┐
                     │    Graph Memory      │
                     │  (Node Storage)      │
                     └──────────┬───────────┘
                                │
                     ┌──────────▼───────────┐
                     │  Dependency Tracker  │
                     │  (Counts ready inputs)│
                     └──────────┬───────────┘
                                │
                     ┌──────────▼───────────┐
                     │    Ready Queue       │
                     │  (Node IDs ready to  │
                     │   execute)           │
                     └──────────┬───────────┘
                                │
                     ┌──────────▼───────────┐
                     │  Scheduler Core      │
                     │  (State Machine)     │
                     └──────────┬───────────┘
                                │
              ┌─────────────────┼────────────────┐
              │                 │                │
     ┌────────▼───────┐  ┌─────▼──────┐  ┌──────▼────────┐
     │ Node Exec FSM  │  │ Node Exec  │  │ Node Exec     │
     │ (Dispatch via  │  │ FSM        │  │ FSM           │
     │  message bus)  │  │            │  │               │
     └────────────────┘  └────────────┘  └───────────────┘
              │                 │                │
              └─────────────────┼────────────────┘
                                │
                     ┌──────────▼───────────┐
                     │   Result Collector  │
                     │ (Writes results back │
                     │  to graph memory)   │
                     └─────────────────────┘
```

### 2.1 Execution Flow

1. **Graph Load:** Host CPU writes Lucid IR nodes into graph memory via Wishbone
2. **Graph Start:** Host sets scheduler control register to begin execution
3. **Dependency Scan:** Scheduler scans graph nodes, finds nodes with no dependencies (literals)
4. **Ready Queue:** Literal nodes are pushed to the ready queue
5. **Dispatch:** Scheduler pops ready nodes and dispatches them via the message system
6. **Execute:** Execution unit processes the node and returns a result
7. **Result Collection:** Scheduler receives the result and writes it to the node's result field
8. **Dependency Update:** Scheduler increments ready-input count for dependent nodes
9. **New Ready Nodes:** If all inputs of a dependent are ready, push to ready queue
10. **Repeat:** Continue until root node is complete

---

## 3. Node Memory Format

Each Lucid IR node occupies 6 words (24 bytes) in graph memory:

| Word | Field | Width | Description |
|------|-------|-------|-------------|
| 0 | STATE | 2 | Node state (idle, waiting, ready, done) |
| 0 | OPCODE | 8 | Node operation type |
| 0 | NUM_INPUTS | 6 | Number of input dependencies |
| 0 | READY_INPUTS | 6 | Count of satisfied inputs |
| 0 | FLAGS | 10 | Node flags |
| 1 | IMM0 | 32 | Immediate value / inline data |
| 2 | IMM1 | 32 | Second immediate value |
| 3 | RESULT | 32 | Pointer to heap result value |
| 4 | DEP_MASK | 32 | Bitmask of dependent nodes (up to 32) |
| 5 | INPUTS | 32 | Bitmask/array of input source node IDs |

Total: 192 bits per node.

### 3.1 Node States

| State | Value | Description |
|-------|-------|-------------|
| IDLE | 00 | Node loaded but not yet activated |
| WAITING | 01 | Activated, waiting for dependencies |
| READY | 10 | All dependencies satisfied, queued for execution |
| DONE | 11 | Execution complete, result available |

### 3.2 Opcodes

| Opcode | Name | Description |
|--------|------|-------------|
| 0x01 | LIT_INT | Integer literal |
| 0x02 | LIT_BOOL | Boolean literal |
| 0x10 | ADD | Integer addition |
| 0x11 | SUB | Integer subtraction |
| 0x12 | MUL | Integer multiplication |
| 0x1A | CONS | Pair construction |
| 0x20 | LAMBDA | Closure creation |
| 0x21 | APPLY | Function application |
| 0x23 | LOOKUP | Variable lookup |
| 0x30 | IF | Conditional |

---

## 4. Graph Memory Controller

### 4.1 Interface

| Port | Width | Direction | Description |
|------|-------|-----------|-------------|
| clk | 1 | In | Clock |
| reset_n | 1 | In | Reset |
| wb_cyc/stb/we/adr/dat_i/sel | various | In | Wishbone slave (host CPU writes graph) |
| wb_dat_o/ack | various | Out | Wishbone readback |
| node_addr | 32 | In | Node ID to read/write |
| node_wr_data | 192 | In | Full node data to write |
| node_wr_en | 1 | In | Node write enable |
| node_rd_data | 192 | Out | Full node data at addr |
| node_rd_valid | 1 | Out | Node read data valid |

### 4.2 Storage

Graph memory stores up to 512 nodes (configurable). Each node is 6 × 32-bit words. Total: 512 × 24 = 12,288 bytes. On the Tang Nano 20K this uses ~6 block RAMs.

---

## 5. Dependency Tracker

When a node completes execution, the dependency tracker:
1. Reads the completed node's DEP_MASK field (bitmap of dependents)
2. For each dependent node, increments READY_INPUTS
3. If READY_INPUTS == NUM_INPUTS, transitions the node to READY state
4. Pushes the ready node ID to the ready queue

### 5.1 Interface

| Port | Width | Direction | Description |
|------|-------|-----------|-------------|
| node_id | 32 | In | Completed node ID |
| result | 32 | In | Result value |
| trigger | 1 | In | Start dependency resolution |
| ready_node_id | 32 | Out | Newly ready node ID |
| ready_valid | 1 | Out | Ready node available |
| ready_ack | 1 | In | Consumed ready node |

---

## 6. Ready Queue

Standard FIFO storing node IDs ready for execution. Depth of 16 entries (configurable).

### 6.1 Interface

| Port | Width | Direction | Description |
|------|-------|-----------|-------------|
| push_id | 32 | In | Node ID to push |
| push_en | 1 | In | Push enable |
| pop_id | 32 | Out | Node ID popped |
| pop_en | 1 | In | Pop enable |
| empty | 1 | Out | Queue is empty |
| full | 1 | Out | Queue is full |

---

## 7. Scheduler Core

The scheduler core is the main state machine coordinating graph execution.

### 7.1 States

| State | Description |
|-------|-------------|
| LOAD | Waiting for host to load graph and start |
| SCAN | Scanning nodes for initial ready set |
| DISPATCH | Popping ready queue and sending to execution units |
| COLLECT | Waiting for execution results |
| UPDATE | Updating dependency counts and detecting new ready nodes |
| DONE | Graph execution complete |

### 7.2 Flow

```
LOAD → SCAN → DISPATCH → (message to execution unit)
                         → COLLECT → UPDATE → DISPATCH → ...
                         → DONE
```

### 7.3 Register Interface

| Offset | Width | Register | Description |
|--------|-------|----------|-------------|
| 0x00 | 32 | SCHED_CTRL | Control: start, halt, reset |
| 0x04 | 32 | SCHED_STATUS | Status: running, idle, done, error |
| 0x08 | 32 | SCHED_GRAPH_ADDR | Graph base address |
| 0x0C | 32 | SCHED_NODE_COUNT | Number of nodes in graph |
| 0x10 | 32 | SCHED_ROOT_NODE | Root node ID |
| 0x14 | 32 | SCHED_NODES_DONE | Nodes completed count |
| 0x18 | 32 | SCHED_ERROR | Error code |

---

## 8. Message Integration

The scheduler dispatches nodes by sending messages to execution units via the message system from Phase 2.

Message format for node execution:

| Word | Field | Description |
|------|-------|-------------|
| 0 | Header | DEST=ARITH, SRC=SCHED, TYPE=EXEC_PRIM |
| 1 | Node ID | Graph node ID being executed |
| 2 | Opcode | Node opcode |
| 3 | Input 0 | First input value |
| 4 | Input 1 | Second input value (if applicable) |

Result message:

| Word | Field | Description |
|------|-------|-------------|
| 0 | Header | DEST=SCHED, SRC=ARITH, TYPE=PRIM_RESULT |
| 1 | Node ID | Completed node ID |
| 2 | Result | Computed result value |

---

## 9. Implementation Plan

1. Create graph memory controller (BRAM-based node storage)
2. Create dependency tracker module
3. Create ready queue (FIFO wrapper)
4. Create scheduler core state machine
5. Connect scheduler to message system
6. Write testbench with a simple graph (literal + add)
7. Simulate and verify

---

## 10. Verification Plan

| Test | Description |
|------|-------------|
| Empty graph | Graph with 0 nodes, verify immediate done |
| Single literal | One LIT_INT node, verify it becomes ready and completes |
| Linear chain | A → B (B depends on A), verify ordering |
| Fan-in | A, B → C (C depends on both), verify C waits for both |
| Fan-out | A → B, C (B and C depend on A), verify both get result |
| Hello graph | lit1=2, lit2=3, mul(lit1,lit2)=6, verify result=6 |
| Dispatch via message | Literal node dispatched to arith unit via message, verify result |
