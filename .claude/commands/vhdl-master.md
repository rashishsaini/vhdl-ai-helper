# Claude Code Master Prompt for VHDL Development

## Context
You are assisting with VHDL development using two automation scripts:
1. `vhdl_iteration_orchestrator.py` - Full automation framework with error categorization
2. `vhdl_claude_helper.py` - Focused tools for specific tasks that work well

## FIRST: Ask for File Paths

Before starting, ask the user for the following file paths:

**Please provide the following information:**
1. **VHDL source file path**: (Required - e.g., `./design/my_module.vhd`)
2. **Testbench file path**: (Optional - leave blank if none exists)
3. **Vivado log file path**: (Optional - leave blank if you want me to run synthesis first)

Wait for the user to provide these paths before proceeding.

---

## Your Current Task

### Step 1: Initial Assessment
Once you have the file paths, read the following files and assess what type of assistance is needed:
- VHDL source file: [USER_PROVIDED_PATH]
- Testbench (if exists): [USER_PROVIDED_PATH]
- Vivado log file: [USER_PROVIDED_PATH]

Based on the Vivado errors, categorize them using these categories:
- **SYNTAX**: Missing semicolons, keywords, typos (AUTOMATED FIX POSSIBLE)
- **PORT_MISMATCH**: Port size/connection issues (AUTOMATED FIX POSSIBLE)
- **MISSING_SIGNAL**: Undeclared signals (AUTOMATED FIX POSSIBLE)
- **TYPE_MISMATCH**: Type conversion needed (MAYBE FIXABLE)
- **TIMING**: Setup/hold violations (MANUAL FIX REQUIRED)
- **RESOURCE**: Exceeds FPGA resources (MANUAL FIX REQUIRED)
- **FUNCTIONAL**: Behavioral issues (MANUAL FIX REQUIRED)

### Step 2: Determine Appropriate Action

Based on error categories, choose ONE of these approaches:

#### Approach A: Automated Fix (if >70% errors are SYNTAX/PORT/SIGNAL)
```python
# Use vhdl_iteration_orchestrator.py for automated fixing
# Maximum 2 iterations - if not fixed by then, switch to Approach C

import vhdl_iteration_orchestrator as orchestrator

# Run automated fix attempt
orchestrator.run_iteration(vhdl_file, testbench_file)
```

Provide fixed VHDL code with:
- All syntax errors corrected
- Missing signals declared with appropriate types
- Port connections fixed to match interfaces
- Comments explaining each fix

#### Approach B: Testbench Generation (if no testbench exists)
```python
# Use vhdl_claude_helper.py for testbench generation
# This is where AI assistance provides maximum value

import vhdl_claude_helper as helper

# Generate comprehensive testbench
helper.generate_comprehensive_testbench(vhdl_file)
```

Generate a testbench including:
1. Clock generation (appropriate frequency)
2. Reset sequence
3. Directed test vectors for normal operation
4. Edge cases (boundary values, overflow conditions)
5. Random constrained stimulus
6. Self-checking assertions
7. File I/O for test vectors if appropriate
8. Clear PASS/FAIL reporting

#### Approach C: Analysis and Recommendations (if errors are TIMING/RESOURCE/FUNCTIONAL)
```python
# Use helper for analysis, not fixes
# Be honest about what requires manual intervention

import vhdl_claude_helper as helper

# Analyze but don't attempt to fix
helper.analyze_timing_issues(timing_report)
```

Provide:
1. Plain English explanation of each issue
2. Root cause analysis
3. Architectural recommendations (not implementations):
   - Where to add pipeline stages (specific signal paths)
   - Which combinational logic chains to break
   - Resource sharing opportunities
4. Priority order for addressing issues
5. Clear statement: "These require manual architectural changes"

### Step 3: Output Format

Structure your response as follows:

```markdown
## Error Analysis
- Total errors found: [NUMBER]
- Fixable by automation: [NUMBER]
- Require manual intervention: [NUMBER]

## Category Breakdown
- Syntax errors: [COUNT] ✅ Auto-fixable
- Port mismatches: [COUNT] ✅ Auto-fixable
- Missing signals: [COUNT] ✅ Auto-fixable
- Type mismatches: [COUNT] ⚠️ Maybe fixable
- Timing violations: [COUNT] ❌ Manual fix required
- Resource issues: [COUNT] ❌ Manual fix required
- Functional bugs: [COUNT] ❌ Manual fix required

## Recommended Approach
[Choose: Automated Fix | Testbench Generation | Analysis Only]

## Implementation
[Provide the appropriate output based on approach]

## What You Need to Do Manually
[List specific manual interventions required]
```

### Step 4: Iteration Control

**IMPORTANT RULES**:
1. Never attempt more than 2 iterations of automated fixes
2. If timing/resource errors exist, do not attempt fixes - only analyze
3. If the same error appears in iteration 2 that was "fixed" in iteration 1, STOP
4. When generating testbenches, make them self-checking (don't require manual review)
5. Be explicit about what cannot be automated

### Special Commands

If the user asks for parallel processing, explain:
"Parallel Claude Code execution works for:
- Analyzing multiple independent modules (read-only operations)
- Generating testbenches for multiple modules

It does NOT work for:
- Fixing the same module multiple ways (creates conflicts)
- Iterating on fixes that depend on previous fixes"
