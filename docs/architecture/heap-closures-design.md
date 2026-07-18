# Lucid Phase 5: Heap, Closures, and Environments

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Scope

Phase 5 implements the functional heap and the core data structures of functional programming: closures and environments. It delivers:
- Heap controller managing the FPU's object memory
- Object allocator with common-header allocation
- Closure creation unit
- Environment management (create, extend, lookup)
- Pair and vector allocation
- Testbench for heap operations

---

## 2. Heap Architecture

```
┌─────────────────────────────────────────────┐
│                 FPU Heap                     │
│  (64 KB at 0x00300000)                      │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │  Header   │  │  Object  │  │  Free    │  │
│  │  (256 B) │  │  Space   │  │  List    │  │
│  │          │  │  (~31 KB)│  │  (~16 KB)│  │
│  └──────────┘  └──────────┘  └──────────┘  │
└─────────────────────────────────────────────┘
```

### 2.1 Heap Header

| Offset | Field | Description |
|--------|-------|-------------|
| 0x00 | MAGIC | 0x48454150 ("HEAP") |
| 0x04 | HEAP_SIZE | Total heap size in bytes |
| 0x08 | FREE_PTR | Offset of next free allocation |
| 0x0C | OBJECT_COUNT | Number of allocated objects |
| 0x10 | GC_COUNT | Number of GC cycles |
| 0x14 | FLAGS | Heap control flags |

### 2.2 Object Format

Every heap object begins with a 4-word header:

| Word | Field | Width | Description |
|------|-------|-------|-------------|
| 0 | TAG | 8 | Object type (see below) |
| 0 | FLAGS | 8 | GC flags (mark, forwarded, etc.) |
| 0 | SIZE | 16 | Object size in bytes |
| 1+ | PAYLOAD | varies | Object-specific data |

### 2.3 Object Types

| TAG | Type | PAYLOAD |
|-----|------|---------|
| 0x01 | INTEGER | 4 bytes: value |
| 0x02 | BOOLEAN | — (tagged pointer) |
| 0x03 | CHARACTER | 4 bytes: Unicode code point |
| 0x04 | STRING | 4 bytes length + N bytes data |
| 0x05 | SYMBOL | 4 bytes string ptr + 4 bytes hash |
| 0x06 | PAIR | 4 bytes car + 4 bytes cdr |
| 0x07 | VECTOR | 4 bytes length + N×4 bytes elements |
| 0x08 | CLOSURE | 4 bytes arity + 4 bytes code ptr + 4 bytes env ptr |
| 0x09 | ENVIRONMENT | 4 bytes size + N×8 bytes (name, value) pairs |
| 0x0A | PRIMITIVE | 4 bytes name ptr + 4 bytes arity + 4 bytes fn ptr |
| 0x0B | CONTINUATION | 16+ bytes saved state |
| 0x0C | THUNK | 4 bytes graph ptr + 4 bytes env ptr |
| 0x0D | PROMISE | 4 bytes state + 4 bytes value ptr |

---

## 3. Heap Controller

The heap controller manages the FPU's object memory. It processes ALLOCATE messages from the scheduler and returns object pointers.

### 3.1 Interface

| Port | Width | Direction | Description |
|------|-------|-----------|-------------|
| clk | 1 | In | Clock |
| reset_n | 1 | In | Reset |
| alloc_valid | 1 | In | Allocation request |
| alloc_size | 16 | In | Object size in bytes |
| alloc_ptr | 32 | Out | Allocated address (0=OOM) |
| alloc_ack | 1 | Out | Allocation complete |

### 3.2 Operation

1. Receive allocation request with size
2. Check if free_ptr + size ≤ heap_end
3. If yes: write object header, return pointer, advance free_ptr
4. If no: return 0 (out of memory, trigger GC)

---

## 4. Closure Unit

Creates closure objects in the heap.

### 4.1 Closure Format

| Word | Field | Description |
|------|-------|-------------|
| 0 | Header | TAG=CLOSURE, SIZE=16+4*N |
| 1 | Arity | Number of parameters |
| 2 | Code Ptr | Pointer to function graph in graph memory |
| 3+ | Env Entries | Pointers to bound variables |

### 4.2 Interface

| Port | Width | Direction | Description |
|------|-------|-----------|-------------|
| clk | 1 | In | Clock |
| reset_n | 1 | In | Reset |
| closure_req | 1 | In | Request closure creation |
| arity | 8 | In | Number of parameters |
| code_ptr | 32 | In | Pointer to graph |
| env_size | 8 | In | Environment size |
| env_data | 256 | In | Environment entries |
| closure_ptr | 32 | Out | Pointer to new closure (0=OOM) |
| closure_ack | 1 | Out | Creation complete |

---

## 5. Environment Unit

Manages lexical environments (variable bindings).

### 5.1 Environment Format

| Word | Field | Description |
|------|-------|-------------|
| 0 | Header | TAG=ENVIRONMENT, SIZE=8+8*N |
| 1 | Size | Number of bindings |
| 2+ | Pairs | (symbol_ptr, value_ptr) pairs |

### 5.2 Operations

- **Create:** Allocate empty environment of given size
- **Extend:** Create new environment with additional bindings
- **Lookup:** Find value pointer for given symbol

---

## 6. Verification Plan

| Test | Description |
|------|-------------|
| Allocate integer | Allocate one integer object, verify header |
| Allocate pair | Allocate a pair (cons), verify car/cdr slots |
| Create closure | Create closure with arity and code pointer |
| Create environment | Create environment with bindings |
| Extend environment | Create child environment with new bindings |
| Full heap | Allocate until OOM, verify error |
