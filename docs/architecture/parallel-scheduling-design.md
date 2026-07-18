# Lucid Phase 7: Parallel Scheduling

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Scope

Phase 7 extends the Lucid FPU scheduler to dispatch multiple ready nodes to execution units concurrently. It delivers:
- A parallel scheduler core with multi-issue dispatch
- A multi-read, multi-write ready queue
- Out-of-order completion tracking
- Hazard detection (read-after-write, write-after-write)
- A testbench demonstrating concurrent execution of independent subgraphs

---

## 2. Architecture

```
                   ┌──────────────────────────┐
                   │    Ready Queue           │
                   │  (multi-pop, multi-push) │
                   └──────┬──────────┬────────┘
                          │          │
                 ┌────────▼──┐  ┌────▼────────┐
                 │ Dispatch  │  │ Dispatch    │
                 │ Unit 0    │  │ Unit 1      │
                 └─────┬─────┘  └──────┬──────┘
                       │               │
              ┌────────▼───┐    ┌──────▼───────┐
              │ Execution  │    │ Execution    │
              │ Unit 0     │    │ Unit 1       │
              └──────┬─────┘    └──────┬───────┘
                     │                 │
              ┌──────▼─────────────────▼───────┐
              │      Result Collector          │
              │  (out-of-order completion)     │
              └──────────────┬─────────────────┘
                             │
              ┌──────────────▼─────────────────┐
              │     Dependency Updater         │
              │  (may push new ready nodes)    │
              └────────────────────────────────┘
```

### 2.1 Pipeline Stages

1. **Dispatch:** Pop up to N ready node IDs from the queue. For each, read operands and send to an available execution unit.
2. **Execute:** Each execution unit processes its assigned node (1 cycle for arithmetic).
3. **Collect:** Results arrive in any order. The collector holds results until the dependency updater is ready.
4. **Update:** For each completed node, update its dependents' ready counts. Newly ready nodes are pushed to the ready queue.

### 2.2 Hazard Detection

| Hazard | Condition | Resolution |
|--------|-----------|------------|
| RAW | Node B reads a result that Node A is computing | B stays in queue until A completes |
| WAW | Two nodes write to the same dependent | Dependency counter handles ordering |
| Structural | More ready nodes than execution units | Queue holds excess nodes |

---

## 3. Multi-Issue Ready Queue

The ready queue supports:
- **Multi-pop:** Dequeue up to N node IDs in one cycle
- **Multi-push:** Enqueue up to N node IDs in one cycle

### 3.1 Interface

| Port | Width | Direction | Description |
|------|-------|-----------|-------------|
| pop_en[N] | N | In | Pop request per slot |
| pop_id[N] | N×32 | Out | Popped node IDs |
| pop_valid[N] | N | Out | Valid pop data |
| push_en[N] | N | In | Push request per slot |
| push_id[N] | N×32 | In | Node IDs to push |
| count | log2(DEPTH) | Out | Number of entries |

---

## 4. Parallel Scheduler Core

### 4.1 States

| State | Description |
|-------|-------------|
| LOAD | Waiting for graph load |
| SCAN | Scanning for initial ready nodes |
| DISPATCH | Issuing ready nodes to execution units |
| COLLECT | Gathering results from execution units |
| UPDATE | Updating dependencies |
| DONE | Execution complete |

### 4.2 Dispatch Logic

Each cycle:
1. Count ready nodes in queue
2. Pop up to NUM_UNITS node IDs
3. For each:
   a. Read node operands from node memory
   b. Check if all operands are ready (all deps met)
   c. Send to execution unit via message system
   d. Mark node as IN_FLIGHT
4. Update performance counters

### 4.3 Out-of-Order Completion

Results may arrive in any order. The collector:
1. Buffers incoming results (node ID + value)
2. When the dependency updater is free, processes the next buffered result
3. Updates node state, increments dependent ready counts
4. Pushes newly ready nodes to the queue

---

## 5. Verification Plan

| Test | Description |
|------|-------------|
| Independent ADD | Two independent ADD nodes: (+ 1 2) and (+ 3 4), execute concurrently |
| Mixed chain | (define a (+ 1 2)) (define b (+ 3 4)) (* a b) — some serial, some parallel |
| Saturation | 10 independent operations, only 2 execution units |
| Out-of-order | Nodes with different latencies complete out of order |
| Hazards | RAW dependency chain: A → B → C (no parallelism possible) |
