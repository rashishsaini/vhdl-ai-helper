---
name: vhdl-rl-iteration
description: Specialized workflow for automated VHDL hardware design refinement using recursive iteration with Vivado synthesis/simulation feedback. Use when Claude Code needs to iteratively improve VHDL modules through analysis of Vivado errors, synthesis reports, and testbench results. Supports syntax correction, testbench generation, error categorization, and intelligent iteration management with proper stopping conditions.
---

# VHDL RL Iteration Skill

Expert system for automated VHDL module refinement through recursive iteration with Vivado toolchain feedback.

## Core Principles

### What Can Be Automated
- **Syntax fixes**: Missing semicolons, type mismatches, signal declarations
- **Testbench generation**: Creating comprehensive test vectors and assertions
- **Code analysis**: Identifying architectural issues, suggesting improvements
- **Error categorization**: Distinguishing fixable issues from design constraints
- **Documentation**: Adding comments, improving code clarity

### What Cannot Be Automated (Requires Human)
- **Timing closure**: Physics constraints that need architectural changes
- **Resource optimization**: Fundamental design decisions about area/speed tradeoffs
- **Architectural problems**: FSM state encoding, pipeline depth, bus widths
- **Requirements clarification**: Understanding actual design intent
- **Technology-specific constraints**: FPGA-specific primitives, IP core issues

## Iteration Workflow

### Phase 1: Analysis
1. **Read all context**:
   ```bash
   # Read VHDL source
   cat module.vhd
   # Read testbench
   cat tb_module.vhd
   # Read Vivado logs
   cat vivado.log
   cat vivado.jou
   # Read previous iteration history if exists
   cat iteration_history.json
   ```

2. **Parse errors** using log parser:
   ```bash
   python scripts/parse_vivado_logs.py vivado.log
   ```

3. **Categorize errors** (see references/error_patterns.md):
   - **FIXABLE**: Syntax, missing signals, type mismatches
   - **TESTBENCH**: Test vector issues, timing problems in TB
   - **ARCHITECTURE**: Design-level issues requiring human input
   - **PHYSICS**: Timing, resource constraints beyond code fixes

### Phase 2: Decision Making

**Stop iteration if**:
- Error category is ARCHITECTURE or PHYSICS
- Same error appears 3+ times consecutively
- No progress in last 2 iterations
- Iteration count > 10

**Continue iteration if**:
- Error is FIXABLE or TESTBENCH
- Clear path to resolution
- Making measurable progress

### Phase 3: Implementation

**For FIXABLE errors**:
1. Apply targeted fixes using str_replace or create new file
2. Preserve all comments and original structure
3. Add explanatory comments for changes
4. Commit with descriptive message

**For TESTBENCH errors**:
1. Generate improved test vectors
2. Add assertions for edge cases
3. Ensure proper clocking and reset
4. Update testbench documentation

**For ARCHITECTURE/PHYSICS**:
1. Document the issue clearly
2. Provide human-readable analysis
3. Suggest architectural alternatives
4. Stop iteration and return control

### Phase 4: Validation

Before running Vivado:
```bash
# Quick syntax check with GHDL
ghdl -s module.vhd
ghdl -s tb_module.vhd

# Run linter if available
vhdl-linter module.vhd
```

After passing syntax:
```bash
# Run Vivado simulation
vivado -mode batch -source run.tcl

# Check results
grep "ERROR" vivado.log
grep "Simulation completed successfully" vivado.log
```

### Phase 5: Reporting

Generate iteration report:
```json
{
  "iteration": 3,
  "timestamp": "2025-11-21T10:30:00Z",
  "status": "success|failed|stopped",
  "error_category": "FIXABLE|TESTBENCH|ARCHITECTURE|PHYSICS",
  "changes_made": ["Fixed missing semicolon line 42", "Added reset logic"],
  "positives": ["Syntax errors resolved", "Testbench now compiles"],
  "negatives": ["Still has timing violation", "Resource usage high"],
  "confidence": 85,
  "next_action": "continue|stop|human_needed",
  "rationale": "Clear progress on syntax, but timing needs architectural review"
}
```

## Script Usage

### parse_vivado_logs.py
```bash
# Parse Vivado log and categorize errors
python scripts/parse_vivado_logs.py vivado.log --output errors.json

# With custom rules
python scripts/parse_vivado_logs.py vivado.log --rules custom_patterns.yaml
```

