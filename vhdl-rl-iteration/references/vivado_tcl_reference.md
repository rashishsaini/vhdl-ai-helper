# Vivado TCL Automation Reference

Quick reference for Vivado TCL commands used in VHDL iteration.

## Basic Vivado Invocation

### Batch Mode (Non-Interactive)
```bash
vivado -mode batch -source run.tcl
vivado -mode batch -source run.tcl -log vivado.log -journal vivado.jou
```

### TCL Mode (Interactive)
```bash
vivado -mode tcl
```

### GUI Mode with Script
```bash
vivado -source init.tcl
```

## Project Management

### Create Project
```tcl
# Create new project
create_project my_project ./project_dir -part xc7a35ticsg324-1L

# Set project properties
set_property target_language VHDL [current_project]
set_property simulator_language VHDL [current_project]
```

### Add Files
```tcl
# Add VHDL source files
add_files {module.vhd helper.vhd}

# Add testbench (simulation only)
add_files -fileset sim_1 {tb_module.vhd}

# Add constraints
add_files -fileset constrs_1 {timing.xdc}
```

### Project Settings
```tcl
# Set top module
set_property top module_name [current_fileset]

# Set top testbench
set_property top tb_module [get_filesets sim_1]
```

## Simulation Commands

### Launch Simulation
```tcl
# Launch behavioral simulation
launch_simulation

# Launch post-synthesis simulation
launch_simulation -mode post-synthesis

# Launch post-implementation simulation
launch_simulation -mode post-implementation
```

### Run Simulation
```tcl
# Run for specific time
run 1000 ns
run 10 us
run all

# Restart simulation
restart

# Close simulation
close_sim
```

### Simulation Results
```tcl
# Get simulation errors
get_value /tb_module/error_count

# Check for assertion failures
if {[get_value /tb_module/test_failed] == 1} {
    puts "ERROR: Test failed"
    exit 1
}
```

## Synthesis Commands

### Run Synthesis
```tcl
# Synthesize design
synth_design -top module_name -part xc7a35ticsg324-1L

# With additional options
synth_design -top module_name \
             -part xc7a35ticsg324-1L \
             -flatten_hierarchy rebuilt \
             -keep_equivalent_registers
```

### Synthesis Reports
```tcl
# Utilization report
report_utilization -file utilization.rpt

# Timing summary
report_timing_summary -file timing_summary.rpt

# DRC (Design Rule Check)
report_drc -file drc.rpt
```

## Implementation Commands

### Run Implementation
```tcl
# Optimize design
opt_design

# Place design
place_design

# Route design
route_design
```

### Implementation Reports
```tcl
# Timing analysis
report_timing -file timing.rpt -max_paths 10

# Power analysis
report_power -file power.rpt

# Final utilization
report_utilization -file final_utilization.rpt
```

## Error Handling

### Check for Errors
```tcl
# Check synthesis status
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed"
    exit 1
}

# Check for critical warnings
set crit_warn [get_msg_config -count -severity {CRITICAL WARNING}]
if {$crit_warn > 0} {
    puts "WARNING: $crit_warn critical warnings found"
}
```

### Log Parsing
```tcl
# Write all messages to file
set log_file [open "messages.log" w]
foreach msg [get_msg_config -id * -severity ERROR] {
    puts $log_file $msg
}
close $log_file
```

## Complete Iteration Script Templates

### Template 1: Simulation Only
```tcl
# simulation_only.tcl
# Quick simulation for iteration

# Create project
create_project -force iteration_project ./project -part xc7a35ticsg324-1L
set_property target_language VHDL [current_project]

# Add files
add_files {module.vhd}
add_files -fileset sim_1 {tb_module.vhd}

# Set tops
set_property top module_name [current_fileset]
set_property top tb_module [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Launch simulation
launch_simulation

# Run simulation
run 1000 ns

# Check results
set test_status [get_value /tb_module/test_passed]
if {$test_status == 1} {
    puts "SUCCESS: Simulation passed"
    exit 0
} else {
    puts "ERROR: Simulation failed"
    exit 1
}
```

### Template 2: Synthesis Check
```tcl
# synthesis_check.tcl
# Syntax and synthesis check

# Create project
create_project -force synth_check ./project -part xc7a35ticsg324-1L
set_property target_language VHDL [current_project]

# Add files
add_files {module.vhd helper.vhd}
set_property top module_name [current_fileset]

# Run synthesis
synth_design -top module_name -part xc7a35ticsg324-1L

# Check status
set status [get_property STATUS [get_runs synth_1]]
if {$status == "synth_design Complete!"} {
    puts "SUCCESS: Synthesis passed"
    
    # Generate reports
    report_utilization -file utilization.rpt
    report_timing_summary -file timing.rpt
    
    exit 0
} else {
    puts "ERROR: Synthesis failed"
    exit 1
}
```

