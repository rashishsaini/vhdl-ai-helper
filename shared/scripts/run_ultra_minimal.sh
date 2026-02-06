#!/bin/bash
# Test with ultra minimal testbench (no math_real)

echo "========================================"
echo "Ultra Minimal Test (No math_real)"
echo "========================================"

WORK_DIR="/tmp/cholesky_ultra_minimal"
rm -rf $WORK_DIR
mkdir -p $WORK_DIR
cd $WORK_DIR

echo ""
echo "=== Compiling Design Files ==="

echo "Compiling: fixed_point_pkg_simple.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/fixed_point_pkg_simple.vhd

echo "Compiling: sqrt_newton_xsim.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/sqrt_newton_xsim.vhd

echo "Compiling: code.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/code.vhd

echo "Compiling: ultra_minimal_tb.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/ultra_minimal_tb.vhd

echo ""
echo "=== Elaborating Design ==="
xelab -debug typical xil_defaultlib.ultra_minimal_tb -s ultra_minimal_sim

if [ $? -eq 0 ]; then
    echo ""
    echo "SUCCESS: Elaboration completed!"
    echo "========================================"
else
    echo ""
    echo "ERROR: Elaboration failed"
    exit 1
fi

exit 0
