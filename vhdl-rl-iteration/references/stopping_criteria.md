# Iteration Stopping Criteria

Detailed rules for when to stop VHDL iteration loops.

## Core Principle

**Stop iterating when continued automation won't help.** The goal is honest assessment of when AI can contribute vs when human expertise is required.

## Stopping Criteria Categories

### 1. Success Criteria (Good Stops)

#### A. All Tests Pass
```
Condition: Vivado simulation/synthesis completes with no errors
Evidence:
- Return code = 0
- No ERROR or FATAL messages in log
- All assertions pass
- Simulation completes successfully

Action: STOP with success status
Rationale: Goal achieved
```

#### B. Iteration Limit Reached with Progress
```
Condition: Max iterations reached but making progress
Evidence:
- Iteration count >= max_iterations
- Error count decreasing each iteration
- Different errors being fixed

Action: STOP but flag as "partial success"
Rationale: Made progress but needs more iterations
Recommendation: Increase max_iterations and resume
```

### 2. Constraint Criteria (Must Stop)

#### A. Physical Constraints Detected
```
Condition: PHYSICS category errors present
Evidence:
- Timing violations (setup/hold)
- Resource overflow (LUT/BRAM/DSP)
- Routing failures
- Clock distribution issues

Action: STOP immediately
Rationale: Cannot be fixed with code changes alone
Next Steps:
1. Document timing/resource requirements
2. Suggest architectural alternatives:
   - Reduce clock frequency
   - Add pipeline stages
   - Simplify logic
   - Use larger device
```

**Example Stop Message**:
```
⏹️  STOP: Physical constraints detected

Issues found:
- Setup time violation: -2.3 ns slack on critical path
- Requires 15000 LUTs, device has 10000

These cannot be fixed with code iteration. Required actions:
1. Reduce clock frequency from 250 MHz to 200 MHz, or
2. Add pipeline stage to critical path, or
3. Migrate to larger FPGA device

Architectural review required.
```

#### B. Architecture Issues Detected
```
Condition: ARCHITECTURE category errors present
Evidence:
- FSM encoding decisions needed
- Bus width selection required
- Pipeline depth optimization
- Memory hierarchy design

Action: STOP immediately
Rationale: Requires design decisions, not code fixes
Next Steps:
1. Document design choices needed
2. Present alternatives with tradeoffs
3. Return control to human designer
```

**Example Stop Message**:
```
⏹️  STOP: Architectural decisions required

Issues found:
- FSM with 50 states needs encoding strategy
- Data path width insufficient for required throughput

Design decisions needed:
1. FSM encoding:
   - One-hot: Faster but uses more LUTs
   - Binary: Compact but slower
   - Gray: Low power but complex
2. Data path:
   - Widen to 32-bit: Higher throughput, more resources
   - Keep 16-bit: Lower resources, pipeline needed

Human designer input required.
```

### 3. Stagnation Criteria (Should Stop)

#### A. Repeated Error Pattern (Loop Detection)
```
Condition: Same error appearing 3+ consecutive iterations
Evidence:
- Error hash matches previous iterations
- Same line numbers failing
- Identical error messages

Action: STOP after 3 repeats
Rationale: Stuck in a loop, automation not helping
Next Steps:
1. Analyze why fix isn't working
2. Check if error is actually fixable
3. Suggest human review of specific issue
```

**Example Stop Message**:
```
⚠️  STOP: Stuck in error loop

Same error repeated for 3 iterations:
Line 42: Type mismatch - integer vs std_logic

Attempted fixes:
- Iteration 5: Added type conversion
- Iteration 6: Changed signal type
- Iteration 7: Modified conversion function

All fixes failed. This likely requires:
- Understanding of upstream signal source
- Architectural decision on data types
- Human review of interface specifications
```

#### B. No Progress for 2 Iterations
```
Condition: Error count unchanged for 2+ iterations
Evidence:
- Same number of errors
- Same error types
- No measurable improvement

Action: STOP after 2 stagnant iterations
Rationale: Fixes not effective
Next Steps:
1. Review what was attempted
2. Check if problem is actually solvable
3. Get human assessment
```

**Example Stop Message**:
```
⚠️  STOP: No progress in last 2 iterations

Error count stable at 5 errors:
- Iteration 8: 5 errors
- Iteration 9: 5 errors (attempted signal declaration fixes)
- Iteration 10: 5 errors (attempted type conversions)

Current approach not working. Recommend:
- Human review of error patterns
- Possible testbench issue
- May need different solution strategy
```

#### C. Oscillating Fixes
```
Condition: Alternating between two states
Evidence:
- Fix in iteration N
- Breaks again in iteration N+1
- Same as iteration N-1

Action: STOP after 2 oscillations
Rationale: Fix creates new problem, automation in conflict
Next Steps:
1. Identify conflicting constraints
2. Analyze root cause
3. Need human to resolve conflict
```

**Example Stop Message**:
```
⚠️  STOP: Oscillating between fixes

Pattern detected:
- Iteration 5: Fixed type mismatch, broke sensitivity list
- Iteration 6: Fixed sensitivity list, broke type mismatch
- Iteration 7: Fixed type mismatch, broke sensitivity list again

This indicates conflicting requirements that need human analysis.
```

### 4. Confidence Criteria (Should Stop)

#### A. Low Confidence in Fixes
```
Condition: LLM confidence score < 60% for 2+ iterations
Evidence:
- Confidence scores: 55%, 58%, 52%
- Uncertainty in responses
- Contradictory suggestions

Action: STOP after 2 low-confidence iterations
Rationale: AI not sure how to proceed
Next Steps:
1. Document what's unclear
2. Request human clarification
3. May need more context or specifications
```

