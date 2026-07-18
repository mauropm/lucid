# Lucid Memory Map

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Overview

The Lucid system uses a unified 32-bit memory address space shared between the Management CPU (RV32IM) and the Lucid FPU. The Wishbone bus matrix arbitrates access between the two processors and peripherals.

---

## 2. Complete Memory Map

| Start | End | Region | Access | Description |
|-------|-----|--------|--------|-------------|
| 0x00000000 | 0x00000FFF | Boot ROM | R | Reset vector and bootloader (4 KB) |
| 0x00001000 | 0x00001FFF | Boot ROM Mirror | R | Mirrored for alignment |
| 0x00010000 | 0x00010FFF | Management RAM | R/W | CPU stack and data (4 KB) |
| 0x00011000 | 0x00011FFF | Management Scratch | R/W | CPU scratchpad (4 KB) |
| 0x00020000 | 0x0002000F | UART | R/W | Serial communication registers |
| 0x00020010 | 0x0002001F | UART Rx FIFO | R | Receive FIFO data |
| 0x00020020 | 0x0002002F | UART Tx FIFO | W | Transmit FIFO data |
| 0x00030000 | 0x000300FF | Debug Interface | R/W | Debug control registers |
| 0x00030100 | 0x000301FF | Debug Buffer | R/W | Debug data buffer |
| 0x00100000 | 0x001000FF | FPU Control | R/W | FPU control and status registers |
| 0x00100100 | 0x001001FF | Scheduler Control | R/W | Scheduler configuration |
| 0x00100200 | 0x001002FF | GC Control | R/W | GC control registers |
| 0x00100300 | 0x001003FF | Heap Control | R/W | Heap control registers |
| 0x00100400 | 0x001004FF | Message Control | R/W | Message dispatcher control |
| 0x00200000 | 0x00203FFF | Graph Memory | R/W | Lucid IR graph storage (16 KB) |

| 0x00300000 | 0x0030FFFF | FPU Heap | R/W | Functional object heap (64 KB) |
| 0x00300000 | 0x003000FF | Heap Header | R/W | Heap metadata |
| 0x00300100 | 0x00307FFF | Heap Object Space | R/W | Active heap objects (~31 KB) |
| 0x00308000 | 0x0030BFFF | Heap GC Space | R/W | GC work area (16 KB) |
| 0x0030C000 | 0x0030FFFF | Heap Free List | R/W | Free block tracking (16 KB) |

| 0x00400000 | 0x00400FFF | GC Scratch | R/W | GC temporary storage (4 KB) |
| 0x00401000 | 0x00401FFF | GC Root Set | R/W | GC root set (4 KB) |

| 0x80000000 | 0x83FFFFFF | External DRAM | R/W | Off-chip SDRAM (64 MB) |

---

## 3. Region Details

### 3.1 Boot ROM (0x00000000 - 0x00000FFF)

The boot ROM contains the initial program for the Management CPU. It is loaded from the FPGA bitstream configuration flash.

Contents:
- Reset vector (0x00000000)
- Exception vectors (0x00000004 - 0x0000001F)
- Bootloader: copies Management RAM from flash, initializes FPU, starts REPL

### 3.2 Management RAM (0x00010000 - 0x00011FFF)

Two 4 KB blocks of BRAM dedicated to the Management CPU:
- Stack and heap for the C runtime
- Scratchpad for temporary data

### 3.3 UART (0x00020000 - 0x0002002F)

| Offset | Width | Register | Description |
|--------|-------|----------|-------------|
| 0x00 | 8 | UART_STATUS | Status flags (TX ready, RX ready, error) |
| 0x04 | 8 | UART_CTRL | Control (enable, baud rate, interrupt enable) |
| 0x08 | 8 | UART_BAUD | Baud rate divisor |
| 0x0C | 8 | UART_DATA | Data register (read = RX, write = TX) |
| 0x10 | 8 | UART_RX_LEVEL | Number of bytes in RX FIFO |
| 0x14 | 8 | UART_TX_LEVEL | Available space in TX FIFO |
| 0x18 | 8 | UART_INT_STATUS | Interrupt status |
| 0x1C | 8 | UART_INT_MASK | Interrupt mask |

### 3.4 Debug Interface (0x00030000 - 0x000301FF)

