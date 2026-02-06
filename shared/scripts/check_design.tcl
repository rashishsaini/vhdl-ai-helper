# Quick VHDL Design Check Script
set design_name "cholesky_check"
set output_dir "./vhdl_iterations/logs"
file mkdir $output_dir

puts "========================================"
puts "VHDL Design Compilation Check"
puts "========================================"

set part "xc7a100tcsg324-1"
create_project -in_memory -part $part

puts "\n=== Adding Files ==="
puts "Adding: fixed_point_pkg.vhd"
read_vhdl /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/fixed_point_pkg.vhd

puts "Adding: sqrt_newton (NewtonRaphson.vhd)"
read_vhdl /home/arunupscee/vivado/rootNewton/rootNewton.srcs/sources_1/new/NewtonRaphson.vhd

puts "Adding: cholesky_3x3 (code.vhd)"
read_vhdl /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/code.vhd

puts "Adding: comprehensive_cholesky_tb"
read_vhdl /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/comprehensive_cholesky_tb.vhd

puts "\n=== Checking Syntax ==="
update_compile_order -fileset sources_1

puts "\n========================================"
puts "COMPILATION CHECK COMPLETE"
puts "========================================"
exit