### Template 3: Full Flow with Error Handling
```tcl
# full_flow.tcl
# Complete synthesis, implementation, and timing check

# Error handling procedure
proc handle_error {stage} {
    puts "ERROR: Failed at $stage"
    
    # Dump error messages
    set errors [get_msg_config -id * -severity ERROR]
    foreach err $errors {
        puts "  $err"
    }
    
    exit 1
}

# Create project
create_project -force full_flow ./project -part xc7a35ticsg324-1L
set_property target_language VHDL [current_project]

# Add files
add_files {module.vhd}
add_files -fileset constrs_1 {timing.xdc}
set_property top module_name [current_fileset]

# Synthesis
puts "Running synthesis..."
if {[catch {synth_design -top module_name -part xc7a35ticsg324-1L}]} {
    handle_error "synthesis"
}

report_utilization -file utilization_post_synth.rpt

# Check resource usage
set lut_used [get_property LUT [get_cells]]
puts "LUTs used: $lut_used"

# Implementation
puts "Running implementation..."
if {[catch {opt_design}]} { handle_error "optimization" }
if {[catch {place_design}]} { handle_error "placement" }
if {[catch {route_design}]} { handle_error "routing" }

# Timing analysis
puts "Checking timing..."
set timing_met [get_property SLACK [get_timing_paths]]
if {$timing_met < 0} {
    puts "ERROR: Timing not met, slack = $timing_met"
    report_timing -file timing_violations.rpt -max_paths 10
    exit 1
}

puts "SUCCESS: Design meets timing"
report_timing_summary -file timing_summary.rpt
report_utilization -file utilization_final.rpt

exit 0
```

## Useful Helper Procedures

### Check Compilation
```tcl
proc check_compile {} {
    set errors 0
    foreach file [get_files *.vhd] {
        if {[catch {check_syntax $file}]} {
            puts "ERROR: Syntax error in $file"
            incr errors
        }
    }
    return $errors
}
```

### Extract Error Messages
```tcl
proc extract_errors {} {
    set error_list {}
    
    # Get all errors
    set msgs [get_msg_config -id * -severity ERROR]
    foreach msg $msgs {
        lappend error_list $msg
    }
    
    # Get critical warnings
    set msgs [get_msg_config -id * -severity {CRITICAL WARNING}]
    foreach msg $msgs {
        lappend error_list $msg
    }
    
    return $error_list
}
```

### Timing Check
```tcl
proc check_timing {required_freq_mhz} {
    # Calculate required period in ns
    set required_period [expr {1000.0 / $required_freq_mhz}]
    
    # Get worst slack
    set wns [get_property SLACK [get_timing_paths -max_paths 1]]
    
    if {$wns < 0} {
        puts "ERROR: Timing not met"
        puts "  Required period: ${required_period} ns"
        puts "  Worst slack: ${wns} ns"
        return 0
    } else {
        puts "SUCCESS: Timing met"
        puts "  Worst slack: ${wns} ns"
        return 1
    }
}
```

## Quick Commands for Debugging

### List Current Status
```tcl
# List all files
get_files

# List synthesis runs
get_runs

# Current project info
report_property [current_project]
```

### Check Messages
```tcl
# All errors
get_msg_config -id * -severity ERROR

# All critical warnings
get_msg_config -id * -severity {CRITICAL WARNING}

# Count of errors
get_msg_config -count -severity ERROR
```

### Resource Queries
```tcl
# Get utilization
get_property USED [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ LUT*}]

# Get clock info
get_clocks

# Get timing paths
get_timing_paths -max_paths 10
```

## Integration with Python Orchestrator

### Python Subprocess Call
```python
import subprocess

result = subprocess.run(
    ['vivado', '-mode', 'batch', '-source', 'run.tcl'],
    capture_output=True,
    text=True,
    timeout=300
)

# Check return code
if result.returncode == 0:
    print("Success")
else:
    print(f"Failed: {result.stderr}")
```

### Pass Parameters to TCL
```python
# Python side
vivado_cmd = [
    'vivado', '-mode', 'batch',
    '-source', 'run.tcl',
    '-tclargs', 'module_name', 'xc7a35t'
]

subprocess.run(vivado_cmd)
```

```tcl
# TCL side (run.tcl)
set module_name [lindex $argv 0]
set part [lindex $argv 1]

puts "Module: $module_name"
puts "Part: $part"
```

## Best Practices for Iteration

1. **Always use batch mode** for automation
2. **Capture all output** to log files
3. **Check return codes** for errors
4. **Use timeouts** to prevent hanging
5. **Generate reports** for analysis
6. **Clean up** between iterations

## Common Issues and Solutions

### Issue: Vivado GUI Opens
```tcl
# Solution: Use -mode batch
vivado -mode batch -source script.tcl
```

### Issue: Files Not Found
```tcl
# Solution: Use absolute paths or cd first
cd [file dirname [info script]]
add_files [file join [pwd] "module.vhd"]
```

### Issue: Slow Synthesis
```tcl
# Solution: Use quick synthesis mode for iteration
synth_design -mode out_of_context  # Faster for module testing
```

### Issue: Memory/License Issues
```bash
# Solution: Set environment variables
export XILINX_LOCAL_USER_DATA=no
ulimit -s unlimited
```
