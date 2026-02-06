# Tanh/Sigmoid Overflow Fix - Q2.13 Fixed-Point Limitations

## Date: 2024-11-26

## Problem Summary

The `tanh_unit` was producing incorrect results for negative inputs:
- `tanh(-1)` expected: `-0.7616`, got: `-0.5034` (33.9% error)
- `tanh(-2)` also failing with OVERFLOW flag

## Root Cause Analysis

### The Mathematical Chain

The tanh unit uses the identity:
```
tanh(x) = 2 * sigmoid(2x) - 1
```

For `tanh(-1)`:
1. Compute `2x = -2`
2. Compute `sigmoid(-2) = 1/(1 + e^(-(-2))) = 1/(1 + e^2)`
3. `e^2 ≈ 7.389`

### The Overflow Issue

**Q2.13 format limitations:**
- 16-bit signed: range approximately [-4.0, +4.0)
- Maximum representable value: `32767/8192 ≈ 3.9999`

**Problem:** `e^2 ≈ 7.389` **exceeds Q2.13 maximum**

When `exp_approximator` received `+2.0` (to compute `e^2`), it saturated to `~4.0`:
```
e^2 = 7.389 → saturates to 4.0
1 + e^2 = 8.389 → becomes 1 + 4.0 = 5.0
sigmoid(-2) = 1/5.0 = 0.2 (should be 0.119)
tanh(-1) = 2*0.2 - 1 = -0.6 (should be -0.762)
```

### Why Positive Inputs Worked

For `tanh(+1)`:
1. `2x = +2`
2. `sigmoid(+2) = 1/(1 + e^-2) = 1/(1 + 0.135) ≈ 0.88`
3. `e^-2 ≈ 0.135` - **within Q2.13 range**

The asymmetry: `e^(-x)` for positive x stays small, but `e^(-x)` for negative x becomes large.

## Solution: Piecewise Linear Fast-Path in Sigmoid

### Design Decision

For `|x| > 1.35`, bypass the exp/reciprocal computation entirely and use **piecewise linear approximation**.

### Why 1.35 Threshold?

- `e^1.35 ≈ 3.86` - still fits in Q2.13
- `e^1.5 ≈ 4.48` - **overflows** Q2.13
- Safety margin: use 1.35

### Implementation

Added to `sigmoid_unit.vhd`:

```vhdl
-- Thresholds
constant FAST_POS_THRESH : signed(DATA_WIDTH-1 downto 0) := to_signed(11059, DATA_WIDTH);  -- +1.35
constant FAST_NEG_THRESH : signed(DATA_WIDTH-1 downto 0) := to_signed(-11059, DATA_WIDTH); -- -1.35

-- Piecewise linear coefficients (5 segments per polarity)
-- Segment 0: x in [-4, -3]: slope=0.029, intercept=0.134
-- Segment 1: x in [-3, -2.5]: slope=0.058, intercept=0.221
-- ... etc

-- In FSM:
when IDLE =>
    if data_in > FAST_POS_THRESH or data_in < FAST_NEG_THRESH then
        state <= FAST_PATH;
    else
        state <= START_EXP;  -- Normal computation
    end if;

when FAST_PATH =>
    -- sigma(x) = slope * x + intercept
    -- For positive x: sigma(x) = 1 - sigma(-x) = (1-intercept) + slope*x
```

### Segment Coefficients

| Segment | X Range | Slope (Q2.13) | Intercept (Q2.13) |
|---------|---------|---------------|-------------------|
| 0 | [-4, -3] | 238 | 1098 |
| 1 | [-3, -2.5] | 475 | 1811 |
| 2 | [-2.5, -2] | 705 | 2384 |
| 3 | [-2, -1.5] | 1032 | 3039 |
| 4 | [-1.5, -1.35] | 1311 | 3457 |

For positive x, use symmetry: `sigma(x) = 1 - sigma(-x)`

## Results

| Test | Before Fix | After Fix |
|------|------------|-----------|
| tanh(-1) | 33.9% error, FAIL | 0.08% error, PASS |
| tanh(-2) | FAIL with overflow | 0.03% error, PASS |
| tanh(0.8) | 14.7% error, FAIL | 0.44% error, PASS |
| **Total** | ~40/71 pass | **71/71 pass** |
| Max Error | 33.9% | 6.26% |
| Avg Error | N/A | 1.21% |

## Key Learnings

### 1. Fixed-Point Range Analysis is Critical

Before implementing any transcendental function, analyze the **full range** of intermediate values:
- What inputs does the function receive?
- What are the maximum/minimum intermediate values?
- Do any intermediate values exceed the fixed-point format range?

### 2. Asymmetric Behavior in Symmetric Functions

Even mathematically symmetric functions like sigmoid can have asymmetric fixed-point behavior:
- `e^x` for positive x grows unbounded
- `e^x` for negative x stays in (0, 1]

### 3. Piecewise Linear Approximation

For slowly-varying regions of transcendental functions, piecewise linear approximation is:
- **Accurate enough** (sigmoid changes slowly for |x| > 1.5)
- **Fast** (1-2 cycles vs 20+ cycles)
- **Safe** (no overflow risk)

### 4. Sigmoid Symmetry Exploitation

Use `sigma(x) = 1 - sigma(-x)` to:
- Halve the LUT size
- Ensure numerical symmetry
- Simplify positive-side computation

### 5. Debugging Fixed-Point Chains

When debugging multi-stage fixed-point computation:
1. Trace values through each stage
2. Check for saturation at each stage
3. Verify intermediate values against expected mathematical results
4. Look for overflow flags that indicate saturation occurred

## Files Modified

- `/home/arunupscee/Desktop/vhdl-ai-helper/Neuron/Neuron.srcs/sources_1/new/sigmoid_unit.vhd`
  - Added fast-path state to FSM
  - Added piecewise linear approximation constants
  - Added threshold-based path selection

## Related Learnings

- `sigmoid_unit_design_patterns.md` - Original sigmoid design
- `reciprocal_division_overflow_fixes.md` - Reciprocal unit overflow handling
- `log_approximator_piecewise_linear_fixes.md` - Similar piecewise linear approach

## Applicability

This pattern applies to any fixed-point implementation where:
- Intermediate computations may exceed format range
- The function has slowly-varying regions amenable to linear approximation
- Speed/accuracy tradeoffs are acceptable in extreme input regions
