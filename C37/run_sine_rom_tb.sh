#!/bin/bash

################################################################################
# Simulation Script for tb_sine_single_k_rom
# Supports GHDL simulator
################################################################################

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "  SINE_SINGLE_K_ROM Testbench Simulation"
echo "========================================"

# Check if GHDL is installed
if ! command -v ghdl &> /dev/null
then
    echo -e "${RED}ERROR: GHDL not found. Please install GHDL.${NC}"
    exit 1
fi

# Clean previous build artifacts
echo -e "${YELLOW}Cleaning previous build artifacts...${NC}"
rm -f *.o *.cf tb_sine_single_k_rom work-obj*.cf

# Analyze VHDL files
echo -e "${YELLOW}Analyzing VHDL source files...${NC}"

echo "  - Analyzing sine.vhd (DUT)"
ghdl -a --std=08 sine.vhd
if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Failed to analyze sine.vhd${NC}"
    exit 1
fi

echo "  - Analyzing tb_sine_single_k_rom.vhd (Testbench)"
ghdl -a --std=08 tb_sine_single_k_rom.vhd
if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Failed to analyze tb_sine_single_k_rom.vhd${NC}"
    exit 1
fi

# Elaborate testbench
echo -e "${YELLOW}Elaborating testbench...${NC}"
ghdl -e --std=08 tb_sine_single_k_rom
if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Failed to elaborate testbench${NC}"
    exit 1
fi

# Run simulation
echo -e "${YELLOW}Running simulation...${NC}"
echo "========================================"

# Run with VCD output for waveform viewing
ghdl -r --std=08 tb_sine_single_k_rom --vcd=sine_rom_tb.vcd --stop-time=90us

RETVAL=$?

echo "========================================"

if [ $RETVAL -eq 0 ]; then
    echo -e "${GREEN}Simulation completed successfully!${NC}"
    echo -e "${GREEN}Waveform saved to: sine_rom_tb.vcd${NC}"
    echo ""
    echo "To view waveforms, use:"
    echo "  gtkwave sine_rom_tb.vcd"
    exit 0
else
    echo -e "${RED}Simulation failed with errors.${NC}"
    exit 1
fi
