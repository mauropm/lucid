# Lucid Scheduler Specification

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Overview

The scheduler is the central control unit of the Lucid FPU. It is responsible for:
- Tracking node dependencies within a Lucid IR graph
- Maintaining the ready queue of nodes whose inputs are all available
- Dispatching ready nodes to execution units
- Receiving results and updating node state
- Notifying dependent nodes when their inputs become available

The scheduler behaves more like a GPU scheduler than a CPU instruction sequencer. Execution is driven by data readiness, not program order.

---

## 2. Scheduler Architecture

```
                    ┌──────────────────┐
                    │  Graph Memory     │
                    │  (Node State)     │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │ Dependency Tracker│
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │   Ready Queue     │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │  Dispatch Unit    │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────▼───┐  ┌──────▼─────┐  ┌────▼────────┐
     │ Execution   │  │ Execution  │  │ Execution   │
     │ Unit 0      │  │ Unit 1     │  │ Unit 2      │
     └────────┬───┘  └──────┬─────┘  └────┬────────┘
              │              │              │
              └──────────────┼──────────────┘
                             │
                    ┌────────▼─────────┐
                    │ Result Collector  │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │  Graph Memory     │
                    │  (Result Write)   │
                    └──────────────────┘
```

### 2.1 Main Components

| Component | Role |
|-----------|------|
| Dependency Tracker | Monitors node state, detects when all inputs are ready |
| Ready Queue | Holds node IDs ready for execution |
| Dispatch Unit | Assigns ready nodes to available execution units |
| Result Collector | Receives execution results and updates graph state |

---

## 3. Node State Machine

Each node in the graph passes through the following states:

```
    IDLE ──> WAITING ──> READY ──> EXECUTING ──> DONE
                    │                    │
                    └── (deptracker)     └── (result collector)
```

| State | Meaning |
|-------|---------|
| IDLE | Node has been loaded but not yet activated |
| WAITING | Node is activated, waiting for dependencies |
| READY | All dependencies satisfied, waiting in ready queue |
| EXECUTING | Node has been dispatched to an execution unit |
| DONE | Node execution complete, result available |

### 3.1 State Transitions

1. **IDLE → WAITING:** When a graph is loaded and the root node is activated. All nodes start in WAITING except literals which go directly to READY.
2. **WAITING → READY:** The dependency tracker detects that all input values are available. The node is enqueued in the ready queue.
3. **READY → EXECUTING:** The dispatch unit pops the node from the ready queue and sends it to an execution unit.
4. **EXECUTING → DONE:** The result collector receives the result. The node's result value is stored. Dependents are notified.

---

## 4. Dependency Tracking

### 4.1 Node Metadata in Graph Memory

Each node stores:

| Field | Width | Description |
|-------|-------|-------------|
| State | 2 | Current node state |
| Opcode | 8 | Node operation |
| InputCount | 6 | Number of inputs (0-63) |
| ReadyInputs | 6 | Count of ready inputs |
| Immediate0 | 32 | Inline data |
| Immediate1 | 32 | Inline data |
| ResultPtr | 32 | Pointer to result value |
| DependentMask/List | 32 | Tracking of dependent nodes |

### 4.2 Dependency Detection

When a node completes:
1. The scheduler reads the node's `DependentMask` or dependent list
2. For each dependent, it increments `ReadyInputs`
3. If `ReadyInputs == InputCount`, the dependent transitions to READY
4. The dependent is enqueued in the ready queue

### 4.3 Dependency Representation

For small graphs (≤ 32 nodes), a bitmask is used:

```
DependentMask[31:0]: bit i is set if node i depends on this node
```

For larger graphs, a linked list of dependent IDs is used.

---

## 5. Ready Queue

### 5.1 Queue Structure

The ready queue is a FIFO of node IDs ready for execution.

| Property | Specification |
|----------|--------------|
| Width | 32 bits (node ID) |
| Depth | Configurable (default 16) |
| Implementation | BRAM-based FIFO |
| Priority | Optional priority field for critical nodes |

### 5.2 Queue Operations

```
Push(node_id)    → Add node to ready queue
Pop()            → Remove and return highest-priority node
Peek()           → View top node without removing
Count()          → Return number of ready nodes
```

### 5.3 Priority (Future)

The scheduler may support priority levels:
- High priority: continuation captures/restores, GC operations
- Normal priority: application, primitive execution
- Low priority: thunk forcing, speculative execution

