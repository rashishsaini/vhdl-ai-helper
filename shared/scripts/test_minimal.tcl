# Test minimal design without custom package
set part "xc7a100tcsg324-1"
create_project -in_memory -part $part

puts "=== Testing MINIMAL Design (No Package, No Sqrt) ==="
read_vhdl /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/code_minimal.vhd
read_vhdl /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.srcs/sources_1/new/minimal_tb.vhd

update_compile_order -fileset sources_1

puts "=== Compilation Complete ==="
exit
