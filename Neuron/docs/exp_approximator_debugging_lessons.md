# Exponential Approximator Debugging Lessons

## Module: exp_approximator.vhd
**Date:** 2025-11-26
**Status:** All 75 tests passing with <1% error

---

## Overview

The `exp_approximator` module computes e^x using piecewise linear approximation with a lookup table (LUT). It is designed for neural network activation functions using Q2.13 fixed-point format.

---

## Bugs Found and Fixed

### Bug #1: VHDL Signal Timing Hazard (Critical)

**Symptom:** All negative inputs produced underflow (SAT_MIN), positive inputs had ~20-30% error.

**Root Cause:** In VHDL, signal assignments are **non-blocking** - they take effect at the **next clock edge**. The original code fetched LUT values and used them in the same clock cycle:

```vhdl
-- WRONG: Uses OLD values of slope_val and intercept_val
when COMPUTE =>
    slope_val     <= SLOPES(seg_index);      -- Scheduled for NEXT clock
    intercept_val <= INTERCEPTS(seg_index);  -- Scheduled for NEXT clock
    product <= slope_val * x_reg;            -- Uses OLD value (zero from reset)!
    state <= OUTPUT_ST;
```

**Fix:** Add an intermediate state to allow signal propagation:

```vhdl
when FETCH_LUT =>
    slope_val     <= SLOPES(seg_index);
    intercept_val <= INTERCEPTS(seg_index);
    state <= COMPUTE;

when COMPUTE =>
    -- Now slope_val and intercept_val have correct values
    product <= slope_val * x_reg;
    state <= OUTPUT_ST;
```

**Lesson Learned:** In clocked processes, signal assignments scheduled in one state are NOT available until the next clock edge. Either:
1. Add pipeline stages (states) between assignment and use
2. Use **variables** instead of signals for combinational logic within a process

---

### Bug #2: Variable Width Mismatch

**Symptom:** Incorrect segment index calculation for some inputs.

**Root Cause:** The segment calculation variable was too narrow:

```vhdl
-- WRONG: 19 bits not enough for 20-bit arithmetic
variable seg_calc : signed(DATA_WIDTH+2 downto 0);  -- 19 bits
seg_calc := resize(x_reg, DATA_WIDTH+3) + to_signed(32768, DATA_WIDTH+3);  -- 20-bit result
```

**Fix:** Match variable width to arithmetic requirements:

```vhdl
variable seg_calc : signed(DATA_WIDTH+3 downto 0);  -- 20 bits
seg_calc := resize(x_reg, DATA_WIDTH+4) + to_signed(32768, DATA_WIDTH+4);
```

**Lesson Learned:** Always verify that intermediate variables have sufficient width for:
- The resize() target width
- Any additions that may increase the bit count
- Signed arithmetic range requirements

---

### Bug #3: Intermediate Overflow Before Saturation

**Symptom:** Values for x > 1.25 produced underflow instead of expected ~3.5-4.0 results.

**Root Cause:** The scaled product was truncated to 16 bits before saturation check:

```vhdl
-- WRONG: prod_scaled overflows for large slope*x products
variable prod_scaled : signed(DATA_WIDTH-1 downto 0);  -- 16-bit signed, max 32767

-- For x=1.3, slope=32400: product>>13 = 42122, which exceeds 32767!
-- 42122 wraps to -23414 in 16-bit signed
prod_scaled := resize(shift_right(...), DATA_WIDTH);  -- Overflow!
```

**Fix:** Use wider intermediate before saturation:

```vhdl
variable prod_scaled : signed(DATA_WIDTH+4 downto 0);  -- 21 bits
prod_scaled := resize(shift_right(...), DATA_WIDTH+5);  -- No overflow
-- Saturation check happens on the full-width value
```

**Lesson Learned:** Intermediate computations in fixed-point arithmetic can exceed the final output range. Always use wider intermediates and apply saturation/clamping as the **last step** before output assignment.

---

### Bug #4: Incorrect LUT Values

**Symptom:** 5-30% error across most of the input range.

**Root Cause:** The intercept values were calculated using an incorrect formula. For piecewise linear approximation of y = e^x:

- **Correct formula:** b = y_mid - m * x_mid = e^(x_mid) * (1 - x_mid)
- **Original values:** Used a different (incorrect) calculation

**Fix:** Regenerated all 24 LUT entries using Python:

```python
for segment in range(24):
    x_mid = -4.0 + segment * 0.25 + 0.125  # Segment midpoint
    slope = math.exp(x_mid)                 # Derivative at midpoint
    intercept = math.exp(x_mid) * (1 - x_mid)  # y-intercept

    slope_fixed = int(round(slope * 8192))      # Q2.13 format
    intercept_fixed = int(round(intercept * 8192))
```

**Lesson Learned:** When implementing mathematical functions in hardware:
1. Derive formulas carefully with pen and paper first
2. Create a software reference implementation to generate/verify LUT values
3. Test against known values (e.g., e^0=1, e^1=2.718, e^(-1)=0.368)

---

### Bug #5: Unicode Characters in Testbench

**Symptom:** GHDL compilation error: "invalid character not allowed"

**Root Cause:** Unicode "approximately equal" symbol (≈) in string literals:

```vhdl
run_test(0.693, "e^ln(2) ≈ 2");  -- Unicode ≈ not valid
```

**Fix:** Use ASCII-only strings:

```vhdl
run_test(0.693, "e^ln(2) approx 2");
```

**Lesson Learned:** VHDL string literals must contain only ISO 8859-1 (Latin-1) characters. Avoid Unicode symbols in VHDL source files.

---

## Key VHDL Patterns Learned

### 1. Signal vs Variable Timing

| Construct | When Updated | Scope |
|-----------|--------------|-------|
| Signal | Next clock edge (after process ends) | Visible outside process |
| Variable | Immediately (sequential within process) | Local to process |

**Rule:** Use variables for intermediate combinational logic within a clocked process when you need immediate availability.

### 2. Fixed-Point Arithmetic Checklist

- [ ] Verify intermediate width accommodates maximum values
- [ ] Add rounding constant before right-shift: `(product + 2^(shift-1)) >> shift`
- [ ] Apply saturation as the last step before output
- [ ] Test boundary conditions and segment transitions
- [ ] Verify LUT values with software reference

### 3. Piecewise Linear Approximation Formula

For approximating f(x) over segment [x_start, x_end]:

```
x_mid = (x_start + x_end) / 2
slope = f'(x_mid)           -- Derivative at midpoint
intercept = f(x_mid) - slope * x_mid

result = slope * x + intercept
```

For e^x specifically: slope = intercept derivative = e^(x_mid)

---

## Test Results After Fixes

```
Total Tests:   75
Passed:        75
Failed:        0
Max Error:     0.88%
Avg Error:     0.53%
Latency:       5 clock cycles
```

---

## Files Modified

1. `exp_approximator.vhd` - Main design file
   - Added FETCH_LUT state to FSM
   - Fixed variable widths
   - Corrected all LUT values
   - Widened intermediate computation

2. `exp_approximator_tb.vhd` - Testbench
   - Replaced Unicode characters with ASCII

---

## Recommended Debug Workflow

1. **Compile check:** `ghdl -a --std=08 design.vhd`
2. **Simulate with reference values:** Test known inputs (e^0=1, e^1=2.718)
3. **Trace intermediate signals:** If results wrong, check:
   - Segment index calculation
   - LUT value fetching (timing!)
   - Product computation
   - Saturation logic
4. **Verify with Python:** Create reference implementation to generate expected values