---

## 6. Dispatch Unit

### 6.1 Execution Unit Selection

The dispatch unit maintains the status of each execution unit:

| Field | Description |
|-------|-------------|
| Unit ID | Unique unit identifier |
| Busy | Unit is currently executing |
| Opcode Support | Bitmask of supported opcodes |
| Queue Depth | Available capacity in input FIFO |

### 6.2 Dispatch Algorithm (Round-Robin)

```
for each ready node:
    for each execution unit (round-robin):
        if unit supports opcode and not busy:
            dispatch node to unit
            break
    if no unit available:
        node stays in ready queue
```

### 6.3 Dispatch Message

When dispatching a node, the scheduler sends:

```
Message: NODE_SCHEDULE
Payload: node_id, opcode, input_values[0..N-1]
```

---

## 7. Result Collection

### 7.1 Result Processing

When an execution unit completes:

```
Message: NODE_RESULT
Payload: node_id, result_value (tagged pointer)
```

The result collector:
1. Writes the result value to the node's `ResultPtr` field
2. Updates node state to DONE
3. Notifies the dependency tracker
4. If this was the root node: signals GRAPH_COMPLETE

### 7.2 Result FIFO

Results are received through a dedicated FIFO:

| Property | Specification |
|----------|--------------|
| Width | 64 bits (node_id + value) |
| Depth | Configurable (default 16) |

---

## 8. Scheduling Modes

### 8.1 Single-Threaded (Phase 3)

One execution unit processes all nodes sequentially. The ready queue ensures correct ordering but no parallelism.

### 8.2 Multi-Unit (Phase 4+)

Multiple execution units operate in parallel. The scheduler dispatches to available units as nodes become ready.

### 8.3 Future: Speculative Execution

The scheduler may execute both branches of a conditional speculatively. When the condition resolves, the incorrect branch's results are discarded.

### 8.4 Future: Work Stealing

In a multi-scheduler configuration, idle schedulers may steal ready nodes from busy schedulers' queues.

---

## 9. Scheduler Registers

| Offset | Width | Name | Description |
|--------|-------|------|-------------|
| 0x00 | 32 | SCHED_CTRL | Control (enable, disable, reset, step) |
| 0x04 | 32 | SCHED_STATUS | Status (running, idle, halted, error) |
| 0x08 | 32 | SCHED_READY_COUNT | Number of ready nodes |
| 0x0C | 32 | SCHED_WAITING_COUNT | Number of waiting nodes |
| 0x10 | 32 | SCHED_DONE_COUNT | Number of completed nodes |
| 0x14 | 32 | SCHED_EXEC_UNITS | Number of execution units |
| 0x18 | 32 | SCHED_MODE | Scheduling mode |
| 0x1C | 32 | SCHED_CYCLES | Scheduler cycle counter |
| 0x20 | 32 | SCHED_DISPATCH_COUNT | Total nodes dispatched |
| 0x24 | 32 | SCHED_STALL_COUNT | Cycles stalled (no ready nodes) |

---

## 10. Performance Considerations

### 10.1 Pipeline Depth

The scheduler pipeline has these stages:

1. Result arrival (1 cycle)
2. Dependency update (1 cycle)
3. Ready detect (1 cycle)
4. Queue push (1 cycle)
5. Queue pop (1 cycle)
6. Dispatch (1 cycle)
7. Execution unit processing

Total scheduler latency: ~5 cycles per node (excludes execution time)

### 10.2 Bottlenecks

- Ready queue depth limits parallelism
- Graph memory bandwidth limits dependency tracking throughput
- Execution unit availability limits dispatch rate

### 10.3 Scaling

The scheduler is designed to scale:
- More execution units = more parallelism
- Deeper ready queue = more in-flight nodes
- Multi-scheduler = concurrent graph execution

---

## 11. Verification Plan

| Test | Description |
|------|-------------|
| Single node | Execute a node with no dependencies |
| Linear chain | Execute A → B → C (serial dependency) |
| Fan-out | Execute A → B, C (one producer, two consumers) |
| Fan-in | Execute A, B → C (two producers, one consumer) |
| Diamond | Execute A → B, C → D |
| All literals | Graph where all nodes are immediately ready |
| Empty graph | Graph with zero nodes |
| Full queue | Ready queue saturation |
| Execution unit busy | All units busy, queue builds up |
| Error handling | Node execution error propagation |