### vhdl_orchestrator.py
```bash
# Run full iteration cycle
python scripts/vhdl_orchestrator.py \
  --vhdl module.vhd \
  --testbench tb_module.vhd \
  --max-iterations 10 \
  --vivado-tcl run.tcl

# Continue from iteration N
python scripts/vhdl_orchestrator.py \
  --resume iteration_5/ \
  --max-iterations 15
```

### generate_testbench.py
```bash
# Auto-generate testbench from VHDL entity
python scripts/generate_testbench.py module.vhd --output tb_module.vhd

# With custom test vectors
python scripts/generate_testbench.py module.vhd --vectors test_vectors.yaml
```

## Prompt Engineering

### Analysis Prompt Template
```
You are analyzing VHDL code that failed Vivado simulation/synthesis.

Context:
- Iteration: {iteration_number}
- Previous attempts: {previous_fixes}

Files:
{vhdl_content}

Errors:
{parsed_errors}

Task:
1. Categorize each error (FIXABLE/TESTBENCH/ARCHITECTURE/PHYSICS)
2. For FIXABLE errors, provide exact fixes with line numbers
3. For others, explain why human intervention is needed
4. Assess whether to continue iteration

Response format:
{
  "error_analysis": [...],
  "category": "...",
  "fixes": [...],
  "continue_iteration": true/false,
  "rationale": "..."
}
```

### Fix Generation Template
```
Generate fixes for VHDL errors.

Rules:
- Preserve ALL existing comments
- Use VHDL-2008 syntax
- Add explanatory comments for changes
- Maintain original code structure
- No unnecessary reformatting

Error: {error_description}
Location: {file}:{line}

Provide fix as:
1. Old code (5 lines context)
2. New code (with fix)
3. Explanation (1-2 sentences)
```

## Error Pattern Reference

See `references/error_patterns.md` for comprehensive catalog including:
- Syntax errors (missing semicolons, keywords)
- Type mismatches (std_logic vs integer)
- Signal declaration issues
- Process sensitivity lists
- Timing violations
- Resource constraints
- Testbench common errors

## Best Practices

### Iteration Management
1. **Track progress**: Log every change with rationale
2. **Avoid loops**: Detect repeated errors early
3. **Be honest**: Stop when automation can't help
4. **Preserve history**: Keep all iteration artifacts

### Code Quality
1. **Comment changes**: Explain why fixes were applied
2. **Maintain style**: Don't reformat unnecessarily
3. **Test incrementally**: Validate each change
4. **Version control**: Commit after each iteration

### Communication
1. **Clear reports**: Human-readable iteration summaries
2. **Actionable diagnostics**: Specific next steps
3. **Honest assessment**: Admit when stuck
4. **Documentation**: Explain architectural issues

## Common Iteration Scenarios

### Scenario 1: Syntax Errors (2-3 iterations expected)
- Parse error locations
- Apply targeted fixes
- Validate with GHDL
- Run Vivado simulation

### Scenario 2: Testbench Issues (3-5 iterations expected)
- Analyze test vector coverage
- Generate additional test cases
- Fix timing in testbench
- Add assertions

### Scenario 3: Hit Architecture Limit (Stop immediately)
- Detect timing violations needing redesign
- Identify resource constraints beyond code
- Document issue clearly
- Return control to human

### Scenario 4: Stuck in Loop (Stop after 3 repeats)
- Detect same error recurring
- Analyze root cause
- Admit limitation
- Suggest human review

## Integration with Development Flow

### Standalone Usage
```bash
# Direct invocation
claude-code "Iterate on this VHDL module until Vivado simulation passes"
# Skill automatically activates and manages iteration
```

### Pipeline Integration
```bash
# Part of CI/CD
git commit -m "Initial VHDL implementation"
claude-code --skill vhdl-rl-iteration \
  "Refine module.vhd until tests pass, max 10 iterations"
# Results stored in iteration_history/
```

### Interactive Mode
```bash
# With human oversight
claude-code "Start VHDL iteration on module.vhd, check with me before applying fixes"
# Pause points: after analysis, before major changes, when stuck
```

## References

- **error_patterns.md**: Comprehensive error catalog with solutions
- **vhdl_style_guide.md**: Coding standards and best practices
- **vivado_tcl_reference.md**: TCL commands for automation
- **stopping_criteria.md**: Detailed rules for iteration termination

## Success Metrics

**Good iteration session**:
- 70%+ of simple syntax issues resolved automatically
- Clear stopping point identified for complex issues
- Complete iteration history with rationale
- Human-readable summary of what succeeded/failed

**Poor iteration session**:
- Looping on same error 5+ times
- Attempting to fix architectural issues with code tweaks
- No clear progress metric
- Unclear why iteration stopped
