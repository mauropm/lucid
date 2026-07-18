# Lucid IR Specification

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Overview

Lucid IR is a graph-based intermediate representation designed for direct execution on the Lucid Functional Processing Unit. It is not an abstract syntax tree and it is not bytecode. It is a dependency graph where nodes represent computation and edges represent data flow.

Lucid IR is the architectural interface between language frontends and the FPU hardware. Every frontend (Scheme, Racket, OCaml, Haskell, ...) compiles to Lucid IR. The FPU hardware executes Lucid IR graphs directly.

### 1.1 Design Principles

- **Graph structure:** The IR is a directed acyclic graph (DAG) of nodes
- **Explicit dependencies:** Every edge represents a data dependency
- **No ordering:** The graph encodes partial order only; total order is determined by the scheduler
- **Implicit parallelism:** Independent subgraphs may execute concurrently
- **Language neutral:** No node should favor one source language over another

---

## 2. Graph Structure

A Lucid IR graph is defined as:

```
Graph ::= Node*
Node  ::= NodeID Opcode [Input*] [Output*] [Metadata]
```

### 2.1 Node ID

Each node has a unique 32-bit identifier within a graph.

### 2.2 Opcodes

Opcodes define the operation a node performs.

#### 2.2.1 Value Nodes

| Opcode | Code | Description |
|--------|------|-------------|
| LIT_INT | 0x01 | Integer literal |
| LIT_BOOL | 0x02 | Boolean literal |
| LIT_CHAR | 0x03 | Character literal |
| LIT_STR | 0x04 | String literal |
| LIT_SYM | 0x05 | Symbol literal |
| LIT_EMPTY_LIST | 0x06 | Empty list (nil) |

#### 2.2.2 Primitive Nodes

| Opcode | Code | Description |
|--------|------|-------------|
| ADD | 0x10 | Integer addition |
| SUB | 0x11 | Integer subtraction |
| MUL | 0x12 | Integer multiplication |
| DIV | 0x13 | Integer division |
| MOD | 0x14 | Integer modulus |
| EQ | 0x15 | Equality comparison |
| LT | 0x16 | Less-than comparison |
| GT | 0x17 | Greater-than comparison |
| LE | 0x18 | Less-or-equal |
| GE | 0x19 | Greater-or-equal |
| CONS | 0x1A | Pair construction |
| CAR | 0x1B | First element of pair |
| CDR | 0x1C | Rest of pair |
| VECTOR | 0x1D | Vector construction |
| VECTOR_REF | 0x1E | Vector element access |

#### 2.2.3 Functional Nodes

| Opcode | Code | Description |
|--------|------|-------------|
| LAMBDA | 0x20 | Closure creation |
| APPLY | 0x21 | Function application |
| TAIL_APPLY | 0x22 | Tail-call application |
| LOOKUP | 0x23 | Variable lookup |
| ENV_EXTEND | 0x24 | Environment extension |

#### 2.2.4 Control Nodes

| Opcode | Code | Description |
|--------|------|-------------|
| IF | 0x30 | Conditional |
| BRANCH | 0x31 | Multi-way branch |
| LET | 0x32 | Local binding |
| LETREC | 0x33 | Recursive local binding |
| BEGIN | 0x34 | Sequential composition |
| CALL_CC | 0x35 | Call with current continuation |

#### 2.2.5 Structure Nodes

| Opcode | Code | Description |
|--------|------|-------------|
| PRIMOP | 0x40 | Primitive operation reference |
| CLOSURE | 0x41 | Closure value |
| THUNK | 0x42 | Suspended computation |
| PROMISE | 0x43 | Future/promise |
| MATCH | 0x44 | Pattern match |

#### 2.2.6 GC Hints

| Opcode | Code | Description |
|--------|------|-------------|
| GC_BARRIER | 0x50 | GC synchronization point |
| PIN | 0x51 | Prevent object from being moved |

---

## 3. Graph Serialization

Lucid IR graphs are serialized into a binary format for transfer to the FPU's graph memory.

### 3.1 Graph Header

| Offset | Width | Field | Description |
|--------|-------|-------|-------------|
| 0 | 32 | Magic | 0x4C554349 ("LUCI") |
| 4 | 32 | Version | IR format version |
| 8 | 32 | Node count | Number of nodes in graph |
| 12 | 32 | Root node | Node ID of graph root |
| 16 | 32 | String table offset | Offset to string table |
| 20 | 16 | String table size | Size of string table |
| 22 | 16 | Flags | Graph-level flags |