#### B. Mixed Error Categories
```
Condition: FIXABLE + ARCHITECTURE/PHYSICS errors together
Evidence:
- Some errors are fixable
- Others require human intervention
- Cannot separate concerns

Action: STOP and request prioritization
Rationale: Can't fix code without addressing constraints
Next Steps:
1. Fix what's clearly fixable first
2. Document constraints separately
3. Have human address constraints
4. Then resume iteration on remaining code issues
```

## Decision Tree

```
┌─────────────────────────────────────┐
│ Parse Vivado Log                     │
└──────────────┬──────────────────────┘
               │
               ▼
       ┌───────────────┐
       │ Any PHYSICS   │──YES──► STOP (Physical constraints)
       │ errors?       │
       └───────┬───────┘
               │ NO
               ▼
       ┌───────────────┐
       │ Any ARCH      │──YES──► STOP (Design decisions needed)
       │ errors?       │
       └───────┬───────┘
               │ NO
               ▼
       ┌───────────────┐
       │ Error hash    │──YES──► STOP (Loop detected)
       │ repeated 3x?  │
       └───────┬───────┘
               │ NO
               ▼
       ┌───────────────┐
       │ No progress   │──YES──► STOP (Stagnation)
       │ for 2 iter?   │
       └───────┬───────┘
               │ NO
               ▼
       ┌───────────────┐
       │ All errors    │──YES──► CONTINUE (Can fix)
       │ FIXABLE/TB?   │
       └───────┬───────┘
               │ NO
               ▼
       ┌───────────────┐
       │ Mixed         │
       │ categories?   │──YES──► EVALUATE (Case by case)
       └───────┬───────┘
               │ NO
               ▼
       ┌───────────────┐
       │ Unknown       │
       │ errors?       │──YES──► STOP (Unclear situation)
       └───────┬───────┘
               │ NO
               ▼
       ┌───────────────┐
       │ Max iter      │──YES──► STOP (Iteration limit)
       │ reached?      │
       └───────┬───────┘
               │ NO
               ▼
           CONTINUE
           (Next iteration)
```

## Iteration Budget Guidelines

### Simple Syntax Issues (2-3 iterations expected)
```
Iteration 1: Identify and fix syntax errors
Iteration 2: Fix resulting type issues
Iteration 3: Verify compilation
```
If not resolved by iteration 4, STOP and review.

### Testbench Issues (3-5 iterations expected)
```
Iteration 1: Generate/fix test vectors
Iteration 2: Adjust timing
Iteration 3: Add missing test cases
Iteration 4: Refine coverage
Iteration 5: Final verification
```
If not resolved by iteration 6, STOP and review.

### Complex Module (5-8 iterations expected)
```
Iteration 1-2: Basic syntax and compilation
Iteration 3-4: Type and signal issues
Iteration 5-6: Testbench development
Iteration 7-8: Integration and verification
```
If not resolved by iteration 10, STOP and review.

### Never Exceed
- **10 iterations without success**: Something is fundamentally wrong
- **5 iterations on same error**: Stuck, need human intervention
- **3 oscillations**: Conflicting requirements

## Stop Messages Template

### Success Stop
```
✅ STOP: Simulation passed all checks

Summary:
- Total iterations: {n}
- Errors fixed: {count}
- Final status: All tests passing
- Vivado simulation completed successfully

The module is ready for further testing.
```

### Constraint Stop
```
⏹️  STOP: {PHYSICS|ARCHITECTURE} constraints detected

Cannot proceed with iteration because:
{specific_constraint_description}

Required actions:
1. {action_1}
2. {action_2}
3. {action_3}

This requires human design review.
```

### Stagnation Stop
```
⚠️  STOP: {Loop|No progress|Oscillation} detected

Problem:
{description_of_stagnation}

Attempted fixes:
- Iteration {n}: {what_was_tried}
- Iteration {n+1}: {what_was_tried}

This situation requires human analysis because:
{rationale}
```

### Confidence Stop
```
⚠️  STOP: Uncertain how to proceed

Current situation:
- Errors present: {count}
- Confidence in fixes: {low}%
- Unclear requirements: {list}

Recommend:
1. Human review of specifications
2. Clarify design requirements
3. Provide more context if available
```

## Resume Conditions

After stopping, iteration can resume if:

1. **Human addresses constraints**:
   - Timing requirements relaxed
   - Larger device selected
   - Design decisions made

2. **Max iterations increased**:
   - If making progress but hit limit
   - Add budget for more attempts

3. **Specification clarified**:
   - After addressing confidence issues
   - With better requirements

4. **Different approach**:
   - New strategy for stuck problems
   - Alternative fix method

Do NOT resume if:
- Same approach will repeat failure
- Fundamental constraints not addressed
- No new information available

## Metrics to Track

For each stop decision, record:

```json
{
  "stop_reason": "PHYSICS|ARCHITECTURE|LOOP|STAGNATION|SUCCESS|LIMIT",
  "iteration_count": 8,
  "errors_at_stop": 3,
  "error_categories": ["PHYSICS"],
  "progress_made": true/false,
  "confidence_scores": [85, 78, 65],
  "repeated_errors": 2,
  "recommendation": "Human review of timing constraints",
  "can_resume": false
}
```

This helps analyze when stops are appropriate and improve future decisions.
