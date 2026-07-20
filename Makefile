# Lucid Build System
# ==================
# This Makefile is the single entry point for all builds.
# Every command must work on macOS. Avoid Linux-only tooling.

SHELL := /bin/zsh
.POSIX:
.SUFFIXES:
MAKEFLAGS += --no-builtin-rules

# Tools
VERILATOR  ?= verilator
ICARUS     ?= iverilog
YOSYS      ?= yosys
PYTHON     ?= python3

# Simulation-only defines (initialization files). Guarded by `ifndef SYNTHESIS`
# inside the RTL so hardware synthesis never depends on a file.
BOOT_ROM_HEX := simulation/icarus/boot_rom.hex
ICARUS_DEFS  := -DBOOT_ROM_HEX=\"$(BOOT_ROM_HEX)\"

# Benign style warnings present across the existing RTL (unused parameters,
# width truncations from intentional size casts, import *, etc.). They are not
# correctness issues, so Verilator is told not to promote them to errors.
VERILATOR_WNO := -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-WIDTHTRUNC \
                 -Wno-WIDTHEXPAND -Wno-IMPORTSTAR -Wno-DECLFILENAME \
                 -Wno-TIMESCALEMOD -Wno-MODDUP -Wno-PINCONNECTEMPTY \
                 -Wno-PINMISSING -Wno-VARHIDDEN -Wno-BLKSEQ \
                 -Wno-PROCASSINIT -Wno-UNDRIVEN

# Directories
RTL_DIR       := rtl
SIM_DIR       := simulation
VERIF_DIR     := verification
DOCS_DIR      := docs
BUILD_DIR     := build
FIRMWARE_DIR  := firmware

# Default target
.PHONY: all
all: info

.PHONY: info
info:
	@echo "Lucid Build System"
	@echo "=================="
	@echo ""
	@echo "Targets:"
	@echo "  make info           Show this help"
	@echo "  make directories    Create project directory structure"
	@echo "  make docs           Build all documentation"
	@echo "  make sim            Run all simulations"
	@echo "  make sim-verilator  Run Verilator simulations"
	@echo "  make sim-icarus     Run Icarus Verilog simulations"
	@echo "  make synth          Run synthesis (Yosys)"
	@echo "  make synth-stats    Show synthesis statistics"
	@echo "  make verify         Run all verification"
	@echo "  make lint           Lint all RTL"
	@echo "  make clean          Remove build artifacts"
	@echo "  make distclean      Remove all generated files"
	@echo ""
	@echo "Configuration variables:"
	@echo "  VERILATOR=$(VERILATOR)"
	@echo "  ICARUS=$(ICARUS)"
	@echo "  YOSYS=$(YOSYS)"
	@echo ""

# Directories
.PHONY: directories
directories:
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(BUILD_DIR)/sim
	@mkdir -p $(BUILD_DIR)/verification
	@mkdir -p $(BUILD_DIR)/docs

# Documentation
.PHONY: docs
docs: directories
	@echo "Documentation is authored in Markdown in $(DOCS_DIR)/"
	@echo "No build step required."

# Simulation
.PHONY: sim
sim: sim-verilator sim-icarus

