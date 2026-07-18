# Lucid Phase 6: Scheme Frontend

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Scope

Phase 6 implements the Scheme language frontend for Lucid. It delivers:
- A Scheme tokenizer and reader (s-expression parser)
- A compiler from Scheme AST to Lucid IR graphs
- An IR graph loader that writes compiled graphs into graph memory
- An end-to-end testbench demonstrating the full pipeline
- A REPL stub for future RV32IM firmware

The frontend is written in Python for prototyping and will be ported to C for the Management CPU firmware.

---

## 2. Architecture

```
Scheme Source Code
       │
       ▼
  Tokenizer/Reader ───→ S-expression AST
       │
       ▼
  Lucid IR Compiler ──→ Dependency Graph
       │                     │
       ▼                     ▼
  Node Encoder        Graph Memory Writes
       │
       ▼
  Testbench loads graph → Scheduler executes → Result verified
```

### 2.1 Pipeline Stages

1. **Read:** Tokenize source into tokens, parse into s-expression AST
2. **Analyze:** Resolve variable references, annotate AST
3. **Compile:** Walk AST, emit Lucid IR nodes with dependency tracking
4. **Encode:** Serialize nodes into graph memory format
5. **Load:** Write nodes to graph memory via register interface
6. **Execute:** Start scheduler, wait for completion
7. **Read:** Extract root node result

---

## 3. Supported Scheme Subset

For Phase 6, we support a minimal Scheme subset:

| Feature | Example | Support |
|---------|---------|---------|
| Integer literals | `42` | ✓ |
| Boolean literals | `#t` `#f` | ✓ |
| Arithmetic | `(+ a b)` `(- a b)` `(* a b)` | ✓ |
| Comparison | `(< a b)` `(> a b)` `(= a b)` | ✓ |
| `if` | `(if cond then else)` | ✓ |
| `lambda` | `(lambda (x) body)` | ✓ (closure creation) |
| Application | `(f x)` | ✓ |
| `define` | `(define x val)` | ✓ |
| Variables | `x` | ✓ |
| `let` | `(let ((x v)) body)` | ✓ |
| `quote` | `'()` | Pair allocation |

---

## 4. Compilation Scheme

### 4.1 Literals

```
42  →  Node: LIT_INT imm0=42 num_inputs=0
#t  →  Node: LIT_BOOL flags=[0]=1 num_inputs=0
```

### 4.2 Primitive Application

```
(+ a b)  →  Node: ADD op0=a_result op1=b_result num_inputs=2
```

### 4.3 Lambda

```
(lambda (x) body)  →  Node: LAMBDA arity=1 body=body_node
```

### 4.4 Variable Reference

```
x  →  Node: LOOKUP name=x num_inputs=0
```

---

## 5. Verification Plan

| Test | Description |
|------|-------------|
| `(+ 2 3)` | Compile, execute, verify 5 |
| `(* 3 4)` | Compile, execute, verify 12 |
| `(+ 2 (* 3 4))` | Multi-node graph, verify 14 |
| `(if #t 1 2)` | Conditional, verify 1 |
| `(< 3 5)` | Comparison, verify 1 |
