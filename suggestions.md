# FPGA Code Review

**Project:** Lucid — Open Hardware Functional Processing Unit (FPU)
**Target:** Sipeed Tang Nano 20K (Gowin GW2AR-18; 20,736 LUT4, ~15.5K FFs, 828 Kbit BSRAM, 32 × 18×18 DSP)
**Reviewer role:** Principal FPGA Architect / Senior Digital Design Engineer
**Review type:** Static architectural and code review (analysis only — no source files were modified)
**Commit reviewed:** `89c5d3b` ("Fix address overlap bug in scheduler register interface")
**Method:** Full read of all 23 RTL files, all 10 Icarus testbenches, constraints, build scripts, CI, and documentation. Findings were cross-checked empirically by running the project's own flows (`make sim-icarus`, `make lint`, `make synth`) and by compiling/running targeted scratch testbenches and synthesis scripts **outside** the repository (under `/tmp`; no repo files were changed). Every finding marked **Verified** was reproduced with a tool; findings marked **Analysis** are code-inspection conclusions (high confidence); findings marked **Hypothesis** are uncertain and explicitly flagged as such.

**Note on prior review:** `old_suggestions.md` documents an earlier review whose C1–C10 fixes were applied in commits `81d7025`/`89c5d3b`. This review re-verified those fixes (most are real and correct — see Positive Observations) and focused on the current state. Several fixed areas have *regressed again*; details below.

---

## Executive Summary

Lucid remains an ambitious, unusually well-documented project: a heterogeneous RV32IM management CPU plus a message-passing, graph-executing Functional Processing Unit. The documentation discipline (ADRs, per-phase design docs, memory map, known-issues file) is excellent, the coding style is consistent and readable, and several leaf modules (FIFO, Wishbone bus, reset synchronizer) are clean and correct. The phase-3 graph scheduler genuinely works — its testbench passes, including dependency chains.

However, at the reviewed commit the project is in a **non-building, non-verifying, non-fitting state**:

- **The entire Icarus regression fails to elaborate.** One illegal expression (`|err_count` on an unpacked array in `message_dispatcher.sv:87`) is compiled into every testbench by the Makefile, so **0 of 10** testbenches even build. The commit that introduced it claims "9/10 testbenches passing". `make lint` is also red (same error + 100 warnings), and CI runs both gates on every push. **(Verified)**
- **Phase-4 message dispatch is functionally broken.** `graph_scheduler_fp` and `primitive_exec` implement two different PRIM_RESULT formats; results are written to the wrong node. All 3 checks in `tb_primitive_exec` fail. **(Verified)**
- **The design cannot fit the target FPGA.** Synthesizing `graph_scheduler` *alone* (Yosys, ABC LUT4) yields **19,738 LUTs + 10,627 FFs** — ≈95% of the LUTs and ≈68% of the FFs of the entire GW2AR-18 — before adding CPU, UART, heap, GC, or message fabric. Node state is stored in ~20K flip-flops instead of BRAM. **(Verified)**
- **The UART RX register path is off by one byte.** Every read of the RX data register returns the *previous* byte; the first read returns `0x00`. `implementation_report.md` declares this fixed ("C7") — the fix is incorrect. **(Verified)**
- **The scheduler register interface can only reach 10 of the 64 nodes** (8-bit address window ÷ 6 words/node); nodes ≥ 10 are silently dropped or alias onto control registers. **(Analysis)**
- **Timing closure at 100+ MHz is not credible** with single-cycle combinational 32-bit dividers and 33×33 multipliers in up to four modules. The CPU alone maps to ~45K gate-level cells pre-ABC. **(Verified)**

**Strengths**

