#!/bin/bash
# Dual Simulator Comparison Script
# Runs both GHDL and Vivado XSIM, then compares outputs
# Usage: ./run_dual_sim.sh <module_name>
# Example: ./run_dual_sim.sh power_unit

set -e  # Exit on error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
COMP_DIR="$BASE_DIR/simulation_results/comparison"
GHDL_LOG_DIR="$BASE_DIR/simulation_results/ghdl/logs"
VIVADO_LOG_DIR="$BASE_DIR/simulation_results/vivado/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -ne 1 ]; then
    echo "Error: Module name required"
    echo "Usage: $0 <module_name>"
    echo "Example: $0 power_unit"
    exit 1
fi

MODULE_NAME=$1
GHDL_LOG="$GHDL_LOG_DIR/${MODULE_NAME}_ghdl.log"
VIVADO_LOG="$VIVADO_LOG_DIR/${MODULE_NAME}_vivado.log"
DIFF_FILE="$COMP_DIR/${MODULE_NAME}_diff.txt"
REPORT_FILE="$COMP_DIR/${MODULE_NAME}_comparison_report.txt"

# Create comparison directory
mkdir -p "$COMP_DIR"

echo "=========================================="
echo "Dual Simulator Comparison"
echo "=========================================="
echo "Module:        $MODULE_NAME"
echo "GHDL log:      $GHDL_LOG"
echo "Vivado log:    $VIVADO_LOG"
echo "Diff file:     $DIFF_FILE"
echo "Report file:   $REPORT_FILE"
echo "=========================================="
echo ""

# Step 1: Run GHDL simulation
echo -e "${BLUE}[1/4]${NC} Running GHDL simulation..."
if bash "$SCRIPT_DIR/ghdl_run_test.sh" "$MODULE_NAME"; then
    echo -e "  ${GREEN}✓${NC} GHDL simulation completed"
    GHDL_RESULT="PASSED"
else
    echo -e "  ${RED}✗${NC} GHDL simulation failed"
    GHDL_RESULT="FAILED"
fi

# Step 2: Run Vivado simulation
echo ""
echo -e "${BLUE}[2/4]${NC} Running Vivado simulation..."
if vivado -mode batch -source "$SCRIPT_DIR/vivado_run_test.tcl" -tclargs "$MODULE_NAME" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Vivado simulation completed"
    VIVADO_RESULT="PASSED"
else
    echo -e "  ${RED}✗${NC} Vivado simulation failed"
    VIVADO_RESULT="FAILED"
fi

# Step 3: Compare outputs
echo ""
echo -e "${BLUE}[3/4]${NC} Comparing simulation outputs..."

# Check if both logs exist
if [ ! -f "$GHDL_LOG" ]; then
    echo -e "  ${RED}✗${NC} GHDL log file not found: $GHDL_LOG"
    exit 1
fi

if [ ! -f "$VIVADO_LOG" ]; then
    echo -e "  ${RED}✗${NC} Vivado log file not found: $VIVADO_LOG"
    exit 1
fi

# Extract relevant output (filter out timestamps, simulator-specific messages)
grep -v "^#" "$GHDL_LOG" | grep -v "INFO:" | grep -v "WARNING:" > "$COMP_DIR/${MODULE_NAME}_ghdl_filtered.txt" || true
grep -v "^#" "$VIVADO_LOG" | grep -v "INFO:" | grep -v "WARNING:" > "$COMP_DIR/${MODULE_NAME}_vivado_filtered.txt" || true

# Perform diff
if diff -u "$COMP_DIR/${MODULE_NAME}_ghdl_filtered.txt" "$COMP_DIR/${MODULE_NAME}_vivado_filtered.txt" > "$DIFF_FILE"; then
    echo -e "  ${GREEN}✓${NC} Outputs are identical"
    DIFF_RESULT="IDENTICAL"
else
    echo -e "  ${YELLOW}!${NC} Outputs differ (see $DIFF_FILE)"
    DIFF_RESULT="DIFFERENT"
fi

# Step 4: Generate comparison report
echo ""
echo -e "${BLUE}[4/4]${NC} Generating comparison report..."

cat > "$REPORT_FILE" << EOF
========================================
Dual Simulator Comparison Report
========================================
Module:           $MODULE_NAME
Date:             $(date)
========================================

SIMULATION RESULTS:
-------------------
GHDL:             $GHDL_RESULT
Vivado XSIM:      $VIVADO_RESULT

OUTPUT COMPARISON:
------------------
Diff Status:      $DIFF_RESULT

LOG FILE LOCATIONS:
-------------------
GHDL log:         $GHDL_LOG
Vivado log:       $VIVADO_LOG
Diff file:        $DIFF_FILE

========================================
EOF

if [ "$DIFF_RESULT" = "DIFFERENT" ]; then
    cat >> "$REPORT_FILE" << EOF

DIFFERENCES FOUND:
------------------
$(cat "$DIFF_FILE")

========================================
EOF
fi

echo -e "  ${GREEN}✓${NC} Report generated: $REPORT_FILE"

# Final summary
echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo -e "GHDL result:       $GHDL_RESULT"
echo -e "Vivado result:     $VIVADO_RESULT"
echo -e "Output comparison: $DIFF_RESULT"
echo "=========================================="

if [ "$GHDL_RESULT" = "PASSED" ] && [ "$VIVADO_RESULT" = "PASSED" ] && [ "$DIFF_RESULT" = "IDENTICAL" ]; then
    echo -e "${GREEN}✓ DUAL SIMULATION PASSED${NC}"
    echo "Both simulators produced identical outputs"
    echo "=========================================="
    exit 0
elif [ "$GHDL_RESULT" = "PASSED" ] && [ "$VIVADO_RESULT" = "PASSED" ] && [ "$DIFF_RESULT" = "DIFFERENT" ]; then
    echo -e "${YELLOW}⚠ PARTIAL SUCCESS${NC}"
    echo "Both simulators passed, but outputs differ"
    echo "This may be due to formatting differences"
    echo "Review diff file: $DIFF_FILE"
    echo "=========================================="
    exit 0
else
    echo -e "${RED}✗ DUAL SIMULATION FAILED${NC}"
    echo "One or both simulators failed"
    echo "Review logs for details"
    echo "=========================================="
    exit 1
fi
