# Makefile for Adam Optimizer VHDL Implementation
# Supports GHDL and Vivado XSIM dual simulator testing

# =============================================================================
# Configuration
# =============================================================================

# Directories
SRC_DIR := adam_modules
TB_DIR := adam_testbenches
REF_DIR := adam_reference
VEC_DIR := test_vectors
SCRIPT_DIR := scripts
RESULT_DIR := simulation_results
GHDL_DIR := $(RESULT_DIR)/ghdl
VIVADO_DIR := $(RESULT_DIR)/vivado
COMP_DIR := $(RESULT_DIR)/comparison

# GHDL Configuration
GHDL := ghdl
GHDL_FLAGS := --std=08 --ieee=synopsys -frelaxed-rules
GHDL_ELAB_FLAGS := --std=08 --ieee=synopsys -frelaxed-rules
GHDL_RUN_FLAGS := --stop-time=100us --ieee-asserts=disable

# Vivado Configuration
VIVADO := vivado
XVHDL := xvhdl
XELAB := xelab
XSIM := xsim
VIVADO_FLAGS := -2008

# Python
PYTHON := python3

# =============================================================================
# Source Files (Dependency Order)
# =============================================================================

# Primitive modules (no dependencies)
PRIMITIVES := \
	$(SRC_DIR)/reciprocal_unit.vhd \
	$(SRC_DIR)/moment_register_bank.vhd

# Reused modules from BasicMath (assumed to be in parent or current directory)
REUSED := \
	mac_unit.vhd \
	sqrt_unit.vhd \
	division_unit.vhd

# New modules (with dependencies)
MODULES := \
	$(SRC_DIR)/power_unit.vhd \
	$(SRC_DIR)/moment_update_unit.vhd \
	$(SRC_DIR)/bias_correction_unit.vhd \
	$(SRC_DIR)/adaptive_lr_unit.vhd \
	$(SRC_DIR)/adam_update_unit.vhd \
	$(SRC_DIR)/adam_optimizer.vhd

# All sources in dependency order
ALL_SOURCES := $(REUSED) $(PRIMITIVES) $(MODULES)

# Testbenches
TESTBENCHES := \
	$(TB_DIR)/power_unit_tb.vhd \
	$(TB_DIR)/moment_register_bank_tb.vhd \
	$(TB_DIR)/moment_update_unit_tb.vhd \
	$(TB_DIR)/bias_correction_unit_tb.vhd \
	$(TB_DIR)/adaptive_lr_unit_tb.vhd \
	$(TB_DIR)/adam_update_unit_tb.vhd \
	$(TB_DIR)/adam_optimizer_tb.vhd

# Extract testbench names (without _tb suffix)
TB_NAMES := power_unit moment_register_bank moment_update_unit bias_correction_unit \
            adaptive_lr_unit adam_update_unit adam_optimizer

# =============================================================================
# Phony Targets
# =============================================================================

.PHONY: all clean help \
        ghdl ghdl-compile ghdl-clean \
        vivado vivado-compile vivado-clean \
        test-all test-ghdl test-vivado dual-sim \
        $(addprefix test-,$(TB_NAMES)) \
        $(addprefix dual-,$(TB_NAMES)) \
        vectors compare

# =============================================================================
# Default Target
# =============================================================================

all: help

help:
	@echo "=========================================="
	@echo "Adam Optimizer VHDL Build System"
	@echo "=========================================="
	@echo ""
	@echo "Compilation Targets:"
	@echo "  make ghdl              - Compile all VHDL with GHDL"
	@echo "  make vivado            - Compile all VHDL with Vivado"
	@echo ""
	@echo "Testing Targets (Individual Modules):"
	@echo "  make test-power_unit              - Test power_unit (GHDL)"
	@echo "  make test-moment_register_bank    - Test moment_register_bank (GHDL)"
	@echo "  make test-moment_update_unit      - Test moment_update_unit (GHDL)"
	@echo "  make test-bias_correction_unit    - Test bias_correction_unit (GHDL)"
	@echo "  make test-adaptive_lr_unit        - Test adaptive_lr_unit (GHDL)"
	@echo "  make test-adam_update_unit        - Test adam_update_unit (GHDL)"
	@echo "  make test-adam_optimizer          - Test adam_optimizer (GHDL)"
	@echo ""
	@echo "Testing Targets (Batch):"
	@echo "  make test-all          - Run all testbenches (GHDL)"
	@echo "  make test-ghdl         - Run all testbenches (GHDL only)"
	@echo "  make test-vivado       - Run all testbenches (Vivado only)"
	@echo ""
	@echo "Dual Simulator Testing:"
	@echo "  make dual-sim MODULE=<name>  - Run GHDL + Vivado, compare results"
	@echo "  make dual-power_unit         - Dual-sim for power_unit"
	@echo "  make dual-moment_update_unit - Dual-sim for moment_update_unit"
	@echo "  (etc. for all modules)"
	@echo ""
	@echo "Utility Targets:"
	@echo "  make vectors           - Generate test vectors (Python)"
	@echo "  make compare           - Compare simulation results to golden reference"
	@echo "  make clean             - Remove all build artifacts"
	@echo ""
	@echo "Examples:"
	@echo "  make ghdl && make test-power_unit"
	@echo "  make dual-sim MODULE=bias_correction_unit"
	@echo "=========================================="

# =============================================================================
# GHDL Targets
# =============================================================================

ghdl: ghdl-compile
	@echo "[GHDL] Compilation complete"

ghdl-compile: $(GHDL_DIR)/.compile_done

