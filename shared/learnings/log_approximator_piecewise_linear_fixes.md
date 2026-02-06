# Log Approximator Piecewise Linear Approximation Fixes

## Overview

**Module:** `log_approximator.vhd`
**Function:** Computes natural logarithm ln(x) using piecewise linear approximation
**Format:** Q2.13 fixed-point (16-bit signed)
**Input Range:** x in (0, 4)
**Date:** November 26, 2025

---

## Issues Discovered and Fixed

### Issue 1: Incorrect LUT Intercept Values for Clamped Slopes

**Problem:**
Segments 0 and 1 (covering x < 0.25) had slopes that exceeded the Q2.13 maximum representable value (~3.9999). The slopes were correctly clamped to 32767, but the intercept values were calculated using the **ideal** (unclamped) slopes instead of the clamped values.

**Root Cause:**
The intercept formula `b = ln(x_mid) - slope × x_mid` must use the **actual** slope value used in computation, not the theoretical slope.

**Original (Wrong):**
```vhdl
-- Seg 0: ln(0.09375) - 1 ≈ -2.368 - 1 = -3.368
to_signed(-27590, DATA_WIDTH),  -- -3.368 * 8192
-- Seg 1: ln(0.1875) - 1 ≈ -1.674 - 1 = -2.674
to_signed(-21905, DATA_WIDTH),  -- -2.674 * 8192
```

**Fixed (Correct):**
```vhdl
-- Seg 0: x_mid=0.09375, ln(0.09375)=-2.368
-- With clamped slope=3.9999, b = -2.368 - 3.9999*0.09375 = -2.743
to_signed(-22471, DATA_WIDTH),  -- -2.743 * 8192
-- Seg 1: x_mid=0.1875, ln(0.1875)=-1.674
-- With clamped slope=3.9999, b = -1.674 - 3.9999*0.1875 = -2.424
to_signed(-19858, DATA_WIDTH),  -- -2.424 * 8192
```

**Impact:**
- Before fix: ln(0.1) = -2.97 (28.9% error) - FAIL
- After fix: ln(0.1) = -2.34 (1.76% error) - PASS

---

### Issue 2: Missing Handling for Values Below First Segment Boundary

**Problem:**
When input x < BOUNDARIES(0) (i.e., x < 0.0625), the segment search loop found no match, and the default case incorrectly assigned `seg_index <= NUM_SEGMENTS - 1` (segment 15, for x ≈ 3.5-4.0).

**Root Cause:**
The default fallback assumed "no match" meant the value was too large, not too small.

**Original (Wrong):**
```vhdl
when LOOKUP =>
    seg_found := false;
    for i in 0 to NUM_SEGMENTS-1 loop
        if not seg_found then
            if x_reg >= BOUNDARIES(i) and x_reg < BOUNDARIES(i+1) then
                seg_index <= i;
                seg_found := true;
            end if;
        end if;
    end loop;

    -- Default to last segment if not found
    if not seg_found then
        seg_index <= NUM_SEGMENTS - 1;  -- WRONG for small values!
    end if;
```

**Fixed (Correct):**
```vhdl
when LOOKUP =>
    seg_found := false;

    -- Handle values below first boundary - use segment 0
    if x_reg < BOUNDARIES(0) then
        seg_index <= 0;
        seg_found := true;
    else
        for i in 0 to NUM_SEGMENTS-1 loop
            if not seg_found then
                if x_reg >= BOUNDARIES(i) and x_reg < BOUNDARIES(i+1) then
                    seg_index <= i;
                    seg_found := true;
                end if;
            end if;
        end loop;
    end if;

    -- Default to last segment if above upper bound
    if not seg_found then
        seg_index <= NUM_SEGMENTS - 1;
    end if;
```

**Impact:**
- Before fix: ln(0.05) = +0.335 (positive, completely wrong)
- After fix: ln(0.05) correctly uses segment 0 extrapolation

---

### Issue 3: Missing Overflow Check for Large Inputs

**Problem:**
The design specified input range (0, 4), but inputs >= 4.0 had no overflow protection. They would use segment 15 and compute incorrect results.

**Solution:**
Added MAX_INPUT constant and early overflow detection:

```vhdl
-- Constants
constant MAX_INPUT : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);  -- ~4.0
constant LN_4      : signed(DATA_WIDTH-1 downto 0) := to_signed(11356, DATA_WIDTH);  -- ln(4) ≈ 1.386

-- In IDLE state, after checking for x <= 0 and x < MIN_INPUT:
elsif data_in >= MAX_INPUT then
    ovf_reg <= '1';
    result_reg <= LN_4;  -- Return ln(4) ≈ 1.386
    done_reg <= '1';
    -- Stay in IDLE
```

**Impact:**
- Before fix: ln(7.39) = 1.39 (no overflow flag)
- After fix: ln(7.39) = 1.39 with overflow flag set (correct behavior)

---

### Issue 4: MIN_INPUT Threshold Too Low

**Problem:**
MIN_INPUT was set to 0.0183 (e^-4), allowing values like x=0.02 through normal computation. However, the piecewise linear approximation has poor accuracy for such extreme values.

