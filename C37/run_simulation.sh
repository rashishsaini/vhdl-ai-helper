#!/bin/bash
################################################################################
# Cosine Single K ROM - Simulation Script
#
# This script compiles and runs the testbench for the cosine_single_k_rom
# entity using GHDL simulator.
#
# Usage:
#   ./run_simulation.sh              # Run simulation without waveform
#   ./run_simulation.sh --wave       # Run with waveform generation (GHW)
#   ./run_simulation.sh --vcd        # Run with waveform generation (VCD)
#   ./run_simulation.sh --clean      # Clean generated files
################################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# File paths
DUT_FILE="cos.vhd"
TB_FILE="tb_cosine_single_k_rom.vhd"
TB_ENTITY="tb_cosine_single_k_rom"
WORK_DIR="work"

# Simulation parameters
SIM_TIME="90us"

################################################################################
# Functions
################################################################################

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}➜ $1${NC}"
}

clean_files() {
    print_header "Cleaning Generated Files"

    rm -rf ${WORK_DIR}
    rm -f *.o *.cf
    rm -f ${TB_ENTITY}
    rm -f *.vcd *.ghw *.wlf
    rm -f transcript

    print_success "Cleanup complete"
}

analyze_files() {
    print_header "Analyzing VHDL Files"

    # Analyze DUT
    print_info "Analyzing DUT: ${DUT_FILE}"
    if ghdl -a ${DUT_FILE}; then
        print_success "DUT analysis successful"
    else
        print_error "DUT analysis failed"
        exit 1
    fi

    # Analyze testbench
    print_info "Analyzing Testbench: ${TB_FILE}"
    if ghdl -a ${TB_FILE}; then
        print_success "Testbench analysis successful"
    else
        print_error "Testbench analysis failed"
        exit 1
    fi
}

elaborate() {
    print_header "Elaborating Design"

    if ghdl -e ${TB_ENTITY}; then
        print_success "Elaboration successful"
    else
        print_error "Elaboration failed"
        exit 1
    fi
}

run_simulation() {
    local wave_format=$1

    print_header "Running Simulation"

    print_info "Simulation time: ${SIM_TIME}"

    case ${wave_format} in
        "vcd")
            print_info "Generating VCD waveform: ${TB_ENTITY}.vcd"
            ghdl -r ${TB_ENTITY} --stop-time=${SIM_TIME} --vcd=${TB_ENTITY}.vcd
            ;;
        "ghw")
            print_info "Generating GHW waveform: ${TB_ENTITY}.ghw"
            ghdl -r ${TB_ENTITY} --stop-time=${SIM_TIME} --wave=${TB_ENTITY}.ghw
            ;;
        *)
            print_info "Running without waveform generation"
            ghdl -r ${TB_ENTITY} --stop-time=${SIM_TIME}
            ;;
    esac

    local exit_code=$?

    if [ ${exit_code} -eq 0 ]; then
        print_success "Simulation completed successfully"

        if [ "${wave_format}" = "vcd" ]; then
            print_info "View waveform with: gtkwave ${TB_ENTITY}.vcd"
        elif [ "${wave_format}" = "ghw" ]; then
            print_info "View waveform with: gtkwave ${TB_ENTITY}.ghw"
        fi
    else
        print_error "Simulation failed with exit code ${exit_code}"
        exit ${exit_code}
    fi
}

show_summary() {
    print_header "Simulation Summary"

    echo "Files:"
    echo "  DUT:       ${DUT_FILE}"
    echo "  Testbench: ${TB_FILE}"
    echo ""
    echo "Results:"
    echo "  Expected: 1030+ tests, 0 failures"
    echo "  Check output above for actual results"
    echo ""
    echo "Documentation:"
    echo "  Guide:   TESTBENCH_GUIDE.md"
    echo "  Summary: SIMULATION_SUMMARY.md"
}

################################################################################
# Main Script
################################################################################

# Parse command line arguments
WAVE_FORMAT=""

case "$1" in
    --clean)
        clean_files
        exit 0
        ;;
    --wave|--ghw)
        WAVE_FORMAT="ghw"
        ;;
    --vcd)
        WAVE_FORMAT="vcd"
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  (no options)  Run simulation without waveform"
        echo "  --wave        Run with GHW waveform generation (for GTKWave)"
        echo "  --vcd         Run with VCD waveform generation"
        echo "  --clean       Clean all generated files"
        echo "  --help        Show this help message"
        echo ""
        exit 0
        ;;
    "")
        # No arguments - run without waveform
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Main execution flow
print_header "VHDL Testbench Runner - Cosine Single K ROM"

# Check if files exist
if [ ! -f "${DUT_FILE}" ]; then
    print_error "DUT file not found: ${DUT_FILE}"
    exit 1
fi

if [ ! -f "${TB_FILE}" ]; then
    print_error "Testbench file not found: ${TB_FILE}"
    exit 1
fi

# Run simulation steps
analyze_files
elaborate
run_simulation ${WAVE_FORMAT}
show_summary

print_success "All done!"