$(GHDL_DIR)/.compile_done: $(ALL_SOURCES)
	@echo "[GHDL] Compiling all VHDL sources..."
	@mkdir -p $(GHDL_DIR)
	@cd $(GHDL_DIR) && \
	for src in $(addprefix ../../,$(ALL_SOURCES)); do \
		echo "  Analyzing $$src..."; \
		$(GHDL) -a $(GHDL_FLAGS) $$src || exit 1; \
	done
	@touch $(GHDL_DIR)/.compile_done
	@echo "[GHDL] All sources compiled successfully"

ghdl-clean:
	@echo "[GHDL] Cleaning build artifacts..."
	@rm -rf $(GHDL_DIR)
	@echo "[GHDL] Clean complete"

# =============================================================================
# Vivado Targets
# =============================================================================

vivado: vivado-compile
	@echo "[Vivado] Compilation complete"

vivado-compile: $(VIVADO_DIR)/.compile_done

$(VIVADO_DIR)/.compile_done: $(ALL_SOURCES)
	@echo "[Vivado] Compiling all VHDL sources..."
	@mkdir -p $(VIVADO_DIR)
	@cd $(VIVADO_DIR) && \
	for src in $(addprefix ../../,$(ALL_SOURCES)); do \
		echo "  Analyzing $$src..."; \
		$(XVHDL) $(VIVADO_FLAGS) $$src || exit 1; \
	done
	@touch $(VIVADO_DIR)/.compile_done
	@echo "[Vivado] All sources compiled successfully"

vivado-clean:
	@echo "[Vivado] Cleaning build artifacts..."
	@rm -rf $(VIVADO_DIR)
	@echo "[Vivado] Clean complete"

# =============================================================================
# Testing Targets - Individual Modules (GHDL)
# =============================================================================

test-power_unit: ghdl-compile
	@echo "[TEST] Running power_unit testbench (GHDL)..."
	@bash $(SCRIPT_DIR)/ghdl_run_test.sh power_unit

test-moment_register_bank: ghdl-compile
	@echo "[TEST] Running moment_register_bank testbench (GHDL)..."
	@bash $(SCRIPT_DIR)/ghdl_run_test.sh moment_register_bank

test-moment_update_unit: ghdl-compile
	@echo "[TEST] Running moment_update_unit testbench (GHDL)..."
	@bash $(SCRIPT_DIR)/ghdl_run_test.sh moment_update_unit

test-bias_correction_unit: ghdl-compile
	@echo "[TEST] Running bias_correction_unit testbench (GHDL)..."
	@bash $(SCRIPT_DIR)/ghdl_run_test.sh bias_correction_unit

test-adaptive_lr_unit: ghdl-compile
	@echo "[TEST] Running adaptive_lr_unit testbench (GHDL)..."
	@bash $(SCRIPT_DIR)/ghdl_run_test.sh adaptive_lr_unit

test-adam_update_unit: ghdl-compile
	@echo "[TEST] Running adam_update_unit testbench (GHDL)..."
	@bash $(SCRIPT_DIR)/ghdl_run_test.sh adam_update_unit

test-adam_optimizer: ghdl-compile
	@echo "[TEST] Running adam_optimizer testbench (GHDL)..."
	@bash $(SCRIPT_DIR)/ghdl_run_test.sh adam_optimizer

# =============================================================================
# Testing Targets - Batch
# =============================================================================

test-all: test-ghdl
	@echo "[TEST] All tests complete"

test-ghdl: ghdl-compile
	@echo "[TEST] Running all testbenches with GHDL..."
	@bash $(SCRIPT_DIR)/ghdl_batch_test.sh

test-vivado: vivado-compile
	@echo "[TEST] Running all testbenches with Vivado..."
	@bash $(SCRIPT_DIR)/vivado_batch_test.sh

# =============================================================================
# Dual Simulator Testing
# =============================================================================

dual-sim:
	@if [ -z "$(MODULE)" ]; then \
		echo "Error: MODULE not specified. Usage: make dual-sim MODULE=power_unit"; \
		exit 1; \
	fi
	@echo "[DUAL-SIM] Running dual simulator test for $(MODULE)..."
	@bash $(SCRIPT_DIR)/run_dual_sim.sh $(MODULE)

# Individual dual-sim targets
dual-power_unit:
	@$(MAKE) dual-sim MODULE=power_unit

dual-moment_register_bank:
	@$(MAKE) dual-sim MODULE=moment_register_bank

dual-moment_update_unit:
	@$(MAKE) dual-sim MODULE=moment_update_unit

dual-bias_correction_unit:
	@$(MAKE) dual-sim MODULE=bias_correction_unit

dual-adaptive_lr_unit:
	@$(MAKE) dual-sim MODULE=adaptive_lr_unit

dual-adam_update_unit:
	@$(MAKE) dual-sim MODULE=adam_update_unit

dual-adam_optimizer:
	@$(MAKE) dual-sim MODULE=adam_optimizer

# =============================================================================
# Utility Targets
# =============================================================================

vectors:
	@echo "[VECTORS] Generating test vectors..."
	@cd $(REF_DIR) && $(PYTHON) generate_test_vectors.py
	@echo "[VECTORS] Test vectors generated in $(VEC_DIR)/"

compare:
	@echo "[COMPARE] Comparing simulation results to golden reference..."
	@cd $(REF_DIR) && $(PYTHON) compare_results.py
	@echo "[COMPARE] Comparison complete. See $(COMP_DIR)/ for reports"

# =============================================================================
# Clean Target
# =============================================================================

clean: ghdl-clean vivado-clean
	@echo "[CLEAN] Removing all build artifacts..."
	@rm -rf $(RESULT_DIR)
	@rm -f *.cf *.o work-obj*.cf
	@echo "[CLEAN] Clean complete"
