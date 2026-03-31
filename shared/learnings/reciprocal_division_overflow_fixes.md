# Reciprocal and Division Unit Overflow Handling Fixes

**Date**: November 26, 2025
**Module**: `reciprocal_unit.vhd`, `division_unit.vhd`
**Format**: Q2.13 Fixed-Point (16-bit signed, 13 fractional bits)

## Problem Summary

The `reciprocal_unit` and `division_unit` modules had overflow handling bugs that caused incorrect results when:
1. Computing reciprocals of small values (e.g., 1/0.01, 1/0.125, 1/0.25)
2. Division results exceeded the Q2.13 representable range (~-4.0 to +3.999)

### Symptoms
- Small inputs like 0.01, 0.125, 0.25 produced near-zero or negative results instead of saturating to max
- Overflow flag not being set correctly
- Test results: 43/51 passed before fix, 48/51 after fix

## Root Cause Analysis

### Issue Location
`reciprocal_unit.vhd`, DENORMALIZE state (lines 284-339)

### Technical Details

The reciprocal unit uses Newton-Raphson iteration with normalization:

1. **Input normalization**: Shift input left until MSB is 1 (maps to [0.5, 1.0) range)
2. **Newton-Raphson**: Compute 1/normalized using iterations in Q4.28 internal format
3. **Denormalization**: Shift result back and convert to Q2.13 output

The denormalization combines two operations:
```
final = (x_reg << shift_amount) >> 17
```
Where `17 = INTERNAL_FRAC - FRAC_BITS + 2 = 28 - 13 + 2`

### Bug 1: Missing Overflow Check in "Safe" Path

**Original code assumed**: If `shift_amount < 17`, the net operation is a right-shift, so "no overflow possible"

**Reality**: Even with net right-shift, the intermediate value can exceed Q2.13 max. For example:
- Input: 0.01 in Q2.13 = 82
- shift_amount = 8 (from normalization)
- x_reg after Newton-Raphson ≈ 419,430,400 (1.5625 in Q4.28)
- After shift_right by 9: 818,809 (still >> 32767 max!)

### Bug 2: Intermediate Overflow in Left-Shift Path

For large shift_amount values, `shift_left(x_reg, shift_amount)` could overflow the 32-bit signed variable before saturation check was applied.

## Solution

### Code Changes (reciprocal_unit.vhd lines 307-339)

**Before:**
```vhdl
when DENORMALIZE =>
    out_shifted := shift_left(x_reg, shift_amount);
    final_val := shift_right(out_shifted, INTERNAL_FRAC - FRAC_BITS + 2);

    -- Saturation check (too late - overflow already occurred!)
    if final_val > resize(SAT_MAX, INTERNAL_WIDTH) then
        final_val := resize(SAT_MAX, INTERNAL_WIDTH);
        ovf_reg <= '1';
    ...
```

**After:**
```vhdl
when DENORMALIZE =>
    -- Combine shifts mathematically to avoid intermediate overflow
    if shift_amount < (INTERNAL_FRAC - FRAC_BITS + 2) then
        -- Net right shift: compute then check overflow
        final_val := shift_right(x_reg, (INTERNAL_FRAC - FRAC_BITS + 2) - shift_amount);

        -- CRITICAL: Still need overflow check!
        if final_val > resize(SAT_MAX, INTERNAL_WIDTH) then
            final_val := resize(SAT_MAX, INTERNAL_WIDTH);
            ovf_reg <= '1';
        elsif final_val < resize(SAT_MIN, INTERNAL_WIDTH) then
            final_val := resize(SAT_MIN, INTERNAL_WIDTH);
            ovf_reg <= '1';
        else
            ovf_reg <= '0';
        end if;
    else
        -- Net left shift: smaller shift, then check
        out_shifted := shift_left(x_reg, shift_amount - (INTERNAL_FRAC - FRAC_BITS + 2));

        if out_shifted > resize(SAT_MAX, INTERNAL_WIDTH) then
            final_val := resize(SAT_MAX, INTERNAL_WIDTH);
            ovf_reg <= '1';
        elsif out_shifted < resize(SAT_MIN, INTERNAL_WIDTH) then
            final_val := resize(SAT_MIN, INTERNAL_WIDTH);
            ovf_reg <= '1';
        else
            final_val := out_shifted;
            ovf_reg <= '0';
        end if;
    end if;
```

### Key Insight

The mathematical rewrite avoids intermediate overflow:
- `(x << A) >> B` with A < B becomes `x >> (B - A)` (pure right shift)
- `(x << A) >> B` with A >= B becomes `x << (A - B)` (smaller left shift)

Both paths still require overflow checking against Q2.13 bounds!

## Testing Results

| Test Case | Before Fix | After Fix |
|-----------|------------|-----------|
| 1/0.25 = 4.0 | -0.0001 | 3.9998 |
| 1/0.125 = 8.0 (SAT) | -0.0001 | 3.9998 + overflow flag |
| 0.1/0.01 = 10 (SAT) | -0.009 | 3.9998 + overflow flag |
| Total Pass | 43/51 | 48/51 |

### Remaining 3 "Failures"

These are **testbench issues**, not code bugs:
- Tests `1/6`, `1/7`, `3/7` use divisors (6.0, 7.0) that exceed Q2.13 range
- Input saturates to ~4.0 during conversion
- Results are mathematically correct for actual inputs received

## Lessons Learned

### 1. Overflow Can Occur Even with Right Shifts
When working with large internal precision (32-bit Q4.28) converting to smaller output (16-bit Q2.13), overflow checking is needed AFTER the shift, not just before.

### 2. Combine Shift Operations Mathematically
Instead of `shift_left` followed by `shift_right` (which can overflow intermediate), compute the net shift direction and magnitude first.

### 3. Fixed-Point Range Awareness
Q2.13 format has range [-4.0, +3.999]. Test cases should respect this limit. Values like 6.0 or 7.0 will saturate during input conversion.

### 4. Normalization Shift Amount Varies
The `shift_amount` from normalization depends on input magnitude:
- Large inputs (near 4.0): small shift_amount (0-2)
- Small inputs (near 0.01): large shift_amount (8-10)

Large shift_amount means the reciprocal result will be large, requiring careful overflow handling.

## Related Files
- `/home/arunupscee/Desktop/vhdl-ai-helper/Neuron/Neuron.srcs/sources_1/new/reciprocal_unit.vhd`
- `/home/arunupscee/Desktop/vhdl-ai-helper/Neuron/Neuron.srcs/sources_1/new/division_unit.vhd`
- `/home/arunupscee/Desktop/vhdl-ai-helper/Neuron/Neuron.srcs/sources_1/new/division_unit_tb.vhd`

## See Also
- `newton_raphson_lessons.md` - Newton-Raphson algorithm details
- `xsim_fixed_point_issue.md` - General fixed-point debugging
- `COMPREHENSIVE_VHDL_XSIM_REFERENCE.md` - Simulation reference
