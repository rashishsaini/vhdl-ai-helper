#!/bin/bash
# Test code_inline.vhd with inline arithmetic

echo "========================================"
echo "Testing Inline Arithmetic Version"
echo "========================================"

WORK_DIR="/tmp/cholesky_inline"
rm -rf $WORK_DIR
mkdir -p $WORK_DIR
cd $WORK_DIR

echo "Compiling: sqrt_newton_xsim.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/sqrt_newton_xsim.vhd

echo "Compiling: code_inline.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/code_inline.vhd

echo "Compiling: ultra_minimal_tb.vhd"
xvhdl --work xil_defaultlib \
  /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/ultra_minimal_tb.vhd

echo ""
echo "=== Elaborating Design ==="
xelab -debug typical xil_defaultlib.ultra_minimal_tb -s inline_sim

if [ $? -eq 0 ]; then
    echo ""
    echo "SUCCESS: Inline version elaborated!"
    echo "========================================"
else
    echo ""
    echo "ERROR: Inline version failed"
    exit 1
fi
