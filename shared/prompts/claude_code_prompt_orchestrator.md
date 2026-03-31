# Claude Code Prompt: VHDL Iteration Orchestrator

## Mission
Use the `vhdl_iteration_orchestrator.py` to intelligently manage VHDL development iterations. This orchestrator categorizes errors, determines what's fixable, and prevents infinite loops while maintaining a complete history of attempts.

## Initial Setup and Assessment

### Step 1: Prepare the Iteration Environment
```bash
# Create organized workspace
mkdir -p vhdl_iterations/{logs,fixed,testbenches,reports}

# Check for required tools
echo "Checking environment..."
which vivado || echo "WARNING: Vivado not found in PATH"
which python3 || echo "ERROR: Python3 required"

# Install the orchestrator
cp vhdl_iteration_orchestrator.py ./
chmod +x vhdl_iteration_orchestrator.py

# List your VHDL files
echo "Available VHDL files:"
find . -maxdepth 2 -name "*.vhd" -o -name "*.vhdl"
```

### Step 2: Analyze the Current Design
Before starting iterations, understand what we're working with:

```bash
# Read the main design file
DESIGN_FILE="[your_design.vhd]"
TESTBENCH_FILE="[your_testbench.vhd]"

echo "Analyzing: $DESIGN_FILE"
wc -l $DESIGN_FILE
grep -E "entity|component|process" $DESIGN_FILE

# Check existing error logs if any
if [ -f "vivado.log" ]; then
    echo "Existing errors found:"
    grep -E "ERROR:|CRITICAL" vivado.log | head -10
fi
```

### Step 3: Run the Orchestrator with Intelligent Categorization

```python
#!/usr/bin/env python3
import subprocess
import json
from pathlib import Path

# Initialize the orchestrator
orchestrator = VHDLIterationOrchestrator(
    project_dir="./",
    iteration_dir="./vhdl_iterations",
    max_iterations=5  # Stop after 5 attempts to prevent infinite loops
)

# Run first analysis
design_file = Path("[your_design.vhd]")
testbench_file = Path("[your_testbench.vhd]")

print("Starting intelligent VHDL iteration...")
```

### Step 4: Iteration Loop with Error Categorization

For each iteration, analyze and categorize errors properly:

```python
def analyze_iteration_results(log_file):
    """
    Parse Vivado log and categorize errors by fixability.
    This is CRUCIAL for knowing when to stop.
    """
    
    with open(log_file, 'r') as f:
        log_content = f.read()
    
    # Categorize errors
    error_analysis = {
        "syntax_errors": [],      # Can fix automatically
        "port_mismatches": [],     # Can fix automatically
        "missing_signals": [],     # Can fix automatically
        "type_mismatches": [],     # Sometimes fixable
        "timing_violations": [],   # CANNOT fix automatically
        "resource_overflow": [],   # CANNOT fix automatically
        "functional_bugs": []      # CANNOT fix automatically
    }
    
    # Parse and categorize each error
    # [Implementation here based on error patterns]
    
    # Make intelligent decision
    fixable_count = len(error_analysis["syntax_errors"]) + \
                    len(error_analysis["port_mismatches"]) + \
                    len(error_analysis["missing_signals"])
    
    unfixable_count = len(error_analysis["timing_violations"]) + \
                      len(error_analysis["resource_overflow"]) + \
                      len(error_analysis["functional_bugs"])
    
    return {
        "can_continue": fixable_count > 0 and unfixable_count == 0,
        "analysis": error_analysis,
        "recommendation": generate_recommendation(error_analysis)
    }
```

### Step 5: Generate Fixes for Each Error Category

#### For FIXABLE Errors (Syntax, Ports, Signals):
```vhdl
-- Original code with error:
signal data : std_logic_vector(7 downto 0)  -- Missing semicolon

-- Fixed code:
signal data : std_logic_vector(7 downto 0); -- FIXED: Added semicolon

-- Original code with port mismatch:
port_map => my_signal(15 downto 0)  -- But port expects 8 bits

-- Fixed code:
port_map => my_signal(7 downto 0)   -- FIXED: Corrected bit width
```