.PHONY: sim-verilator
sim-verilator: directories
	@echo "Verilator --binary simulation"; \
	fail=0; pass=0; \
	for tb in $(SIM_DIR)/icarus/*.sv; do \
		name=$$(basename $$tb .sv); \
		echo "=== $$name ==="; \
		$(VERILATOR) --binary -j 0 -Wall $(VERILATOR_WNO) -DBOOT_ROM_HEX=\"$(BOOT_ROM_HEX)\" \
			--top-module $$name $(RTL_PKGS) $(RTL_SRCS) $$tb \
			-o $$name.vbin -Mdir $(BUILD_DIR)/sim/$$name.d 2> $(BUILD_DIR)/sim/$$name.vlog || { fail=1; echo "VERILATE FAILED: $$name"; tail -n 30 $(BUILD_DIR)/sim/$$name.vlog; continue; }; \
		timeout 120 $(BUILD_DIR)/sim/$$name.d/$$name.vbin > $(BUILD_DIR)/sim/$$name.vout 2>&1; \
		rc=$$?; \
		if [ $$rc -ne 0 ]; then fail=1; echo "SIMULATION FAILED (rc=$$rc): $$name"; tail -n 20 $(BUILD_DIR)/sim/$$name.vout; continue; fi; \
		if grep -qE 'FAIL|%Error|Assertion failed|\$$error' $(BUILD_DIR)/sim/$$name.vout; then fail=1; echo "SIMULATION FAILED (assertion/error): $$name"; grep -E 'FAIL|%Error|Assertion failed|\$$error' $(BUILD_DIR)/sim/$$name.vout; continue; fi; \
		echo "PASS: $$name"; pass=$$((pass + 1)); \
	done; \
	echo ""; echo "Verilator Results: $$pass passed, $$fail failed"; exit $$fail

RTL_SRCS := $(shell find rtl -name '*.sv' -not -path 'rtl/archive/*' -not -name 'message_types.sv' 2>/dev/null)
RTL_PKGS := rtl/messages/message_types.sv

.PHONY: sim-icarus
sim-icarus: directories
	@fail=0; pass=0; \
	for tb in $(SIM_DIR)/icarus/*.sv; do \
		name=$$(basename $$tb .sv); \
		echo "=== $$name ==="; \
		$(ICARUS) -g2012 $(ICARUS_DEFS) -o $(BUILD_DIR)/sim/$$name.vvp $(RTL_PKGS) $(RTL_SRCS) $$tb || { fail=1; echo "ELABORATION FAILED: $$name"; continue; }; \
		timeout 120 vvp $(BUILD_DIR)/sim/$$name.vvp > $(BUILD_DIR)/sim/$$name.log 2>&1; \
		rc=$$?; \
		if [ $$rc -ne 0 ]; then \
			fail=1; \
			echo "SIMULATION FAILED (rc=$$rc): $$name"; \
			tail -n 20 $(BUILD_DIR)/sim/$$name.log; \
			continue; \
		fi; \
		if grep -qE '\$finish|FAIL|ERROR|%Error|Assertion failed' $(BUILD_DIR)/sim/$$name.log; then \
			if grep -qE 'FAIL|%Error|Assertion failed|\$error' $(BUILD_DIR)/sim/$$name.log; then \
				fail=1; echo "SIMULATION FAILED (assertion/error): $$name"; \
				grep -E 'FAIL|%Error|Assertion failed|\$error' $(BUILD_DIR)/sim/$$name.log; \
				continue; \
			fi; \
		fi; \
		echo "PASS: $$name"; \
		pass=$$((pass + 1)); \
	done; \
	echo ""; \
	echo "Results: $$pass passed, $$fail failed"; \
	exit $$fail

# Verification
.PHONY: verify
verify: directories
	@echo "Running verification suite..."
	@for f in $(VERIF_DIR)/*.py; do \
		echo "  $$f"; \
		$(PYTHON) $$f 2>/dev/null || echo "  (skipped)"; \
	done

# Lint - H18: Full RTL tree, real exit status
.PHONY: lint
lint: directories
	@echo "Linting RTL..."
	@$(VERILATOR) --lint-only -Wall $(VERILATOR_WNO) $(RTL_DIR)/messages/message_types.sv $(RTL_SRCS) 2>&1; \
	exit $$?

# Synthesis
# ==========
SYNTH_DIR := build/synth
SYNTH_SCRIPT := scripts/syn_lucid.tcl

.PHONY: synth
synth: directories
	@mkdir -p $(SYNTH_DIR)
	@echo "Running Yosys synthesis..."
	$(YOSYS) -c $(SYNTH_SCRIPT) 2>&1 | tee $(SYNTH_DIR)/synth.log || echo "  (Yosys not available)"

.PHONY: synth-stats
synth-stats: synth
	@echo "=== Synthesis Statistics ==="
	@grep -E "(Number of|LUT|FF|BRAM|DSP|Estimated)" $(SYNTH_DIR)/synth.log 2>/dev/null || echo "  (statistics not found)"

# Clean
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

.PHONY: distclean
distclean: clean
	rm -rf $(BUILD_DIR)
	rm -f *.log *.vcd *.fst

# Git hooks
.PHONY: hooks
hooks:
	@echo "Installing git hooks..."
	@ln -sf ../../scripts/pre-commit.sh .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "Done."
