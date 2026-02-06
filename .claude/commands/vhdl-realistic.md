# Claude Code Prompt: Realistic VHDL Automation Helper

## Context Setup
I need you to help me automate VHDL development using the `vhdl_claude_helper.py` script. This script provides realistic automation for syntax fixes, testbench generation, and code analysis - focusing on what AI can actually do well for hardware design.

## FIRST: Ask for File Paths

Before starting, ask the user for the following file paths:

**Please provide the following information:**
1. **VHDL module file path**: (Required - e.g., `./src/counter.vhd`)
2. **Existing testbench path**: (Optional - I can generate a comprehensive one)
3. **What should I focus on?**: (Choose: Syntax fixes | Testbench generation | Error analysis)

Wait for the user to provide these paths before proceeding.

---

## Your Task

### Step 1: Environment Analysis
First, check my environment and VHDL files:
```bash
# Check if Vivado is installed and accessible
which vivado
vivado -version

# List all VHDL files in current directory
find . -name "*.vhd" -o -name "*.vhdl" | head -20

# Check for any existing Vivado project files
find . -name "*.xpr" | head -5

# Look for synthesis/simulation logs
find . -name "*.log" | grep -E "(synth|sim)" | head -10
```

### Step 2: Analyze VHDL Code Issues
For each VHDL file I'm working with, analyze it and identify issues:

1. **Read the main VHDL module:**
```bash
cat [MY_VHDL_FILE.vhd]
```

2. **Check for common syntax issues that you CAN fix:**
   - Missing semicolons or keywords
   - Undeclared signals (add declarations)
   - Port size mismatches (fix connections)
   - Type conversion issues (add conversions)
   - Missing sensitivity list items
   - Incomplete case statements

3. **Identify but DON'T attempt to fix:**
   - Timing violations (explain them instead)
   - Resource utilization issues (provide analysis only)
   - Functional logic bugs (suggest debug approaches)

### Step 3: Fix Syntax and Structural Issues
Create a fixed version focusing ONLY on what's automatable:

```vhdl
-- Generate the complete fixed VHDL here
-- Include comments like:
-- FIXED: Added missing semicolon on line X
-- FIXED: Declared signal 'data_valid'
-- FIXED: Corrected port width mismatch
-- CANNOT FIX (Manual Required): Timing violation on critical path
```

Save the fixed file:
```bash
# Create backup of original
cp [original.vhd] [original_backup.vhd]

# Write the fixed version
cat > [fixed_original.vhd] << 'EOF'
[Insert fixed VHDL code here]
EOF

# Show what changed
diff [original_backup.vhd] [fixed_original.vhd]
```

### Step 4: Generate Comprehensive Testbench
This is where you can provide MAXIMUM value. Create an excellent testbench:

```vhdl
-- Generate a testbench that includes:
-- 1. Clock generation (parametrizable frequency)
-- 2. Reset sequence
-- 3. Directed tests for normal operation
-- 4. Edge cases (boundary values, overflow, underflow)
-- 5. Random tests with constraints
-- 6. Self-checking assertions
-- 7. Coverage tracking
-- 8. Clear PASS/FAIL reporting
-- 9. Waveform annotations for debugging
```

Save the testbench:
```bash
cat > tb_[module_name].vhd << 'EOF'
[Insert comprehensive testbench here]
EOF
```

### Step 5: Run Synthesis and Parse Errors
Execute Vivado synthesis and analyze results:

```bash
# Create a simple TCL script for synthesis
cat > quick_synth.tcl << 'EOF'
create_project -force test_proj ./test_proj -part xc7a100tcsg324-1
add_files [YOUR_VHDL_FILE]
update_compile_order -fileset sources_1
synth_design -top [YOUR_TOP_MODULE]
report_timing_summary -file timing.rpt
report_utilization -file utilization.rpt
exit
EOF

# Run synthesis
vivado -mode batch -source quick_synth.tcl 2>&1 | tee synthesis.log

# Extract and categorize errors
grep -E "ERROR:|WARNING:|CRITICAL" synthesis.log > errors_summary.txt
```

### Step 6: Categorize Errors and Provide Honest Assessment

After parsing the errors, categorize them and be HONEST about what can be fixed:

```python
# Use this categorization logic:
error_categories = {
    "FIXABLE_AUTOMATICALLY": [
        # List syntax errors, missing declarations, port mismatches
    ],
    "REQUIRES_ANALYSIS": [
        # List timing issues, explain critical paths
    ],
    "NEEDS_MANUAL_INTERVENTION": [
        # List resource issues, functional bugs, architectural problems
    ]
}
```

### Step 7: Iteration Decision
Based on the error analysis, decide whether to iterate:

```bash
# Count fixable vs unfixable errors
FIXABLE=$(grep -c "syntax\|undeclared\|port" errors_summary.txt)
UNFIXABLE=$(grep -c "timing\|resource\|LUT" errors_summary.txt)

echo "Fixable errors: $FIXABLE"
echo "Unfixable errors (need manual work): $UNFIXABLE"

if [ $FIXABLE -gt 0 ] && [ $UNFIXABLE -eq 0 ]; then
    echo "Running another iteration to fix remaining syntax issues..."
    # Proceed with fixes
elif [ $UNFIXABLE -gt 0 ]; then
    echo "STOPPING: Remaining issues require design decisions:"
    echo "- Timing: Consider pipelining or clock frequency reduction"
    echo "- Resources: Consider algorithmic optimization or larger device"
    echo "- Functional: Review your state machines and data flow"
fi
```

### Step 8: Generate Improvement Report
Create a realistic assessment of what was achieved:

```markdown
## VHDL Automation Report

### Successfully Fixed (Automated)
- [List all syntax fixes]
- [List all structural fixes]

### Generated Assets
- Comprehensive testbench with X test cases
- Self-checking assertions for Y conditions

### Requires Manual Intervention
- **Timing Issues**: [Explain specific paths and suggested fixes]
- **Resource Usage**: [Explain utilization and optimization strategies]
- **Functional Issues**: [Describe verification failures and debug approach]

### Recommended Next Steps
1. [Specific manual fixes needed]
2. [Design decisions required]
3. [Verification strategy]
```

## Important Principles

1. **BE HONEST**: If something requires architectural understanding, say so. Don't pretend to fix timing with syntax changes.

2. **FOCUS ON STRENGTHS**:
   - Excellent at testbench generation
   - Great at syntax fixes
   - Good at explaining complex errors

3. **AVOID FALSE PROMISES**:
   - Don't claim to fix timing automatically
   - Don't promise resource optimization through code tweaks
   - Don't attempt functional bug fixes without understanding intent

4. **PROVIDE VALUE WHERE POSSIBLE**:
   - Generate comprehensive test scenarios
   - Create clear documentation
   - Explain errors in plain English

## Example Usage

```bash
# Initial setup
python3 vhdl_claude_helper.py

# For a specific module
./fix_vhdl.sh my_design.vhd

# Check results
cat fixed_my_design.vhd
cat tb_my_design.vhd
```

## Output Format

Always structure your response as:
1. What I CAN fix (with actual fixes)
2. What I CANNOT fix (with explanations)
3. What you need to do manually (with specific guidance)
4. Generated testbench and verification code

This honest approach saves time by focusing automation where it actually works.
