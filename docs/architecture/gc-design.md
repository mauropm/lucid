# Lucid Phase 8: Garbage Collection

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Scope

Phase 8 implements a hardware mark-sweep garbage collector for the FPU heap. It delivers:
- A mark-sweep GC engine that scans the heap and reclaims unused objects
- Root set management (identifying live references from registers and scheduler state)
- Integration with the heap controller (trigger on OOM)
- GC status monitoring via registers
- A testbench demonstrating GC in action

---

## 2. Architecture

```
┌─────────────┐     GC Trigger     ┌──────────────────┐
│  Scheduler  │──────────────────→│   GC Controller  │
│  (Roots)    │                    │                  │
│             │                    │  ┌────────────┐  │
│  Registers  │──→ Root Set ──────→│  │ Mark Phase │  │
│  Stack      │                    │  └──────┬─────┘  │
│  Env Chain  │                    │         │         │
└─────────────┘                    │  ┌──────▼─────┐  │
                                   │  │ Sweep Phase│  │
                                   │  └──────┬─────┘  │
                                   │         │         │
                                   │  ┌──────▼─────┐  │
                                   │  │ Free List  │  │
                                   │  │ Update     │  │
                                   │  └────────────┘  │
                                   └────────┬─────────┘
                                            │
                                   ┌────────▼─────────┐
                                   │   Heap Memory    │
                                   │  (Object Storage)│
                                   └──────────────────┘
```

### 2.1 GC Phases

1. **Trigger:** GC starts when allocation fails (OOM) or on explicit request
2. **Root Collection:** Gather all live references from scheduler and stack
3. **Mark:** Starting from roots, recursively mark all reachable objects
4. **Sweep:** Scan heap linearly, collect unmarked objects
5. **Finish:** Update free pointer, resume execution

### 2.2 Object Header

| Bits | Field | Description |
|------|-------|-------------|
| 31:24 | TAG | Object type |
| 23:16 | FLAGS | GC flags: bit 0 = MARK, bit 1 = FORWARDED |
| 15:0 | SIZE | Object size in bytes |

### 2.3 GC Mark Stack

The mark phase uses a hardware stack to track objects-to-visit:
- Max depth: 64 entries (configurable)
- Each entry: 32-bit object pointer
- Push when a new reachable object is found
- Pop when returning from an object's child traversal

---

## 3. GC Controller Interface

| Port | Width | Direction | Description |
|------|-------|-----------|-------------|
| clk | 1 | In | Clock |
| reset_n | 1 | In | Reset |
| gc_start | 1 | In | Start GC |
| gc_busy | 1 | Out | GC in progress |
| gc_done | 1 | Out | GC complete |
| gc_freed | 32 | Out | Bytes reclaimed |
| heap_mem_addr | 32 | Out | Heap memory read address |
| heap_mem_data | 32 | In | Heap memory read data |
| heap_mem_we | 1 | Out | Heap memory write enable |
| heap_mem_wdata | 32 | Out | Heap memory write data |
| heap_free_ptr | 32 | In | Current free pointer |
| heap_free_updated | 32 | Out | Updated free pointer after GC |
| root_count | 8 | In | Number of root pointers |
| root_ptrs | 256 | In | Root pointer array (8 × 32-bit) |

---

## 4. Mark-Sweep Algorithm

### 4.1 Mark Phase

```
mark_phase:
  for each root_ptr in root_set:
    if root_ptr points to heap:
      push(root_ptr)
      while stack not empty:
        ptr = pop()
        if not marked(ptr):
          set_mark(ptr)
          for each child_ptr in object(ptr):
            if child_ptr points to heap:
              push(child_ptr)
```

### 4.2 Sweep Phase

```
sweep_phase:
  new_free_ptr = HEAP_BASE + HEADER_SIZE
  scan_ptr = HEAP_BASE + HEADER_SIZE
  while scan_ptr < old_free_ptr:
    size = object_size(scan_ptr)
    if marked(scan_ptr):
      clear_mark(scan_ptr)
      new_free_ptr = scan_ptr + size
    else:
      // Object is garbage: skip it (free space)
    scan_ptr = scan_ptr + size
  // new_free_ptr points to first free byte after live objects
  return new_free_ptr
```

---

## 5. Verification Plan

| Test | Description |
|------|-------------|
| Allocate then GC | Allocate objects, trigger GC, verify heap is swept |
| Reachable objects | Allocate reachable objects, GC preserves them |
| Unreachable objects | Allocate then drop references, GC reclaims them |
| GC on OOM | Fill heap, verify GC triggers automatically |
| GC status | Check gc_busy/gc_done timing |
