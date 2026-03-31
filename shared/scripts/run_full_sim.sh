#!/bin/bash
# Full simulation test with simple_cholesky_tb

echo "========================================"
echo "Full Cholesky Simulation Test"
echo "========================================"

WORK_DIR="/tmp/cholesky_full_sim"
rm -rf $WORK_DIR
mkdir -p $WORK_DIR
cd $WORK_DIR

echo "=== Compiling Design Files ==="

echo "Compiling: sqrt_newton_xsim.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/sqrt_newton_xsim.vhd

echo "Compiling: code.vhd (inline arithmetic version)"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/code.vhd

echo "Compiling: simple_cholesky_tb.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/simple_cholesky_tb.vhd

echo ""
echo "=== Elaborating Design ==="
xelab -debug typical xil_defaultlib.simple_cholesky_tb -s cholesky_sim

if [ $? -ne 0 ]; then
    echo "ERROR: Elaboration failed"
    exit 1
fi

echo ""
echo "=== Running Simulation ==="
xsim cholesky_sim -runall -log simulation.log

echo ""
echo "========================================"
echo "Simulation Output:"
echo "========================================"
cat simulation.log

echo ""
echo "========================================"
echo "SIMULATION COMPLETE"
echo "========================================"