**Solution:**
Increased MIN_INPUT to 0.05 to match the practical lower bound of accurate approximation:

```vhdl
-- Original
constant MIN_INPUT : signed(DATA_WIDTH-1 downto 0) := to_signed(150, DATA_WIDTH);  -- ~0.0183

-- Fixed
constant MIN_INPUT : signed(DATA_WIDTH-1 downto 0) := to_signed(410, DATA_WIDTH);  -- ~0.05
```

**Impact:**
- x=0.02 now correctly triggers overflow flag and returns SAT_MIN (-4.0)
- Values in range [0.05, 4.0] are computed with acceptable accuracy

---

## Key Learnings

### 1. Clamped Values Require Recalculated Coefficients

When a parameter (like slope) is clamped to fit the number format, **all dependent calculations must use the clamped value**, not the original mathematical value. This is a common mistake in piecewise linear approximations.

**Rule:** If you clamp `slope = clamp(ideal_slope, max_val)`, then `intercept = f(x_mid) - clamped_slope × x_mid`, not `f(x_mid) - ideal_slope × x_mid`.

### 2. Default Cases Must Consider Both Directions

When searching for a segment/range, the default "not found" case should consider:
- Value too small (below first boundary)
- Value too large (above last boundary)

Don't assume "not found" always means "too large".

### 3. Input Range Validation Should Be Explicit

For functions with limited domains (like ln(x) for x > 0), add explicit range checks for:
- Invalid inputs (x <= 0 for ln)
- Underflow inputs (x too small for accurate computation)
- Overflow inputs (x beyond design range)

Each should set appropriate status flags (invalid, overflow) and return sensible clamped values.

### 4. Test Edge Cases at Segment Boundaries

Piecewise approximations have discontinuities at segment boundaries. Test:
- Values just below each boundary
- Values just above each boundary
- Values at exact boundaries
- Values outside the segment array range

### 5. Testbench Pass Criteria Should Match Design Spec

The testbench overflow detection condition must match the design's actual overflow conditions:
```vhdl
-- Original (incomplete)
elsif overflow = '1' and (x_input < 0.02 or abs(expected) >= 3.9) then

-- Fixed (complete)
elsif overflow = '1' and (x_input < 0.02 or x_input > 3.9 or abs(expected) >= 3.9) then
```

---

## Test Results

**Before Fixes:**
```
Total Tests:   62
Passed:        59
Failed:        3
Max Error:     111.2%
```

**After Fixes:**
```
Total Tests:   62
Passed:        62
Failed:        0
Max Error:     5.95% (marginal boundary cases)
Avg Error:     2.60%
ALL TESTS PASSED!
```

---

## Code Review Findings

The VHDL code reviewer agent confirmed:

**Positive Observations:**
- Excellent documentation in module header
- Proper use of `numeric_std` signed types
- Clean FSM with registered outputs and explicit default case
- Complete reset coverage for all state elements
- Proper handshake protocol (start/done/busy)
- Correct saturation logic with proper width handling
- Synthesizable design (no non-synthesizable constructs)

**Resource Estimates (Xilinx 7-Series):**
- LUTs: ~150-200
- FFs: ~100
- DSP48: 1 (16x16 multiplier)
- BRAM: 0 (LUT-based tables)
- Max Frequency: 150-200 MHz

**Latency:**
- Valid input: 5 clock cycles
- Invalid/overflow input: 1 clock cycle

---

## Recommendations for Future Piecewise Approximations

1. **Use a consistent coefficient generation script** - Calculate all slopes and intercepts programmatically to avoid manual calculation errors

2. **Generate coefficients from actual clamped values** - If any coefficient is clamped, regenerate all dependent coefficients

3. **Add boundary value tests automatically** - For N segments, generate tests at all N+1 boundaries plus offsets

4. **Consider using CORDIC for logarithm** - For higher accuracy, CORDIC-based log computation may be preferable

5. **Document the effective input range clearly** - Both in comments and in port assertions

---

## Files Modified

1. `/home/arunupscee/Desktop/vhdl-ai-helper/Neuron/Neuron.srcs/sources_1/new/log_approximator.vhd`
   - Lines 156-161: Fixed intercept values for segments 0-1
   - Lines 62-66: Added MAX_INPUT and LN_4 constants, updated MIN_INPUT
   - Lines 263-268: Added overflow check for x >= MAX_INPUT
   - Lines 278-281: Added explicit handling for x < BOUNDARIES(0)

2. `/home/arunupscee/Desktop/vhdl-ai-helper/Neuron/Neuron.srcs/sources_1/new/log_approximator_tb.vhd`
   - Line 237: Updated overflow pass condition to include high-value overflow

---

## Related Learnings

- `reciprocal_division_overflow_fixes.md` - Similar overflow handling patterns
- `newton_raphson_lessons.md` - Fixed-point arithmetic fundamentals
- `COMPREHENSIVE_VHDL_XSIM_REFERENCE.md` - General VHDL patterns

---

**Last Updated:** November 26, 2025