### 3.2 Node Serialization

Each node is serialized as:

| Offset | Width | Field | Description |
|--------|-------|-------|-------------|
| 0 | 32 | Node ID | Unique node identifier |
| 4 | 8 | Opcode | Node operation |
| 5 | 8 | Input count | Number of input edges |
| 6 | 16 | Output count | Number of output edges |
| 8 | 32 | Flags | Node flags (lazy, strict, etc.) |
| 12 | 32 | Immediate 0 | Inline data (for literals) |
| 16 | 32 | Immediate 1 | Inline data (for literals) |
| 20 | 32*N | Input IDs | Array of input node IDs |
| ... | ... | Output IDs | Array of output node IDs |

### 3.3 Wire Format

The complete serialized graph:

```
[Graph Header]
[Node 0]
[Node 1]
...
[Node N-1]
[String Table]
```

---

## 4. Graph Construction

### 4.1 From Scheme Example

Source:
```scheme
(+ 2 (* 3 4))
```

Lucid IR graph:
```
Node 0: LIT_INT  imm=2
Node 1: LIT_INT  imm=3
Node 2: LIT_INT  imm=4
Node 3: MUL      inputs=[1, 2]
Node 4: ADD      inputs=[0, 3]
Root: Node 4
```

Dependency structure:
- Nodes 0, 1, 2 have no dependencies (literals)
- Node 3 depends on nodes 1 and 2
- Node 4 depends on nodes 0 and 3

### 4.2 From Closure Example

Source:
```scheme
(lambda (x) (+ x 1))
```

Lucid IR graph:
```
Node 0: LAMBDA   params=[x] body=Node 3
Node 1: LOOKUP   name=x
Node 2: LIT_INT  imm=1
Node 3: ADD      inputs=[1, 2]
Root: Node 0
```

---

## 5. Execution Semantics

### 5.1 Node Execution

When a node is executed:
1. All input dependencies must be resolved (values available)
2. The opcode determines the operation
3. The result is produced as a single output value
4. Downstream nodes are notified of the ready value

### 5.2 Literal Execution

Literal nodes (LIT_INT, LIT_BOOL, etc.) are always ready immediately. They produce their inline value as output.

### 5.3 Primitive Execution

Primitive nodes read their input values, perform the operation, and produce a result.

### 5.4 Application Execution

APPLY nodes evaluate the function and argument, then create a new graph for the function body.

TAIL_APPLY replaces the current graph with the function body graph (reuses stack/scheduler state).

### 5.5 Conditional Execution

IF nodes evaluate the condition. Based on the result, only the selected branch is scheduled.

---

## 6. Graph Properties

### 6.1 Well-Formedness Constraints

1. Every node ID is unique within a graph
2. Every input reference points to a valid node ID
3. The graph contains no cycles (is a DAG)
4. Exactly one root node is designated
5. All nodes are reachable from the root

### 6.2 Optimizations

Future IR optimizations may include:
- Constant folding (replace constant expressions with literals)
- Dead node elimination (remove unreachable nodes)
- Inlining (replace APPLY with function body)
- Strictness analysis (mark nodes as strict/eager)

---

## 7. Memory Representation

Within the FPU, each graph node occupies a fixed-size entry in Graph Memory:

| Field | Width | Description |
|-------|-------|-------------|
| State | 2 | idle, waiting, ready, done |
| Opcode | 8 | Node operation |
| InputCount | 6 | Number of inputs (0-63) |
| ReadyCount | 6 | Number of ready inputs |
| Immediate0 | 32 | Inline data |
| Immediate1 | 32 | Inline data |
| ResultPtr | 32 | Pointer to result value in heap |
| Dependents | 32 | Bitmap or list of dependent nodes |

Total: ~152 bits per node (rounded to 160 bits = 5 × 32-bit words)

With 32 Kbits of BRAM available for graph memory, this supports approximately 200 nodes per graph.

---

## 8. Future Extensions

### 8.1 Region-Based Graphs

Large programs will be compiled into multiple graph regions. The scheduler will manage region switching.

### 8.2 Serialization to External Memory

For programs larger than on-chip graph memory, graphs can be serialized to external DRAM and paged in.

### 8.3 Graph Fusion

Multiple small graphs can be fused into a single graph for scheduling efficiency.
