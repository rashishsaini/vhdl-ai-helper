#!/bin/bash
# Test skeleton version

echo "========================================"
echo "Testing Skeleton code.vhd"
echo "========================================"

WORK_DIR="/tmp/cholesky_skeleton"
rm -rf $WORK_DIR
mkdir -p $WORK_DIR
cd $WORK_DIR

echo "Compiling: fixed_point_pkg_simple.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/fixed_point_pkg_simple.vhd

echo "Compiling: sqrt_newton_xsim.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/sqrt_newton_xsim.vhd

echo "Compiling: code_skeleton.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/code_skeleton.vhd

echo "Compiling: ultra_minimal_tb.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/ultra_minimal_tb.vhd

echo ""
echo "=== Elaborating Design ==="
xelab -debug typical xil_defaultlib.ultra_minimal_tb -s skeleton_sim

if [ $? -eq 0 ]; then
    echo ""
    echo "SUCCESS: Skeleton elaborated!"
    echo "========================================"
else
    echo ""
    echo "ERROR: Skeleton failed"
    exit 1
fi
