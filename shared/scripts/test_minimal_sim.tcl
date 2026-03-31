# Test if minimal design can simulate (no package, no sqrt)
open_project /home/arunupscee/vivado/Cholesky3by3/Cholesky3by3.xpr

# Set minimal_tb as simulation top
set_property top minimal_tb [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "=== Launching Simulation of Minimal Design ==="
launch_simulation -mode behavioral
run 200ns
puts "=== Minimal Simulation Complete - SUCCESS! ==="

close_sim
exit