| Offset | Width | Register | Description |
|--------|-------|----------|-------------|
| 0x00 | 32 | DEBUG_CTRL | Control register (enable, step, reset FPU) |
| 0x04 | 32 | DEBUG_STATUS | Debug status |
| 0x08 | 32 | DEBUG_ADDR | Address for peek/poke |
| 0x0C | 32 | DEBUG_DATA | Data for peek/poke |
| 0x10 | 32 | DEBUG_BREAK0 | Breakpoint address 0 |
| 0x14 | 32 | DEBUG_BREAK1 | Breakpoint address 1 |
| 0x18 | 32 | DEBUG_BREAK_CTRL | Breakpoint control |
| 0x100 | 256 | DEBUG_BUF | Debug message buffer |

### 3.5 FPU Control (0x00100000 - 0x001004FF)

#### 3.5.1 FPU Control (0x00100000 - 0x001000FF)

| Offset | Width | Register | Description |
|--------|-------|----------|-------------|
| 0x00 | 32 | FPU_CTRL | FPU control (enable, reset, halt) |
| 0x04 | 32 | FPU_STATUS | FPU status (running, halted, error) |
| 0x08 | 32 | FPU_ERROR | Last error code |
| 0x0C | 32 | FPU_GRAPH_ADDR | Current graph address |
| 0x10 | 32 | FPU_GRAPH_SIZE | Current graph size |
| 0x14 | 32 | FPU_STATE | FPU internal state (debug) |
| 0x18 | 32 | FPU_CYCLES | Cycle counter |
| 0x1C | 32 | FPU_NODES_EXEC | Nodes executed counter |
| 0x20 | 32 | FPU_MSG_SENT | Messages sent counter |
| 0x24 | 32 | FPU_MSG_RECV | Messages received counter |

#### 3.5.2 Scheduler Control (0x00100100 - 0x001001FF)

| Offset | Width | Register | Description |
|--------|-------|----------|-------------|
| 0x00 | 32 | SCHED_CTRL | Scheduler control |
| 0x04 | 32 | SCHED_STATUS | Scheduler status |
| 0x08 | 32 | SCHED_READY_Q_COUNT | Number of ready nodes |
| 0x0C | 32 | SCHED_WAITING_COUNT | Number of waiting nodes |
| 0x10 | 32 | SCHED_EXEC_UNIT_COUNT | Active execution unit count |
| 0x14 | 32 | SCHED_MODE | Scheduling mode (round-robin, priority, etc.) |
| 0x18 | 32 | SCHED_MAX_CONCURRENCY | Maximum concurrent nodes |

#### 3.5.3 GC Control (0x00100200 - 0x001002FF)

| Offset | Width | Register | Description |
|--------|-------|----------|-------------|
| 0x00 | 32 | GC_CTRL | GC control (trigger mode, collect) |
| 0x04 | 32 | GC_STATUS | GC status |
| 0x08 | 32 | GC_HEAP_USAGE | Current heap usage in bytes |
| 0x0C | 32 | GC_HEAP_CAPACITY | Total heap capacity |
| 0x10 | 32 | GC_OBJECT_COUNT | Number of live objects |
| 0x14 | 32 | GC_LAST_COLLECT | Cycles since last collection |
| 0x18 | 32 | GC_THRESHOLD | Collection trigger threshold |

#### 3.5.4 Heap Control (0x00100300 - 0x001003FF)

| Offset | Width | Register | Description |
|--------|-------|----------|-------------|
| 0x00 | 32 | HEAP_CTRL | Heap control |
| 0x04 | 32 | HEAP_STATUS | Heap status |
| 0x08 | 32 | HEAP_FREE_PTR | Current free pointer |
| 0x0C | 32 | HEAP_ALLOC_COUNT | Allocation counter |
| 0x10 | 32 | HEAP_FAIL_COUNT | Allocation failure counter |
| 0x14 | 32 | HEAP_ALIGNMENT | Allocation alignment (default 4) |

#### 3.5.5 Message Control (0x00100400 - 0x001004FF)

