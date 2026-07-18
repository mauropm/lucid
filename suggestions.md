# FPGA Code Review

**Project:** Lucid — Open Hardware Functional Processing Unit (FPU)
**Target:** Sipeed Tang Nano 20K (Gowin GW2AR-18, 20,736 LUT4, 828 Kbit BSRAM, 32 DSP)
**Reviewer role:** Principal FPGA Architect / Senior Digital Design Engineer
**Review type:** Static architectural and code review (analysis only, no source modifications)
**Method:** Full read of all RTL (23 `.sv` files, ~3,400 lines), testbenches, build scripts, constraints, and documentation; findings cross-checked by compiling and running the existing Icarus/Verilator/Yosys flows and by targeted scratch simulations run outside the repository (no repo files were modified).

---

## Executive Summary

Lucid is an ambitious, well-documented heterogeneous architecture: an RV32IM management CPU plus a message-passing graph-execution engine. The documentation discipline (ADRs, specs, roadmap) is excellent and rare for a project at this stage. The RTL is written in a consistent, readable style with sensible module partitioning, and several leaf modules (FIFO, BRAM wrapper, Wishbone bus) are clean and correct.

However, the project currently has a **broken verification loop and a non-buildable top level**, and several **functionally critical bugs** in the CPU, the graph schedulers, the UART, and the GC subsystem. Key findings were reproduced empirically:

- `make sim-icarus` **fails to elaborate every one of the 10 testbenches** (regression introduced in commit `10753fc` "phase 9 optimization", whose commit message claims "All 10 testbenches pass").
- `lucid_top` **does not elaborate** (invalid hierarchical reference `cpu.status[0]` + illegal parameter override), so the Tang Nano 20K target cannot be synthesized; the recorded `build/synth/synth.log` aborts mid-run.
- `(- (* 4 5) 3)` executes as `3 - 20 = -17` on the base scheduler (operand-order bug, reproduced).
- With 18 ready nodes and `Q_DEPTH=16`, exactly 16 nodes execute and the scheduler reports DONE with no error (silent queue overflow, reproduced).
- `MULH(0x10000, 0x10000)` returns `0` instead of `1` (32-bit context truncation, reproduced).
- All 3 checks in `tb_parallel` fail, yet the testbench prints `PASS: tb_parallel` and exits 0.

**Strengths**
- Outstanding documentation set (architecture guide, specs, ADRs, known-issues file).
- Clean, consistent coding style; good file/module organization by subsystem.
- Correct, compact leaf modules: `fifo.sv` (proper extra-bit pointer full/empty), `bram.sv`, `wishbone_bus.sv` (simple and workable).
- Message-passing philosophy with registered router outputs is a sound, testable architecture.
- Testbenches use golden-value self-checks and hierarchical probes (good intent, even if pass/fail propagation is missing).
- Honest issue tracking (`KNOWN_ISSUES.md`, `TODO.md`) — though it lags reality.

**Weaknesses**
- The merge gate is broken: sims don't compile, lint is vacuous, testbenches cannot fail.
- Multiple always-block drivers of the same state in all three schedulers (Verilator `MULTIDRIVEN`, Yosys "multiple conflicting drivers" — formally unsynthesizable/race-prone).
- Fundamental data-model gaps: operand ordering is lost at the compiler→hardware boundary; dependency masks are 32-bit while `NUM_NODES=64`; EXEC_PRIM/PRIM_RESULT truncate data to 16/24 bits.
- GC, closure unit, environment unit, and `graph_memory` are stubs/dead code despite being marked as complete phases.
- CPU M-extension: broken MULH family, single-cycle combinational dividers — correctness and timing risks.

**Estimated code quality:** Low–Medium. Style is good; correctness is not there yet (6+ verified critical functional bugs).
**Estimated maintainability:** Medium. Excellent docs, but heavy triplicated scheduler code, dead modules, and doc/RTL drift.
**Estimated synthesis quality:** Low. Top level does not elaborate; multi-driver conflicts; no complete synthesis run exists; the SDC and PLL configuration are wrong for Gowin.
**Estimated timing quality:** At risk / unknown. No completed STA; single-cycle 32-bit dividers and single-cycle 32×32→64 multipliers at 100 MHz on a GW2AR speed-grade are unlikely to close timing.

---

## Findings

### Critical

---

**C1. Entire simulation flow fails to elaborate (build regression)**
- **Severity:** Critical
- **Category:** Verification / Synthesis / Maintainability
- **File(s):** `rtl/cpu/mgmt_ram.sv` (line 30), `rtl/peripherals/bram.sv`, `Makefile` (`sim-icarus` target), `.github/workflows/ci.yml`
- **Module(s):** `mgmt_ram`, `bram`
- **Description:** `mgmt_ram` instantiates `bram #(.ADDR_WIDTH(10), .DATA_WIDTH(32), .HEX_FILE(""))`, but `bram` no longer has a `HEX_FILE` parameter (removed in commit `10753fc`). Because the Makefile compiles **all** of `rtl/**/*.sv` into every testbench, the elaboration error `parameter HEX_FILE not found` kills **all 10 Icarus testbenches**. Verified: `make sim-icarus` → 5–7 elaboration errors per testbench; zero run. The phase-9 commit message claims "All 10 testbenches pass".
- **Why it matters:** The project has had no working regression since the phase-9 commit. Every subsequent change (phase 10) was developed without a functioning sim gate. This is the single most urgent issue: with verification dark, real bugs (below) accumulate undetected.
- **Suggested improvement:** Reconcile `mgmt_ram` with `bram` (either restore an init mechanism in `bram` using an integer/hex parameter, or drop the override). Also stop compiling the entire RTL tree into every unit testbench — compile only the DUT's dependencies (a per-testbench file list), so one broken module cannot take down the whole suite.
- **Expected benefit:** Restores the verification loop; isolates future regressions to the affected module's tests.

---

**C2. `lucid_top` does not elaborate — Tang Nano 20K target cannot be built**
- **Severity:** Critical
- **Category:** RTL Quality / Synthesis / Architecture
- **File(s):** `rtl/top/lucid_top.sv` (line 194), `rtl/cpu/mgmt_ram.sv`
- **Module(s):** `lucid_top`, `rv32im_core`
- **Description:** `assign led[1] = cpu.status[0];` references a `status` signal that **does not exist** in `rv32im_core`. Verilator: `Can't find definition of 'status' in dotted variable/method: 'cpu.status'`. Combined with C1's `HEX_FILE` error inside `lucid_top.ram.ram`, the top level fails elaboration in both Icarus and Verilator. The checked-in `build/synth/synth.log` stops abruptly while reading `fifo.sv` — synthesis never completed. Additionally, `s3_*` (Debug/FPU control) signals are declared but never connected (the bus has only 3 slaves), and the entire FPU side (scheduler, heap, message system) is absent from the top, contrary to the block diagram in `docs/ARCHITECTURE.md`.
- **Why it matters:** The deliverable that Phase 9 claims ("Tang Nano 20K top-level … synthesis results: ~500 cells") does not exist; the device cannot be programmed. Hierarchical probes into modules are fragile by nature — this is exactly why.
- **Suggested improvement:** Expose a proper `status`/`running` output port on `rv32im_core` (or tie the LED to a bus-visible status register); remove the hierarchical reference; connect or remove `s3_*`; rerun and archive a *complete* synth log as a CI artifact.
- **Expected benefit:** A bitstream-buildable top; honest synthesis metrics; no hidden elaboration breakage.

---

**C3. RV32IM: MULH/MULHSU/MULHU always return 0 (32-bit context truncation)**
- **Severity:** Critical
- **Category:** RTL Quality (correctness)
- **File(s):** `rtl/cpu/rv32im_core.sv` (lines 295–302; also 183–184)
- **Module(s):** `rv32im_core`
- **Description:** In a 32-bit assignment context, `($signed(alu_a) * $signed(alu_b)) >> 32` evaluates the multiply at 32 bits (max operand width), truncating the upper half **before** the shift. Reproduced: `MULH(0x10000,0x10000)` → `0` (expect `1`); `MULH(-1,1)` → `0` (expect `0xFFFFFFFF`). Two more defects in the same lines: MULHSU uses `$unsigned × $unsigned` (spec requires signed × unsigned), and the correct 64-bit product `mul_full` is computed at line 184 but **never used** (dead code that would have fixed this).
- **Why it matters:** Any compiled code using 64-bit multiply-high (e.g., fixed-point, `long long` on RV32) silently produces wrong results. DIV/REM were implemented with more care than MULH, so this will surprise users.
- **Suggested improvement:** Drive MULH/MULHSU/MULHU from a single 64-bit product computed in a 64-bit context (sign-extend operands to 64 bits first; use three signedness variants or one shared 33×33-bit arrangement). Delete the duplicated inline multiplies.
- **Expected benefit:** Correct M extension; one shared multiplier (area saving on a part with only 32 DSPs).

---

**C4. RV32IM: LB/LH/LBU/LHU ignore address alignment — wrong bytes loaded**
- **Severity:** Critical
- **Category:** RTL Quality (correctness)
- **File(s):** `rtl/cpu/rv32im_core.sv` (lines 146–155)
- **Module(s):** `rv32im_core`
- **Description:** `ld_result` always selects `wb_dat_i[7:0]` / `wb_dat_i[15:0]` regardless of `wb_adr[1:0]`. A byte load from address `A` with `A[1:0] != 0` returns the wrong byte lane. Stores correctly rotate `wb_sel` and replicate data, so the bug is load-side only. There is also no misaligned-access trap (acceptable for a minimal core, but must be documented).
- **Why it matters:** Any firmware touching byte/halfword arrays (strings, UART buffers, packed structs) reads corrupted data. The management CPU's primary jobs (REPL, compiler frontend, UART I/O) are all byte-oriented.
- **Suggested improvement:** Select the byte/halfword lane with `wb_adr[1:0]` (i.e., `wb_dat_i[8*wb_adr[1:0] +: 8]`), then sign/zero-extend; optionally add an alignment exception for LH/LW crossing word boundaries.
- **Expected benefit:** Correct C-level byte/halfword access; firmware-compiler compatibility.

---