#### For UNFIXABLE Errors (Timing, Resources, Functional):
```python
def generate_manual_intervention_guide(error_type, details):
    """
    Instead of attempting to fix, provide actionable guidance.
    """
    
    if error_type == "timing_violation":
        return f"""
        TIMING VIOLATION DETECTED
        Critical Path: {details['path']}
        Slack: {details['slack']} ns
        
        MANUAL INTERVENTION REQUIRED:
        1. Add pipeline registers in the critical path
           - Identify combinational logic depth
           - Insert registers at logical boundaries
        2. Consider multicycle path constraints if applicable
        3. Review clock frequency requirements
        4. Examine synthesis optimization settings
        
        Example fix approach:
        -- Before (combinational):
        result <= complex_function(input_a, input_b);
        
        -- After (pipelined):
        process(clk)
        begin
            if rising_edge(clk) then
                stage1 <= partial_function(input_a);
                result <= final_function(stage1, input_b);
            end if;
        end process;
        """
    
    elif error_type == "resource_overflow":
        return f"""
        RESOURCE OVERFLOW DETECTED
        Resource: {details['resource_type']}
        Used: {details['used']}
        Available: {details['available']}
        
        MANUAL INTERVENTION REQUIRED:
        1. Implement resource sharing
           - Time-multiplex expensive operations
           - Share arithmetic units between processes
        2. Optimize bit widths
           - Review if all bits are necessary
           - Use appropriate data types
        3. Consider algorithmic changes
           - Different algorithm might use fewer resources
        4. Target larger device if necessary
        """
```

### Step 6: Detect and Handle Oscillations

```python
def detect_oscillation(iteration_history):
    """
    Detect if we're stuck in a fix-break-fix cycle.
    This is CRITICAL to avoid wasting time.
    """
    
    if len(iteration_history) < 3:
        return False
    
    # Check if error signatures repeat
    recent_errors = [set(h['error_types']) for h in iteration_history[-3:]]
    
    # If we see the same error pattern twice, we're oscillating
    if recent_errors[0] == recent_errors[2]:
        print("⚠️ OSCILLATION DETECTED!")
        print("The fixes are creating circular dependencies.")
        print("Manual architectural review required.")
        return True
    
    return False
```

### Step 7: Run Complete Iteration with Proper Stopping Conditions

```bash
# Main execution script
cat > run_vhdl_iteration.sh << 'EOF'
#!/bin/bash

DESIGN_FILE=$1
TESTBENCH_FILE=$2
MAX_ITERATIONS=5
ITERATION=0

echo "Starting VHDL Optimization Pipeline"
echo "====================================="

while [ $ITERATION -lt $MAX_ITERATIONS ]; do
    echo -e "\n--- Iteration $((ITERATION + 1)) ---"
    
    # Run synthesis
    vivado -mode batch -source synth.tcl 2>&1 | tee iteration_${ITERATION}.log
    
    # Check for errors
    ERROR_COUNT=$(grep -c "ERROR:" iteration_${ITERATION}.log)
    
    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ SUCCESS: No errors found!"
        break
    fi
    
    # Categorize errors
    SYNTAX_ERRORS=$(grep -c "Syntax error\|parse error" iteration_${ITERATION}.log)
    TIMING_ERRORS=$(grep -c "Timing constraint\|Setup violation" iteration_${ITERATION}.log)
    RESOURCE_ERRORS=$(grep -c "exceeded.*resources\|Insufficient" iteration_${ITERATION}.log)
    
    echo "Found: $SYNTAX_ERRORS syntax, $TIMING_ERRORS timing, $RESOURCE_ERRORS resource errors"
    
    # Decision logic
    if [ $SYNTAX_ERRORS -gt 0 ] && [ $TIMING_ERRORS -eq 0 ] && [ $RESOURCE_ERRORS -eq 0 ]; then
        echo "Attempting automatic fix for syntax errors..."
        # Call Claude Code to fix syntax
    elif [ $TIMING_ERRORS -gt 0 ] || [ $RESOURCE_ERRORS -gt 0 ]; then
        echo "❌ STOP: Non-fixable errors detected"
        echo "Timing errors: $TIMING_ERRORS"
        echo "Resource errors: $RESOURCE_ERRORS"
        echo "These require manual design changes."
        break
    fi
    
    ITERATION=$((ITERATION + 1))
done

echo -e "\nGenerating final report..."
EOF

chmod +x run_vhdl_iteration.sh
./run_vhdl_iteration.sh $DESIGN_FILE $TESTBENCH_FILE
```

### Step 8: Generate Comprehensive Iteration Report