| Offset | Width | Register | Description |
|--------|-------|----------|-------------|
| 0x00 | 32 | MSG_CTRL | Message dispatcher control |
| 0x04 | 32 | MSG_STATUS | Dispatcher status |
| 0x08 | 32 | MSG_QUEUE_DEPTH | Depth of each message queue |
| 0x0C | 32 | MSG_DROP_COUNT | Count of dropped messages |
| 0x10 | 32 | MSG_SENT_COUNT | Total messages sent |

---

## 4. Heap Layout (Detailed)

### 4.1 Heap Header (0x00300000 - 0x003000FF)

| Offset | Width | Field | Description |
|--------|-------|-------|-------------|
| 0x00 | 32 | HEAP_MAGIC | 0x48454150 ("HEAP") |
| 0x04 | 32 | HEAP_VERSION | Heap format version |
| 0x08 | 32 | HEAP_SIZE | Total heap size in bytes |
| 0x0C | 32 | HEAP_FREE_PTR | Offset of next free allocation |
| 0x10 | 32 | HEAP_OBJECT_COUNT | Number of allocated objects |
| 0x14 | 32 | HEAP_GC_COUNT | Number of GC cycles performed |
| 0x18 | 32 | HEAP_FLAGS | Heap flags (compacting, generational, etc.) |
| 0x1C | 64 | HEAP_RESERVED | Reserved for future use |

### 4.2 Object Format

Every heap object begins with a common header (8 bytes):

| Offset | Width | Field | Description |
|--------|-------|-------|-------------|
| 0x00 | 8 | TAG | Object type tag |
| 0x01 | 8 | FLAGS | GC flags (mark bit, forwarded, etc.) |
| 0x02 | 16 | SIZE | Object size in bytes (including header) |
| 0x04 | 32 | PAYLOAD | Object-specific data begins here |

### 4.3 Object Type Tags

| Tag | Type | Payload Size (bytes) | Description |
|-----|------|---------------------|-------------|
| 0x01 | Integer | 8 | 32-bit value boxed (when not fitting in tag bits) |
| 0x02 | Boolean | 4 | 1 word (0 or 1) |
| 0x03 | Character | 8 | 32-bit Unicode code point |
| 0x04 | String | 8+N | Length (32) + character data |
| 0x05 | Symbol | 12 | String pointer (32) + hash (32) |
| 0x06 | Pair | 8 | car (32) + cdr (32) |
| 0x07 | Vector | 4+4*N | Length (32) + elements |
| 0x08 | Closure | 12+N | Arity (32) + code pointer (32) + env pointer (32) |
| 0x09 | Environment | 4+8*N | Size (32) + (name, value) pairs |
| 0x0A | Primitive | 12 | Name string pointer + arity + function pointer |
| 0x0B | Continuation | 16+N | Saved graph state + registers |
| 0x0C | Thunk | 8 | Graph pointer (32) + environment (32) |
| 0x0D | Promise | 12 | State (32) + value (32) or thunk pointer |

---

## 5. Graph Memory Layout (0x00200000 - 0x00203FFF)

Each graph node occupies 5 words (20 bytes):

| Word | Field | Description |
|------|-------|-------------|
| 0 | State/Opcode/FB | State (2), Opcode (8), InputCount (6), ReadyCount(6), Flags(10) |
| 1 | Immediate0 | Inline literal value or pointer |
| 2 | Immediate1 | Second inline value |
| 3 | ResultPtr | Pointer to heap object (result) |
| 4 | DependentMask | Bitmask of dependent nodes (up to 32) |

Maximum nodes: 16384 / 20 = 819 nodes (theoretical)
Practical limit: ~512 nodes (accounting for linked lists of dependents)

---

## 6. Access Control

| Region | CPU Read | CPU Write | FPU Read | FPU Write |
|--------|----------|-----------|----------|-----------|
| Boot ROM | Yes | No | No | No |
| Management RAM | Yes | Yes | No | No |
| UART | Yes | Yes | No | No |
| Debug | Yes | Yes | Yes | Yes |
| FPU Control | Yes | Yes | Yes | Yes |
| Graph Memory | Yes (load) | Yes (load) | Yes | No (scheduler writes) |
| FPU Heap | No | No | Yes | Yes |
| GC Scratch | Yes (debug) | Yes (debug) | Yes | Yes |

The Management CPU programs graph memory, then signals the FPU to execute. During execution, the CPU reads FPU control registers to monitor progress and reads heap only for debug/diagnostic purposes.
