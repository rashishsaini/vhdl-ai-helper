# Comprehensive VHDL & XSIM Reference Guide

**Last Updated**: 2025-10-24
**Project**: vhdl-ai-helper
**Scope**: Cholesky Decomposition, Newton-Raphson, XSIM Debugging
**Version**: 1.0

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [XSIM Known Issues & Workarounds](#xsim-known-issues--workarounds)
3. [XSIM Binary Search Debugging Method](#xsim-binary-search-debugging-method)
4. [Fixed-Point Arithmetic Best Practices](#fixed-point-arithmetic-best-practices)
5. [Newton-Raphson Square Root Implementation](#newton-raphson-square-root-implementation)
6. [Cholesky Decomposition Specifics](#cholesky-decomposition-specifics)
7. [Testbench Design Guidelines](#testbench-design-guidelines)
8. [Complete Troubleshooting Workflow](#complete-troubleshooting-workflow)
9. [Quick Reference Tables](#quick-reference-tables)

---

## Executive Summary

This document consolidates all learnings from implementing fixed-point numerical algorithms in VHDL, specifically targeting Xilinx Vivado XSIM 2023.02-2025.1. The primary projects covered are:

- **Newton-Raphson square root** (Q20.12 fixed-point)
- **Cholesky 3x3 matrix decomposition** (using Newton-Raphson for sqrt)
- **XSIM compatibility debugging** (SIGSEGV crashes, elaboration failures)

### Key Achievements

- **97.5% test pass rate** for Newton-Raphson (39/40 tests)
- **99.7% accuracy improvement** for edge cases (0.01-10000 range)
- **100% XSIM compatibility** achieved through systematic debugging
- **Binary search debugging technique** developed for SIGSEGV crashes

### Most Important Lessons

1. **XSIM has serious elaboration bugs** - avoid component declarations, package function arithmetic, and `to_signed()` in constants
2. **Adaptive initial guess** is critical for iterative algorithms - 99.7% improvement vs fixed guess
3. **Overflow protection** must be implemented at every arithmetic operation
4. **Division by zero** protection is essential in testbenches when testing edge cases
5. **Inline arithmetic** is required for XSIM compatibility - package functions crash

---

## XSIM Known Issues & Workarounds

### Critical XSIM 2025.1 Bugs

XSIM has multiple elaboration bugs that cause `ERROR: [XSIM 43-3316] Signal SIGSEGV received` crashes:

#### Issue #1: Component Instances Cause SIGSEGV

**Broken Code**:
```vhdl
architecture Behavioral of my_tb is
    component my_design
        port (clk : in std_logic; ...);
    end component;
begin
    uut: my_design port map (clk => clk, ...);  -- CRASHES!
end architecture;
```

**Working Solution** ✅:
```vhdl
architecture Behavioral of my_tb is
    -- No component declaration!
begin
    uut: entity work.my_design
        port map (clk => clk, ...);  -- WORKS
end architecture;
```

**Impact**: Direct entity instantiation required for all XSIM testbenches.

---

#### Issue #2: Package Function Arithmetic Causes SIGSEGV

**Broken Code**:
```vhdl
-- In package body
function fixed_divide(a, b : signed(31 downto 0)) return signed is
begin
    return a / b;  -- Even this simple operation CRASHES!
end function;

-- In architecture
result <= fixed_divide(x, y);  -- SIGSEGV during elaboration
```

**Working Solution** ✅:
```vhdl
-- In architecture (inline arithmetic)
process(clk)
    variable temp_div : signed(63 downto 0);
begin
    temp_div := x * 4096;  -- Scale for Q20.12
    temp_div := temp_div / y;
    result <= temp_div(31 downto 0);  -- WORKS
end process;
```

**Impact**: **ALL arithmetic must be inline** - package functions only for trivial operations.

---

#### Issue #3: to_signed() in Package Constants

**Broken Code**:
```vhdl
package my_pkg is
    constant MAX_VAL : signed(31 downto 0) := to_signed(1000, 32);  -- CRASHES!
end package;
```

**Working Solution** ✅:
```vhdl
package my_pkg is
    constant MAX_VAL_INT : integer := 1000;  -- Use integer constant
end package;

-- In architecture/process
signal max_val_sig : signed(31 downto 0) := to_signed(MAX_VAL_INT, 32);  -- WORKS
```

**Impact**: Use integer constants in packages, convert at point of use.

---

#### Issue #4: shift_right() / resize() Can Crash

**Broken Code**:
```vhdl
x_current <= shift_right(x_input, 1);  -- May crash in some contexts
temp := resize(value, 64);  -- May crash
```

**Working Solution** ✅:
```vhdl
-- Manual bit slicing instead
x_current <= '0' & x_input(31 downto 1);  -- Manual right shift
temp := (63 downto 32 => value(31)) & value;  -- Manual sign extension
```

**Impact**: Prefer manual bit operations over library functions in XSIM.

---

#### Issue #5: UTF-8 Characters in Strings

**Broken Code**:
```vhdl
report "Test ✅ PASSED";  -- UTF-8 emoji causes issues
```

**Working Solution** ✅:
```vhdl
report "Test PASSED";  -- ASCII only
```

**Impact**: Use only ASCII characters in VHDL strings.

---

### Complete XSIM Workaround Table

| Issue | Symptom | Workaround |
|-------|---------|-----------|
| Component instances | SIGSEGV during elaboration | Use direct entity instantiation |
| Package function arithmetic | SIGSEGV with any `+`, `-`, `*`, `/` | Use inline arithmetic in architecture |
| `to_signed()` in constants | SIGSEGV in package | Use integer constants |
| `shift_right()`, `resize()` | Occasional SIGSEGV | Use manual bit slicing |
| UTF-8 characters | Encoding errors | Use ASCII only |
| Fixed/floating point libs | Package not found | Use `ieee_proposed.fixed_pkg` |
| Complex record types | SIGSEGV | Use simple signal types |

---

## XSIM Binary Search Debugging Method

When XSIM crashes with SIGSEGV and no useful error message, use systematic binary search:

### Step 1: Verify Problem is in Architecture

**Comment out EVERYTHING**:
```vhdl
architecture Behavioral of my_design is
    /*
    signal sig1, sig2 : std_logic;
    */
begin
    /*
    process(clk)
    begin
        ...
    end process;

    inst1: entity work.component1 port map (...);
    */
end architecture;
```

**Test**: Build simulation.
- **If crashes**: Problem in entity interface or testbench
- **If works**: Problem in architecture body → proceed to Step 2

---

### Step 2: Binary Search Architecture

**Uncomment half at a time**:

```vhdl
-- Test 1: First half
architecture Behavioral of my_design is
    signal sig1, sig2 : std_logic;
begin
    process(clk) begin ... end process;
    /*
    inst1: entity work.component1 port map (...);
    */
end architecture;
```

- **If crashes**: Problem in first half
- **If works**: Problem in second half

**Repeat** until you isolate the smallest crashing section.

---

### Step 3: Isolate Exact Line

Once you find the problematic process/component:

```vhdl
process(clk)
    /* variable var1 : integer; */
begin
    /* statement1; */
    statement2;  -- Testing this
    /* statement3; */
end process;
```

Test each statement individually until crash is isolated to specific line.

---

### Example: Full Binary Search Session

**Start**: Design crashes with SIGSEGV ❌

**Test 1**: Comment everything → Works ✅ (problem in architecture)

**Test 2**: Uncomment signals + first process → Works ✅

**Test 3**: Add first component instance → Crashes ❌ (problem in inst1)

**Test 4**: Comment all port maps → Works ✅

**Test 5**: Uncomment ports one by one:
- `clk => clk` → Works ✅
- `data => sig1` → Crashes ❌

**Found**: Problem is with `sig1` signal or the `data` port connection.

**Fix**: Check signal type, port type, or use different signal.

---

### Binary Search Success Criteria

✅ **You've succeeded when you can identify**:
1. Exact line causing crash
2. Exact construct that triggers SIGSEGV
3. Pattern (e.g., "always crashes with division in function")

Then apply appropriate workaround from table above.

---

## Fixed-Point Arithmetic Best Practices

### Q Notation Format

**Q20.12** means:
- 20 integer bits (range: -524288 to +524287)
- 12 fractional bits (resolution: 1/4096 = 0.000244)
- Total: 32 bits (signed)

**Example Values in Q20.12**:
```vhdl
-- Integer 5 = 5 * 4096 = 20480 (0x00005000)
constant FIVE : signed(31 downto 0) := to_signed(20480, 32);

-- 2.5 = 2.5 * 4096 = 10240 (0x00002800)
constant TWO_HALF : signed(31 downto 0) := to_signed(10240, 32);

-- 0.25 = 0.25 * 4096 = 1024 (0x00000400)
constant QUARTER : signed(31 downto 0) := to_signed(1024, 32);
```

---

### Fixed-Point Multiplication

**Formula**: `(a * b) >> FRAC_BITS`

**Correct Implementation**:
```vhdl
process(clk)
    variable temp_mult : signed(63 downto 0);  -- MUST use wider type!
begin
    -- Multiply in 64-bit to avoid overflow
    temp_mult := a * b;  -- Both a, b are signed(31 downto 0)

    -- Extract result: bits [43:12] for Q20.12 format
    -- This is equivalent to right shift by 12 (FRAC_BITS)
    result <= temp_mult(43 downto 12);
end process;
```

**Why 64-bit?**
- `a` (32-bit) * `b` (32-bit) = 64-bit intermediate
- Without resize, truncation causes incorrect results

**Why [43:12]?**
- Full 64-bit result has fractional bits at [11:0]
- We want 32-bit output with [11:0] as fractional
- So extract [43:12] = bits 12-43 of product

---

### Fixed-Point Division

**Formula**: `(a << FRAC_BITS) / b`

**Correct Implementation**:
```vhdl
process(clk)
    variable temp_div : signed(63 downto 0);
begin
    -- Scale numerator by 2^FRAC_BITS (4096 for Q20.12)
    temp_div := a * 4096;  -- OR: resize(a, 64) shifted left by 12

    -- Divide by denominator
    temp_div := temp_div / b;

    -- Extract 32-bit result
    result <= temp_div(31 downto 0);
end process;
```

**Alternative with shift**:
```vhdl
temp_div := resize(a, 64);  -- Extend to 64-bit
temp_div := shift_left(temp_div, 12);  -- Multiply by 2^12
temp_div := temp_div / b;
result <= temp_div(31 downto 0);
```

**WARNING**: Second method may crash XSIM - prefer direct multiplication by 4096.

---

### Overflow Protection (CRITICAL)

**Problem**: Fixed-point operations can overflow 32-bit range.

**Solution 1: Saturating Arithmetic**
```vhdl
-- Check before narrowing bit width
if temp_sum > to_signed(2147483647, 64) then
    result <= to_signed(2147483647, 32);  -- Saturate to max
elsif temp_sum < to_signed(-2147483648, 64) then
    result <= to_signed(-2147483648, 32);  -- Saturate to min
else
    result <= temp_sum(31 downto 0);  -- Normal case
end if;
```

**Solution 2: Clamp Divisors**
```vhdl
-- Prevent division by very small numbers (causes overflow)
if abs(divisor) < to_signed(4, 32) then  -- ~0.001 in Q20.12
    divisor_safe := to_signed(4, 32);  -- Minimum safe divisor
else
    divisor_safe := divisor;
end if;

-- Now safe to divide
result <= numerator / divisor_safe;
```

**Solution 3: Range Checking**
```vhdl
-- Validate inputs are within supported range
assert input >= MIN_INPUT and input <= MAX_INPUT
    report "Input out of range!"
    severity error;
```

---

### Complete Fixed-Point Template

```vhdl
architecture Behavioral of fixed_point_example is
    constant FRAC_BITS : integer := 12;
    constant SCALE : integer := 4096;  -- 2^FRAC_BITS

    signal a, b, mult_result, div_result : signed(31 downto 0);
begin
    process(clk)
        variable temp_mult : signed(63 downto 0);
        variable temp_div : signed(63 downto 0);
        variable divisor_safe : signed(31 downto 0);
    begin
        if rising_edge(clk) then
            -- MULTIPLY: (a * b) >> FRAC_BITS
            temp_mult := a * b;
            mult_result <= temp_mult(43 downto 12);

            -- DIVIDE: (a << FRAC_BITS) / b with protection
            if abs(b) < to_signed(4, 32) then
                divisor_safe := to_signed(4, 32);  -- Clamp
            else
                divisor_safe := b;
            end if;

            temp_div := a * SCALE;
            temp_div := temp_div / divisor_safe;

            -- Saturate result
            if temp_div > to_signed(2147483647, 64) then
                div_result <= to_signed(2147483647, 32);
            elsif temp_div < to_signed(-2147483648, 64) then
                div_result <= to_signed(-2147483648, 32);
            else
                div_result <= temp_div(31 downto 0);
            end if;
        end if;
    end process;
end architecture;
```

---

## Newton-Raphson Square Root Implementation

### Algorithm Overview

Newton-Raphson iteration for `sqrt(x)`:

```
x_next = (x_current + x / x_current) / 2
```

Converges to `sqrt(x)` when `x_next ≈ x_current`.

---

### Critical Success Factor #1: Adaptive Initial Guess

**Problem**: Fixed initial guess fails for wide input range.

**Example Failures**:
- Input 0.01: guess = 0.005, actual = 0.1 → **20x error!**
- Input 10000: guess = 5000, actual = 100 → **50x error!**

**Solution**: Range-based initial guess:

```vhdl
when INIT =>
    -- Q20.12 format: 4096 = 1.0, 409600 = 100.0
    if x_input < to_signed(4096, 32) then
        -- Input < 1.0: use input itself
        x_current <= x_input;
    elsif x_input > to_signed(409600, 32) then
        -- Input > 100: use input / 4
        x_current <= '0' & '0' & x_input(31 downto 2);  -- Manual shift right 2
    else
        -- Normal range (1-100): use input / 2
        x_current <= '0' & x_input(31 downto 1);  -- Manual shift right 1
    end if;
    state <= ITERATE;
```

**Results**:
- Input 0.01: Error reduced from **52.8% → 0.15%** (99.7% improvement)
- Input 10000: Error reduced from **223% → 1.2%** (99.5% improvement)

---

### Critical Success Factor #2: Early Convergence Detection

**Problem**: Fixed iteration count wastes cycles or gives insufficient accuracy.

**Solution**: Tolerance-based early termination:

```vhdl
constant MAX_ITERATIONS : integer := 12;
constant TOLERANCE : signed(31 downto 0) := to_signed(4, 32);  -- ~0.001

when ITERATE =>
    -- Compute delta = |x_next - x_current|
    if x_next > x_current then
        delta := x_next - x_current;
    else
        delta := x_current - x_next;
    end if;

    -- Check convergence
    if delta < TOLERANCE then
        state <= FINISH;  -- Converged early!
    elsif iteration >= MAX_ITERATIONS - 1 then
        state <= FINISH;  -- Max iterations reached
    else
        x_current <= x_next;
        iteration <= iteration + 1;
        state <= ITERATE;
    end if;
```

**Benefits**:
- Easy inputs finish in 4-6 iterations (save cycles)
- Hard inputs get full 12 iterations (better accuracy)
- Optimal performance/accuracy tradeoff

---

### Critical Success Factor #3: Overflow Protection

**Problem**: Large inputs cause overflow in `x / x_current`.

**Solution**: Protect division operation:

```vhdl
-- Clamp divisor to safe minimum
if abs(x_current) < to_signed(4, 32) then
    x_current <= to_signed(4, 32);
end if;

-- Fixed-point division with overflow check
temp_div := shift_left(resize(x_input, 64), 12);  -- x << FRAC_BITS
temp_div := temp_div / x_current;

if temp_div > to_signed(2147483647, 64) then
    div_result <= to_signed(2147483647, 32);  -- Saturate
elsif temp_div < to_signed(-2147483648, 64) then
    div_result <= to_signed(-2147483648, 32);
else
    div_result <= temp_div(31 downto 0);
end if;
```

---

### Complete Newton-Raphson FSM

```vhdl
type state_type is (IDLE, INIT, ITERATE, FINISH);
signal state : state_type := IDLE;

process(clk)
    variable temp_div : signed(63 downto 0);
    variable temp_sum : signed(63 downto 0);
    variable x_next : signed(31 downto 0);
    variable delta : signed(31 downto 0);
begin
    if rising_edge(clk) then
        case state is
            when IDLE =>
                if start = '1' then
                    x_input <= input;
                    iteration <= 0;
                    state <= INIT;
                end if;

            when INIT =>
                -- Adaptive initial guess
                if x_input < to_signed(4096, 32) then
                    x_current <= x_input;
                elsif x_input > to_signed(409600, 32) then
                    x_current <= '0' & '0' & x_input(31 downto 2);
                else
                    x_current <= '0' & x_input(31 downto 1);
                end if;
                state <= ITERATE;

            when ITERATE =>
                -- Compute x_next = (x_current + x / x_current) / 2

                -- Division: x / x_current
                temp_div := x_input * 4096;
                temp_div := temp_div / x_current;

                -- Addition: x_current + div_result
                temp_sum := resize(x_current, 64) + temp_div;

                -- Division by 2: shift right 1
                x_next := temp_sum(32 downto 1);

                -- Check convergence
                delta := abs(x_next - x_current);

                if delta < TOLERANCE then
                    state <= FINISH;
                elsif iteration >= MAX_ITERATIONS - 1 then
                    state <= FINISH;
                else
                    x_current <= x_next;
                    iteration <= iteration + 1;
                end if;

            when FINISH =>
                output <= x_current;
                done <= '1';
                state <= IDLE;
        end case;
    end if;
end process;
```

---

### Performance Metrics

| Input Range | Iterations (avg) | Max Error | Status |
|-------------|------------------|-----------|---------|
| 0.01 - 0.1 | 10-12 | 0.15% | ✅ PASS |
| 0.1 - 1.0 | 8-10 | 0.5% | ✅ PASS |
| 1.0 - 100 | 6-8 | 0.5% | ✅ PASS |
| 100 - 1000 | 8-10 | 0.00007% | ✅ PASS |
| 1000 - 10000 | 10-12 | 1.2% | ⚠️ MARGINAL |

**Overall**: 39/40 tests pass (97.5% success rate)

---

## Cholesky Decomposition Specifics

### Algorithm Overview

For symmetric positive-definite 3x3 matrix `A`, decompose into `L * L^T`:

```
A = | a11  a21  a31 |     L = | l11   0    0  |
    | a21  a22  a32 |         | l21  l22   0  |
    | a31  a32  a33 |         | l31  l32  l33 |
```

**Formulas**:
```
l11 = sqrt(a11)
l21 = a21 / l11
l31 = a31 / l11
l22 = sqrt(a22 - l21^2)
l32 = (a32 - l21*l31) / l22
l33 = sqrt(a33 - l31^2 - l32^2)
```

---

### FSM Implementation

**States**: `IDLE → CALC_L11 → WAIT_L11 → CALC_L21_L31 → CALC_L22 → WAIT_L22 → CALC_L32 → CALC_L33 → WAIT_L33 → FINISH`

**Key Points**:
- Each sqrt requires **start → wait for done** handshake
- Each state computes one or two matrix elements
- Fixed-point arithmetic **must be inline** (XSIM requirement)

```vhdl
process(clk)
    variable temp_mult : signed(63 downto 0);
    variable temp_div : signed(63 downto 0);
begin
    if rising_edge(clk) then
        sqrt_start <= '0';  -- Default

        case state is
            when IDLE =>
                if start = '1' then
                    -- Load input matrix
                    a11 <= input_matrix(0);
                    a21 <= input_matrix(1);
                    a22 <= input_matrix(2);
                    -- ...
                    state <= CALC_L11;
                end if;

            when CALC_L11 =>
                sqrt_x_in <= a11;
                sqrt_start <= '1';
                state <= WAIT_L11;

            when WAIT_L11 =>
                if sqrt_done = '1' then
                    l11 <= sqrt_x_out;
                    state <= CALC_L21_L31;
                end if;

            when CALC_L21_L31 =>
                -- Inline fixed-point division
                temp_div := a21 * 4096;
                temp_div := temp_div / l11;
                l21 <= temp_div(31 downto 0);

                temp_div := a31 * 4096;
                temp_div := temp_div / l11;
                l31 <= temp_div(31 downto 0);

                state <= CALC_L22;

            when CALC_L22 =>
                -- Inline fixed-point multiply and subtract
                temp_mult := l21 * l21;
                sqrt_x_in <= a22 - temp_mult(43 downto 12);
                sqrt_start <= '1';
                state <= WAIT_L22;

            when WAIT_L22 =>
                if sqrt_done = '1' then
                    l22 <= sqrt_x_out;
                    state <= CALC_L32;
                end if;

            when CALC_L32 =>
                -- Inline multiply, subtract, divide
                temp_mult := l21 * l31;
                temp_div := (a32 - temp_mult(43 downto 12)) * 4096;
                temp_div := temp_div / l22;
                l32 <= temp_div(31 downto 0);
                state <= CALC_L33;

            when CALC_L33 =>
                -- Inline multiply, subtract, sqrt
                variable temp_sub : signed(31 downto 0);
                temp_mult := l31 * l31;
                temp_sub := a33 - temp_mult(43 downto 12);
                temp_mult := l32 * l32;
                sqrt_x_in <= temp_sub - temp_mult(43 downto 12);
                sqrt_start <= '1';
                state <= WAIT_L33;

            when WAIT_L33 =>
                if sqrt_done = '1' then
                    l33 <= sqrt_x_out;
                    state <= FINISH;
                end if;

            when FINISH =>
                output_matrix(0) <= l11;
                output_matrix(1) <= l21;
                output_matrix(2) <= l22;
                output_matrix(3) <= l31;
                output_matrix(4) <= l32;
                output_matrix(5) <= l33;
                done <= '1';
                state <= IDLE;
        end case;
    end if;
end process;
```

---

### Integration with sqrt_newton

**Entity ports must match exactly**:

```vhdl
-- sqrt_newton entity
entity sqrt_newton is
    port (
        clk      : in  std_logic;
        start_rt : in  std_logic;  -- NOT 'start'!
        x_in     : in  signed(31 downto 0);
        x_out    : out signed(31 downto 0);  -- NOT 'result'!
        done     : out std_logic
    );
end entity;

-- In Cholesky design
sqrt_inst: entity work.sqrt_newton
    port map (
        clk      => clk,
        start_rt => sqrt_start,  -- Match port name
        x_in     => sqrt_x_in,
        x_out    => sqrt_x_out,  -- Match port name
        done     => sqrt_done
    );
```

---

### Common Pitfalls

| Problem | Symptom | Solution |
|---------|---------|----------|
| Wrong sqrt port names | Compilation error | Check original entity definition |
| Using package functions | SIGSEGV in XSIM | Inline all arithmetic |
| Forgot to pulse sqrt_start | Hangs in WAIT state | Set `sqrt_start <= '1'` in CALC state |
| Didn't reset sqrt_start | Continuous triggers | Default `sqrt_start <= '0'` |
| Overflow in subtraction | Wrong results | Check intermediate values |
| Division by small l_ii | Huge results | Validate matrix is pos-definite |

---

## Testbench Design Guidelines

### Essential Protection #1: Division by Zero

**Problem**: Testing `sqrt(0)` or edge cases causes testbench crash.

**Broken Code**:
```vhdl
error_pct := abs((actual - expected) / expected) * 100.0;  -- CRASHES if expected = 0!
```

**Fixed Code**:
```vhdl
if expected = 0.0 then
    if actual = 0.0 then
        error_pct := 0.0;  -- Both zero = perfect match
    else
        error_pct := 100.0;  -- Non-zero actual = 100% error
    end if;
else
    error_pct := abs((actual - expected) / expected) * 100.0;
end if;
```

---

### Essential Protection #2: Tolerance vs Absolute Error

**For values near zero**: Relative error is meaningless.

**Solution**: Use absolute tolerance for small values:

```vhdl
constant ABS_TOLERANCE : real := 0.01;  -- Absolute error < 0.01
constant REL_TOLERANCE : real := 0.5;   -- Relative error < 0.5%

procedure verify_result(actual, expected : real; test_name : string) is
    variable abs_error : real;
    variable rel_error : real;
begin
    abs_error := abs(actual - expected);

    if abs(expected) < ABS_TOLERANCE then
        -- Near zero: use absolute error
        if abs_error < ABS_TOLERANCE then
            report test_name & " PASS (abs error: " & real'image(abs_error) & ")";
        else
            report test_name & " FAIL (abs error: " & real'image(abs_error) & ")" severity error;
        end if;
    else
        -- Normal: use relative error
        rel_error := abs_error / abs(expected) * 100.0;
        if rel_error < REL_TOLERANCE then
            report test_name & " PASS (rel error: " & real'image(rel_error) & "%)";
        else
            report test_name & " FAIL (rel error: " & real'image(rel_error) & "%)" severity error;
        end if;
    end if;
end procedure;
```

---

### Comprehensive Test Strategy

#### Test Categories

**1. Directed Tests** (Basic functionality)
```vhdl
-- Perfect squares
test_sqrt(4.0, 2.0);
test_sqrt(9.0, 3.0);
test_sqrt(16.0, 4.0);
test_sqrt(25.0, 5.0);

-- Edge cases
test_sqrt(0.0, 0.0);
test_sqrt(1.0, 1.0);

-- Simple values
test_sqrt(2.0, 1.414);
test_sqrt(3.0, 1.732);
```

**2. Parametric Sweep** (Coverage)
```vhdl
-- Systematic range coverage
for i in 1 to 20 loop
    test_sqrt(real(i * 5), sqrt(real(i * 5)));
end loop;
```

**3. Edge/Stress Cases** (Algorithm limits)
```vhdl
-- Very small
test_sqrt(0.01, 0.1);
test_sqrt(0.1, 0.316);

-- Very large
test_sqrt(1000.0, 31.62);
test_sqrt(10000.0, 100.0);

-- Fractional
test_sqrt(0.25, 0.5);
test_sqrt(2.25, 1.5);
```

**4. Boundary Cases** (Q format limits)
```vhdl
-- Maximum safe value for Q20.12
test_sqrt(524000.0, 724.0);  -- Near max integer bits
```

---

### Test Result Reporting

```vhdl
-- Track statistics
variable tests_passed : integer := 0;
variable tests_failed : integer := 0;

-- At end of testbench
report "========================================";
report "TEST SUMMARY";
report "========================================";
report "Total:  " & integer'image(tests_passed + tests_failed);
report "Passed: " & integer'image(tests_passed);
report "Failed: " & integer'image(tests_failed);
if tests_failed = 0 then
    report "ALL TESTS PASSED";
else
    report "SOME TESTS FAILED" severity error;
end if;
```

---

### XSIM-Compatible Testbench Template

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity my_tb is
end entity;

architecture Behavioral of my_tb is
    -- Clock and reset
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';

    -- DUT signals
    signal start : std_logic := '0';
    signal done : std_logic;
    signal input : signed(31 downto 0);
    signal output : signed(31 downto 0);

    -- Testbench control
    signal sim_done : boolean := false;

    -- Constants
    constant CLK_PERIOD : time := 10 ns;
    constant SCALE : real := 4096.0;  -- For Q20.12

begin
    -- Clock generation
    clk <= not clk after CLK_PERIOD/2 when not sim_done else '0';

    -- DUT instantiation (direct entity, not component!)
    uut: entity work.my_design
        port map (
            clk => clk,
            rst => rst,
            start => start,
            done => done,
            input => input,
            output => output
        );

    -- Stimulus process
    process
        -- Helper function: Convert real to Q20.12
        function to_fixed(val : real) return signed is
        begin
            return to_signed(integer(val * SCALE), 32);
        end function;

        -- Helper function: Convert Q20.12 to real
        function from_fixed(val : signed) return real is
        begin
            return real(to_integer(val)) / SCALE;
        end function;

        -- Test procedure
        procedure test_case(input_val : real; expected : real; name : string) is
            variable actual : real;
            variable error : real;
        begin
            wait until rising_edge(clk);
            input <= to_fixed(input_val);
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            wait until done = '1';
            actual := from_fixed(output);

            -- Protected error calculation
            if expected = 0.0 then
                if actual = 0.0 then
                    error := 0.0;
                else
                    error := 100.0;
                end if;
            else
                error := abs((actual - expected) / expected) * 100.0;
            end if;

            if error < 1.0 then
                report name & " PASS (error: " & real'image(error) & "%)";
            else
                report name & " FAIL (error: " & real'image(error) & "%)" severity error;
            end if;
        end procedure;

    begin
        -- Reset
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait until rising_edge(clk);

        -- Run tests
        test_case(4.0, 2.0, "sqrt(4)");
        test_case(9.0, 3.0, "sqrt(9)");
        test_case(0.0, 0.0, "sqrt(0)");

        -- Finish
        wait for 100 ns;
        sim_done <= true;
        report "SIMULATION COMPLETE";
        wait;
    end process;

end architecture;
```

---

## Complete Troubleshooting Workflow

### Scenario 1: XSIM SIGSEGV Crash

**Symptom**: `ERROR: [XSIM 43-3316] Signal SIGSEGV received`

**Workflow**:
1. ✅ Check if using component declarations → Replace with direct entity instantiation
2. ✅ Check if using package functions with arithmetic → Inline the arithmetic
3. ✅ Check if using `to_signed()` in package constants → Use integer constants
4. ✅ If still crashing: Binary search (comment everything, uncomment half at a time)
5. ✅ Isolate exact line causing crash
6. ✅ Apply workaround from [XSIM Known Issues](#xsim-known-issues--workarounds)

---

### Scenario 2: Numerical Algorithm Inaccuracy

**Symptom**: Tests failing with high error percentage

**Workflow**:
1. ✅ Check testbench: Is division by zero protected?
2. ✅ Check algorithm: Is initial guess appropriate for input range?
3. ✅ Check convergence: Are enough iterations provided?
4. ✅ Check arithmetic: Is overflow protection implemented?
5. ✅ Check Q format: Is fractional resolution sufficient?
6. ✅ Add debug: Print intermediate values in simulation

**Example Debug**:
```vhdl
report "Iteration " & integer'image(iteration) &
       ": x_current = " & integer'image(to_integer(x_current)) &
       " delta = " & integer'image(to_integer(delta));
```

---

### Scenario 3: Design Hangs in Simulation

**Symptom**: Simulation runs forever, no output

**Workflow**:
1. ✅ Check FSM: Are all states reachable?
2. ✅ Check handshakes: Is `start → done` working?
3. ✅ Check signals: Are control signals pulsed or held?
4. ✅ Add timeouts in testbench:

```vhdl
-- In testbench
wait until done = '1' for 10 us;
if done /= '1' then
    report "TIMEOUT: Design did not complete" severity error;
    sim_done <= true;
end if;
```

5. ✅ Add state tracking:
```vhdl
-- In DUT
signal state_debug : integer;
state_debug <= state_type'pos(state);  -- Convert enum to integer for waveform
```

---

### Scenario 4: Synthesis vs Simulation Mismatch

**Symptom**: Works in simulation, fails in hardware

**Workflow**:
1. ✅ Check for uninitialized signals
2. ✅ Check for combinational loops
3. ✅ Check timing: Add constraints, check timing report
4. ✅ Check bit widths: Are all signals sized correctly?
5. ✅ Run post-synthesis simulation (functional)
6. ✅ Run post-implementation simulation (timing)

---

## Quick Reference Tables

### XSIM Compatibility Checklist

| Feature | XSIM Safe? | Alternative |
|---------|-----------|-------------|
| Component declaration | ❌ NO | Direct entity instantiation |
| Package function arithmetic | ❌ NO | Inline arithmetic |
| `to_signed()` in package | ❌ NO | Integer constant + convert at use |
| `shift_right()`, `resize()` | ⚠️ RISKY | Manual bit slicing |
| Direct entity instantiation | ✅ YES | - |
| Inline arithmetic | ✅ YES | - |
| Integer constants | ✅ YES | - |
| ASCII strings only | ✅ YES | - |

---

### Fixed-Point Operation Reference (Q20.12)

| Operation | Code | Notes |
|-----------|------|-------|
| Multiply | `temp := a * b;`<br>`result <= temp(43:12);` | Use 64-bit intermediate |
| Divide | `temp := a * 4096;`<br>`result <= (temp / b)(31:0);` | Scale numerator |
| Add | `result <= a + b;` | Direct (same scale) |
| Subtract | `result <= a - b;` | Direct (same scale) |
| To fixed | `to_signed(integer(val * 4096.0), 32)` | Real → Q20.12 |
| From fixed | `real(to_integer(val)) / 4096.0` | Q20.12 → Real |

---

### Newton-Raphson Tuning Parameters

| Parameter | Recommended | Range | Impact |
|-----------|------------|-------|--------|
| MAX_ITERATIONS | 12 | 8-16 | Accuracy vs latency |
| TOLERANCE | 4 (0.001) | 2-10 | Convergence threshold |
| Initial guess (< 1.0) | input | - | Best for small |
| Initial guess (1-100) | input/2 | - | Best for normal |
| Initial guess (> 100) | input/4 | - | Best for large |

---

### Error Categorization

| Category | Can Auto-Fix? | Examples |
|----------|--------------|----------|
| Syntax errors | ✅ YES | Missing semicolon, wrong keyword |
| Port mismatches | ✅ YES | Wrong entity name, port name |
| Type mismatches | ✅ YES | std_logic vs signed |
| Division by zero | ✅ YES | Add protection in testbench |
| Algorithm design | ❌ NO | Initial guess strategy |
| Convergence criteria | ❌ NO | Tolerance, max iterations |
| Overflow handling | ❌ NO | Saturate vs wrap vs flag |
| Input validation | ❌ NO | Supported range |

---

## Conclusion

### Key Success Factors

1. **XSIM Compatibility**
   - Use direct entity instantiation
   - Inline all arithmetic operations
   - Avoid component declarations and package functions
   - Test incrementally with binary search debugging

2. **Fixed-Point Arithmetic**
   - Document Q format clearly
   - Use 64-bit intermediates for 32-bit operations
   - Implement overflow protection at every step
   - Clamp divisors to prevent extreme results

3. **Iterative Algorithms**
   - Adaptive initial guess (range-based)
   - Early convergence detection (tolerance-based)
   - Maximum iteration safety limit
   - Comprehensive edge case testing

4. **Testbench Design**
   - Protect division by zero
   - Use absolute tolerance near zero
   - Test edge cases: 0, very small, very large
   - Report statistics: passed/failed/total

### Most Impactful Improvements

- **Adaptive initial guess**: 99.7% error reduction
- **Overflow protection**: Prevents catastrophic failures
- **Binary search debugging**: Isolated XSIM bugs in minutes vs hours
- **Inline arithmetic**: Made XSIM compatibility possible

### Future Recommendations

1. **Always start simple** - Minimal design first, add complexity incrementally
2. **Test after every change** - Catch issues early
3. **Document Q format** - In comments, constants, and documentation
4. **Use binary search** - First debugging step for XSIM crashes
5. **Keep backups** - Save working versions before major changes

---

**Document Version**: 1.0
**Last Updated**: 2025-10-24
**Status**: Complete and Verified
**Projects Covered**: Newton-Raphson Square Root, Cholesky 3x3 Decomposition
**Target Simulator**: Xilinx Vivado XSIM 2023.02 - 2025.1

---

## Document History

- **2025-10-24**: Initial compilation from individual learning documents
  - newton_raphson_lessons.md
  - cholesky_fixes_applied.md
  - xsim_debugging_techniques.md
  - xsim_fixed_point_issue.md
  - cholesky_xsim_solution.md

---

**End of Document**
