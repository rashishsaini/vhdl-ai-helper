# Vivado XSIM Test Runner TCL Script
# Usage: vivado -mode batch -source vivado_run_test.tcl -tclargs <module_name>
# Example: vivado -mode batch -source vivado_run_test.tcl -tclargs power_unit

# Get module name from command line arguments
if { $argc != 1 } {
    puts "ERROR: Module name required"
    puts "Usage: vivado -mode batch -source vivado_run_test.tcl -tclargs <module_name>"
    puts "Example: vivado -mode batch -source vivado_run_test.tcl -tclargs power_unit"
    exit 1
}

set module_name [lindex $argv 0]
set tb_name "${module_name}_tb"

# Configuration
set base_dir [file dirname [file dirname [file normalize [info script]]]]
set src_dir "$base_dir/adam_modules"
set tb_dir "$base_dir/adam_testbenches"
set vivado_dir "$base_dir/simulation_results/vivado"
set log_dir "$vivado_dir/logs"

# Create log directory
file mkdir $log_dir
set log_file "$log_dir/${module_name}_vivado.log"

puts "=========================================="
puts "Vivado XSIM Test Runner"
puts "=========================================="
puts "Module:     $module_name"
puts "Testbench:  $tb_name"
puts "Log file:   $log_file"
puts "=========================================="
puts ""

# Navigate to Vivado work directory
cd $vivado_dir

# Check if testbench exists
set tb_file "$tb_dir/${tb_name}.vhd"
if { ![file exists $tb_file] } {
    puts "ERROR: Testbench not found: $tb_file"
    exit 1
}

# Step 1: Analyze testbench
puts "\[1/4\] Analyzing testbench..."
if { [catch {exec xvhdl -2008 $tb_file 2>@1} result] } {
    puts "ERROR: Testbench analysis failed"
    puts $result
    set log_fd [open $log_file a]
    puts $log_fd $result
    close $log_fd
    exit 1
}
set log_fd [open $log_file a]
puts $log_fd $result
close $log_fd
puts "  ✓ Analysis complete"

# Step 2: Elaborate testbench
puts "\[2/4\] Elaborating testbench..."
if { [catch {exec xelab -debug typical -top $tb_name -snapshot ${tb_name}_snapshot 2>@1} result] } {
    puts "ERROR: Testbench elaboration failed"
    puts $result
    set log_fd [open $log_file a]
    puts $log_fd $result
    close $log_fd
    exit 1
}
set log_fd [open $log_file a]
puts $log_fd $result
close $log_fd
puts "  ✓ Elaboration complete"

# Step 3: Create simulation script
set sim_tcl "$vivado_dir/${tb_name}_sim.tcl"
set sim_script [open $sim_tcl w]
puts $sim_script "run all"
puts $sim_script "quit"
close $sim_script

# Step 4: Run simulation
puts "\[3/4\] Running simulation..."
set sim_result 0
if { [catch {exec xsim ${tb_name}_snapshot -tclbatch $sim_tcl 2>@1} result] } {
    puts "WARNING: Simulation returned non-zero exit code"
    set sim_result 1
}
set log_fd [open $log_file a]
puts $log_fd $result
close $log_fd

# Check for errors in log
puts "\[4/4\] Checking results..."
set log_content [read [open $log_file r]]
if { [string match "*ERROR*" $log_content] || [string match "*FAILURE*" $log_content] } {
    set sim_result 1
}

puts ""
puts "=========================================="
if { $sim_result == 0 } {
    puts "✓ SIMULATION PASSED: $module_name"
    puts "=========================================="
    exit 0
} else {
    puts "✗ SIMULATION FAILED: $module_name"
    puts "=========================================="
    puts "Check log file: $log_file"
    exit 1
}