**C5. Graph schedulers: operands assigned in completion order, not input order (verified wrong results)**
- **Severity:** Critical
- **Category:** Architecture / RTL Quality (correctness)
- **File(s):** `rtl/scheduler/graph_scheduler.sv` (lines 294–313, S_UPD_NEXT), `rtl/scheduler/graph_scheduler_fp.sv` (lines 347–362), `rtl/scheduler/graph_scheduler_parallel.sv` (lines 207–229), `frontend/scheme/compiler.py` (line 233, `encode_dep_mask`)
- **Module(s):** `graph_scheduler`, `graph_scheduler_fp`, `graph_scheduler_parallel`
- **Description:** When a producer node completes, its result is written to `op0` if the consumer's `rdyinp == 0`, to `op1` if `rdyinp == 1`, etc. The slot index is therefore **arrival order**, not source operand order. The Scheme compiler keeps an ordered `inputs[]` list, but only a dependent *bitmask* is emitted to hardware — operand ordering is discarded at the ABI. Reproduced on the base scheduler: graph for `(- (* 4 5) 3)` yields `0xFFFFFFEF` (−17) instead of 17, because the literal `3` completes before the `MUL` and is assigned to `op0`. All non-commutative ops are affected (SUB, DIV, MOD, LT, GT, LE, GE, IF). Existing tests pass only because they use commutative ops or happen to complete in input order.
- **Why it matters:** This is a *semantic* bug in the execution engine: any real program with subtraction, division, comparisons, or `if` can compute wrong results depending on scheduling order. It will also make parallel scheduling (Phase 7) nondeterministic.
- **Suggested improvement:** Carry operand identity to the consumer. Two practical options: (a) store a per-consumer ordered input list (e.g., 2–3 small input-slot ID fields per node, matching the existing `INPUTS` word already reserved in `graph_memory`'s layout) and, at update time, look up which slot the completing node occupies; or (b) replace the flat dep-mask with per-slot dependent records (dependent ID + slot index, e.g., 8+2 bits per edge) in an edge memory.
- **Expected benefit:** Deterministic, correct execution for all opcodes regardless of completion order; unblocks sound parallel execution.

---

**C6. Ready-queue overflow silently drops nodes (verified: 16 of 18 nodes executed)**
- **Severity:** Critical
- **Category:** Architecture / RTL Quality (correctness)
- **File(s):** `rtl/scheduler/graph_scheduler.sv` (lines 49–56, 160–171, 200–213), `rtl/scheduler/graph_scheduler_fp.sv`, `rtl/scheduler/graph_scheduler_parallel.sv`
- **Module(s):** `graph_scheduler` (all variants)
- **Description:** `Q_DEPTH=16` while `NUM_NODES=64`. `S_SCAN` pushes every 0-input node without backpressure; `if (push_q && !q_full)` silently discards pushes beyond 16. Reproduced: 18 independent roots → exactly 16 execute, `done_cnt=16`, FSM reaches `S_DONE` and reports status "done" with no error flag. In graphs, dropped nodes also leave their dependents starved (which this FSM tolerates by finishing anyway — see S_EXEC: queue empty → S_DONE).
- **Why it matters:** Wide graphs (common for real expressions: every literal is a root) silently compute wrong or partial results while reporting success. `done_cnt != node_cnt` is never checked.
- **Suggested improvement:** Make the queue at least `NUM_NODES` deep (a node can never be ready more than once per run — scan pushes each node at most once and re-push happens only after pop), or add scan backpressure (pause scan when full) plus a sticky overflow error bit in the status register and a final `done_cnt == node_cnt` consistency check.
- **Expected benefit:** Lossless scheduling for any graph up to `NUM_NODES`; visible failure instead of silent corruption.

---

**C7. UART RX read path off-by-one: CPU reads stale byte, current byte is consumed and lost**
- **Severity:** Critical
- **Category:** RTL Quality (correctness) / Interface protocol
- **File(s):** `rtl/peripherals/uart.sv` (lines 82, 100–109), `rtl/messages/fifo.sv` (lines 61–68)
- **Module(s):** `uart`, `fifo`
- **Description:** The FIFO has a *registered* read (`rd_data_q` updates one cycle after `rd_en`), but the UART asserts Wishbone `wb_ack` combinationally in the same cycle as the read (`wb_ack = wb_stb && wb_cyc`, `rd_en = wb_rd && addr==4`). The CPU therefore samples `rx_fifo_data` in the same cycle the pop occurs — receiving the **previously** popped byte while the current head byte is consumed and lost. Every `UART_RX_DATA` read returns the byte from the *previous* read; the first read returns reset garbage; the last received byte is never readable. A related TX-side race: in `TX_IDLE` the FSM pulses `tx_fifo_rd` and in `TX_START` loads `tx_shift <= tx_fifo_data` on `baud_tick`; if the free-running `baud_tick` fires in the single cycle between the FIFO pop and `rd_data_q` updating, the shift register captures the stale byte (probability ≈ 1/`baud_div` per byte ≈ 0.1 % at 115200 baud).
- **Why it matters:** The UART is the management CPU's only host interface (REPL). RX data loss/corruption makes the REPL unusable; the TX race inserts rare, hard-to-reproduce byte corruption on output.
- **Suggested improvement:** Convert the UART FIFOs to first-word-fall-through (drive `rd_data` combinationally from `mem[rd_ptr]`) **or** register the read data and ack one cycle later (matching `boot_rom`/`mgmt_ram` latency). For TX, load `tx_shift` from the FIFO output in the state after the pop is guaranteed visible (or make the TX FIFO FWFT too).
- **Expected benefit:** Correct byte stream on the primary interface; deterministic TX content.

---

**C8. GC subsystem is functionally inert (no child marking, no reclaim, mark bits never cleared, integration deadlock)**
- **Severity:** Critical
- **Category:** Architecture / RTL Quality (correctness) / Verification
- **File(s):** `rtl/gc/gc_controller.sv`, `rtl/heap/heap_controller_gc.sv`, `simulation/icarus/tb_gc.sv`
- **Module(s):** `gc_controller`, `heap_controller_gc`
- **Description:** Multiple independent defects:
  1. **Nothing is ever pushed onto the mark stack.** `ST_MARK_CHILDREN` issues child-pointer reads but the "push child" code is absent (comments admit: *"For simplicity: push all non-zero children"* — not implemented). Only roots are marked; reachable children would be swept as garbage.
  2. **Sweep reclaims nothing.** `ST_SWEEP_SCAN` never clears mark bits, never increments `freed_bytes`, never builds a free list, and ends with `updated_free_ptr <= scan_ptr` (= the old `heap_free_ptr`). Because marks are never cleared, a *second* GC run would mark nothing (all objects already marked) — dangerous if sweep is ever finished.
  3. **`updated_free_ptr` is ignored.** `heap_controller_gc` saves `gc_saved_free` but never restores/updates `free_ptr` on `gc_done` — freed space is never reused.
  4. **Integration gap / deadlock.** On OOM, `heap_controller_gc` sets `gc_active/gc_busy` internally but produces no trigger output; `gc_controller` waits on its own `gc_start`. Nothing in the repo connects OOM → `gc_start` → `gc_done` back to the heap. Allocation blocks permanently after the first OOM in any integrated system. `tb_gc` sidesteps this by driving `gc_done` manually and never instantiating `gc_controller` (which is instantiated **nowhere** in the repo — no testbench covers it).
  5. Sweep advance uses a stale `obj_size` (registered read latency not accounted for), so even the stub scan can walk misaligned.
- **Why it matters:** Phase 8 is marked complete, but the GC cannot free a single byte and would corrupt the heap if sweep were enabled. In an integrated FPU, the first OOM deadlocks the machine.
- **Suggested improvement:** Either (a) implement the full loop per `docs/architecture/gc-design.md`: push children, wait one cycle for registered read data before using it, clear marks and compact/update `free_ptr` in sweep, wire OOM → `gc_start` and `updated_free_ptr` back into the heap, and add a real `gc_controller` testbench; or (b) explicitly descope GC (document as non-functional, remove from `make synth` and the roadmap's "complete" list) until Phase 8 is properly scheduled.
- **Expected benefit:** Honest project state; a GC that reclaims memory instead of deadlocking; no false sense of safety.

---

**C9. Parallel scheduler: dual-pop accounting corrupts the ready queue; all `tb_parallel` checks fail while reporting PASS**
- **Severity:** Critical
- **Category:** RTL Quality (correctness) / Verification
- **File(s):** `rtl/scheduler/graph_scheduler_parallel.sv` (lines 100–113, 154–185), `simulation/icarus/tb_parallel.sv`
- **Module(s):** `graph_scheduler_parallel`
- **Description:** In `S_EXEC`, the FSM asserts `pop_q` (the queue process decrements `q_cnt` by 1) **and** directly assigns `q_rptr <= q_rptr + 1; q_cnt <= q_cnt - 1;` for the second pop — from a *different* always block. Two processes drive `q_rptr`/`q_cnt` (a multiple-driver race; both happen to write the same value), so a dual pop decrements the count by only 1 instead of 2. The count desynchronizes → the scheduler later pops stale/empty slots, re-executes nodes, and cascades corruption. Verified behavior: `tb_parallel` prints `node4 = 0 (exp 3)`, `node6 = 0 (exp 90)`, `node2 = 0 (exp 16)`, `node8 = 0 (exp 22)` — **all checks fail** — then prints `PASS: tb_parallel` and exits 0. (The known-issues file documents a different `upd_src` bug; the accounting race is an additional, independent defect. The module also writes `q_wptr/q_rptr/q_cnt`, `done_cnt`, `perf_conc`, and all `node_*` arrays from two or more always blocks — see H1.)
- **Why it matters:** The Phase 7 deliverable computes wrong results on dependent graphs, and the test infrastructure reports it as passing. This is the canonical example of why exit-code-based gating matters (see H18).
- **Suggested improvement:** Drive the queue from exactly one process; implement dual-pop inside that process (`q_rptr <= q_rptr + 2; q_cnt <= q_cnt - 2` guarded by `q_cnt >= 2`), or pop once per cycle into a 2-entry skid buffer. Fix the documented `upd_src`/backup interaction at the same time, and make `tb_parallel` fail loudly (see H18).
- **Expected benefit:** A parallel scheduler whose results match the sequential one; regression tests that can catch it.

---

**C10. `mgmt_ram` ignores `wb_sel` — byte/halfword stores corrupt the whole word**
- **Severity:** Critical
- **Category:** RTL Quality (correctness)
- **File(s):** `rtl/cpu/mgmt_ram.sv` (lines 27–38), `rtl/peripherals/bram.sv`
- **Module(s):** `mgmt_ram`, `bram`
- **Description:** The CPU correctly computes byte-enables (`wb_sel`) for SB/SH, but `mgmt_ram` never forwards them: `bram` has no byte-enable input, so every store writes the full 32-bit word. An SB to address N overwrites the other 3 bytes of that word with the replicated byte pattern the CPU drives. (`graph_memory` has the same unimplemented `wb_sel`.)
- **Why it matters:** C code on the management CPU routinely performs byte/halfword stores (strings, buffers). This silently corrupts adjacent data — including stack contents — and interacts with C4 to make all sub-word memory access broken.
- **Suggested improvement:** Add `sel[3:0]` byte-enable support to `bram` (four 8-bit write enables — maps natively onto Gowin BSRAM byte-write enables) and forward `wb_sel` in `mgmt_ram`.
- **Expected benefit:** Correct SB/SH semantics; native BSRAM byte-enable usage (no extra logic on Gowin).

---

### High

---

**H1. Multiple always-block drivers of the same state in all three schedulers (simulation race / synthesis conflict)**
- **Severity:** High
- **Category:** RTL Quality / Synthesis
- **File(s):** `rtl/scheduler/graph_scheduler.sv`, `rtl/scheduler/graph_scheduler_fp.sv`, `rtl/scheduler/graph_scheduler_parallel.sv`
- **Module(s):** all three schedulers
- **Description:** `node_state`, `node_rdyinp`, `node_result`, `done_cnt` (and in the parallel variant also `q_wptr/q_rptr/q_cnt`, `perf_conc`) are written from the register-file `always_ff` (reset + CPU writes) **and** from the FSM `always_ff`. Verilator reports `MULTIDRIVEN` (10+ warnings in `graph_scheduler` alone, e.g. `done_cnt` at line 196); Yosys reports *"multiple conflicting drivers"* (two DFF cells driving the same net, e.g. `node_rdyinp[61]`). In simulation this is an NBA race whose outcome depends on simulator scheduling order; in strict synthesis flows it is an error or produces physically shorted drivers.
- **Why it matters:** Beyond portability, this makes current simulation results simulator-dependent — the same race class that hides behind C9. It also blocks any move to Verilator-based simulation or vendor synthesis of these modules.
- **Suggested improvement:** Merge each state element into a single process (a common pattern: one `always_ff` per module with a clear default + case structure), or split register-file state and FSM state into distinct variables with explicit muxing.
- **Expected benefit:** Deterministic simulation, clean Verilator/Yosys runs, vendor-tool portability.

---

**H2. Dependency mask is 32-bit but `NUM_NODES=64` (and 256 in `graph_memory`); priority encoders are hard-coded and incomplete**
- **Severity:** High
- **Category:** Architecture / Scalability / RTL Quality
- **File(s):** `rtl/scheduler/graph_scheduler.sv` (lines 41, 249–292), `rtl/scheduler/graph_scheduler_fp.sv` (lines 305–345), `rtl/scheduler/graph_scheduler_parallel.sv` (lines 207–229), `rtl/scheduler/graph_memory.sv`
- **Module(s):** all schedulers, `graph_memory`
- **Description:** `node_dep` is 32 bits, so nodes 32–63 can never receive a dependency update. The S_UPD_SCAN priority encoder enumerates exactly 32 cases; the parallel scheduler's encoder enumerates only **11** (bits ≥ 11 silently ignored → dependent never becomes ready → queue drains → `S_EXEC` waits forever: livelock). `graph_memory` defaults to 256 nodes. Four inconsistent node-count/dependency-width assumptions coexist.
- **Why it matters:** Graphs larger than 32 nodes (trivially reached by real programs) silently mis-execute or hang; the parameterization promises scalability the RTL doesn't deliver.
- **Suggested improvement:** Parameterize the dependency width (`localparam DEP_W = NUM_NODES`) and generate the priority encoder in a loop (or use a `for` loop with `upd_mask & (upd_mask-1)` and an index scan). Align `NUM_NODES` across `graph_memory` and schedulers. Add an assertion that no dep bit ≥ `NUM_NODES` is ever set.
- **Expected benefit:** Scalable, consistent graph execution; elimination of a livelock class.

---

**H3. EXEC_PRIM/PRIM_RESULT message protocol truncates data (16-bit op0, 24-bit result, sign loss)**
- **Severity:** High
- **Category:** Architecture / RTL Quality (correctness)
- **File(s):** `rtl/scheduler/graph_scheduler_fp.sv` (lines 262–280, 291–303), `rtl/primitives/primitive_exec.sv` (lines 93–99, 120–127)
- **Module(s):** `graph_scheduler_fp`, `primitive_exec`
- **Description:** Data word 0 packs `{node_id[8], opcode[8], op0[16]}` — `op0` is truncated to 16 bits. The response packs `{node_id[8], result[24]}` and the scheduler zero-extends it to 32 bits, destroying sign (e.g., `-2` from a SUB becomes `0x00FFFFFE`). `graph_scheduler_fp` also drops `op2` entirely, so IF (3 operands) cannot be dispatched.
- **Why it matters:** The message-based execution path (Phase 4, the architecture's stated direction) silently corrupts any value ≥ 2^16/2^24 and every negative result — the common case for integer arithmetic.
- **Suggested improvement:** Extend the protocol to carry full 32-bit operands and results (e.g., 4-word EXEC_PRIM: header, {node_id, opcode, rsvd}, op0, op1(+op2); 3-word PRIM_RESULT: header, node_id, result) and update `message-protocol.md` accordingly.
- **Expected benefit:** Correct signed 32-bit arithmetic over the message fabric; IF support; protocol consistency.

---

**H4. UART receiver: no mid-bit sampling, shared free-running baud tick, no input synchronizer**
- **Severity:** High
- **Category:** Clocking (CDC) / RTL Quality
- **File(s):** `rtl/peripherals/uart.sv` (lines 119–136, 186–252)
- **Module(s):** `uart`
- **Description:** (a) `rx` is sampled directly (`if (!rx && ctrl[0])`) with no 2-FF synchronizer — metastability risk on an asynchronous pin. (b) RX samples on the shared, free-running `baud_tick`: after detecting the start-bit edge, the first sample occurs 1–2 bit periods later (uniform phase), not at mid-bit; the intended half-bit offset (`rx_tick_cnt <= baud_div[16:1]`) is loaded but **never used** (dead code, as are `tx_tick_cnt`, `tx_tick`, `rx_start_bit`). Sampling jitter is ±0.5 bit — far outside the ±~0.2 bit budget needed for robust 8N1 reception. (c) `rx_ready` is set on reception but never cleared (sticky forever); `rx_overrun` likewise.
- **Why it matters:** Reception works only when the phase happens to align; with clock drift between endpoints, frames drift toward sample edges → framing errors on the REPL link. Metastability on `rx` can corrupt the RX FSM.
- **Suggested improvement:** Synchronize `rx` through 2 FFs; give RX its own bit timer restarted at the start-bit falling edge, sampling at 1/2-bit then 1-bit intervals (or 16× oversampling); clear `rx_ready` when `UART_RX_DATA` is read (or make it `!rx_fifo_empty`) and provide a status-clear write.
- **Expected benefit:** Robust 8N1 reception across realistic clock tolerances; correct status semantics.

---

**H5. Wishbone bus: access to an unmapped address stalls the CPU forever**
- **Severity:** High
- **Category:** Architecture / Reliability
- **File(s):** `rtl/bus/wishbone_bus.sv` (lines 43–76)
- **Module(s):** `wishbone_bus`, `rv32im_core` (victim)
- **Description:** Address decode covers only `m_adr[31:16]` ∈ {0x0000, 0x0001, 0x0002}; for any other address `m_ack` is held at 0 permanently. The CPU's fetch/load/store FSM waits on `wb_ack` indefinitely → hard hang with no visibility. A `NUM_SLAVES` parameter exists but is unused; `clk`/`reset_n` are unused (documented as intentional).
- **Why it matters:** One bad pointer in firmware (or execution from a non-ROM region) bricks the chip with no error path; debugging in hardware is painful.
- **Suggested improvement:** Add a default slave that acks immediately with an error indication (or all-ones read data), and/or a watchdog timeout in the CPU; expose a bus-error status bit. Also align with the documented memory map (0x00030000 debug, 0x00100000 FPU regions in `memory-map.md` are not decoded).
- **Expected benefit:** Fail-visible behavior instead of silent deadlock; forward path to the documented address map.

---

**H6. Boot ROM contents are never loaded (`$readmemh` removed; stale comment); `boot_rom.hex` is a dead file**
- **Severity:** High
- **Category:** Synthesis / Verification / Maintainability
- **File(s):** `rtl/peripherals/bram.sv` (line 3 comment), `rtl/cpu/boot_rom.sv`, `simulation/icarus/boot_rom.hex`
- **Module(s):** `boot_rom`, `bram`, `rv32im_core` (victim)
- **Description:** Phase-1 `bram` had `initial if (HEX_FILE != "") $readmemh(...)`. The current `bram` has no initialization at all, yet its header comment still claims "Initialize from hex file via `$readmemh`". `boot_rom` passes no hex file; `tb_platform` doesn't load one hierarchically either. The CPU therefore fetches `X`/0 instructions. (`tb_platform` currently can't compile anyway — C1 — and its UART TX check depends on this ROM image.)
- **Why it matters:** The platform test's results are meaningless if the CPU executes an empty ROM; on hardware, the management CPU boots into garbage.
- **Suggested improvement:** Restore a tool-tolerant init path (e.g., integer parameter + `` `ifdef SIMULATION `` `$readmemh`, or a synthesis-friendly initialized-memory block for Gowin BSRAM data-init), and have the Makefile generate/refresh `boot_rom.hex` from firmware.
- **Expected benefit:** A CPU that boots real code in simulation and on the board; platform tests that test something.

---

**H7. Message router: multi-word messages corrupt on any sender bubble; arbiter hard-coded to 4 inputs**
- **Severity:** High
- **Category:** Architecture / RTL Quality
- **File(s):** `rtl/messages/message_router.sv` (lines 58–63, 78–108, 128–136)
- **Module(s):** `message_router`
- **Description:** (a) During a locked multi-word transfer, if the connected input momentarily deasserts `in_valid` (a bubble), the `!found` branch clears `busy/lock/conn` — terminating the message early. The remaining payload words are then routed by their top 8 bits **interpreted as a DEST field** (payload data!) → arbitrary misdelivery. The design implicitly requires bubble-free senders; nothing enforces or documents it. (b) The priority chain enumerates `grant[0..3]` literally: `NUM_INPUTS > 4` leaves higher inputs unserved (undriven grant bits); `NUM_INPUTS < 4` indexes out of bounds. (c) Fixed priority ⇒ input 0 can starve others (round-robin is already on the TODO). (d) Broadcast (`DEST=0xFF`) is silently dropped, though `message_types.sv` defines `MODULE_BROADCAST`.
- **Why it matters:** The EXEC_PRIM flow is a 3-word message — exactly the pattern at risk if any unit adds flow control later (e.g., a FIFO-backed sender). Data-dependent misrouting is a nightmare failure mode.
- **Suggested improvement:** Hold `busy/lock` during bubbles and deassert `out_valid` until the next word is present (never terminate early); generate the priority chain in a `for` loop parameterized by `NUM_INPUTS`; decide and implement broadcast semantics or remove the constant.
- **Expected benefit:** Robust multi-word transport; correct parameterization; no hidden protocol constraints.

---

**H8. Message dispatcher: `status` register undriven; routing table dead; statistics inverted/dead**
- **Severity:** High
- **Category:** RTL Quality / Architecture
- **File(s):** `rtl/messages/message_dispatcher.sv` (lines 44–53, 109–147)
- **Module(s):** `message_dispatcher`
- **Description:** (a) `status` is readable at 0x04 but never assigned → reads X in sim / constant 0 after synthesis. (b) The `route[]` table is writable/readable but has **no effect on routing** (the router routes purely by the header DEST field) — a documented feature ("software-programmable routing table") that does nothing. (c) `msg_count` increments on `tx_valid && tx_ready && !last` (counts all words *except* the last — inverted message counting) and is never readable; `err_count` is never incremented or readable. All of this logic synthesizes into dead flip-flops.
- **Why it matters:** Dead/misleading CSRs waste area and erode trust in the register map; software will read garbage status.
- **Suggested improvement:** Either implement (drive `status` from router busy/queue state; count on `last`; make counters readable; delete or implement the route table) or remove the dead registers and fix the documentation.
- **Expected benefit:** A truthful CSR map and less dead logic.

---

**H9. Heap controllers: double allocation when `alloc_valid` is held; no alignment enforcement; header mirror costs a second write port**
- **Severity:** High
- **Category:** RTL Quality / Resource Optimization
- **File(s):** `rtl/heap/heap_controller.sv` (lines 55–77), `rtl/heap/heap_controller_gc.sv` (lines 65–120)
- **Module(s):** `heap_controller`, `heap_controller_gc`
- **Description:** (a) `if (alloc_valid && !alloc_ack)` re-fires every other cycle while `valid` is held (ack pulses for one cycle, then the condition is true again) → duplicate allocations. Current testbenches pulse `valid` for exactly 1 cycle, masking it. (b) `alloc_size` is byte-granular and `free_ptr` advances unaligned while headers are written at `free_ptr>>2` — an unaligned size silently corrupts layout; round up to 4 bytes. (c) `mem[2] <= free_ptr` every cycle adds a second write to the memory array each cycle → multi-write-port inference → likely FF-instead-of-BSRAM mapping for the heap (16 KB heap = 131 kbit → impossible in FFs on this device). (d) `heap_used` includes the 256-byte header (misleading metric); header layouts differ between the two variants (5 vs 6 words) and both differ from `memory-map.md` (which includes a VERSION word).
- **Why it matters:** (a) and (b) are latent heap-corruption bugs for any caller that doesn't exactly mimic the testbench; (c) decides whether the heap fits the device at all.
- **Suggested improvement:** Accept one request per `valid` rising edge (or require `valid` deassertion before re-arming, documented); align `alloc_size` up to 4; keep heap metadata in registers, not mirrored into the object BRAM (single write port); unify the header layout with the memory-map doc.
- **Expected benefit:** Safe allocator contract; BSRAM-inferable heap; consistent object model.

---

**H10. Environment unit: create requests complete via the extend path; lookup and extend are stubs**
- **Severity:** High
- **Category:** RTL Quality (correctness) / Architecture
- **File(s):** `rtl/heap/environment_unit.sv` (lines 83–101)
- **Module(s):** `environment_unit`
- **Description:** In `ST_ALLOC`, the create-vs-extend decision tests the **live** `env_create_req` input rather than a registered request type. A 1-cycle create pulse (the natural driver) is already gone by `ST_ALLOC` → the create result is returned on `child_env_ptr`/`extend_ack`, `env_ptr`/`env_ack` never assert → caller hangs. Lookup returns `ack` immediately with `found=0` (never searches); extend allocates space for parent+new bindings but copies nothing; `binding_data`, `parent_env_ptr`, `new_bindings`, `lookup_env`, `lookup_sym` are unused inputs.
- **Why it matters:** The environment unit is on the critical path for closures/lambda (Phase 5, marked complete). As written it cannot be used.
- **Suggested improvement:** Register the request type at acceptance; implement lookup against the heap (requires the heap read port — currently missing) and extend-copy; or mark the module as a stub and exclude it from "complete" claims.
- **Expected benefit:** Functional environments; honest phase status.

---

**H11. Closure unit: closure body never written; hangs for `env_size ≥ 6`**
- **Severity:** High
- **Category:** RTL Quality (correctness)
- **File(s):** `rtl/heap/closure_unit.sv` (lines 38, 79–89)
- **Module(s):** `closure_unit`
- **Description:** `ST_WRITE` only increments `write_idx` — the comment says it writes closure data "via the heap controller's write port", but no such port exists in the interface; `arity`, `code_ptr`, `env_data` are unused. Also `write_idx` is 3 bits while the loop bound is `2 + env_size` (up to 257): for `env_size ≥ 6` the counter wraps before reaching the bound → infinite loop (module hangs permanently).
- **Why it matters:** Closures are the core object of a functional machine; the unit allocates a header and loses the payload; a large environment deadlocks the FPU.
- **Suggested improvement:** Add a heap data-write interface (or write payload words through the allocator protocol); size `write_idx` to `$clog2(MAX_ENV+3)`; bound `env_size` by parameter with an assertion.
- **Expected benefit:** Real closure objects; no livelock.

---

**H12. `graph_memory` is unsynthesizable as intended and dead (never instantiated)**
- **Severity:** High
- **Category:** Synthesis / Resource Optimization / Architecture
- **File(s):** `rtl/scheduler/graph_memory.sv`
- **Module(s):** `graph_memory`
- **Description:** The scheduler port reads **6 words in one cycle** (`sched_rd_data <= {mem[base+5],…}`) and both the Wishbone process and the scheduler process write `mem` — a 6-read-port/2-write-port memory. No FPGA BRAM supports this; synthesis inflates it to ~49k flip-flops (1536×32) — more than double the device's FF budget. It is also written from two always blocks (multi-driver). And nothing instantiates it: the schedulers use per-field FF arrays instead (~15 kFF for 64 nodes — itself a large fraction of the device).
- **Why it matters:** The module that was supposed to make graphs fit in BRAM can't be used; current schedulers burn FFs for node storage, which won't scale past toy graphs on the GW2AR.
- **Suggested improvement:** Redesign node storage as sequential word access over 6 cycles (or 2×BRAM banks) with a single write port and explicit WB/scheduler arbitration; then make the schedulers use it. Remove `wb_sel` (unimplemented) or implement byte enables.
- **Expected benefit:** Graph storage in BSRAM (≈12 kbit for 64 nodes vs ~15 kFF); a path to 256+ node graphs.

---

**H13. Single-cycle combinational 32-bit dividers (CPU ×4, scheduler, primitive unit) — timing and area hazard at 100 MHz**
- **Severity:** High
- **Category:** Timing / Resource Optimization
- **File(s):** `rtl/cpu/rv32im_core.sv` (lines 303–318), `rtl/scheduler/graph_scheduler.sv` (lines 233–234), `rtl/primitives/primitive_exec.sv` (lines 58–59)
- **Module(s):** `rv32im_core`, `graph_scheduler`, `primitive_exec`
- **Description:** DIV/DIVU/REM/REMU are four separate combinational 32-bit divide/remainder units in the CPU (≈1–2 kLUT each on this architecture), plus `/` and `%` in both the scheduler and the primitive unit. A 32-bit combinational divider is ~30+ levels of logic — very unlikely to meet 10 ns on a GW2AR speed grade, and it sits on the register-write path of the CPU. The single-cycle 32×32→64 signed multiply (CPU) and 32×32 multiply (schedulers) are also aggressive (should map to 4 Gowin DSPs each if inferred well — unverified).
- **Why it matters:** Worst-case timing likely fails at 100 MHz; area pressure is significant on a 20 kLUT part. `KNOWN_ISSUES.md` already suspects this for the CPU — this review extends it to the FPU units.
- **Suggested improvement:** Implement one iterative (e.g., 32-cycle radix-2 or 16-cycle radix-4) shared divider per domain with a busy/ack handshake (CPU: multi-cycle M-extension; FPU: multi-cycle primitive). Confirm DSP inference for multipliers with Yosys-Gowin and add `(* use_dsp *)`-style guidance if needed.
- **Expected benefit:** Realistic timing closure; ≈3–6 kLUT saved.

---

**H14. PLL configuration is wrong for Gowin; no pin constraints exist; SDC references nonexistent objects**
- **Severity:** High
- **Category:** Gowin-Specific / Constraints / Clocking
- **File(s):** `rtl/peripherals/gowin_pll.sv`, `rtl/top/lucid_top.sv` (lines 27–47), `scripts/lucid.sdc`
- **Module(s):** `lucid_top`, `rPLL`
- **Description:** (a) The blackbox `rPLL` and its `defparam`s use `FCLKIN/DIV_F/DIV_Q/FILTER` — these are **iCE40-style** parameters. Gowin's `rPLL` uses `FCLKIN`, `IDIV_SEL`, `FBDIV_SEL`, `ODIV_SEL`, `DYN_*_SEL`, `PSDA_SEL`, etc. As written, Gowin tools will reject the parameters or misconfigure the PLL; 27 MHz → 100 MHz needs legal IDIV/FBDIV/ODIV values within the GW2A VCO range (e.g., ÷27 ×100 → VCO 100 MHz is *below* the allowed VCO range, so a real configuration must multiply higher and divide down, e.g. VCO 500 MHz with ODIV=5). (b) No `.cst` file exists — pins for `clk_27m`, `uart_rx/tx`, `btn_rst_n`, `led[2:0]` are unconstrained, so no board bitstream can be produced. (c) The SDC creates a clock on port `clk` (no such port — the port is `clk_27m`), a generated clock on `pll_inst/CLKOUT` (the blackbox port is `clkout`), and declares `sys_clk` and `pll_100m` asynchronous although they describe the same net; input/output delays reference a clock that doesn't exist. The SDC is also not referenced by any build flow in the repo.
- **Why it matters:** Clock generation/constraints are the difference between a working board and an expensive coaster; every element of the current clock chain needs correction before bring-up.
- **Suggested improvement:** Instantiate the Gowin `rPLL` (or the IDE-generated PLL IP) with correct parameters for 27→100 MHz; add `constraints/tangnano20k.cst` with the board's pinout (27 MHz oscillator pin, UART pins to the BL702 bridge, button, LEDs); rewrite the SDC against real objects and wire it into the Gowin/nextpnr flow; gate PLL use on `lock` in the reset path.
- **Expected benefit:** A buildable, correctly constrained design for the Tang Nano 20K.

---

**H15. Scheduler register interface: node fields are write-only; read addresses alias onto control registers**
- **Severity:** High
- **Category:** RTL Quality / Verification / Interface
- **File(s):** `rtl/scheduler/graph_scheduler.sv` (lines 139–151), `rtl/scheduler/graph_scheduler_fp.sv`, `rtl/scheduler/graph_scheduler_parallel.sv`
- **Module(s):** all schedulers
- **Description:** The read mux decodes only `reg_adr[5:2]` ∈ 0–4; node-field addresses (≥ 0x20) are not decoded and alias (e.g., reading node 4's result at 0x8C returns `node_cnt` — reproduced: `tb_graph_scheduler` prints "Node 4 result = 5" while the hierarchical probe shows the correct 14). Testbenches therefore verify via backdoor hierarchical probes (`sched.node_result[4]`), which hardware and firmware cannot do.
- **Why it matters:** The management CPU cannot read results — the REPL can't print an answer; the displayed test output misleads readers into thinking the register interface works.
- **Suggested improvement:** Mirror the write decode for reads (node-field readback via the same `(addr-0x20)/24` decode), or document write-only nodes and add a dedicated RESULT register. Keep testbench checks on the architectural interface, using backdoor probes only as auxiliary.
- **Expected benefit:** Firmware-visible results; tests that validate the real interface.

---

**H16. Reset strategy: no asynchronous assert, uninitialized synchronizer, excessive reset fanout**
- **Severity:** High
- **Category:** Reset Strategy / Timing
- **File(s):** `rtl/top/lucid_top.sv` (lines 52–58), all scheduler/heap files
- **Module(s):** `lucid_top` (and consumers of `reset_n`)
- **Description:** (a) Both assert and deassert of `reset_n` pass through the 4-FF synchronizer — a button press takes ~4 cycles to assert reset; standard practice is async-assert/sync-deassert. (b) `reset_sync` has no initial/reset state — in simulation `reset_n` is X for the first 4 clocks (benign if the TB drives the button, but `lucid_top` has no TB — undetected). (c) The synchronizer ignores `pll_lock` — on hardware the design runs from an unlocked/unstable PLL clock. (d) All node arrays (64 nodes × ~150–240 bits) and the 64×32 mark stack sit under async reset: ~15 kFF of reset fanout per scheduler, hurting reset routing/timing; only `node_state`/`rdyinp` and pointers actually need reset.
- **Why it matters:** Reset reliability and routability at 100 MHz; simulation/hardware behavioral parity.
- **Suggested improvement:** Assert asynchronously, deassert synchronously, and qualify with `pll_lock` on hardware; initialize the synchronizer for sim; remove reset from pure data arrays (node payload fields, mark stack RAM) keeping it only on control state.
- **Expected benefit:** Robust bring-up; reduced reset fanout and better timing; sim/hw parity.

---

**H17. Documentation/RTL drift in interface contracts (message header format, node layout, UART map, heap header, node word count)**
- **Severity:** High
- **Category:** Maintainability / Architecture
- **File(s):** `docs/architecture/message-protocol.md` vs `rtl/messages/message_types.sv`; `docs/architecture/memory-map.md` vs `rtl/scheduler/graph_memory.sv`, `rtl/peripherals/uart.sv`, `rtl/heap/heap_controller.sv`; `docs/ARCHITECTURE.md` vs current test status
- **Module(s):** system-wide
- **Description:** (a) `message-protocol.md` defines the header as `{TYPE, FLAGS, TAG}`; the RTL uses `{DEST, SRC, TYPE, FLAGS}` — incompatible formats; the message-type tables also differ (e.g., NODE_READY 0x13 doc vs 0x12 RTL). (b) `memory-map.md` says 5 words/node (20 B); RTL uses 6 (24 B). (c) Documented UART map (STATUS@0x00, CTRL@0x04, BAUD@0x08, DATA@0x0C) is the *reverse* of the RTL (CTRL@0x00, BAUD@0x04, STATUS@0x08, TX@0x0C, RX@0x10) — firmware written from the doc breaks. (d) Heap header layout (VERSION word) differs from both heap controllers. (e) `ARCHITECTURE.md` claims "10 Icarus Verilog testbenches covering all subsystems" — currently zero compile (C1), and `gc_controller`/`closure_unit`/`environment_unit`/`graph_memory` have no testbench at all. (f) The phase-9 commit message claims synthesis results (~500 cells) that the truncated synth log doesn't support.
- **Why it matters:** This project's stated philosophy is "Architecture before RTL; documentation before code". Interface-contract drift silently invalidates firmware, frontends, and reviews.
- **Suggested improvement:** Pick the RTL or the doc as source of truth per interface and reconcile; add a CI doc-vs-RTL consistency check (even a simple grep-based script for register maps); record real synth/lint/sim results as CI artifacts instead of prose claims.
- **Expected benefit:** Trustworthy specs; no cross-team breakage.

---

**H18. Testbenches cannot fail: `$error` doesn't affect exit status; unconditional "PASS" banners; CI gating ineffective**
- **Severity:** High
- **Category:** Verification
- **File(s):** `simulation/icarus/*.sv` (all), `Makefile`, `.github/workflows/ci.yml`, `scripts/pre-commit.sh`
- **Module(s):** n/a (infrastructure)
- **Description:** Every testbench prints `PASS: tb_*` unconditionally and uses `$error` (which does **not** make `vvp` exit nonzero). `tb_parallel` demonstrates the result: all checks fail, suite reports PASS, CI stays green. Additionally: `make lint` runs Verilator only on `rtl/fpu/*.sv` (empty directory — zsh aborts on the unmatched glob) and `rtl/cpu/*.sv`, with stderr discarded and `|| echo` swallowing failure → vacuous lint, always exit 0; `make sim-verilator` only *echoes* filenames (stub); `make verify` iterates an empty `verification/` directory; the CMake flow (`cmake ..`) fails because `simulation/` and `verification/` contain no `CMakeLists.txt`; the pre-commit hook re-runs the same vacuous lint.
- **Why it matters:** The project believes it is verified; it is not. Combined with C1, there is currently no signal at all from any gate.
- **Suggested improvement:** Give each testbench a pass/fail counter ending in `if (fails==0) $display("PASS") else $fatal(1)` (or `$finish(1)`); make the Makefile stop on first failing testbench (or aggregate and return nonzero); make `lint` cover the full RTL tree with visible output and real exit status; implement or remove `sim-verilator`/CMake/verify targets; add the missing subdirectory `CMakeLists.txt` files or drop CMake from the README.
- **Expected benefit:** A regression gate that can actually go red; CI that means something.

---

### Medium

---

**M1. CSR implementation is partial and internally inconsistent**
- **Severity:** Medium
- **Category:** RTL Quality
- **File(s):** `rtl/cpu/rv32im_core.sv` (lines 237–252, 389–407)
- **Module(s):** `rv32im_core`
- **Description:** `csr_mscratch` is readable via CSRRS but **never writable** (comment claims CSRRW to mscratch is "handled in always_ff" — it isn't); `mtvec/mepc/mcause` are never written; ECALL/EBREAK/MRET fall through silently (no trap); `csr_instret` excludes completed loads/stores (conditioned on `!is_load && !is_store`), so it undercounts retired instructions.
- **Why it matters:** Debuggers and benchmarks rely on `instret`; firmware using `mscratch` (context save) breaks silently.
- **Suggested improvement:** Implement CSR write decode for the supported CSRs (or remove them and document the supported set); count every completed instruction in `instret`; define ECALL/EBREAK behavior (trap to a fixed vector or documented nop).
- **Expected benefit:** Predictable minimal-CSR behavior; correct performance counters.

---

**M2. Triplicated scheduler code (~200 lines × 3) with divergent opcode support**
- **Severity:** Medium
- **Category:** Maintainability / Architecture
- **File(s):** `rtl/scheduler/graph_scheduler.sv`, `graph_scheduler_fp.sv`, `graph_scheduler_parallel.sv`
- **Module(s):** all schedulers
- **Description:** Register file, node arrays, queue, scan, and update logic are copy-pasted across three modules, yet opcode coverage differs: base computes 14 ops inline; `_fp` dispatches (with truncation, H3) and lacks `op2`; `_parallel` supports only LIT/ADD/SUB/MUL — other opcodes silently fall to `default: result <= imm0` (wrong results, no error flag). Opcode encodings are magic numbers repeated in RTL, testbenches, Python, and docs (and collide numerically with message-type codes: IF=0x30 == MSG_EXEC_PRIM).
- **Why it matters:** Fixes (C5, C6, H1, H2) must be applied three times — they already diverge once (parallel's 11-entry encoder).
- **Suggested improvement:** Consolidate into one parameterized scheduler (INLINE vs MESSAGE dispatch strategy); move opcodes/states/message types into a shared `lucid_pkg` package imported by RTL and generated for Python.
- **Expected benefit:** Single point of truth; ⅓ the scheduler code to verify.

---

**M3. FIFO header comment promises a handshake the implementation doesn't have (registered read)**
- **Severity:** Medium
- **Category:** Documentation / RTL Quality
- **File(s):** `rtl/messages/fifo.sv` (lines 22–25, 51–68)
- **Module(s):** `fifo`
- **Description:** The header documents "Standard ready/valid handshake — `rd_en && !empty` → data read", implying same-cycle data; the implementation registers `rd_data_q` one cycle after `rd_en`. This mismatch is the direct cause of C7. The module itself is otherwise correct (pointers, full/empty, count) — it's a contract/documentation bug. Also: `DEPTH` must be a power of two (pointer wrap logic), which is unchecked.
- **Why it matters:** Every consumer must independently discover the 1-cycle read latency; one consumer (UART) already got it wrong.
- **Suggested improvement:** Fix the header to specify registered-read timing (or make the FIFO FWFT); add `initial assert ((DEPTH & (DEPTH-1)) == 0)`.
- **Expected benefit:** No more integration off-by-ones.

---

**M4. `unique case` without default in several `always_comb` blocks (simulation violations observed)**
- **Severity:** Medium
- **Category:** RTL Quality / Synthesis
- **File(s):** `rtl/cpu/rv32im_core.sv` (lines 91, 160, 171, 190, 390), `rtl/primitives/primitive_exec.sv` (line 54)
- **Module(s):** `rv32im_core`, `primitive_exec`
- **Description:** e.g. `st_data`'s `unique case (funct3)` has no `default` and is evaluated for *every* opcode (not just stores); Icarus prints `value is unhandled for priority or unique case statement` at runtime (observed in every testbench). Latches are avoided only because of the pre-assigned defaults. `unique` also acts as a full-case synthesis pragma over an intentionally partial list — risky if defaults are later removed. Icarus ignores `unique` entirely (documented in KNOWN_ISSUES), so sim/synthesis behavior can diverge silently.
- **Why it matters:** Runtime noise masks real issues; pragma semantics differ across tools.
- **Suggested improvement:** Add explicit `default:` branches (or drop `unique` where the case is intentionally partial and rely on the pre-assigned default).
- **Expected benefit:** Deterministic, warning-free simulation; uniform tool behavior.

---

**M5. Blocking assignments in sequential blocks / `int` temporaries / divide-by-6 decode in the register write path**
- **Severity:** Medium
- **Category:** RTL Quality / Synthesis
- **File(s):** `rtl/scheduler/graph_scheduler.sv` (lines 81, 118–119, 226, 295), `graph_scheduler_fp.sv`, `graph_scheduler_parallel.sv`, `rtl/heap/heap_controller.sv` (line 59)
- **Module(s):** schedulers, heap controllers
- **Description:** `tmp_nid/tmp_fid/tmp_d` are 32-bit `int`s assigned with blocking `=` inside `always_ff` (Verilator BLKSEQ warnings; used-before-written hazards if reordered). The node-field decode computes `(reg_adr[7:2] - 8) / 6` and `% 6` — a dynamic divide/modulo by a constant in the CPU write path (synthesizes to real arithmetic logic; fine functionally, but wasteful and surprising). Width mismatches abound (8-bit vs 32-bit compares) — Verilator reports ~30 WIDTHTRUNC/WIDTHEXPAND warnings.
- **Why it matters:** Style that invites race bugs; wasted LUTs; lint noise hides real warnings.
- **Suggested improvement:** Replace with local automatic variables inside the block (or compute indices combinationally); decode node/field by address range compare instead of `/6`,`%6` (24 B stride → use shift-based decode or make the stride 32 B power-of-two); clean up widths.
- **Expected benefit:** Race-free style; smaller decode logic; actionable lint output.

---

**M6. Parallel scheduler: `q_cnt` hard-coded to 4 bits against parameterized `Q_DEPTH`; opcode coverage gaps fail silently**
- **Severity:** Medium
- **Category:** RTL Quality
- **File(s):** `rtl/scheduler/graph_scheduler_parallel.sv` (lines 83, 159–166)
- **Module(s):** `graph_scheduler_parallel`
- **Description:** `logic [3:0] q_cnt` can count to 15, but `Q_DEPTH=16` (`q_full` at `q_cnt == Q_DEPTH` needs 5 bits). Unsupported opcodes (DIV, MOD, EQ, LT, …, IF) fall into `default: result <= imm0` with no error indication. `perf_conc` records a max (1 or 2), despite its name implying a concurrency counter.
- **Why it matters:** Parameter changes break the module silently; silent defaulting masks wrong results.
- **Suggested improvement:** `logic [$clog2(Q_DEPTH):0] q_cnt`; raise an error flag for unsupported opcodes; rename or properly accumulate `perf_conc`.
- **Expected benefit:** Parameter-safe queue; honest error reporting.

---

**M7. `primitive_exec`: no LAST check on input message; DIV-by-zero semantics inconsistent with the CPU**
- **Severity:** Medium
- **Category:** RTL Quality / Architecture
- **File(s):** `rtl/primitives/primitive_exec.sv` (lines 33–40, 58, 103–109)
- **Module(s):** `primitive_exec`
- **Description:** `RX_DATA1` accepts `op1` without verifying `msg_in_last` (a malformed 2- or 4-word message desynchronizes the unit). Divide-by-zero returns 0 here and in the schedulers, but the RV32IM core returns −1 (RISC-V semantics) — three behaviors for the same operation. `RX_HEADER` enum state is dead.
- **Why it matters:** Protocol robustness; cross-unit semantic consistency (results differ by execution path — inline vs dispatched).
- **Suggested improvement:** Check `msg_in_last` (or count words against the header); define one div-by-zero contract (recommend RISC-V: quotient −1, remainder = dividend) and apply it everywhere.
- **Expected benefit:** Robust message handling; uniform arithmetic semantics.

---

**M8. `message_types.sv` uses compilation-unit-scope parameters instead of a package**
- **Severity:** Medium
- **Category:** Maintainability / RTL Quality
- **File(s):** `rtl/messages/message_types.sv`
- **Module(s):** n/a (definitions file)
- **Description:** All constants and helper functions live at `$unit` scope (no `package`), polluting the global namespace for every compilation; some tools error on duplicate `$unit` declarations when the file is compiled more than once in a library. `HEADER_DEST_BITS` (=31) is unused and mislabeled (it's an index, not a width).
- **Why it matters:** Fragile builds as the file list grows; unclear constant ownership.
- **Suggested improvement:** Wrap in `package lucid_msg_pkg; … endpackage` and `import` where needed; delete dead constants.
- **Expected benefit:** Clean namespace; portable compilation.

---

**M9. Timing: long combinational fetch/load-store path and unregistered bus read mux (hypothesis — no STA exists)**
- **Severity:** Medium
- **Category:** Timing
- **File(s):** `rtl/cpu/rv32im_core.sv`, `rtl/bus/wishbone_bus.sv` (lines 71–76), `rtl/peripherals/bram.sv`
- **Module(s):** `rv32im_core`, `wishbone_bus`
- **Description:** Load/store address path: regfile read → ALU adder → `wb_adr` → 16-bit region comparators → slave BRAM address — one cycle. Read return: BRAM registered output → combinational slave mux → CPU `ld_result` mux → regfile write — one cycle. Probably feasible at 100 MHz on this small system but unverified; the dividers (H13) are the dominant risk. No completed STA exists anywhere in the repo (synth aborts before `abc`/`stat`).
- **Why it matters:** Timing closure is currently assumed, not measured.
- **Suggested improvement:** Get `make synth` completing (C1/C2), then run a real STA (nextpnr-gowin timing report or Gowin STA); register the bus read mux if slack is negative.
- **Expected benefit:** Measured (not guessed) Fmax.

---

**M10. `graph_scheduler` state/error reporting gaps**
- **Severity:** Medium
- **Category:** Architecture / RTL Quality
- **File(s):** `rtl/scheduler/graph_scheduler.sv` (lines 215–223, 315–317)
- **Module(s):** `graph_scheduler` (all variants)
- **Description:** `S_EXEC` transitions to `S_DONE` whenever the queue is empty — even if `root_id` is not DONE (starved dependents, dropped nodes, cyclic graphs). There is no error status, no watchdog, and `S_DONE` has no exit except reset (a second start pulse is ignored once DONE... actually `start_pulse` is only checked in `S_IDLE`, so restart requires reset — undocumented). `status` uses magic numbers (1=running, 2=idle/done).
- **Why it matters:** Failures look like success (compounds C6); CPU-side polling can't distinguish "done" from "stuck".
- **Suggested improvement:** Add an error status (root-not-done on queue-empty, overflow bit from C6), a cycle-count watchdog, and a documented software re-arm sequence.
- **Expected benefit:** Detectable failure modes; clear status semantics.

---

**M11. `lucid_top` integration is far from the documented architecture**
- **Severity:** Medium
- **Category:** Architecture
- **File(s):** `rtl/top/lucid_top.sv`, `docs/ARCHITECTURE.md`
- **Module(s):** `lucid_top`
- **Description:** The top instantiates only the management platform (CPU/bus/ROM/RAM/UART). No scheduler, message system, heap, or FPU control registers exist, despite the block diagram showing both processors and a shared bus; the declared `s3_*` "Debug/FPU Control" slave is unconnected; LED assignments are placeholder (`led[2]=1'b1`); no pin constraints (H14).
- **Why it matters:** Hardware bring-up will hit these gaps immediately; reviewers/users reading the doc expect an integrated system.
- **Suggested improvement:** Either integrate the FPU control plane (scheduler CSR slave + dispatcher on the bus) per the memory map, or document the top as "management platform only" milestone.
- **Expected benefit:** Doc/RTL alignment; a useful first bitstream.

---

### Low

---

**L1. Dead signals and unused items (cleanup list)**
- **Severity:** Low
- **Category:** Readability / Synthesis (lint)
- **File(s)/Module(s):** `rv32im_core` (`mul_full`, `STATE_LOAD`); `uart` (`tx_tick_cnt`, `tx_tick`, `rx_tick_cnt` after load, `rx_start_bit`; header comment documents unimplemented `UART_RX_LEVEL`); `graph_scheduler_fp` (`wait_for_msg_rx`, `tx_phase`); `heap_controller_gc` (`gc_saved_free`); `message_dispatcher` (`route`, `msg_count`, `err_count` — see H8); `wishbone_bus` (`NUM_SLAVES`, `clk`, `reset_n`); `boot_rom` (`wb_we/dat_w/sel` inputs); `lucid_top` (`s3_*`); `message_types.sv` (`HEADER_DEST_BITS`); `primitive_exec` (`RX_HEADER` state); `gowin_pll.sv` (duplicates the config that `lucid_top` applies via `defparam` — two sources of truth).
- **Description:** Accumulated dead code from refactors; all of it synthesizes to dangling logic or lint warnings.
- **Why it matters:** Noise hides real warnings; misleads readers (the UART's abandoned half-bit counter looks intentional).
- **Suggested improvement:** Delete or implement; run `verilator --lint-only -Wall` clean.
- **Expected benefit:** Signal-to-noise in reviews and lint.

---

**L2. Magic numbers for states, status codes, node states, opcodes, tags**
- **Severity:** Low
- **Category:** Readability / Maintainability
- **File(s):** all schedulers (`2'b01/2'b10/2'b11`, status `32'd1/32'd2`), heap tags, UART register indices, CPU opcodes
- **Module(s):** system-wide
- **Description:** Node-state encoding (00=IDLE, 01=WAITING, 10=READY, 11=DONE) is used but never declared as constants; status register values are undocumented literals; object tags (0x01..0x0D) exist only in `memory-map.md`.
- **Why it matters:** Error-prone cross-referencing between docs, RTL, Python, and testbenches.
- **Suggested improvement:** `localparam`/enum for node states and status; a shared package (see M2/M8) including object tags.
- **Expected benefit:** Self-documenting code; fewer encoding mismatches.

---

**L3. `defparam` for PLL configuration**
- **Severity:** Low
- **Category:** RTL Quality / Gowin-Specific
- **File(s):** `rtl/top/lucid_top.sv` (lines 37–40)
- **Module(s):** `lucid_top`
- **Description:** `defparam` is deprecated (IEEE 1800) and fragile with hierarchical paths; combine with H14 (the values themselves are wrong for Gowin).
- **Why it matters:** Tool portability and maintainability.
- **Suggested improvement:** Pass parameters in the instantiation `rPLL #(...) pll_inst (...)` (with corrected Gowin parameters).
- **Expected benefit:** Cleaner, portable PLL configuration.

---

**L4. Reset synchronizer details**
- **Severity:** Low
- **Category:** Reset Strategy
- **File(s):** `rtl/top/lucid_top.sv` (line 56–57)
- **Module(s):** `lucid_top`
- **Description:** `reset_sync` shifts `btn_rst_n` and ANDs bits [2],[3] — functionally OK as a noise filter, but no `pll_lock` gating and no sim initialization (see H16). The button on the Tang Nano 20K also needs a debounce consideration (hypothesis: the 4-FF filter at 27/100 MHz is too short for mechanical bounce; in practice CPU reset buttons usually rely on the RC + long press — flagging as informational).
- **Why it matters:** Bring-up robustness.
- **Suggested improvement:** See H16.
- **Expected benefit:** Reliable hardware reset.

---

**L5. Icarus "constant selects in always_* processes" sorry-warnings**
- **Severity:** Low
- **Category:** Verification (simulation semantics)
- **File(s):** ~35 sites (e.g., `rv32im_core.sv` lines 94–402, schedulers' read muxes, dispatcher)
- **Module(s):** several
- **Description:** Icarus 13 conservatively makes `always_comb` sensitive to all bits of referenced vectors for constant select expressions. This is a *simulator* limitation (already noted in KNOWN_ISSUES); semantics remain correct here because all blocks use full pre-assignment, but it can mask sensitivity-related simulation/synthesis divergence in future edits.
- **Why it matters:** Awareness for anyone adding `always_comb` logic.
- **Suggested improvement:** Prefer explicit `always @*` where convenient, or accept and document; keep Verilator lint as the semantic reference.
- **Expected benefit:** Fewer surprises across simulators.

---

**L6. No `default_nettype none` / no `timescale` in RTL files**
- **Severity:** Low
- **Category:** RTL Quality (hygiene)
- **File(s):** all `rtl/**/*.sv`
- **Module(s):** all
- **Description:** No `default_nettype none` (implicit-net typos would silently create wires — currently none found); no `` `timescale `` in RTL (only testbenches) — fine for synthesis but can cause sim unit mismatches if delays ever appear.
- **Why it matters:** Cheap insurance against a classic bug class.
- **Suggested improvement:** Add `` `default_nettype none `` (and `wire` at file end) per file, per coding-standards doc §3.2 which already lists `timescale / default_nettype` in the file template — the template isn't followed.
- **Expected benefit:** Implicit-net bugs become compile errors.

---

**L7. UART register map vs header comment (minor)**
- **Severity:** Low
- **Category:** Documentation
- **File(s):** `rtl/peripherals/uart.sv` (lines 5–12)
- **Module(s):** `uart`
- **Description:** Header documents `UART_RX_LEVEL` at 0x14; not implemented (read returns 0). The bigger doc mismatch with `memory-map.md` is covered in H17.
- **Why it matters:** Small but concrete doc bug.
- **Suggested improvement:** Implement RX level from the FIFO `count` (already available) or fix the comment.
- **Expected benefit:** Accurate register documentation.

---

**L8. Router single-word throughput ~1 word / 2 cycles per output**
- **Severity:** Low
- **Category:** Timing / Performance (informational)
- **File(s):** `rtl/messages/message_router.sv` (lines 128–136)
- **Module(s):** `message_router`
- **Description:** `in_ready = !busy[dest]`; after accepting a word, `busy` clears one cycle after `out_ready`, so back-to-back single-word messages see a bubble. Within a locked multi-word message it sustains 1 word/cycle. Acceptable at current traffic; worth noting for future high-rate units.
- **Why it matters:** Throughput planning.
- **Suggested improvement:** Allow acceptance when `busy && out_ready` (simultaneous drain+fill), i.e., `in_ready = !busy[dest] || out_ready[dest]`.
- **Expected benefit:** Full-rate streaming.

---

**L9. `heap_used`/`heap_avail` semantics and duplicated heap variants**
- **Severity:** Low
- **Category:** Readability / Maintainability
- **File(s):** `rtl/heap/heap_controller.sv`, `rtl/heap/heap_controller_gc.sv`
- **Module(s):** both heap controllers
- **Description:** `heap_used = free_ptr` includes the 256-byte header; two heap controller variants duplicate the allocator with divergent header layouts (5 vs 6 words) — only `_gc` is exercised in tb_gc, only base in tb_heap.
- **Why it matters:** Metric clarity; duplicate maintenance.
- **Suggested improvement:** Report `free_ptr - HEADER_SIZE` as used; converge to one parameterized controller (GC_ENABLE).
- **Expected benefit:** One heap controller; truthful metrics.

---

**L10. Fixed-priority arbitration starvation**
- **Severity:** Low
- **Category:** Architecture (acknowledged)
- **File(s):** `rtl/messages/message_router.sv`
- **Module(s):** `message_router`
- **Description:** Input 0 always wins; documented and on TODO as round-robin. No impact at current traffic levels.
- **Why it matters:** Future multi-unit fairness.
- **Suggested improvement:** Round-robin or LRU grant when traffic demands it (with a parameter).
- **Expected benefit:** Bounded latency for all modules.

---

### Informational

---

**I1. Verified module inventory and instantiation status**
- **Severity:** Informational
- **Category:** Architecture / Project organization
- **Description:** Instantiated in testbenches: `graph_scheduler` (2 TBs), `message_dispatcher` (2), `heap_controller`, `heap_controller_gc`, `graph_scheduler_fp`, `graph_scheduler_parallel`, `primitive_exec`, `fifo`, `uart`+`rv32im_core`+`wishbone_bus`+`boot_rom`+`mgmt_ram` (via tb_platform). **Instantiated nowhere (no TB, no top): `gc_controller`, `closure_unit`, `environment_unit`, `graph_memory`, `lucid_top`, `gowin_pll`.** Empty directories: `firmware/`, `examples/`, `benchmarks/`, `ci/`, `ir/`, `verification/`, `rtl/fpu/` (the Makefile lint target globs the empty `rtl/fpu/`).

---

**I2. Single clock domain (positive for CDC)**
- **Severity:** Informational
- **Category:** Clocking
- **Description:** The entire design runs in one clock domain (`clk`); the only true asynchronous inputs are `uart_rx` (unsynchronized — see H4) and `btn_rst_n` (synchronized in `lucid_top`). No gated clocks; no derived clocks other than the planned PLL. CDC exposure is minimal once `uart_rx` is synchronized.

---

**I3. Inferred latches / combinational loops: none found**
- **Severity:** Informational
- **Category:** RTL Quality
- **Description:** All `always_comb` blocks use full pre-assignment before case statements; no latch inference detected (Verilator lint clean on LATCH). No combinational loops identified. The multiple-driver structures (H1) are process-level conflicts, not loops.

---

**I4. Boot/test flow dependency on hierarchical references**
- **Severity:** Informational
- **Category:** Verification
- **Description:** Testbenches verify via backdoor probes (`sched.node_result[4]`, `heap.mem[64]`, `uart_inst.tx_busy`, `cpu.regfile[1]`). Acceptable for unit TBs, but architectural-interface checks (H15) are additionally needed; note `lucid_top`'s elaboration failure (C2) stems from the same habit in RTL (`cpu.status`).

---

**I5. Empty placeholder directories and vacuous targets**
- **Severity:** Informational
- **Category:** Project organization
- **Description:** `make sim-verilator` echoes only; `make verify` iterates an empty dir; CMake broken (H18); `verification/`, `benchmarks/`, `examples/`, `ci/`, `ir/` empty despite README layout. Suggest either populating or trimming the documented layout.

---

## Architectural Recommendations

1. **Fix the data model before adding features.** The three deepest issues are data-model gaps, not local bugs: operand ordering is lost at the compiler→hardware boundary (C5), dependency masks are narrower than the node space (H2), and the message protocol truncates operands/results (H3). Define the graph ABI (node word layout, per-slot input mapping, dep record format) in `lucid-ir-spec.md`, then make compiler, RTL, and testbenches follow it. The reserved 6th node word (`INPUTS`) already anticipates the fix for C5.
2. **One scheduler, parameterized.** Consolidate the three scheduler variants into a single module with `DISPATCH_MODE ∈ {INLINE, MESSAGE}` and `ISSUE_WIDTH` parameters (M2). The divergence between variants is already producing inconsistent bug sets (parallel's 11-entry encoder, fp's missing op2).
3. **Single-process-per-state discipline.** Adopt "one variable, one writer" as a coding standard (H1); it eliminates the race class behind C9 and the MULTIDRIVEN/conflicting-driver synthesis failures.
4. **Complete or quarantine stubs.** GC, closure unit, environment unit, `graph_memory` are dead/stub silicon presented as complete phases (C8, H10, H11, H12). Either implement them against their design docs or mark them clearly as non-functional and exclude them from synthesis and "phase complete" claims.
5. **Define the FIFO/message read-latency contract once.** Choose FWFT or registered-read for `fifo` and propagate the convention to all consumers (C7, M3). Document multi-word sender obligations (no bubbles) in `message-protocol.md` or harden the router (H7).
6. **Bus fabric roadmap.** Add a default/error slave (H5), then map the documented regions (FPU control, scheduler, heap, GC, message) as CSR slaves so the management CPU can drive the FPU without backdoor probes (H15, M11). Consider a SystemVerilog `interface` for Wishbone (the coding standard already mandates interfaces; none exist).
7. **Reset & clock architecture for hardware.** Async-assert/sync-deassert with `pll_lock` qualification, reduced reset fanout (H16), correct Gowin rPLL parameters, real pin constraints, and an SDC that matches the netlist (H14) — prerequisites for any Tang Nano 20K bring-up.
8. **Honest status tracking.** Align `roadmap.md`/`ARCHITECTURE.md`/commit messages with reproducible CI artifacts (sim, lint, synth logs) rather than prose claims (H17, H18).

---

## Timing Optimization Opportunities

1. **Replace combinational dividers with one iterative multi-cycle divider per domain** (H13): CPU (multi-cycle M-extension with stall), primitive unit, and scheduler. Largest single timing win; also saves ≈3–6 kLUT.
2. **Multi-cycle or DSP-mapped multiplication:** ensure 32×32 multiplies map to Gowin DSP blocks (verify with Yosys-Gowin; guide with attributes if needed); consider 2-cycle multiply in the CPU to ease the EXEC-stage path.
3. **Register the Wishbone read-data mux / region decode** if STA shows the return path critical (M9) — costs one wait-state, simplifies the worst CPU path.
4. **Cut reset fanout** on node arrays (reset only control state — H16): large fanout async-reset networks are a classic Gowin timing drag.
5. **Pipeline the scheduler update stage:** `S_UPD_SCAN`/`S_UPD_NEXT` is a 2-cycle-per-dependent serial walk; a priority-encode + single-cycle update (or per-slot write enables) shortens graph execution latency at no timing cost (correctness fix C5 should be designed together with this).
6. **Router fill-drain overlap** (L8) for full-rate message streaming.
7. **Then measure:** there is currently **no completed STA** — finish the synth flow and get a nextpnr-gowin/Gowin-STA report before optimizing further (baseline first).

---

## Resource Optimization Opportunities

1. **Move graph node storage to BSRAM** (H12): the per-field FF arrays cost ~15 kFF per scheduler (≈70 % of the device's FF budget) for 64 nodes; a 6-cycle sequential BRAM node store costs ~12 kbit of the 828 kbit BSRAM budget and scales to 256+ nodes. This is the single biggest resource win.
2. **Share arithmetic:** one divider (H13), one multiplier variant (C3's shared 64-bit product path) in the CPU.
3. **Heap metadata in registers, objects in BSRAM** (H9): removes the second write port so the heap infers BSRAM; 16 KB heap = ~15 Gowin 9K-blocks.
4. **Delete dead logic:** dispatcher route table/counters/status (H8), mark stack if GC stays unimplemented (C8), `gc_saved_free`, unused UART counters (L1), unused `mul_full` (if C3 is fixed by using it, it stops being dead).
5. **One scheduler instead of three** (M2): rough estimate — removing two duplicate scheduler bodies saves several kLUT/FF.
6. **Gowin-specific:** use BSRAM byte-enables for `wb_sel` (C10 — free on this architecture); check that small FIFOs (8×8) map to distributed SSRAM rather than blocks; keep the 64×32 mark stack as distributed RAM if retained.
7. **Queue sizing:** after C6, size the ready queue `NUM_NODES`-deep but only `$clog2(NUM_NODES)`-bit entries (small distributed RAM) — cheap insurance.

---

## Maintainability Improvements

1. **Restore the regression gate first** (C1, H18): compiling sims, failing-loud testbenches, meaningful lint, CI that blocks red builds. Everything else depends on this.
2. **Introduce `lucid_pkg`** (package) for opcodes, node states, status codes, message types, object tags (M2, M8, L2); generate the Python side from the same source to prevent frontend/RTL drift.
3. **Reconcile docs with RTL** at the interface level: message header format, UART register map, node word layout, heap header (H17). Consider generating register-map docs from RTL comments or vice versa.
4. **Remove or implement dead code** (L1, H8, H12) — every stub should carry a `// STUB:` marker and be excluded from synthesis lists.
5. **Per-testbench file lists** in the Makefile (C1) so unit tests compile only their dependencies.
6. **Follow the project's own coding standards** (assertions, interfaces, `default_nettype none`, file headers with protocol/clock/reset — L6): the standards document is good; compliance is partial.
7. **Unify the two heap controllers** (L9) and align their header layout with `memory-map.md`.

---

## Verification Improvements

1. **Make failure loud** (H18): pass/fail counters + `$fatal(1)`/`$finish(1)`; Makefile propagates nonzero status; CI fails. Currently `tb_parallel` proves green-CI-with-red-tests is possible.
2. **Fix elaboration coverage** (C1): every testbench must at least compile in CI on every commit.
3. **Directed tests for the verified bugs** (once fixed): non-commutative ops with out-of-order completion (C5 — the `(- (* 4 5) 3)` case used in this review), >16-root graphs (C6), >32-node graphs (H2), MULH/MULHSU/MULHU vectors (C3), sub-word load/store across all alignments (C4/C10), held-`alloc_valid` (H9), UART RX byte stream through the Wishbone read path (C7).
4. **UART loopback test with realistic baud timing**, including phase sweeps of `rx` relative to `baud_tick` and back-to-back frames (H4).
5. **Router multi-word tests with bubbles** and interleaved traffic (H7); currently `tb_primitive_exec` bypasses the router entirely (direct connect), so the EXEC_PRIM path is untested through the fabric.
6. **A real `gc_controller` testbench** (C8): root+chain marking, sweep reclaim, mark-bit clearing, second GC run, OOM→GC→resume integration.
7. **ISA compliance smoke:** run a subset of `riscv-arch-test` (rv32im) against the core — would have caught C3/C4 immediately.
8. **Assertions (SVA)** per the coding standard: FIFO no-overflow/no-underflow, router lock stability mid-message, scheduler invariants (`rdyinp ≤ numinp`, `done_cnt ≤ node_cnt`, queue never overflows), Wishbone ack-within-N-cycles.
9. **Formal/liveness checks** (cheap with Yosys+SBY): prove the scheduler always reaches S_DONE for legal graphs (rules out the H2 livelock class) and that the router never drops a locked message.
10. **Randomized graph testing:** generate random DAGs from the Python frontend, execute, compare against a Python reference model — the `gen_scheme_test.py` bridge already exists to build on.
11. **Gate merges on CI** including lint (real, full-tree), sim, and a completing `make synth` with archived logs (H14, H17).

---

## Prioritized Action Plan

1. **Restore elaboration:** fix `mgmt_ram`/`bram` `HEX_FILE` mismatch (C1); fix `lucid_top` `cpu.status` reference and dangling `s3_*` (C2). Verify: all 10 testbenches compile; `lucid_top` elaborates in Verilator and Yosys.
2. **Make the gate mean something:** testbench pass/fail exit codes, Makefile failure propagation, real full-tree lint, CI blocking (H18). Re-run everything; record the true baseline (expect `tb_parallel` red).
3. **Fix the graph ABI and operand ordering** (C5) together with dep-mask widening (H2) and queue overflow handling (C6) — one coordinated scheduler change, then consolidate the three scheduler variants (M2, H1).
4. **Fix the CPU correctness bugs:** MULH family (C3), load alignment (C4), byte enables in `bram`/`mgmt_ram` (C10); run rv32im smoke vectors.
5. **Fix the UART:** RX synchronizer + per-RX mid-bit timer (H4), FWFT/registered-read contract (C7, M3), TX FIFO race, sticky status bits.
6. **Decide GC scope** (C8): implement mark-push/sweep-clear/free-ptr-restore + integration trigger and a real testbench, or quarantine and document as non-functional.
7. **Fix the message fabric:** bubble-hardened router + parameterized arbiter (H7), full-width EXEC_PRIM/PRIM_RESULT (H3), dispatcher dead-feature resolution (H8).
8. **Heap/closure/environment:** allocator handshake + alignment + single-write-port BSRAM (H9), registered request type (H10), closure payload write path + counter widths (H11).
9. **Hardware build chain:** correct Gowin rPLL parameters (H14), `.cst` pin constraints, rewritten SDC, reset/lock gating (H16), complete `make synth` + STA baseline (M9).
10. **Scheduler register readback** (H15) and bus default/error slave (H5) so firmware can see results and bad accesses fail visibly.
11. **Hygiene sweep:** dead-code removal (L1), packages (M8/L2), `unique case` defaults (M4), blocking-in-`always_ff` cleanup (M5), doc/RTL reconciliation (H17), `default_nettype none` (L6).
12. **Longer-term verification:** SVA assertions, riscv-arch-test subset, randomized graph vs Python reference, formal liveness on scheduler/router (Verification Improvements §8–11).

---

## Positive Observations

1. **Documentation culture is exceptional** for an early-stage project: architecture guide, per-phase design docs, ADRs, coding standards, memory map, known-issues, TODO. The docs enabled this review to find doc/RTL drift precisely.
2. **`fifo.sv` is textbook-clean**: extra-bit pointers, correct full/empty, count, overflow protection — and its testbench is thorough (5 real scenarios including interleaved and rejected-write cases).
3. **`wishbone_bus.sv` is admirably simple** and works: assign-only decode/mux, mutually exclusive one-hot region selects; the 1-cycle BRAM ack protocol of `boot_rom`/`mgmt_ram` is consistent and correctly consumed by the CPU's fetch/load FSM.
4. **The message-router concept is sound**: registered per-output holding registers with multi-word lock is a reasonable micro-architecture for a lightweight fabric (the hazards in H7 are implementation edges, not a flawed concept).
5. **Honest self-tracking:** `KNOWN_ISSUES.md` correctly flags the parallel scheduler bug, Icarus/Yosys limitations, the single-cycle M-extension timing risk, and missing firmware before this review did.
6. **Testbenches are self-checking with golden values and hierarchical probes** (e.g., `tb_heap` verifies header words in memory; `tb_graph_scheduler` checks intermediate results) — the *intent* of the verification is right; only failure propagation is missing.
7. **The compiler→testbench bridge (`tools/gen_scheme_test.py`) and end-to-end Scheme tests** show the full stack working conceptually; `tb_scheme` covering `(+)`, `(*)`, `if`, and `<` through the actual scheduler is a strong integration pattern to build on.
8. **Consistent style and partitioning:** naming follows the coding standard, modules are small and single-purpose, parameters are used in most places, and every module carries a purpose/protocol header comment.
9. **Good defensive details spotted:** FIFO write-while-full rejection, UART framing-error state that waits for line idle, divide-by-zero guards on all divider inputs (returning a defined value rather than X), and `x0` write protection in the CPU register file.
10. **The overall heterogeneous two-processor concept with a documented graph ABI is a solid, well-reasoned architecture** (ADRs 001–003 are clear); the issues found are implementation-phase defects, not conceptual flaws — the project is very much worth the remediation effort above.

---

*End of review. All findings were derived from the repository state at commit `f700ae6`; items marked "verified" were reproduced by compiling/running the project's own flows or scratch testbenches outside the repository. No repository files were modified.*
