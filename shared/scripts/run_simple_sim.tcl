# TCL script to run simple_cholesky_tb simulation
# Uses XSIM-compatible modules

set design_name "simple_cholesky_sim"
set sim_top "simple_cholesky_tb"
set part "xc7a100tcsg324-1"

puts "========================================"
puts "Simple Cholesky Simulation Test"
puts "========================================"

# Create in-memory project
create_project -in_memory -part $part

puts "\n=== Adding Design Files ==="

# Add simplified fixed-point package (XSIM-compatible)
puts "Adding: fixed_point_pkg_simple.vhd"
read_vhdl /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/fixed_point_pkg_simple.vhd

# Add XSIM-compatible sqrt_newton
puts "Adding: sqrt_newton_xsim.vhd"
read_vhdl /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/sqrt_newton_xsim.vhd

# Add main Cholesky design
puts "Adding: code.vhd"
read_vhdl /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/code.vhd

# Add simple testbench
puts "Adding: simple_cholesky_tb.vhd"
read_vhdl /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/simple_cholesky_tb.vhd

puts "\n=== Checking Syntax ==="
update_compile_order -fileset sources_1

puts "\n=== Setting up Simulation ==="
set_property top $sim_top [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "\n=== Running Simulation ==="
launch_simulation

# Run simulation for sufficient time
run 10 us

puts "\n========================================"
puts "SIMULATION COMPLETE"
puts "========================================"

exit
