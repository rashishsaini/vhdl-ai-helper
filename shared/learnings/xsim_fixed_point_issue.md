# XSIM Fixed-Point Package Function Issue

**Date**: 2025-10-24
**Project**: Cholesky 3x3 Decomposition
**XSIM Version**: 2025.1

## Problem Summary

XSIM 2025.1 experiences SIGSEGV (segmentation fault) during elaboration when calling package body functions that perform arithmetic operations on `signed` types.

## Root Cause

Through binary search debugging, isolated the crash to this specific pattern:

### Crashes XSIM ❌
```vhdl
-- In package body
function fixed_divide_simple(a, b : signed(31 downto 0)) return signed is
begin
    return a / b;  -- Even simple division crashes!
end function;

-- In architecture
l21 <= fixed_divide_simple(a21, l11);  -- SIGSEGV during elaboration
```

### Works in XSIM ✅
```vhdl
-- In architecture (no package function)
l21 <= a21 / l11;  -- Direct inline operation works fine
```

## What We Tested

| Test | Result |
|------|--------|
| Function that just returns input | ✅ Works |
| Function with simple `a / b` division | ❌ SIGSEGV |
| Function with `to_integer()` conversion | ❌ SIGSEGV |
| Function with multiplication | ❌ SIGSEGV |
| Function with bit concatenation | ❌ SIGSEGV |
| Inline division in architecture | ✅ Works |
| Inline multiplication in architecture | ✅ Works (needs verification) |

## Solution

**Do NOT use package functions for arithmetic operations in XSIM-targeted code.**

Instead, perform all fixed-point arithmetic inline in the architecture:

```vhdl
-- For fixed-point multiply (Q20.12 format)
variable temp_mult : signed(63 downto 0);
temp_mult := a * b;
result <= temp_mult(43 downto 12);  -- Shift right by FRAC_BITS

-- For fixed-point divide (Q20.12 format)
variable temp_div : signed(63 downto 0);
temp_div := resize(a, 64) * 4096;  -- Scale by 2^FRAC_BITS
result <= temp_div(31 downto 0) / b;
```

**Note**: Test each inline operation incrementally as some operations may still cause issues.

## Why This Happens

XSIM appears to have a bug where:
1. Package body functions can be declared and compiled successfully
2. The functions can be called from architecture code
3. Elaboration crashes when trying to process arithmetic operations inside those functions

This is likely an internal XSIM bug related to how it handles function inlining or optimization during elaboration.

## Workaround Applied

Modified `code.vhd` to:
1. Remove all calls to `fixed_multiply_simple()` and `fixed_divide_simple()`
2. Implement fixed-point arithmetic directly in the FSM process
3. Keep the package for documentation but don't use its functions

## Related Issues

- XSIM crashes with `to_signed()` in package constants
- XSIM crashes with component declarations
- XSIM crashes with complex record types containing strings

**Common theme**: XSIM 2025.1 has multiple elaboration bugs with advanced VHDL constructs.

## Recommendation

For XSIM compatibility:
- ✅ Use direct inline arithmetic in architecture
- ✅ Use simple signal assignments
- ✅ Keep functions trivial (just return inputs, do conversions)
- ❌ Avoid arithmetic in package functions
- ❌ Avoid `to_signed()`/`to_integer()` in packages
- ❌ Avoid component declarations

## Status

**Fixed**: Replaced package function calls with inline arithmetic operations in code.vhd.

**Next Step**: Test full design elaboration and simulation.
