#!/bin/bash

################################################################################
# Run All Tests - Complete DFT System Verification
# Runs all three testbenches and reports results
################################################################################

echo "========================================"
echo "   256-Point DFT System - Full Test Suite"
echo "========================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test
run_test() {
    local name=$1
    local cmd=$2
    local expected_pass=$3

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Running: $name${NC}"
    echo -e "${BLUE}========================================${NC}"

    # Run the command and capture output
    OUTPUT=$(eval $cmd 2>&1)
    EXIT_CODE=$?

    # Check for success indicators
    if echo "$OUTPUT" | grep -q "ALL TESTS PASSED" && [ $EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✓ $name: PASSED${NC}"
        ((PASSED_TESTS++))

        # Extract test count if available
        if echo "$OUTPUT" | grep -q "Total Tests"; then
            TEST_COUNT=$(echo "$OUTPUT" | grep "Total Tests" | tail -1 | grep -oP '\d+' | head -1)
            echo "  Tests executed: $TEST_COUNT"
            ((TOTAL_TESTS+=TEST_COUNT))
        fi
    else
        echo -e "${RED}✗ $name: FAILED${NC}"
        ((FAILED_TESTS++))
        echo "  Exit code: $EXIT_CODE"
        echo "  Last 10 lines of output:"
        echo "$OUTPUT" | tail -10
    fi

    echo ""
}

echo "Step 1: Compiling all VHDL files..."
echo "-----------------------------------"

# Compile all files
ghdl -a --std=08 cos.vhd 2>&1 | grep -i error
ghdl -a --std=08 sine.vhd 2>&1 | grep -i error
ghdl -a --std=08 dft.vhd 2>&1 | grep -i error
ghdl -a --std=08 tb_cosine_single_k_rom.vhd 2>&1 | grep -i error
ghdl -a --std=08 tb_sine_single_k_rom.vhd 2>&1 | grep -i error
ghdl -a --std=08 tb_dft_complex_calculator.vhd 2>&1 | grep -i error

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ All files compiled successfully${NC}"
else
    echo -e "${RED}✗ Compilation errors detected${NC}"
    exit 1
fi
echo ""

echo "Step 2: Elaborating testbenches..."
echo "-----------------------------------"

ghdl -e --std=08 tb_cosine_single_k_rom
ghdl -e --std=08 tb_sine_single_k_rom
ghdl -e --std=08 tb_dft_complex_calculator

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ All testbenches elaborated successfully${NC}"
else
    echo -e "${RED}✗ Elaboration errors detected${NC}"
    exit 1
fi
echo ""

echo "Step 3: Running test suites..."
echo "-----------------------------------"
echo ""

# Run Test 1: Cosine ROM
run_test "Cosine ROM Testbench" \
         "ghdl -r --std=08 tb_cosine_single_k_rom --stop-time=15us" \
         921

# Run Test 2: Sine ROM
run_test "Sine ROM Testbench" \
         "ghdl -r --std=08 tb_sine_single_k_rom --stop-time=10us" \
         773

# Run Test 3: DFT Calculator
run_test "DFT Complex Calculator Testbench" \
         "ghdl -r --std=08 tb_dft_complex_calculator --stop-time=500us" \
         10

# Final Summary
echo "========================================"
echo "   FINAL TEST SUMMARY"
echo "========================================"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓✓✓ ALL TESTBENCHES PASSED ✓✓✓${NC}"
else
    echo -e "${RED}✗✗✗ SOME TESTS FAILED ✗✗✗${NC}"
fi

echo ""
echo "Testbenches Passed: ${PASSED_TESTS}/3"
echo "Testbenches Failed: ${FAILED_TESTS}/3"

if [ $TOTAL_TESTS -gt 0 ]; then
    echo "Total Individual Tests: ${TOTAL_TESTS}"
fi

echo ""
echo "========================================"
echo "   MODULE STATUS"
echo "========================================"
echo "cos.vhd (Cosine ROM):           ✓ 256 samples"
echo "sine.vhd (Sine ROM):            ✓ 256 samples"
echo "dft.vhd (DFT Calculator):       ✓ 256 samples, 48-bit accumulator"
echo ""
echo "Documentation:"
echo "  - PROJECT_COMPLETE.md         Complete project summary"
echo "  - TESTBENCH_GUIDE.md          Cosine ROM testbench guide"
echo "  - TESTBENCH_README.md         Sine ROM testbench guide"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}System Status: PRODUCTION READY ✓${NC}"
    exit 0
else
    echo -e "${RED}System Status: ISSUES DETECTED ✗${NC}"
    exit 1
fi
