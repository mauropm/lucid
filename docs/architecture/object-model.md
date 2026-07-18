# Lucid Object Model

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Introduction

The Lucid Object Model defines how functional data is represented in the FPU heap. Every value manipulated by the FPU is a heap object with a common header. The object model is designed to be language-neutral while efficiently supporting Scheme's semantics (and, in the future, other functional languages).

---

## 2. Common Header

Every heap object begins with a 32-bit header:

| Bits | Field | Description |
|------|-------|-------------|
| 31:24 | TAG | Object type (8 bits, up to 256 types) |
| 23:16 | FLAGS | Object flags (8 bits) |
| 15:0 | SIZE | Object size in bytes (16 bits, up to 64 KB) |

### 2.1 TAG Values

| Value | Name | Description |
|-------|------|-------------|
| 0x00 | FREE | Free/unallocated memory |
| 0x01 | INTEGER | Boxed integer (when not fitting in pointer) |
| 0x02 | BOOLEAN | Boolean (#t or #f) |
| 0x03 | CHAR | Character |
| 0x04 | STRING | String |
| 0x05 | SYMBOL | Interned symbol |
| 0x06 | PAIR | Cons cell |
| 0x07 | VECTOR | Fixed-length array |
| 0x08 | CLOSURE | Function closure |
| 0x09 | ENVIRONMENT | Variable bindings |
| 0x0A | PRIMITIVE | Built-in operation |
| 0x0B | CONTINUATION | Saved execution state |
| 0x0C | THUNK | Suspended computation |
| 0x0D | PROMISE | Deferred result |
| 0x0E | PORT | I/O port |
| 0x0F | RECORD | User-defined record type |
| 0x10-0xEF | Reserved | Future use |
| 0xF0-0xFF | Language-specific | Reserved for frontend extensions |

### 2.2 FLAGS Bits

| Bit | Name | Description |
|-----|------|-------------|
| 0 | MARK | GC mark bit (for mark-sweep) |
| 1 | FORWARDED | Object has been forwarded (for copying GC) |
| 2 | IMMUTABLE | Object cannot be mutated |
| 3 | ROOT | Object is a GC root |
| 4 | FINALIZED | Finalizer has been registered |
| 5 | PINNED | Object cannot be moved |
| 6 | WEAK | Weak reference (GC may clear) |
| 7 | RESERVED | Reserved for future use |

---

## 3. Tagged Pointer Representation

To reduce heap allocation and improve performance, small fixnums use pointer tagging rather than boxed heap objects.

On a 32-bit architecture, pointers are aligned to 4 bytes, leaving the lower 2 bits available for tagging:

| Bit Pattern | Interpretation |
|-------------|---------------|
| xx...xx00 | Heap object pointer |
| xx...xx01 | Fixnum (31-bit signed integer) |
| xx...x010 | Forwarding pointer (during GC) |
| xx...x011 | Special constant |

Fixnum range: -2^30 to 2^30-1 (31-bit signed value shifted left 1, with LSB = 1)

Special constants:

| Pointer Value | Interpretation |
|---------------|---------------|
| 0x00000003 | #f (false) |
| 0x00000007 | #t (true) |
| 0x0000000B | '() (empty list) |
| 0x0000000F | #!eof (end of file) |
| 0x00000013 | #!void (unspecified value) |

---

## 4. Object Layouts

### 4.1 Integer (Boxed)

| Offset | Width | Field |
|--------|-------|-------|
| 0 | 32 | Header (TAG=0x01, SIZE=12) |
| 4 | 32 | Low word |
| 8 | 32 | High word (for 64-bit) |

Note: Most integers are fixnums (tagged pointer). Boxed integers are only used when the value exceeds 31 bits.

### 4.2 Boolean

Boolean values are always represented as tagged special constants. No heap allocation.

### 4.3 Character

| Offset | Width | Field |
|--------|-------|-------|
| 0 | 32 | Header (TAG=0x03, SIZE=8) |
| 4 | 32 | Unicode code point (21 bits, zero-extended) |

### 4.4 String

| Offset | Width | Field |
|--------|-------|-------|
| 0 | 32 | Header (TAG=0x04, SIZE=8+align(N)) |
| 4 | 32 | Length (number of characters) |
| 8 | N | Character data (8-bit per char, ASCII/UTF-8) |
| 8+N | pad | Padding to 4-byte alignment |

### 4.5 Symbol

| Offset | Width | Field |
|--------|-------|-------|
| 0 | 32 | Header (TAG=0x05, SIZE=12) |
| 4 | 32 | String pointer (reference to name string) |
| 8 | 32 | Hash value (32-bit FNV-1a hash) |

Symbols are interned. No two symbols with the same name exist in the heap.

### 4.6 Pair

| Offset | Width | Field |
|--------|-------|-------|
| 0 | 32 | Header (TAG=0x06, SIZE=12) |
| 4 | 32 | Car (tagged pointer) |
| 8 | 32 | Cdr (tagged pointer) |

### 4.7 Vector

| Offset | Width | Field |
|--------|-------|-------|
| 0 | 32 | Header (TAG=0x07, SIZE=8+4*N) |
| 4 | 32 | Length (number of elements) |
| 8 | 4*N | Elements (array of tagged pointers) |

### 4.8 Closure

| Offset | Width | Field |
|--------|-------|-------|
| 0 | 32 | Header (TAG=0x08, SIZE=12+4*N) |
| 4 | 32 | Arity (number of parameters) |
| 8 | 32 | Graph pointer (pointer to function graph in graph memory) |
| 12 | 4*N | Environment entries (tagged pointers to bound variables) |

### 4.9 Environment

| Offset | Width | Field |
|--------|-------|-------|
| 0 | 32 | Header (TAG=0x09, SIZE=8+8*N) |
| 4 | 32 | Size (number of bindings) |
| 8 | 8*N | Bindings: [symbol_ptr (32), value_ptr (32)] |

Environments are immutable once created (the FLAGS.IMMUTABLE bit is set).

### 4.10 Primitive

| Offset | Width | Field |
|--------|-------|-------|
| 0 | 32 | Header (TAG=0x0A, SIZE=16) |
| 4 | 32 | Name string pointer |
| 8 | 32 | Arity |
| 12 | 32 | Primitive ID (index into primitive dispatch table) |

### 4.11 Continuation

| Offset | Width | Field |
|--------|-------|-------|
| 0 | 32 | Header (TAG=0x0B, SIZE=16+4*N) |
| 4 | 32 | Saved graph pointer |
| 8 | 32 | Saved node ID |
| 12 | 32 | Saved environment pointer |
| 16 | 4*N | Saved registers (scheduler-specific) |

### 4.12 Thunk

| Offset | Width | Field |
|--------|-------|-------|
| 0 | 32 | Header (TAG=0x0C, SIZE=12) |
| 4 | 32 | Graph pointer |
| 8 | 32 | Environment pointer |

A thunk represents a delayed computation. When forced, the graph is scheduled for execution. Once evaluated, the result is cached and subsequent forces return the cached value.

### 4.13 Promise

| Offset | Width | Field |
|--------|-------|-------|
| 0 | 32 | Header (TAG=0x0D, SIZE=12) |
| 4 | 32 | State: 0=pending, 1=executing, 2=fulfilled, 3=rejected |
| 8 | 32 | Value (tagged pointer) or thunk pointer |

---

## 5. Memory Management

### 5.1 Allocation

Objects are allocated sequentially from the heap free pointer. The heap controller manages allocation requests from the scheduler and execution units.

Allocation request message:
```
ALLOCATE(size, type) → pointer
```

The heap controller:
1. Checks if `free_ptr + size ≤ heap_end`
2. If not, triggers GC via scheduler message
3. Writes object header
4. Returns pointer to newly allocated object
5. Advances free_ptr

### 5.2 Alignment

All objects are aligned to 4-byte boundaries. The SIZE field includes padding.

### 5.3 GC Interaction

The GC uses the TAG and FLAGS fields to traverse the heap:
1. Roots are identified (ROOT flag or known root set)
2. Reachable objects are marked (MARK flag)
3. Unmarked objects are collected
4. For copying GC, objects are evacuated and FORWARDED pointers are installed

---

## 6. Object Invariants

1. Every heap object begins with a valid header
2. TAG matches the object's actual layout
3. SIZE includes the header and is ≥ 8 bytes
4. All pointer fields are either tagged fixnums, special constants, or valid heap pointers
5. No pointer field points into the middle of an object (unless it's a forwarded pointer during GC)
6. The FREE tag (0x00) only appears in unallocated memory
7. Environment objects have IMMUTABLE set
8. Closure environments are always valid environment objects

---

## 7. Future Extensions

### 7.1 Weak References

Objects with FLAGS.WEAK set are ignored by the GC's marking phase. When all strong references are gone, the GC clears the WEAK reference and may collect the object.

### 7.2 Finalization

Objects with FLAGS.FINALIZED have a registered finalizer function. Before the GC reclaims such an object, the finalizer is called.

### 7.3 Large Objects

Objects larger than a threshold (e.g., 1 KB) may be allocated in a separate large object space and managed with a different GC strategy.
