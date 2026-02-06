#!/bin/bash
# Vivado Batch Test Runner Script
# Runs all testbenches sequentially with Vivado XSIM

set -e  # Exit on error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Test modules (in order of complexity)
MODULES=(
    "power_unit"
    "moment_register_bank"
    "moment_update_unit"
    "bias_correction_unit"
    "adaptive_lr_unit"
    "adam_update_unit"
    "adam_optimizer"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Vivado XSIM Batch Test Runner"
echo "=========================================="
echo "Running ${#MODULES[@]} testbenches..."
echo ""

# Results tracking
PASSED=0
FAILED=0
FAILED_MODULES=()

# Run each test
for MODULE in "${MODULES[@]}"; do
    echo ""
    echo "----------------------------------------"
    echo "Testing: $MODULE"
    echo "----------------------------------------"

    if vivado -mode batch -source "$SCRIPT_DIR/vivado_run_test.tcl" -tclargs "$MODULE"; then
        echo -e "${GREEN}✓ PASSED${NC}: $MODULE"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAILED${NC}: $MODULE"
        ((FAILED++))
        FAILED_MODULES+=("$MODULE")
    fi
done

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Total tests:  ${#MODULES[@]}"
echo -e "Passed:       ${GREEN}$PASSED${NC}"
echo -e "Failed:       ${RED}$FAILED${NC}"
echo "=========================================="

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    echo "=========================================="
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    echo ""
    echo "Failed modules:"
    for MODULE in "${FAILED_MODULES[@]}"; do
        echo "  - $MODULE"
    done
    echo "=========================================="
    exit 1
fi
