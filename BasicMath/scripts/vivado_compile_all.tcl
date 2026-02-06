# Vivado XSIM Compilation Script
# Compiles all VHDL modules in dependency order
# Usage: vivado -mode batch -source vivado_compile_all.tcl

# Configuration
set base_dir [file dirname [file dirname [file normalize [info script]]]]
set src_dir "$base_dir"
set adam_dir "$base_dir/adam_modules"
set vivado_dir "$base_dir/simulation_results/vivado"

puts "=========================================="
puts "Vivado XSIM Compilation Script"
puts "=========================================="
puts "Base directory: $base_dir"
puts "Vivado work:    $vivado_dir"
puts "=========================================="
puts ""

# Create work directory
file mkdir $vivado_dir
cd $vivado_dir

# Compilation order (dependencies first)
# Layer 1: Base primitives (no dependencies)
set layer1_files [list \
    "$src_dir/mac_unit.vhd" \
    "$src_dir/sqrt_unit.vhd" \
    "$adam_dir/reciprocal_unit.vhd" \
    "$src_dir/division_unit.vhd" \
]

# Layer 2: Power unit and register bank (no dependencies)
set layer2_files [list \
    "$adam_dir/power_unit.vhd" \
    "$adam_dir/moment_register_bank.vhd" \
]

# Layer 3: Units with single dependencies
set layer3_files [list \
    "$adam_dir/moment_update_unit.vhd" \
]

# Layer 4: Bias correction and adaptive LR (multiple dependencies)
set layer4_files [list \
    "$adam_dir/bias_correction_unit.vhd" \
    "$adam_dir/adaptive_lr_unit.vhd" \
]

# Layer 5: Integration units
set layer5_files [list \
    "$adam_dir/adam_update_unit.vhd" \
]

# Layer 6: Top-level
set layer6_files [list \
    "$adam_dir/adam_optimizer.vhd" \
]

# Compile function
proc compile_vhdl_file {filename layer} {
    puts ""
    puts "----------------------------------------"
    puts "Layer $layer: Compiling [file tail $filename]..."
    puts "----------------------------------------"

    if { ![file exists $filename] } {
        puts "ERROR: File not found: $filename"
        return 1
    }

    if { [catch {exec xvhdl -2008 $filename 2>@1} result] } {
        puts "ERROR: Compilation failed for $filename"
        puts $result
        return 1
    }

    puts $result
    puts "✓ Success"
    return 0
}

# Compile all layers
set total_files 0
set failed_files 0

puts "\n=========================================="
puts "LAYER 1: Base Primitives"
puts "=========================================="
foreach file $layer1_files {
    incr total_files
    if { [compile_vhdl_file $file 1] != 0 } {
        incr failed_files
    }
}

puts "\n=========================================="
puts "LAYER 2: Power Unit and Register Bank"
puts "=========================================="
foreach file $layer2_files {
    incr total_files
    if { [compile_vhdl_file $file 2] != 0 } {
        incr failed_files
    }
}

puts "\n=========================================="
puts "LAYER 3: Moment Update Unit"
puts "=========================================="
foreach file $layer3_files {
    incr total_files
    if { [compile_vhdl_file $file 3] != 0 } {
        incr failed_files
    }
}

puts "\n=========================================="
puts "LAYER 4: Bias Correction and Adaptive LR"
puts "=========================================="
foreach file $layer4_files {
    incr total_files
    if { [compile_vhdl_file $file 4] != 0 } {
        incr failed_files
    }
}

puts "\n=========================================="
puts "LAYER 5: Adam Update Unit"
puts "=========================================="
foreach file $layer5_files {
    incr total_files
    if { [compile_vhdl_file $file 5] != 0 } {
        incr failed_files
    }
}

puts "\n=========================================="
puts "LAYER 6: Adam Optimizer"
puts "=========================================="
foreach file $layer6_files {
    incr total_files
    if { [compile_vhdl_file $file 6] != 0 } {
        incr failed_files
    }
}

# Summary
puts ""
puts "=========================================="
puts "Compilation Summary"
puts "=========================================="
puts "Total files:    $total_files"
puts "Failed:         $failed_files"
puts "Successful:     [expr {$total_files - $failed_files}]"
puts "=========================================="

if { $failed_files == 0 } {
    puts "✓ ALL MODULES COMPILED SUCCESSFULLY"
    puts "=========================================="
    exit 0
} else {
    puts "✗ COMPILATION FAILED"
    puts "=========================================="
    exit 1
}
