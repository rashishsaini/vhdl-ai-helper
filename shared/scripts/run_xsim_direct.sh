#!/bin/bash
# Direct XSIM compilation and simulation
# Uses XSIM-compatible modules

echo "========================================"
echo "Simple Cholesky XSIM Direct Simulation"
echo "========================================"

# Create work directory
WORK_DIR="/tmp/cholesky_xsim_work"
rm -rf $WORK_DIR
mkdir -p $WORK_DIR
cd $WORK_DIR

echo ""
echo "=== Compiling Design Files ==="

# Compile simplified fixed-point package
echo "Compiling: fixed_point_pkg_simple.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/fixed_point_pkg_simple.vhd

if [ $? -ne 0 ]; then
    echo "ERROR: fixed_point_pkg_simple.vhd compilation failed"
    exit 1
fi

# Compile XSIM-compatible sqrt_newton
echo "Compiling: sqrt_newton_xsim.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/sqrt_newton_xsim.vhd

if [ $? -ne 0 ]; then
    echo "ERROR: sqrt_newton_xsim.vhd compilation failed"
    exit 1
fi

# Compile main Cholesky design
echo "Compiling: code.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/code.vhd

if [ $? -ne 0 ]; then
    echo "ERROR: code.vhd compilation failed"
    exit 1
fi

# Compile testbench
echo "Compiling: simple_cholesky_tb.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/simple_cholesky_tb.vhd

if [ $? -ne 0 ]; then
    echo "ERROR: simple_cholesky_tb.vhd compilation failed"
    exit 1
fi

echo ""
echo "=== Elaborating Design ==="
xelab -debug typical xil_defaultlib.simple_cholesky_tb -s simple_cholesky_tb_sim

if [ $? -ne 0 ]; then
    echo "ERROR: Elaboration failed"
    exit 1
fi

echo ""
echo "=== Running Simulation ==="
xsim simple_cholesky_tb_sim -runall -log simulation.log

if [ $? -ne 0 ]; then
    echo "ERROR: Simulation failed"
    exit 1
fi

echo ""
echo "========================================"
echo "SIMULATION COMPLETE"
echo "========================================"
echo ""
echo "Simulation output:"
cat simulation.log

exit 0
