#!/bin/bash
# GHDL Test Runner Script
# Usage: ./ghdl_run_test.sh <module_name>
# Example: ./ghdl_run_test.sh power_unit

set -e  # Exit on error

# Configuration
GHDL=ghdl
GHDL_FLAGS="--std=08 --ieee=synopsys -frelaxed-rules"
GHDL_ELAB_FLAGS="--std=08 --ieee=synopsys -frelaxed-rules"
GHDL_RUN_FLAGS="--stop-time=100us --ieee-asserts=disable"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
GHDL_DIR="$BASE_DIR/simulation_results/ghdl"
TB_DIR="$BASE_DIR/adam_testbenches"
LOG_DIR="$GHDL_DIR/logs"

# Check arguments
if [ $# -ne 1 ]; then
    echo "Error: Module name required"
    echo "Usage: $0 <module_name>"
    echo "Example: $0 power_unit"
    exit 1
fi

MODULE_NAME=$1
TB_NAME="${MODULE_NAME}_tb"
LOG_FILE="$LOG_DIR/${MODULE_NAME}_ghdl.log"

# Create log directory
mkdir -p "$LOG_DIR"

# Check if testbench exists
TB_FILE="$TB_DIR/${TB_NAME}.vhd"
if [ ! -f "$TB_FILE" ]; then
    echo "Error: Testbench not found: $TB_FILE"
    exit 1
fi

echo "=========================================="
echo "GHDL Test Runner"
echo "=========================================="
echo "Module:     $MODULE_NAME"
echo "Testbench:  $TB_NAME"
echo "Log file:   $LOG_FILE"
echo "=========================================="
echo ""

# Navigate to GHDL work directory
cd "$GHDL_DIR"

# Step 1: Analyze testbench
echo "[1/3] Analyzing testbench..."
$GHDL -a $GHDL_FLAGS "$TB_FILE" 2>&1 | tee -a "$LOG_FILE"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "ERROR: Testbench analysis failed"
    exit 1
fi
echo "  ✓ Analysis complete"

# Step 2: Elaborate testbench
echo "[2/3] Elaborating testbench..."
$GHDL -e $GHDL_ELAB_FLAGS "$TB_NAME" 2>&1 | tee -a "$LOG_FILE"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "ERROR: Testbench elaboration failed"
    exit 1
fi
echo "  ✓ Elaboration complete"

# Step 3: Run simulation
echo "[3/3] Running simulation..."
$GHDL -r $GHDL_ELAB_FLAGS "$TB_NAME" $GHDL_RUN_FLAGS 2>&1 | tee -a "$LOG_FILE"
RESULT=${PIPESTATUS[0]}

echo ""
echo "=========================================="
if [ $RESULT -eq 0 ]; then
    echo "✓ SIMULATION PASSED: $MODULE_NAME"
    echo "=========================================="
    exit 0
else
    echo "✗ SIMULATION FAILED: $MODULE_NAME"
    echo "=========================================="
    echo "Check log file: $LOG_FILE"
    exit 1
fi