- Outstanding documentation set; honest stub annotations (e.g., `gc_controller` header).
- Consistent style: `` `default_nettype none`` everywhere, `always_ff`/`always_comb` discipline, snake_case, generate-based priority encoders.
- Correct FIFO (extra-bit pointer full/empty), assign-only Wishbone bus (clean, workable), proper async-assert/sync-deassert reset synchronizer qualified with PLL lock, 2-FF UART RX synchronizer.
- Prior-review fixes verified as genuinely applied: top level now elaborates (Icarus + Verilator), MULH family is a proper 64-bit implementation, load lane-alignment present, source-based operand ordering in the base scheduler, queue-overflow flag, scheduler register-overlap fix, hierarchical probe removed from `lucid_top`.
- Testbenches are self-checking with `fail_count` and exit codes (a real improvement since the prior review).

**Weaknesses**

- Verification gate is broken *again* (second time in project history), and commit messages/docs assert "all pass" while the suite is red — the process problem is recurring, not incidental.
- Three near-identical 300-line schedulers with copy-paste drift; three mutually inconsistent versions of the EXEC_PRIM/PRIM_RESULT protocol (doc vs. exec vs. scheduler).
- Entire FPU (scheduler, heap, GC, message fabric, primitive unit) is **not instantiated anywhere** — `lucid_top` contains only the management platform.
- Resource model (FF-based node/heap storage) is one to two orders of magnitude over the target device budget; synthesis flow neither covers the FPU nor currently runs at all.
- SDC constraints reference non-existent ports/pins and declare the PLL clock asynchronous to its own source.

**Estimated code quality:** Low–Medium. Good style; several verified functional bugs in mission-critical paths.
**Estimated maintainability:** Medium. Excellent docs but heavy triplication, dead modules, and significant doc/RTL drift.
**Estimated synthesis quality:** Low. Flow is broken (Yosys parse error), partially masked by the Makefile, and covers none of the FPU; latch inference present in all schedulers.
**Estimated timing quality:** At risk / unknown. No completed STA; known-impossible combinational divider/multiplier paths at 100–108 MHz.

---

## Findings

### Critical

---

#### C1. Entire simulation regression fails to elaborate; lint and CI are red

- **Severity:** Critical
- **Category:** Verification / RTL Quality / Maintainability
- **File(s):** `rtl/messages/message_dispatcher.sv` (line 87), `Makefile` (`sim-icarus` target), `.github/workflows/ci.yml`
- **Module(s):** `message_dispatcher`
- **Description:** `assign status = {24'h0, |r_out_valid, |r_in_valid, |err_count, 1'b0};` applies a reduction OR to `err_count`, which is an **unpacked array** (`logic [31:0] err_count [NUM_MODULES]`) — illegal in SystemVerilog. Icarus: `error: Array err_count needs an array index here` (elaboration failure). Verilator: `%Error: Expected numeric type, but got a 'logic[31:0]$[0:3]' data type`. Because `make sim-icarus` compiles **all** of `rtl/**/*.sv` into *every* testbench, this one line kills all 10 testbenches: **0/10 elaborate**. `make lint` fails with the same error (exit 2, plus 100 warnings). Both are CI gates (`ci.yml` runs `make lint` and `make sim-icarus` on every push/PR), so CI is red at HEAD. The bug was introduced in commit `81d7025`, whose message states "Status: 9/10 testbenches passing". **(Verified: ran `make sim-icarus`, `make lint`, and git archaeology.)**
- **Why it matters:** The project currently has *no* working verification loop. Every functional claim in `docs/SESSION_STATE.md` ("Passing Tests 10/10", "Failing Tests: None") is false at HEAD. This is the second time a commit message has asserted green tests over a red suite (see prior review C1) — the pattern indicates gates are not actually run before commit. Until this is fixed, all other bugs below accumulate unchecked.
- **Suggested improvement:** Make `err_count` a scalar (or reduce with an explicit loop/generate-for reduction). Independently: give each testbench its own minimal file list (`.f` files or per-target variables) so one broken module cannot take down the whole suite. Treat CI red as a stop-the-line event; never record test status in a commit message without pasting the gate output.
- **Expected benefit:** Restores the regression loop; prevents silent whole-suite outages; makes commit-message claims verifiable.

---

#### C2. `graph_scheduler_fp` ↔ `primitive_exec` PRIM_RESULT protocol mismatch — Phase 4 dispatch non-functional

- **Severity:** Critical
- **Category:** RTL Quality (correctness) / Architecture
- **File(s):** `rtl/scheduler/graph_scheduler_fp.sv` (lines 227–239), `rtl/primitives/primitive_exec.sv` (lines 109–132), `docs/architecture/primitive-exec-design.md` (§3.2)
- **Module(s):** `graph_scheduler_fp`, `primitive_exec`
- **Description:** Three mutually inconsistent definitions of PRIM_RESULT exist:
  - **Doc:** 2 words — header, then `{node_id[7:0], result[23:0]}` (LAST).
  - **`primitive_exec` ("H3" extended):** 3 words — header, `{node_id, 24'h0}`, then full 32-bit `result` (LAST).
  - **`graph_scheduler_fp`:** ignores the middle word(s), and on the LAST word does `tmp_res_nid = msg_rx_data[NODE_ID_W-1+24:24]` (= bits `[29:24]` of the **result word**) and `node_result[tmp_res_nid] <= msg_rx_data`.
  Net effect: the result is written to node `result[29:24]` (e.g., node 0 for any result < 2²⁴), never to the executing node; `node_state`/`upd_dep_mask` are taken from that wrong node, which then re-triggers spurious readiness updates. **Verified: all 3 checks in `tb_primitive_exec` fail** (`FAIL: tb_primitive_exec (3 failures)`) when the tb is compiled with only its real dependencies. Even against the *documented* 2-word format the scheduler would be wrong (`[29:24]` ≠ documented `node_id` at `[31:24]`).
- **Why it matters:** The message-based execution path — the architectural centerpiece that justifies the router/dispatcher — cannot execute a single ADD correctly. `docs/ARCHITECTURE.md` advertises `tb_primitive_exec` as passing ("3 operations").
- **Suggested improvement:** Pick **one** wire format (recommend the doc's compact `{node_id, result}` in a single data word, or keep 3 words and have the scheduler latch `node_id` from word 1). Encode the format once in `lucid_msg_pkg` (field indices as `localparam`s), reference it from both modules, and add a protocol assertion (SVA or tb check) that `node_id` echoed equals `node_id` sent. Update `primitive-exec-design.md` to match.
- **Expected benefit:** A working Phase-4 dispatch path; a single source of truth preventing future three-way drift.

---

#### C3. Node state stored in flip-flops — schedulers cannot fit the Tang Nano 20K

- **Severity:** Critical
- **Category:** Resource Optimization / Architecture / Synthesis
- **File(s):** `rtl/scheduler/graph_scheduler.sv` (lines 28–43), `rtl/scheduler/graph_scheduler_fp.sv` (lines 39–51), `rtl/scheduler/graph_scheduler_parallel.sv` (lines 25–37), `rtl/scheduler/graph_memory.sv`
- **Module(s):** all three schedulers
- **Description:** Each scheduler stores 64 nodes × ~280–306 bits of per-node state (state, opcode, counts, flags, imm0/1, result, 64-bit dep mask, 2–3 operands, src IDs) in **register arrays with asynchronous reset**, plus queue and control state. Measured with Yosys (`synth -flatten; abc -lut 4`, after patching only the latch from F8 in a scratch copy): **`graph_scheduler` alone = 19,738 `$lut` + 10,627 DFF cells (30,365 cells total)**. The GW2AR-18 offers 20,736 LUT4 / ~15,552 FF, so *one scheduler instance* consumes ≈95% of the device's LUTs and ≈68% of its FFs — before the CPU (~1.2K FF + heavy comb), UART, heap, GC, and message fabric. The design as architected does not fit the reference hardware. `ARCHITECTURE.md`'s "~500 cells, 2–4 BRAMs" estimate predates FPU inclusion; `graph_memory.sv` (the intended BRAM store) is instantiated nowhere and is itself not BRAM-inferable (see F17). **(Verified: Yosys run, log retained.)**
- **Why it matters:** "All RTL must realistically fit this FPGA" (README) is currently impossible by ~2–4× even ignoring the rest of the system. FF arrays also prevent BRAM inference, burn global reset routing, and inflate the bitstream.
- **Suggested improvement:** Move node storage to BRAM. Practical structure for GW2AR: store each node as a 192-bit word across **6 parallel 9K BRAM blocks** (32-bit lanes), read a whole node per cycle into a register file slice; or sequentially read 6 words/node into a small FF cache for the 1–2 nodes being processed. Keep only hot FSM state (queue pointers, exec_id, dep-scan mask) in FFs. Remove the async-reset loop over node arrays (see F9). This should drop scheduler storage from ~19K LUT/FF-equivalent bits to ~2 BRAMs + a few hundred FFs.
- **Expected benefit:** FPU fits the device with >80% margin; enables real hardware bring-up; large routing/fanout relief.

---

#### C4. UART RX data register returns the previous byte (off-by-one) — "fixed" but still broken

- **Severity:** Critical
- **Category:** RTL Quality (correctness) / Verification
- **File(s):** `rtl/peripherals/uart.sv` (lines 72–88), `implementation_report.md` (claims "C7 fixed")
- **Module(s):** `uart`
- **Description:** The RX data read (register `3'h4`) uses a 2-cycle response: cycle N pops the FIFO (`rx_fifo_rd`) and sets `rx_read_pending`; cycle N+1 asserts `wb_ack = rx_read_pending` **and** schedules `rx_read_data_r <= rx_fifo_data` at the *end* of N+1. During N+1, `wb_dat_r = {24'h0, rx_read_data_r}` still holds the **stale** value, and that is exactly when the master samples it. Result: every read returns the *previous* byte; the first read after reset returns `0x00`. **Verified empirically** with a scratch testbench sending 20 distinct bytes: readback was `{prev}` for all 20 (0x31 read as 0x00, 0x32 read as 0x31, …). The "C7" fix in `implementation_report.md` ("registered ack … data returned in cycle 1") describes the intent, but the ack fires one cycle too early. No RX-path test exists in the repo (`tb_platform` ties `rx` to 1 and only checks `tx_busy`), so the regression is invisible to the suite.
- **Why it matters:** Host↔FPU communication (REPL, program download, debug) is byte-shifted and corrupt on real hardware. This is precisely the class of bug the broken gate (C1) is supposed to catch.
- **Suggested improvement:** Either ack one cycle later (3-cycle read: pop → capture → ack), or drive `wb_dat_r` from `rx_fifo_data` directly when `rx_read_pending` is set (combinational forward). Add a testbench that writes ≥2 distinct bytes into the RX FIFO (or drives the RX pin) and checks readback order and values.
- **Expected benefit:** Correct byte stream; a regression test that locks the fix in.

---

#### C5. Single-cycle combinational 32-bit divide/modulo (and 33×33 multiply) — timing closure impossible at target frequency

- **Severity:** Critical
- **Category:** Timing / Resource Optimization / Synthesis
- **File(s):** `rtl/cpu/rv32im_core.sv` (lines 326–357, 186–200), `rtl/scheduler/graph_scheduler.sv` (lines 197–199), `rtl/scheduler/graph_scheduler_parallel.sv` (lines 194–195, 240–241), `rtl/primitives/primitive_exec.sv` (lines 41–44)
- **Module(s):** `rv32im_core`, `graph_scheduler`, `graph_scheduler_parallel`, `primitive_exec`
- **Description:** `/` and `%` on 32-bit operands appear in **four** modules (CPU: DIV/DIVU/REM/REMU; schedulers: opcodes 0x13/0x14; primitive unit: 0x13/0x14), each inferring separate signed/unsigned combinational divider+remainder networks — no sharing, no pipelining. Additionally the CPU instantiates three always-on 33×33→64 multipliers (`mulh_*`) plus an inline signed 33×33 for MUL, and each scheduler/primitive has its own 32×32 multiply. Measured: `rv32im_core` alone maps to **45,642 gate-level cells pre-ABC** (Yosys `synth -noabc`), and a full ABC pass did not finish within 5 minutes; typical small RV32I cores are ~1–2K LUTs. On a GW2AR speed-grade, a single-cycle 32-bit `/${%}` network (logic depth ≫30 levels) cannot close at 100–108 MHz; `KNOWN_ISSUES.md` rates this "Medium Confidence … may limit timing" — that understates it: it is a timing-closure blocker and an area disaster.
- **Why it matters:** Even after C3 is fixed, STA will fail; the M-extension/divide path dominates both area and worst-case path in every execution module.
- **Suggested improvement:** Implement one **multi-cycle iterative divider** (32-cycle shift/subtract, or radix-4 for 16 cycles) per consumer, with a done/valid handshake into the existing FSMs (they are already multi-state — DIV/REM can stall in EXEC). Share quotient/remainder from one engine (DIV=quotient, REM=remainder). Map multiplies to Gowin DSPs: split 32×32 into 18×18 segments with registered pipeline (2–3 cycles) or let the synthesizer infer `MULT36X36` by registering inputs/outputs. If the management firmware can avoid division entirely, consider RV32I + trap-emulated M as an interim.
- **Expected benefit:** Worst-case path drops by an order of magnitude; CPU area likely −60–80%; realistic path to 100 MHz closure; frees DSPs for FPU arithmetic.

---

### High

---

#### H1. Scheduler register interface can only address 10 of 64 nodes; nodes ≥10 silently dropped or aliased

- **Severity:** High
- **Category:** RTL Quality (correctness) / Architecture
- **File(s):** `rtl/scheduler/graph_scheduler.sv` (lines 121–139, 285–287), `graph_scheduler_fp.sv` (lines 121–138), `graph_scheduler_parallel.sv` (lines 141–158)
- **Module(s):** all three schedulers
- **Description:** Node field access uses `tmp_nid = (reg_adr[7:2] - 6'd8) / 6` with only `reg_adr[7:0]` examined. `reg_adr[7:2]` maxes at 63 → `tmp_nid` maxes at **9**. Writes with `reg_adr ≥ 0x20 + 10×24 = 0x110` either (a) fall into the `< 0x20` control window when `reg_adr[7:0] < 0x20` (e.g. node 10 field 0 at 0x110 → `reg_adr[7:0]=0x10` → silently dropped), or (b) alias onto low nodes (e.g. 0x118 → `tmp_nid=0` → overwrites node 0). So `NUM_NODES=64` storage exists, but only nodes 0–9 are loadable; all current testbenches use ≤9 nodes, hiding the cap. Reads have the same defect. Division/modulo by constant 6 in both read and write paths also instantiates two constant dividers per scheduler (see L2). **(Analysis — arithmetic is unambiguous; coverage gap verified by inspection of all tbs.)**
- **Why it matters:** Real compiled graphs larger than 10 nodes cannot be loaded — the documented practical limit is ~512 nodes; the RTL limit is 10. This blocks the architecture's purpose and is invisible to the current suite.
- **Suggested improvement:** Decode on a wider window (e.g. `reg_adr[15:0]`) and replace `/6`,`%6` with a comparison-free map: `node_sel = reg_adr[?]`, `field_sel = reg_adr[4:2]` with nodes at 32-byte (8-word) stride — the 2 unused words/node are cheaper than two dividers. Add a ≥16-node graph test.
- **Expected benefit:** Full node range usable; removes constant dividers; test coverage for realistic graphs.

---

#### H2. Message router routes payload words by their top data byte — multi-word messages misroute or stall

- **Severity:** High
- **Category:** RTL Quality (correctness) / Architecture
- **File(s):** `rtl/messages/message_router.sv` (lines 21–27, 71–94, 112–118)
- **Module(s):** `message_router`
- **Description:** `in_dest[ii]` is *continuously* extracted from the current input word's `[31:24]` and used both for `in_ready` computation and for the locked-connection transfer condition `conn[o][i] && in_valid[i] && in_dest[i] == o`. After the header word, subsequent words are **payload** — their `[31:24]` is data, not a destination. Consequences for a multi-word message: (a) if a payload word's top byte ≠ the locked output, the word is never consumed while `lock` holds → stream stalls (potential deadlock); (b) `in_ready[ii]` is computed from the payload's top byte, so the sender may see "ready" because the payload *happens* to name a free output — the word is then accepted into the **wrong output stream** (cross-talk); (c) out-of-range payload top bytes (≥ `NUM_OUTPUTS`) make `in_ready=1` → payload silently discarded. The failure is masked today because `tb_message_system` only sends single-word messages (and doesn't compile — C1/H8), `tb_primitive_exec` bypasses the router entirely (direct wiring), and the only multi-word producer/consumer pair is itself broken (C2). **(Analysis, high confidence — logic is direct; masking verified by tb inspection.)**
- **Why it matters:** The message fabric — the architectural backbone — cannot reliably carry the 4-word EXEC_PRIM / 3-word PRIM_RESULT traffic it was designed for. Any payload with top byte ≠ destination ID corrupts routing.
- **Suggested improvement:** Capture `dest` once (at the header/first word) into the connection state, and make transfer decisions for locked words depend only on `conn`, `in_valid`, and `out_ready` — never on per-word data. `in_ready` for a locked input must be `out_ready[conn]` regardless of data. Add a multi-word test with payload top bytes deliberately ≠ dest (e.g. 0xDEADBEEF) routed through the dispatcher.
- **Expected benefit:** Data-independent, deadlock-free streaming; the fabric becomes trustworthy for all message types.

---

#### H3. `graph_scheduler_parallel`: queue pointer/count desync and stale `upd_cur` — additional root causes of the documented failure

- **Severity:** High
- **Category:** RTL Quality (correctness) / FSM Design
- **File(s):** `rtl/scheduler/graph_scheduler_parallel.sv` (lines 66–97, 208–219, 258–288, 201)
- **Module(s):** `graph_scheduler_parallel`
- **Description:** `KNOWN_ISSUES.md` documents "chained computations return 0" and attributes it to `backup_valid`/UPDATE interaction. Inspection reveals two further, more fundamental defects:
  1. **Dual-pop pointer desync:** in the queue process, both `if (pop_q …)` and `if (pop_q2 …)` execute `q_rptr <= q_rptr + 1'b1;` — two nonblocking assignments from the same old value → net effect **q_rptr advances by 1**, while the count logic (correctly) subtracts **2** for a dual pop. Pointer and count immediately disagree; entries are re-read/lost and `q_empty`/`q_full` become meaningless. The pointer-bump guard (`q_cnt > 1 || (push_q && !q_full)`) also differs from the count-adjust guard (`q_cnt > 1`), compounding the desync.
  2. **Same-cycle use of freshly-assigned `upd_cur`:** `S_UPD` computes `upd_cur <= b[…]` (nonblocking) in the priority-encoder loop and *in the same state* uses `upd_cur` for operand routing (`node_src0[upd_cur] == upd_src`, `node_rdyinp[upd_cur] + 1 …`) — i.e., it uses the **previous** dependent's index (0 on first pass). The base scheduler avoids this by splitting scan/update into two states (S_UPD_SCAN/S_UPD_NEXT); the parallel merge broke the pipeline. This is a plausible true root cause of the documented "wrong node" symptom.
  3. **Dead IF opcode:** `8'h30: node_result <= op0 != 0 ? op1 : op1;` — both branches identical (and there is no `op2` in this module), so IF is meaningless here.
  Verified: `tb_parallel` fails 2 tests at HEAD.
- **Why it matters:** Phase-7 parallelism is not merely "medium confidence" buggy — the queue integrity itself is broken, so even independent-node runs are one dual-pop away from corruption.
- **Suggested improvement:** Either repair (single combined pointer adjust `q_rptr <= q_rptr + pop_q + pop_q2` with one consistent guard; split S_UPD into SCAN/UPDATE states; implement or remove IF) or formally deprecate the module (exclude from lint/sim/CI until redesigned). Given C3, a redesign around BRAM storage should subsume this module rather than patching it.
- **Expected benefit:** Honest module status; a correct foundation for dual-issue when reimplemented.

---

#### H4. SDC constraints are invalid for the actual design

- **Severity:** High
- **Category:** Timing / Synthesis / Clocking
- **File(s):** `scripts/lucid.sdc`, `rtl/top/lucid_top.sv` (lines 14–36), `rtl/peripherals/gowin_pll.sv`
- **Module(s):** `lucid_top`, `rPLL`
- **Description:** Multiple mismatches: (a) `create_clock … [get_ports clk]` — no such port (it is `clk_27m`); (b) `create_generated_clock … [get_pins pll_inst/CLKOUT]` — the blackbox pin is `clkout` (lowercase), and `-divide_by 27 -multiply_by 100` does not describe the rPLL's actual math; (c) `set_clock_groups -asynchronous` between `sys_clk` and `pll_100m` — these are the *same physical domain* (the PLL is the only system clock), so cross-paths the design relies on would go unanalyzed; (d) everything is constrained at 100 MHz, but the instantiated rPLL parameters yield **108 MHz** per `gowin_pll.sv`'s own comment (`IDIV=2, FBDIV=40, ODIV=5 → VCO=540, OUT=108`); (e) UART input/output delays reference the non-existent `sys_clk`. **(Analysis — direct file comparison.)**
- **Why it matters:** STA with this file is at best a no-op (unmatched objects) and at worst blesses the wrong clock relationships/frequency. Hardware timing sign-off currently has no valid basis.
- **Suggested improvement:** Constrain the real 27 MHz input port; reference the generated clock on `pll_inst/clkout` (or the internal `clk` net); delete the false clock group; pick the actual frequency (fix PLL params for true 100 MHz — e.g. the file's own `IDIV=3, FBDIV=44, ODIV=4 → 99 MHz` alternative — and constrain *that*); reference UART delays to the PLL clock.
- **Expected benefit:** Meaningful STA; correct frequency budget for UART divisor and timing closure work (C5).

---

#### H5. Synthesis flow is broken and structurally blind to the FPU

- **Severity:** High
- **Category:** Synthesis / Maintainability / Verification
- **File(s):** `rtl/peripherals/bram.sv` (line 6), `scripts/syn_lucid.tcl`, `Makefile` (`synth` target), `docs/KNOWN_ISSUES.md`
- **Module(s):** `bram`
- **Description:** (a) `bram.sv` still declares `parameter string HEX_FILE = ""` — Yosys 0.67 aborts with a **syntax error** at line 6, killing `make synth` before any synthesis. `KNOWN_ISSUES.md` and `SESSION_STATE.md` both state string parameters *were removed* from `bram.sv` — they were not (doc drift). **(Verified: `yosys -c scripts/syn_lucid.tcl` aborts.)** (b) The Makefile masks this: `yosys … | tee log || echo "(Yosys not available)"` — the pipeline's exit status is `tee`'s (0), so failures are invisible. (c) `dfflibmap -liberty /dev/null` is a placeholder that cannot map FFs; generic `synth` + `abc -lut 4` is used instead of Yosys's `synth_gowin` (which knows BSRAM/DSP/rPLL). (d) The file list covers only the management platform — no scheduler/heap/GC/message module is ever synthesized, which is exactly why C3's resource blowup went unnoticed.
- **Why it matters:** No synthesis results exist for the design as a whole; the flow fails silently; documented workarounds are untrue; vendor features (BRAM/DSP inference) are not exercised.
- **Suggested improvement:** Replace the string parameter with a plain parameter plus `` `ifdef SIMULATION`` `$readmemh`, or a plusarg-driven init in the tb only. Make the Makefile fail on yosys error (`set -o pipefail` or check `${PIPESTATUS}`). Migrate to `synth_gowin -top lucid_top` (or `synth` + `gowin_*` mapping passes) and add a second script that synthesizes **each FPU module standalone** with `stat` archived in CI so resource regressions are caught.
- **Expected benefit:** A synthesis gate that runs, fails loudly, and watches the modules most likely to explode.

---

#### H6. Inferred latches in all three scheduler read paths

- **Severity:** High
- **Category:** RTL Quality / Synthesis
- **File(s):** `rtl/scheduler/graph_scheduler.sv` (lines 274–303), `graph_scheduler_fp.sv` (lines 288–315), `graph_scheduler_parallel.sv` (lines 299–327)
- **Module(s):** all three schedulers
- **Description:** `tmp_rnid`/`tmp_rfid` are assigned only inside `if (reg_adr[7:0] >= 8'h20)` in the combinational readback block — no assignment on other paths → **inferred latches**. **Verified: Yosys `proc_dlatch` errors `Latch inferred for signal 'tmp_rnid'`.** The same pattern (module-level `int` temporaries with incomplete assignment) exists for `tmp_found` inside the clocked FSM (becomes an FF — harmless but fragile) and `tmp_nid`/`tmp_fid` in the write path (clocked, OK).
- **Why it matters:** Latches on an FPGA are timing and glitch hazards, are flagged as errors by Yosys (blocking `synth` on these modules), and violate the project's own coding standards.
- **Suggested improvement:** Initialize `tmp_rnid`/`tmp_rfid` (and all temporaries) with defaults at the top of each `always_comb` block; better, make them `logic` locals computed via continuous assign functions of `reg_adr`.
- **Expected benefit:** Latch-free synthesis; unblocks Yosys on the FPU modules (prerequisite to H5's standalone synthesis).

---

#### H7. 64-bit dependency mask written from a 32-bit register write (out-of-range select)

- **Severity:** High
- **Category:** RTL Quality (correctness) / Architecture
- **File(s):** `rtl/scheduler/graph_scheduler.sv` (line 130), `graph_scheduler_fp.sv` (line 130), `graph_scheduler_parallel.sv` (line 150)
- **Module(s):** all three schedulers
- **Description:** `node_dep` is `DEP_W = NUM_NODES = 64` bits wide, but field 4 is loaded with `node_dep[tmp_nid] <= reg_dat_w[DEP_W-1:0];` — a `[63:0]` select of a 32-bit bus value. Verilator flags **SELRANGE** ("Selection index out of range: 63:0 outside 31:0") on all three files. In Icarus the upper 32 bits become `x`; in synthesis they tie to 0. Either way, dependents above node 31 cannot be expressed, contradicting `NUM_NODES=64` (and the doc's "up to 32", which at least should be enforced, not accidental). **(Verified: lint output; Analysis for sim/synth behavior.)**
- **Why it matters:** Combined with H1, the effective graph size ceiling is min(10 addressable, 32 maskable, 64 stored) = **10 nodes**, and the mechanisms fail silently.
- **Suggested improvement:** Either parameterize `DEP_W=32` explicitly and document/enforce the 32-node limit, or split the dep mask write into two words (fields 4 and 6). Add a test with dependents above node 31 if 64-node support is intended.
- **Expected benefit:** Explicit, tested graph-size limits; no x-propagation surprises.

---

#### H8. `tb_message_system` fails to compile even with C1 fixed — package not imported

- **Severity:** High (test infrastructure)
- **Category:** Verification / RTL Quality
- **File(s):** `simulation/icarus/tb_message_system.sv` (lines 78–99)
- **Module(s):** `tb_message_system`
- **Description:** The tb references `MSG_NOP`, `MSG_ALLOC`, `MSG_EXEC_PRIM`, `get_dest()`, `get_src()`, `get_type()` with **no `import lucid_msg_pkg::*;`** and no scope resolution → 14 Icarus errors (`No function named 'get_dest' found`, `Unable to bind wire/reg/memory 'MSG_ALLOC'`). **(Verified.)** Additionally, the Makefile's `lint` target passes `message_types.sv` twice (explicitly + via `find`), producing a Verilator MODDUP duplicate-package warning.
- **Why it matters:** Even after C1, the message-system test is dead; the router therefore has *zero* working system-level tests (see H2).
- **Suggested improvement:** Add `import lucid_msg_pkg::*;` (and ensure the package is compiled first in the tb file list); drop the duplicate package from the lint command.
- **Expected benefit:** Restores the only router/dispatcher integration test.

---

#### H9. FPU is not integrated into `lucid_top` — the Tang Nano 20K image contains no FPU

- **Severity:** High
- **Category:** Architecture
- **File(s):** `rtl/top/lucid_top.sv`, `docs/ARCHITECTURE.md` (block diagram), `docs/architecture/memory-map.md` (§3.5)
- **Module(s):** `lucid_top`
- **Description:** The top instantiates only CPU + boot ROM + mgmt RAM + UART. No scheduler, heap, GC, message dispatcher/router, or primitive unit is instantiated **anywhere** in `rtl/` (verified by grep — every FPU module is referenced only from testbenches). None of the documented FPU register windows (0x00100000–0x001004FF), graph memory (0x00200000), or heap (0x00300000) exists on the bus; the bus has only 3 slaves and its 16-bit region decode has no FPU regions.
- **Why it matters:** The deliverable for the reference hardware is currently the management platform alone; the architecture's raison d'être (graph execution) exists only in simulation. This is expected at early phases, but the roadmap/README mark phases 3–8 complete and Phase 9 as "board bring-up ready," which overstates reality.
- **Suggested improvement:** Add an FPU subsystem wrapper instantiating scheduler (post-C3 redesign), heap, GC, dispatcher; hang it off the Wishbone matrix with the documented decodes; reflect actual integration status in README/roadmap (e.g., "FPU: simulation only").
- **Expected benefit:** An honest, incrementally verifiable path to a bitstream that contains the FPU.

---

### Medium

---

#### M1. UART RX sampling phase is arbitrary; the mid-bit timer is dead logic

- **Severity:** Medium
- **Category:** Clocking / RTL Quality / Timing
- **File(s):** `rtl/peripherals/uart.sv` (lines 213–290)
- **Module(s):** `uart`
- **Description:** The comment claims "dedicated bit timer and mid-bit sampling," and `rx_tick_cnt` is loaded with `baud_div>>1` at start-bit detect and reloaded per bit — but **no logic ever reads `rx_tick_cnt`**; it just decrements. Actual sampling happens on the free-running `baud_tick` (shared with TX), whose phase relative to the start edge is uniform over the bit period. Sampling can therefore land anywhere in the bit, including near edges. **Verified empirically:** 20 ideal-waveform phase offsets all received correctly under zero clock mismatch (so the UART *works* in the ideal case), but the noise margin is roughly halved versus mid-bit sampling; combined with H4's 108 MHz PLL (≈8% baud error at the default divisor 868), marginal links will fail. The dead counter also wastes power/area.
- **Why it matters:** UART robustness against real-world baud mismatch is compromised; the dead logic misrepresents the design (comment vs. code).
- **Suggested improvement:** Use the dedicated RX timer as intended: on start detect, count `baud_div/2` to the first sample, then `baud_div` per subsequent bit (i.e., drive sampling from `rx_tick_cnt == 0`, not `baud_tick`). Delete or implement the timer.
- **Expected benefit:** True mid-bit sampling (max tolerance to clock error); honest RTL.

---

#### M2. Heap testbench vs RTL allocation-alignment mismatch (tb_heap fails 4 tests)

- **Severity:** Medium
- **Category:** Verification / RTL Quality
- **File(s):** `rtl/heap/heap_controller.sv` (line 29), `simulation/icarus/tb_heap.sv` (lines 45–72), `docs/architecture/memory-map.md` (HEAP_ALIGNMENT, default 4)
- **Module(s):** `heap_controller`
- **Description:** RTL aligns with `(alloc_size + 15) & ~15` — **16-byte** roundup — while the comment says "round up to 4 bytes" and the memory map documents alignment default 4. The tb expects unaligned sizes (`SIZE=8` stored as 0x01000008, next alloc at +8). **Verified: `tb_heap` fails 4 tests.** Either the RTL (16B) or the tb/docs (4B/exact) is stale.
- **Why it matters:** Another red test hidden by C1; the object-size field semantics (stored aligned vs. requested size) affect GC stride and heap accounting.
- **Suggested improvement:** Decide the alignment (16 bytes is reasonable for GC/object headers), store the **requested** size in the header (GC needs logical size), update tb expectations and docs accordingly.
- **Expected benefit:** Green heap test; unambiguous object format.

---

#### M3. `tb_platform` cannot run to completion (path conflict + Icarus hang on load/store)

- **Severity:** Medium
- **Category:** Verification / Synthesis (simulator compatibility)
- **File(s):** `simulation/icarus/tb_platform.sv` (line 127), `simulation/icarus/boot_rom.hex`, `rtl/peripherals/bram.sv` (line 24), `rtl/cpu/rv32im_core.sv`
- **Module(s):** `tb_platform`, `rv32im_core`
- **Description:** Three layered problems: (a) `$readmemh("boot_rom.hex", …)` resolves relative to CWD (the hex lives in `simulation/icarus/`), while `$dumpfile("build/sim/tb_platform.vcd")` resolves relative to the repo root — no single working directory satisfies both; from the root the ROM is empty (all 9 checks fail), from `simulation/icarus/` the VCD open is **fatal** in Icarus 13 (immediate exit 1). **(Verified.)** (b) With both paths satisfied in a scratch dir, the Icarus sim **hangs (sim-time freeze) at the first load/store instruction** — a zero-delay re-evaluation pathology of Icarus's over-broad `always_comb` sensitivity (the project documents this Icarus limitation in KNOWN_ISSUES). **Verified:** identical CPU + memory model finishes correctly under Verilator (store committed, no combinational loop reported by Verilator lint), so this is an Icarus tool issue, not an RTL loop. (c) There is no Makefile rule to regenerate `boot_rom.hex`.
- **Why it matters:** The only integration test of the platform — the one piece that *is* in the top level — is unusable, so CPU/bus/UART regressions (like C4) ship silently.
- **Suggested improvement:** Pass the hex path via plusarg/`$value$plusargs` or locate it with a `BOOT_HEX` define; make VCD paths CWD-independent (e.g. always write into CWD and let the Makefile redirect). Move `tb_platform` to the Verilator harness (CMake path) or restructure CPU comb blocks per the project's Icarus workarounds. Add a hex-generation rule (even a checked-in Python one-liner) so the ROM image is reproducible.
- **Expected benefit:** A runnable platform integration test in CI.

---

#### M4. Dead and duplicated logic in `rv32im_core`

- **Severity:** Medium
- **Category:** Resource Optimization / RTL Quality / Readability
- **File(s):** `rtl/cpu/rv32im_core.sv` (lines 186–200, 53, 19–23, 328)
- **Module(s):** `rv32im_core`
- **Description:** **Verified by Verilator lint:** `mul_ss`, `mul_su`, `mul_uu` are **never used** — three 33×33→64 multipliers of dead code (mul_ss ≡ mul_su, and mul_uu ≡ mulh_uu, exact duplicates); `is_load` assigned but never read; `STATE_LOAD` unreachable (FSM is really 2-state); MUL uses a signed 33×33 multiply where a plain 32×32 (low word is sign-agnostic) suffices; WIDTHTRUNC warnings on the MUL assignment; ~89 width warnings across the repo (e.g. `uart.sv:67 {27'h0, rx_fifo_count}` pads a 4-bit count to 31 bits).
- **Why it matters:** Dead multipliers cost DSP/LUT budget until trimmed, mislead reviewers, and indicate unfinished refactors; lint noise (100 warnings) hides real warnings — which is partly why C1 went unnoticed.
- **Suggested improvement:** Delete `mul_ss/su/uu`, `is_load`, `STATE_LOAD`; simplify MUL to `alu_a * alu_b` (low 32 bits); drive lint to zero-warning baseline (waive deliberately, fix the rest).
- **Expected benefit:** Cleaner timing/area, meaningful lint gate.

---

#### M5. Reset strategy: full arrays under asynchronous reset — fanout, BRAM-inference, and routing costs

- **Severity:** Medium
- **Category:** Reset Strategy / Resource Optimization / Synthesis
- **File(s):** all three schedulers (reset loops over node arrays), `rtl/cpu/rv32im_core.sv` (line 230, regfile reset), `rtl/heap/heap_controller.sv` (lines 37–41), `rtl/heap/heap_controller_gc.sv` (lines 51–54)
- **Module(s):** schedulers, `rv32im_core`, heap controllers
- **Description:** Every node field array (~20K FF), the 32-entry regfile (1024 FF), and heap header locations `mem[0..4]` are written in the async-reset branch. Consequences: (a) enormous reset fanout; (b) a memory array written in the reset branch **cannot infer BRAM** — heap "BRAM" becomes FFs/LUT RAM (16 KB heap → ~128K FF-equivalent if ever elaborated standalone); (c) unnecessary on SRAM-based FPGAs where FFs power up to 0 and GSR handles initialization (Gowin supports this). The CPU regfile doesn't need reset either (x0 is enforced by the read mux).
- **Why it matters:** Compounds C3; makes the heap structurally unfit for hardware; increases reset-tree skew.
- **Suggested improvement:** Remove array resets (rely on FPGA power-up state + explicit valid bits); keep reset only on control FSM/pointers; move heap header fields (`mem[0..4]`) into a handful of FF registers separate from the object BRAM; qualify header initialization as runtime writes, not reset.
- **Expected benefit:** BRAM-inferable memories, lower fanout, smaller/faster reset tree.

---

#### M6. `heap_controller` memory is write-only — the entire heap array synthesizes to nothing

- **Severity:** Medium
- **Category:** Architecture / Synthesis
- **File(s):** `rtl/heap/heap_controller.sv`
- **Module(s):** `heap_controller`
- **Description:** The 4096-word `mem` array has an alloc write port but **no read port at all**; synthesis trims it entirely. The module is functionally a bump-pointer with a header-write side effect (trimmed). This is presumably a phase artifact, but it is not marked as a stub like `gc_controller` is.
- **Why it matters:** Any integration assuming object payload storage will silently get nothing; the "heap" currently stores only headers (and even those are trimmed).
- **Suggested improvement:** Either annotate as a stub (module header + docs), or add the read port required by GC/closures now (dual-port BRAM: alloc write / GC read-write fits Gowin SDP).
- **Expected benefit:** Honest status; a heap that actually stores objects.

---

#### M7. `heap_controller_gc`: GC can never return memory to the allocator; unbounded GC address port

- **Severity:** Medium
- **Category:** Architecture / RTL Quality
- **File(s):** `rtl/heap/heap_controller_gc.sv` (lines 59–63, 75–93), `rtl/gc/gc_controller.sv` (line 34)
- **Module(s):** `heap_controller_gc`, `gc_controller`
- **Description:** (a) `free_ptr` only ever increases; the GC's `updated_free_ptr` output is not connected back into the heap (no input exists), so after a GC completes the allocator still sees a full heap → every subsequent alloc OOMs → auto-retriggers GC → livelock. (b) `gc_mem_addr` indexes `mem` directly with no bounds check (out-of-range = sim error/synth truncation). (c) `HEAP_SIZE` defaults differ (4096 here vs 16384 in `heap_controller` vs 64 KB in the memory map). Also GC reads (`gc_mem_rdata`) are registered (1-cycle) — fine — but see M8 for the consumer's latency bug.
- **Why it matters:** The GC integration cannot actually reclaim space — the feature is structurally incomplete, not just buggy.
- **Suggested improvement:** Add a `new_free_ptr` write channel (or a `gc_adjust` pulse + value) honored when `gc_done`; bounds-check `gc_mem_addr`; unify `HEAP_SIZE` defaults with the memory map.
- **Expected benefit:** A GC loop that can actually make forward progress.

---

#### M8. `gc_controller` stub internals: mark stack never written; sweep uses stale read data

- **Severity:** Medium
- **Category:** RTL Quality (acknowledged stub — recorded for completeness/priority)
- **File(s):** `rtl/gc/gc_controller.sv` (lines 48, 132–177)
- **Module(s):** `gc_controller`
- **Description:** The header honestly declares the module a stub. Two additional concrete defects worth recording: (a) `mark_stack` is **only ever read** (lines 143–144, 162–163) — there is no push/write anywhere, so pops return uninitialized data (the KNOWN_ISSUES "64-entry mark stack overflow" concern is moot: the stack is never even used); (b) `ST_SWEEP_SCAN` issues `mem_rd_en` and in the *same cycle* advances `scan_ptr` by `obj_size` — but `obj_size` comes from the heap's **registered** read data, i.e., the *previous* address's header (off-by-one stride through the heap). (c) `ST_MARK_ROOT` → `ST_MARK_STACK` similarly consumes `obj_flags` from `mem_rdata` one cycle before the requested data arrives.
- **Why it matters:** When the stub is reimplemented, these latency bugs are the kind that survive; recording them shortens that work.
- **Suggested improvement:** In the redesign, insert explicit wait states between read request and header consumption; actually implement push/pop or switch to a root-recursion-free algorithm (e.g. pointer-reversal or bitmap marking over the heap header region).
- **Expected benefit:** Fewer landmines in the GC rewrite.

---

#### M9. Closure and environment units allocate space but never write payload

- **Severity:** Medium
- **Category:** Architecture / RTL Quality
- **File(s):** `rtl/heap/closure_unit.sv` (lines 67–75), `rtl/heap/environment_unit.sv` (lines 88–92)
- **Module(s):** `closure_unit`, `environment_unit`
- **Description:** Neither module has a heap **write** port: `closure_unit`'s `ST_WRITE` merely counts `write_idx` (dead loop — nothing is written; `env_data` input unused); `environment_unit` never writes `binding_data` (unused) and its lookup is an immediate not-found stub. Objects therefore consist of a header with uninitialized payload. `implementation_report.md`/roadmap mark Phase 5 complete.
- **Why it matters:** Closures/environments are non-functional; status is overstated (unlike the GC, which is at least labeled).
- **Suggested improvement:** Add a heap write channel (shared with alloc through the heap controller, e.g. a `mem_wr` request port) and implement payload writes + real lookup walk; or mark both as stubs in module headers/README.
- **Expected benefit:** Honest phase status; functional closures when wired.

---

#### M10. Broadcast messages are silently discarded; broadcast machinery is dead

- **Severity:** Medium
- **Category:** Architecture / RTL Quality
- **File(s):** `rtl/messages/message_router.sv` (lines 115–116), `rtl/messages/message_types.sv` (lines 13, 27)
- **Module(s):** `message_router`, `lucid_msg_pkg`
- **Description:** `MODULE_BROADCAST = 8'hFF` and `FLAG_BROADCAST` exist, but any word with dest ≥ `NUM_OUTPUTS` gets `in_ready=1` and is routed nowhere — broadcast is implemented as *drop*. No err/drop counting occurs (`err_count` is a stub, and now also the cause of C1).
- **Why it matters:** A documented protocol feature does the opposite of its name; silent drops are the hardest class of fabric bug to debug.
- **Suggested improvement:** Implement broadcast replication in the router (per-output valid fanout with independent drain tracking) or remove the constants and document "broadcast unsupported"; count drops in `err_count`.
- **Expected benefit:** Protocol honesty; observability into fabric errors.

---

#### M11. UART register map disagrees with the memory-map document; sticky overrun; 16-bit divisor in a 32-bit register; baud default vs. actual clock

- **Severity:** Medium
- **Category:** Maintainability (doc drift) / RTL Quality / Timing
- **File(s):** `rtl/peripherals/uart.sv` (lines 46–70, 225, 273), `docs/architecture/memory-map.md` (§3.3)
- **Module(s):** `uart`
- **Description:** (a) Doc: STATUS@0x00, CTRL@0x04, BAUD@0x08, DATA@0x0C, RX_LEVEL@0x10, TX_LEVEL@0x14. RTL: ctrl@0x00, baud@0x04, status@0x08, TX FIFO write@0x0C, RX data@0x10, RX count@0x14 — nearly disjoint. (b) `rx_overrun` sets but has **no clear mechanism** short of reset. (c) `baud_div` is a 32-bit register but only `[15:0]` is used. (d) Default divisor 868 targets 100 MHz; the PLL actually yields 108 MHz (H4) → ~8% baud error → serial link failure on hardware (UART tolerance ≈ ±3%); in non-synthesis simulation the clock is 27 MHz → baud is 4× off (harmless for current tests only because they never check timing).
- **Why it matters:** Firmware written against the doc talks to the wrong registers; the hardware UART likely cannot talk to a terminal at all until divisor/PLL are reconciled.
- **Suggested improvement:** Align RTL to the documented map (or version the doc); add a write-1-to-clear for overrun; size `baud_div` honestly; compute the divisor from the real clock and store it as a `localparam` derived from a `CLK_FREQ_HZ` parameter.
- **Expected benefit:** Working host serial on the board; doc/RTL consistency.

---

#### M12. Wishbone bus: unused clock/reset/parameter; coarse 64 KB decode aliasing

- **Severity:** Medium (Low for aliasing)
- **Category:** RTL Quality / Readability
- **File(s):** `rtl/bus/wishbone_bus.sv`
- **Module(s):** `wishbone_bus`
- **Description:** `clk`, `reset_n`, and parameter `NUM_SLAVES` are unused (module is purely combinational, hardcoded to 3 slaves) — lint noise and misleading parameterization. Region decode on `m_adr[31:16]` aliases each slave across 64 KB (the documented 0x1000 boot-ROM "mirror" is a side effect, and e.g. 0x0000_F000+ hits the ROM). Also no `err` response — unmapped accesses return `0xFFFFFFFF` + ack (acceptable, but worth a deliberate note).
- **Why it matters:** Dead ports/parameters mislead integrators; coarse decode wastes address space and can mask firmware address bugs.
- **Suggested improvement:** Drop the unused ports/parameter (or use them for a registered slave-select); decode at region granularity actually needed (e.g. 4 KB/16 KB); document aliasing.
- **Expected benefit:** Honest interface; cleaner lint.

---

#### M13. Three near-identical schedulers (~250 lines each) with divergent copies

- **Severity:** Medium
- **Category:** Maintainability / Architecture
- **File(s):** `rtl/scheduler/graph_scheduler*.sv`
- **Module(s):** all three schedulers
- **Description:** Node arrays, register decode (including the /6 bug ×3, latch ×3, dep-width bug ×3), ready queue, scan/update FSM, and status logic are copy-pasted; the copies have already diverged (fp drops `src2`/imm opcodes and has different word-5 packing; parallel drops IF and has the queue bugs). Every fix must be applied three times — H1/H6/H7 exist ×3 precisely because of this.
- **Why it matters:** Triplicated bug surface; the parallel scheduler's root-causing (H3) was harder because of drift.
- **Suggested improvement:** One parameterized scheduler module (strategy bits: inline vs. message dispatch vs. multi-issue) or a shared `lucid_node_pkg` (struct + field indices + localparams) with a single register-file implementation; keep experiment variants in `rtl/experimental/` excluded from CI gates.
- **Expected benefit:** Single-point fixes; smaller review surface.

---

#### M14. Documentation/RTL drift is widespread and self-reinforcing

- **Severity:** Medium
- **Category:** Maintainability / Verification
- **File(s):** `docs/SESSION_STATE.md`, `docs/ARCHITECTURE.md`, `docs/KNOWN_ISSUES.md`, `implementation_report.md`, `docs/architecture/memory-map.md`, `docs/architecture/primitive-exec-design.md`
- **Module(s):** —
- **Description:** Verified false/stale claims at HEAD: "All 10 testbenches pass" (SESSION_STATE; reality 0/10 elaborate); ARCHITECTURE.md test table; "String parameters were removed from bram.sv" (KNOWN_ISSUES; they are present, H5); "C7 UART RX off-by-one fixed" (implementation_report; still broken, C4); heap "1024 entries" (KNOWN_ISSUES; now 4096/16384); heap header "8 bytes" (memory-map §4.2; table shows 4 bytes and RTL uses 4); env object "4+8N" (doc) vs `8+8N` (RTL); EXEC_PRIM "3-word" (doc/SESSION_STATE) vs 4-word (RTL); PRIM_RESULT "2-word" (doc) vs 3-word (RTL) vs wrong-word (scheduler); "Synthesis estimate ~500 cells" (ARCHITECTURE) vs measured (C3); graph node "5 words" (memory-map §5) vs 6 words (RTL + compiler).
- **Why it matters:** The docs are the project's greatest asset — and are now actively misleading new contributors and review processes (the "Suggested First Prompt" in SESSION_STATE tells the next session everything passes).
- **Suggested improvement:** After the Critical fixes land, do one doc-reality pass driven by gate outputs; add a CI "docs vs. reality" smoke (run the suites, fail if the claims table can't be regenerated); mark unimplemented subsystems explicitly in README's phase table.
- **Expected benefit:** Trustworthy docs; fewer blind alleys for contributors.

---

#### M15. Verification infrastructure gaps

- **Severity:** Medium
- **Category:** Verification
- **File(s):** `verification/` (empty), `Makefile` (`verify` target), `CMakeLists.txt`, `simulation/verilator/` (only `tb_fifo.cpp`; no CMakeLists in `simulation/`), `scripts/pre-commit.sh`, `Makefile` (`lint` target)
- **Module(s):** —
- **Description:** (a) `verification/` is empty → `make verify` is a no-op that prints success. (b) Top-level CMake does `add_subdirectory(simulation)` and `add_subdirectory(verification)` but neither has a `CMakeLists.txt` → **cmake configure fails** (verified). (c) `benchmarks/`, `examples/`, `firmware/` are empty directories advertised in the README layout. (d) The pre-commit hook runs `make lint`/`make sim-icarus` — both red, so either the hook is not installed or commits bypass it; commit messages claiming green statuses confirm non-enforcement. (e) The lint target lints `message_types.sv` twice (MODDUP) and uses `-Wall` with 100 warnings — no waiver/triage mechanism, so the gate is ignored rather than informative. (f) No SVA/assertions anywhere in RTL; no formal checks; no randomized/graph-vs-golden testing despite a perfect golden model existing (the Python compiler).
- **Why it matters:** Multiple "verification" entry points are theater; real gates that exist are red and therefore ignored — the root process cause of C1/C4 regressions.
- **Suggested improvement:** Fix or remove broken entry points (CMake subdirs, verify target); install/enforce the pre-commit hook in CI; add lint waivers and a zero-warning baseline; add the missing high-value tests (multi-word router, >10-node graphs, UART RX stream, riscv-arch-test for the CPU, SymbiYosys proofs for fifo/router handshakes); add a Python-golden random graph comparator for the scheduler.
- **Expected benefit:** Every advertised gate does real work; regressions surface at commit time.

---

### Low

---

#### L1. Dead control signals in schedulers

- **Severity:** Low
- **Category:** RTL Quality / Readability
- **File(s):** `graph_scheduler.sv`, `graph_scheduler_fp.sv` (`push_q`, `pop_q`, `push_q_id` — assigned, never read; queue manipulated directly)
- **Module(s):** schedulers
- **Description:** Leftover pulse signals from a pre-"single process" refactor. **(Verified: grep shows no readers.)** Remove or implement the intended queue-abstraction.

---

#### L2. Constant ÷6 / mod-6 address decode (×2 per scheduler)

- **Severity:** Low
- **Category:** Resource Optimization
- **File(s):** all three schedulers (write decode and read decode)
- **Module(s):** schedulers
- **Description:** Two small constant dividers per scheduler for the node map; subsumed by H1's suggested 8-word-stride map, which removes them entirely.

---

#### L3. RV32IM compliance gaps

- **Severity:** Low
- **Category:** RTL Quality / Architecture
- **File(s):** `rtl/cpu/rv32im_core.sv`
- **Module(s):** `rv32im_core`
- **Description:** `cycle`/`instret` are 32-bit only (no `cycleh`/`instreth`); ECALL/EBREAK/MRET not implemented (SYSTEM with funct3=0 writes 0 to rd instead of trapping); `mtvec/mepc/mcause` writable but traps are never taken; misaligned loads/stores neither handled nor trapped (LW unaligned silently returns the aligned word); DIV overflow (−2³¹/−1) relies on Verilog truncation semantics — happens to match the RV spec for DIV/REM but is untested (hypothesis: correct, needs an arch-test to confirm). Acceptable for a management core, but should be documented as intentional.
- **Suggested improvement:** Document the subset explicitly; run riscv-arch-test (RV32IM) in CI when the platform sim is revived (M3).

---

#### L4. Clock-frequency assumptions are inconsistent across the project

- **Severity:** Low (design-intent clarity; hardware impact covered by H4/M11)
- **Category:** Clocking / Maintainability
- **File(s):** `rtl/peripherals/gowin_pll.sv`, `rtl/top/lucid_top.sv`, `rtl/peripherals/uart.sv`, `scripts/lucid.sdc`, docs
- **Module(s):** `rPLL`, `uart`
- **Description:** Docs/SDC/divisor assume 100 MHz; PLL params yield 108 MHz; non-synthesis sims run at 27 MHz. Introduce a single `CLK_FREQ_HZ` parameter/localparam propagated to baud divisor and SDC comments, and fix the PLL config to actually hit it.

---

#### L5. FIFO parameter safety and feature gaps

- **Severity:** Low
- **Category:** RTL Quality
- **File(s):** `rtl/messages/fifo.sv`
- **Module(s):** `fifo`
- **Description:** Extra-bit pointer scheme requires `DEPTH` = power of two (used as 8 and 64 — fine today); no guard/error otherwise; no `almost_full`/`almost_empty`. Add a compile-time `initial` assertion `$fatal` if `DEPTH != 2**$clog2(DEPTH)`.

---

#### L6. Package/style nits (functional impact nil)

- **Severity:** Low
- **Category:** Readability / Synthesis hygiene
- **File(s):** `rtl/messages/message_types.sv`, `rtl/scheduler/graph_memory.sv`, `rtl/cpu/boot_rom.sv`
- **Module(s):** `lucid_msg_pkg`, `graph_memory`, `boot_rom`
- **Description:** Package items declared `parameter` (prefer `localparam`); filename ≠ package name (DECLFILENAME); `graph_memory` — unused module, `wb_sel` unused, and its 6-words-per-cycle access pattern can never infer BRAM (needs banking or serialization when adopted — see C3); `boot_rom` write-side ports tied off (harmless but noisy). Also several modules lack the header block required by coding-standards §3.1.

---

### Informational

---

#### I1. Icarus compatibility materially shapes the RTL

- **Severity:** Informational
- **Category:** Synthesis (simulator) / Maintainability
- **File(s):** repo-wide; `docs/KNOWN_ISSUES.md`, `docs/SESSION_STATE.md` ("Failed Experiments")
- **Description:** The design carries deliberate Icarus workarounds (module-level `int` temporaries, assign-only bus, no `unique case`, no automatics). This is a rational, documented trade — but M3 shows the CPU still hits an Icarus pathology on load/store, and some workarounds caused real bugs (H6 latch is a direct descendant of the module-level-temporary rule). Consider Verilator-primary for CPU/platform verification while keeping Icarus for unit tests.

---

#### I2. Reset synchronization is correctly implemented

- **Severity:** Informational (no action)
- **Category:** Reset Strategy / Clocking
- **File(s):** `rtl/top/lucid_top.sv` (lines 41–53)
- **Description:** Async-assert/sync-deassert 4-FF synchronizer qualified with PLL lock; UART RX has a dedicated 2-FF synchronizer. Single clock domain otherwise; no CDC issues beyond the UART pin. This is good practice — recorded as a positive control point for future clock-domain additions (SDRAM, etc.).

---

#### I3. Empty scaffold directories

- **Severity:** Informational
- **Category:** Maintainability
- **File(s):** `firmware/`, `benchmarks/`, `examples/`, `verification/`
- **Description:** Advertised in the README tree but empty. Either seed with minimal content (a README each stating status) or remove from the layout until populated; `firmware/` emptiness is already tracked in KNOWN_ISSUES.

---

## Architectural Recommendations

1. **Re-platform the FPU data plane around BRAM before any further feature work** (C3, F17/L6). Node storage as 192-bit words in 6 parallel 9K BRAMs (or serialized 6-word reads into an FF node cache) reduces scheduler storage by an order of magnitude and is the single highest-leverage change in the project. The same applies to heap storage (dual-port SDP: alloc write port, GC read/write port).
2. **One protocol, one source of truth.** Define EXEC_PRIM/PRIM_RESULT field layouts as `localparam` indices in `lucid_msg_pkg`; have scheduler, exec unit, docs, and Python tools all reference it (C2). Institute a rule: protocol changes land in the package + doc + both endpoints + a test, in one commit.
3. **Unify the schedulers** (M13): a single parameterized scheduler with a strategy knob, or at minimum a shared node-register-file module used by all variants. Retire `graph_scheduler_parallel` to `rtl/experimental/` until redesigned (H3).
4. **Integrate the FPU into `lucid_top` incrementally** (H9): first the scheduler behind the documented register window (0x00100100), with the Wishbone matrix extended to the FPU regions; add heap/GC/message fabric as they become real. This also gives the synthesis flow (H5) something meaningful to measure.
5. **Multi-cycle arithmetic policy** (C5): divide/modulo → shared iterative unit per consumer; multiply → registered DSP inference. Encode "no single-cycle 32-bit `/` or `%`" as a lint/code-review rule.
6. **Decide and enforce graph-size limits explicitly** (H1, H7): pick NUM_NODES=32 (matches 32-bit dep mask, halves BRAM) or implement wide-mask writes; either way, test at the limit.
7. **Reset philosophy** (M5): reset control state only; rely on FPGA power-up + valid bits for arrays; document the policy in coding-standards.

## Timing Optimization Opportunities

1. **Eliminate combinational dividers** (C5) — the dominant path in four modules. Multi-cycle division converts a >30-level path into a 1–2 LUT-level path per cycle.
2. **Pipeline multipliers into Gowin DSPs** — register multiplier inputs and outputs (or use `MULT` IP) so the tools infer DSP18/36 blocks instead of LUT fabric.
3. **Cut the cross-module combinational ready chain** — `message_router`: `out_ready` → `in_ready` → sender's next-word logic is a fabric-wide combinational path (H2 fix naturally registers connection state; additionally consider registering `in_ready` or accepting a 1-cycle turnaround per word).
4. **Scheduler update path** — `node_result → node_op[x] → ALU/compare → node_result` (with the dependency priority encoder) is the FPU critical loop after C5; the BRAM redesign (C3) lets you register node read data, splitting this path.
5. **Register Wishbone read-data muxes** — UART/dispatcher/scheduler readbacks are combinational muxes onto the bus; registering slave read data relaxes the CPU's EXEC-cycle path (and matches the 1-cycle ack already used by BRAM slaves).
6. **Fix the constraint basis** (H4) — none of the above is measurable until the SDC targets the real clock tree/frequency; after fixes, require `nextpnr-gowin` (or Gowin STA) reports in CI artifacts.

## Resource Optimization Opportunities

1. **BRAM for node storage** (C3): ~19.7K LUTs + 10.6K FFs → ~2–4 BRAMs + few hundred FFs. The largest single win.
2. **Remove dead multipliers** (M4): 3 unused 33×33 networks in the CPU; simplify MUL to 32×32 low-word.
3. **Share one divider per module** between DIV and MOD (quotient and remainder fall out of the same engine) — currently `/` and `%` infer separate networks (C5).
4. **Heap/heap_gc to true BRAM** (M5, M6): remove reset-branch writes; header fields to FFs; object space to SDP — saves ~128K FF-equivalent if ever elaborated and makes the heap real.
5. **Drop register resets on arrays** (M5): reduces reset fanout/routing and enables BRAM/distributed-RAM inference (regfile, node arrays, queue).
6. **Remove constant ÷6/mod-6 decoders** (L2/H1) via 8-word node stride.
7. **Delete dead logic** (M4, M1's `rx_tick_cnt`, L1 pulses, dispatcher `err_count` or implement it, `wishbone_bus` unused ports).
8. **Right-size `graph_memory`** when adopted (L6): banked 32-bit BRAMs rather than a 192-bit register array; if kept sequential, share it with the scheduler instead of duplicating node storage.

## Maintainability Improvements

1. **Fix the gates before the code** (C1, M15): per-testbench file lists; `pipefail` in Makefile; remove double-listed package from lint; zero-warning lint baseline with waivers; enforce the pre-commit hook in CI; CI green required for merge.
2. **Kill the triplication** (M13): one scheduler, shared node package; all opcode maps as `localparam`s shared with the Python compiler (single source — currently Python opcodes and RTL hex literals are maintained separately).
3. **Doc-reality pass** (M14): regenerate the test-status tables from CI output; correct KNOWN_ISSUES/SESSION_STATE/implementation_report; mark stub modules consistently in README (GC is the model: honest header comment).
4. **Repair or remove broken entry points** (M15): CMake subdirectories, `make verify`, empty scaffold dirs (I3).
5. **Magic numbers → named constants**: opcodes, message types, register offsets, node field indices — several files hardcode hex where the package already defines names (e.g. `8'h30`/`8'h31` in scheduler_fp/primitive_exec vs `MSG_EXEC_PRIM`).
6. **Module headers per coding-standards §3.1** (L6): several files lack the required block; enforce in review or a tiny lint script.

## Verification Improvements

1. **Restore the suite** (C1, H8, M2): err_count fix, package import, tb/RTL alignment reconciliation; then pin CI green.
2. **Add the tests that would have caught this cycle's bugs:**
   - UART RX multi-byte stream readback (catches C4) + external-waveform phase sweep (M1) + TX bit-width measurement.
   - Router multi-word messages with payload top-bytes ≠ destination (catches H2), including back-to-back messages and slow consumers.
   - Scheduler graphs with >10 nodes (catches H1) and dependents >31 (catches H7); a Python-golden random-graph comparator (the compiler already emits the writes — diff against RTL `node_result` readback).
   - PRIM_RESULT protocol conformance (catches C2).
   - CPU: riscv-arch-test RV32I(M) under Verilator; a load/store smoke test that currently hangs Icarus (M3).
3. **Assertions:** SVA (or SymbiYosys properties) for Wishbone classic rules (cyc ⊇ stb, ack only when cyc&stb), message handshake stability (valid&&!ready ⇒ data stable), FIFO no-overflow/no-underflow, scheduler queue integrity (`q_cnt` == pushes−pops).
4. **Synthesis-as-verification** (H5, C3): standalone `synth_gowin` per FPU module in CI with `stat` artifacts and a resource budget check (e.g. fail if any module > 25% of device LUTs).
5. **Hardware smoke:** once H4/M11 land, a loopback UART test on the Tang Nano 20K (already on the project's TODO).

## Prioritized Action Plan

1. **Restore the verification loop.** Fix `err_count` reduction (C1), `tb_message_system` package import (H8); add per-tb file lists so one module can't poison the suite; make CI green and enforce it. *(Everything else is unverifiable until this lands.)*
2. **Fix the UART RX off-by-one** (C4) and add a byte-stream readback test. This is a one-to-three-line RTL change with immediate hardware payoff.
3. **Unify and fix the EXEC_PRIM/PRIM_RESULT protocol** (C2) in package + doc + scheduler + exec; verify with `tb_primitive_exec` through the **router** (not direct wiring) including multi-word payloads (H2).
4. **Fix the router's connection-based routing** (H2) so payload words are never interpreted as destinations.
5. **Fix scheduler addressing** (H1: wide window, 8-word stride, remove ÷6) and the dep-mask width (H7: 32-bit cap or two-word write); add >10-node and >31-dependent tests.
6. **Replace combinational dividers with a multi-cycle unit and register the multipliers for DSP inference** (C5), in CPU and all execution modules; delete the CPU's dead multipliers (M4).
7. **Move node storage to BRAM** (C3) in the surviving unified scheduler; remove array resets (M5); re-measure with `synth_gowin` and record `stat` in CI.
8. **Repair or retire `graph_scheduler_parallel`** (H3) — at minimum quarantine it from gates; the queue pointer/count desync must be fixed in any redesign.
9. **Fix the clock/constraint basis** (H4, L4): correct SDC objects, resolve the 100 vs 108 MHz PLL question, recompute the UART divisor (M11).
10. **Unbreak the synthesis flow** (H5, H6): bram string parameter, latch fixes, Makefile `pipefail`, `synth_gowin`, per-module FPU synthesis in CI.
11. **Integrate the FPU into `lucid_top`** (H9) behind the documented register windows; update README/roadmap to reflect true status.
12. **Heap/GC honesty and structure** (M6–M9): either implement the read/free-ptr-restore/payload paths or label as stubs; reconcile HEAP_SIZE defaults with the memory map.
13. **Doc-reality pass** (M14) once the above lands; regenerate status tables from gate output.

## Positive Observations

Things that are genuinely well done and worth preserving:

1. **The documentation program is exceptional** for a project at this stage: ADRs with real alternatives/tradeoffs, per-phase design docs, a memory map, a known-issues file, and honest stub annotations (`gc_controller`'s header is the gold standard). The *process* of documenting before building is right; only the sync with reality needs repair.
2. **Prior-review findings were actually fixed and stick** — verified: `lucid_top` elaborates in Icarus and Verilator; the hierarchical `cpu.status` probe is gone; MULH/MULHSU/MULHU are proper 64-bit implementations; LB/LH/LBU/LHU lane alignment is implemented; source-based operand ordering fixed the subtraction-order bug in the base scheduler; queue overflow is now flagged; the register-overlap bug (0x40) is fixed.
3. **`fifo.sv`** — textbook extra-bit-pointer full/empty, registered read data, clean parameterization. Correct and reusable.
4. **`wishbone_bus.sv`** — simple, assign-only, combinational default-slave with ack for unmapped space; appropriate for a 1-master/3-slave platform and simulator-friendly.
5. **Reset architecture at the top level** — async-assert/sync-deassert synchronizer qualified with PLL lock, plus a 2-FF UART RX synchronizer; single-domain design keeps CDC risk near zero (I2).
6. **The base `graph_scheduler` works** — dependency chains (`(+ 2 (* 3 4))`) execute correctly in simulation (verified: `tb_graph_scheduler`, `tb_scheme`-style flows pass when compiled standalone), and its S_UPD_SCAN/S_UPD_NEXT split correctly avoids the same-cycle readback bug present in the parallel variant.
7. **Consistent RTL hygiene**: `` `default_nettype none`` … `wire` sandwich in every file, `always_ff`/`always_comb` separation, generate-loop priority encoders, named-state enums with `default:` recovery branches in FSMs.
8. **Self-checking testbenches** with `fail_count` and proper `$finish` exit codes (a marked improvement over the state recorded in the prior review).
9. **Build-system intent is good**: single Makefile entry point, environment checker, pre-commit hook, CI with lint+sim+docs jobs — the scaffolding is right even though it must now be enforced (M15).
10. **Design decisions are recorded with reasoning** (SESSION_STATE "Failed Experiments", "Things to Avoid") — this institutional memory is rare and valuable; it is why several bugs in this report could be root-caused quickly.

---

*End of review. All empirical claims were reproduced on macOS with Icarus 13.0, Verilator 5.050, and Yosys 0.67+post at commit `89c5d3b`; scratch artifacts lived outside the repository and no project files were modified.*