```python
def generate_iteration_report(iteration_history):
    """
    Create an honest, actionable report of what was achieved.
    """
    
    report = """
# VHDL Iteration Report

## Summary
- Total Iterations: {total}
- Successful Fixes: {fixed_count}
- Remaining Issues: {remaining_count}

## Iteration Details
"""
    
    for i, iteration in enumerate(iteration_history):
        report += f"""
### Iteration {i+1}
- Errors Found: {iteration['error_count']}
- Fixed Automatically: {iteration['fixed_count']}
- Categories: {', '.join(iteration['error_categories'])}
"""
        
        if iteration.get('oscillation_detected'):
            report += """
⚠️ **OSCILLATION DETECTED**: Fixes are creating circular dependencies.
Manual intervention required to break the cycle.
"""
    
    # Add specific recommendations
    if has_timing_issues(iteration_history):
        report += """
## Timing Closure Recommendations
1. **Pipeline Critical Paths**
   - Add register stages in long combinational paths
   - Balance pipeline depth across parallel paths

2. **Optimize Logic**
   - Use dedicated hardware resources (DSP blocks)
   - Restructure arithmetic operations

3. **Adjust Constraints**
   - Review clock period requirements
   - Consider multicycle paths where appropriate
"""
    
    if has_resource_issues(iteration_history):
        report += """
## Resource Optimization Strategies
1. **Resource Sharing**
   - Time-multiplex expensive operations
   - Share arithmetic units

2. **Bit Width Optimization**
   - Review and minimize bit widths
   - Use appropriate numeric types

3. **Algorithmic Changes**
   - Consider alternative algorithms
   - Trade off between time and area
"""
    
    return report
```

### Step 9: Execute and Monitor Progress

```bash
# Run with real-time monitoring
python3 -u vhdl_iteration_orchestrator.py \
    --vhdl-file my_design.vhd \
    --testbench tb_my_design.vhd \
    --iterations 5 \
    --output-dir ./iterations \
    2>&1 | tee orchestration.log

# Monitor progress
tail -f orchestration.log | grep -E "Iteration|SUCCESS|WARNING|ERROR"

# Check iteration history
ls -la ./iterations/
for dir in ./iterations/iteration_*/; do
    echo "=== $(basename $dir) ==="
    cat "$dir/analysis.json" | python3 -m json.tool
done
```

### Step 10: Final Assessment and Next Steps

```bash
# Generate final actionable summary
cat > next_steps.md << 'EOF'
# Next Steps Based on Iteration Results

## ✅ Completed Automatically
- [ ] Syntax errors fixed
- [ ] Port connections corrected  
- [ ] Signal declarations added
- [ ] Testbench generated

## ⚠️ Requires Your Attention

### Timing Issues (if any)
- [ ] Review critical path report: timing.rpt
- [ ] Add pipeline stages where indicated
- [ ] Consider clock frequency reduction

### Resource Issues (if any)
- [ ] Review utilization report: utilization.rpt
- [ ] Implement resource sharing
- [ ] Optimize algorithm

### Functional Issues (if any)
- [ ] Review testbench failures
- [ ] Debug state machine logic
- [ ] Verify algorithm implementation

## Recommended Manual Actions
1. Focus on [highest priority issue]
2. Use generated testbench for verification
3. Iterate manually with insights from automation

Remember: Automation handles the mechanical fixes.
You handle the design decisions.
EOF
```

## Critical Success Factors

### WHEN TO CONTINUE ITERATING:
- Syntax errors only
- Simple structural issues
- Clear, mechanical fixes

### WHEN TO STOP AND GO MANUAL:
- Any timing violation appears
- Resource overflow detected
- Functional test failures
- Oscillation detected (same errors recurring)
- Reached iteration limit

### VALUE PROVIDED BY AUTOMATION:
- Eliminates tedious syntax fixes
- Generates comprehensive testbenches
- Provides clear error categorization
- Maintains iteration history
- Explains complex issues clearly

### WHAT STILL NEEDS HUMAN INTELLIGENCE:
- Architectural decisions
- Pipeline placement
- Algorithm optimization
- Resource sharing strategies
- Timing closure approaches

## Usage Example

```bash
# Basic usage
python3 vhdl_iteration_orchestrator.py my_design.vhd tb_my_design.vhd

# With specific options
python3 vhdl_iteration_orchestrator.py \
    --vhdl-file complex_design.vhd \
    --testbench tb_complex.vhd \
    --iterations 3 \
    --stop-on-timing \
    --generate-report

# Check results
cat ./iterations/iteration_report.md
```

This orchestrator provides the RIGHT level of automation - fixing what can be fixed, explaining what can't, and stopping before wasting time on impossible tasks.
