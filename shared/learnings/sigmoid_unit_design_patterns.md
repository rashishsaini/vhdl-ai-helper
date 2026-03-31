# Sigmoid Unit Design Patterns and Lessons Learned

**Date:** November 26, 2025
**Module:** `sigmoid_unit.vhd`
**Status:** Working - All tests passing

---

## Overview

The sigmoid activation function unit computes:
```
sigmoid(x) = 1 / (1 + e^(-x))
```

This is implemented as a pipeline of two sub-modules:
1. **exp_approximator** - Computes e^(-x) using piecewise linear approximation
2. **reciprocal_unit** - Computes 1/(1 + e^(-x)) using Newton-Raphson iteration

---

## Architecture Summary

### Data Flow
```
Input x (Q2.13)
    |
    v
[Negate: -x]
    |
    v
[exp_approximator] --> e^(-x)
    |
    v
[Add ONE: 1 + e^(-x)]
    |
    v
[reciprocal_unit] --> 1/(1 + e^(-x))
    |
    v
[Saturation: clamp to [0, 1)]
    |
    v
Output sigmoid(x) (Q2.13)
```

### FSM States (7 states)
```
IDLE --> START_EXP --> WAIT_EXP --> ADD_ONE --> START_RECIP --> WAIT_RECIP --> OUTPUT_ST --> IDLE
```

### Latency
- **Total:** 20 clock cycles
- exp_approximator: ~4 cycles
- reciprocal_unit: ~14 cycles (3 Newton-Raphson iterations)
- FSM overhead: ~2 cycles

---

## Key Design Patterns

### Pattern 1: Component-Based Hierarchical Design
The sigmoid unit demonstrates clean modular design:
- Each sub-function is a separate entity
- Clear interfaces with start/done handshaking
- Reusable components (reciprocal_unit used in multiple places)

```vhdl
-- Component declarations in architecture declarative region
component exp_approximator is
    generic (...);
    port (
        clk, rst, start : in std_logic;
        data_in  : in signed(...);
        data_out : out signed(...);
        done, busy, overflow, underflow : out std_logic
    );
end component;
```

### Pattern 2: FSM Sequencing of Multiple Operations
When pipelining multiple operations:
1. **Start** sub-module with start pulse
2. **Wait** in dedicated state until done signal
3. **Process** intermediate result
4. **Start** next sub-module
5. Repeat until complete

```vhdl
when START_EXP =>
    exp_input <= neg_x;
    exp_start <= '1';  -- Single-cycle pulse
    state <= WAIT_EXP;

when WAIT_EXP =>
    if exp_done = '1' then
        state <= ADD_ONE;  -- Process result
    end if;
```

### Pattern 3: Saturation with Extended Arithmetic
Use wider intermediate signals to detect overflow before saturation:

```vhdl
variable sum_extended : signed(DATA_WIDTH downto 0);  -- 1 extra bit
...
sum_extended := resize(ONE, DATA_WIDTH+1) + resize(exp_result, DATA_WIDTH+1);

if sum_extended > to_signed(32767, DATA_WIDTH+1) then
    one_plus_exp <= to_signed(32767, DATA_WIDTH);  -- Saturate
    ovf_reg <= '1';
else
    one_plus_exp <= resize(sum_extended, DATA_WIDTH);  -- Normal
end if;
```

### Pattern 4: Edge Case Handling for Negation
Handle the asymmetry of two's complement (-32768 cannot be negated to +32768):

```vhdl
if data_in = to_signed(-32768, DATA_WIDTH) then
    neg_x <= to_signed(32767, DATA_WIDTH);  -- Clamp to representable value
else
    neg_x <= -data_in;
end if;
```

### Pattern 5: Single-Cycle Start Pulses
Always clear start signals after one cycle to prevent re-triggering:

```vhdl
-- Default: clear single-cycle signals at start of process
done_reg    <= '0';
exp_start   <= '0';
recip_start <= '0';

case state is
    when START_EXP =>
        exp_start <= '1';  -- Will auto-clear next cycle
        state <= WAIT_EXP;
    ...
```

### Pattern 6: Output Range Clamping
Sigmoid output is mathematically bounded to (0, 1), enforce this:

```vhdl
constant SIG_MAX : signed := to_signed(8191, DATA_WIDTH);  -- ~0.9999
constant SIG_MIN : signed := to_signed(1, DATA_WIDTH);     -- ~0.0001

if recip_result > SIG_MAX then
    result_reg <= SIG_MAX;
elsif recip_result < SIG_MIN then
    result_reg <= SIG_MIN;
else
    result_reg <= recip_result;
end if;
```

---

## Fixed-Point Format: Q2.13

### Format Details
- **Total bits:** 16 (signed)
- **Integer bits:** 2 (includes sign)
- **Fractional bits:** 13
- **Range:** [-4.0, +3.9999]
- **Resolution:** 1/8192 = 0.000122

### Key Constants
```vhdl
constant ONE : signed := to_signed(8192, 16);      -- 1.0
constant SCALE : real := 8192.0;                   -- 2^13
```

### Conversion Functions (for testbench)
```vhdl
-- Real to Q2.13
function real_to_fixed(val : real) return signed is
begin
    return to_signed(integer(round(val * 8192.0)), 16);
end function;

-- Q2.13 to Real
function fixed_to_real(val : signed) return real is
begin
    return real(to_integer(val)) / 8192.0;
end function;
```

---

## Performance Analysis

### Accuracy Results
| Input x | Expected | Actual | Error |
|---------|----------|--------|-------|
| 0.0 | 0.5000 | 0.4985 | 0.29% |
| 1.0 | 0.7311 | 0.7327 | 0.22% |
| -1.0 | 0.2689 | 0.2697 | 0.26% |
| 2.0 | 0.8808 | ~0.88 | <1% |
| -2.0 | 0.1192 | ~0.12 | <1% |

**Average Error:** <0.5%
**Maximum Error:** <5% (within tolerance for neural network applications)

### Resource Utilization (Estimated for Full Sigmoid)
- **LUTs:** ~500-600 (exp_approximator LUT + reciprocal logic)
- **Registers:** ~150 (FSM states + pipeline registers)
- **DSPs:** 8 (from reciprocal_unit Newton-Raphson multiplications)
- **BRAMs:** 0 (LUT-based approximation)

### Latency Breakdown
| Stage | Cycles |
|-------|--------|
| Input capture + negate | 1 |
| exp_approximator | 4 |
| Add ONE | 1 |
| reciprocal_unit | 14 |
| Output | 1 |
| **Total** | **~20** |

---

## Testbench Design Patterns

### Pattern 1: Parameterized Test Procedure
```vhdl
procedure run_test(
    x_input   : real;
    test_name : string
) is
begin
    data_in <= real_to_fixed(x_input);
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';

    -- Wait for completion with timeout
    while done /= '1' loop
        wait until rising_edge(clk);
        if cycle_count > 100 then
            report "TIMEOUT" severity error;
            return;
        end if;
    end loop;

    -- Check result
    ...
end procedure;
```

### Pattern 2: Self-Checking with Tolerance
```vhdl
-- Calculate relative error
function rel_error_pct(expected, actual : real) return real is
begin
    if abs(expected) < 0.0001 then
        return abs(expected - actual) * 100.0;  -- Absolute error for near-zero
    else
        return abs((expected - actual) / expected) * 100.0;
    end if;
end function;

-- Check with tolerance
if err_pct <= tolerance then
    report "PASS";
    pass_count <= pass_count + 1;
else
    report "FAIL";
    fail_count <= fail_count + 1;
end if;
```

### Pattern 3: Comprehensive Test Groups
1. **Reference points:** Known values (0, 1, -1)
2. **Linear region:** Small values around 0
3. **Transition region:** Moderate values (1-3)
4. **Saturation region:** Large values (>3)
5. **Symmetry check:** Verify sigmoid(x) + sigmoid(-x) = 1

---

## Common Issues and Solutions

### Issue 1: Sub-module Done Signal Timing
**Problem:** Missing done signal transition
**Solution:** Wait for done='1', not done transition

```vhdl
-- WRONG: May miss single-cycle pulse
wait until done = '1';

-- CORRECT: Sample on clock edge
while done /= '1' loop
    wait until rising_edge(clk);
end loop;
```

### Issue 2: Start Signal Held Too Long
**Problem:** Sub-module triggered multiple times
**Solution:** Clear start in same state or use dedicated clear

```vhdl
when WAIT_EXP =>
    exp_start <= '0';  -- Explicitly clear (also cleared by default)
    if exp_done = '1' then ...
```

### Issue 3: Intermediate Overflow
**Problem:** 1 + e^(-x) can exceed Q2.13 range for large negative x
**Solution:** Use extended precision for intermediate calculation

---

## Integration Checklist

When integrating sigmoid_unit into a larger design:

- [ ] Connect clock and reset properly
- [ ] Ensure start pulse is single-cycle
- [ ] Wait for done signal before reading output
- [ ] Check busy signal to prevent overlapping operations
- [ ] Monitor overflow flag for diagnostic purposes
- [ ] Ensure input range is within Q2.13 bounds [-4, +4)

---

## Dependencies

This module requires:
1. `exp_approximator.vhd` - Exponential function
2. `reciprocal_unit.vhd` - Newton-Raphson reciprocal

Both must be compiled before sigmoid_unit.

---

## Future Improvements

### Potential Optimizations
1. **Parallel exp computation:** Pre-compute e^x and e^(-x) simultaneously
2. **Reduced iterations:** 2 Newton-Raphson iterations may suffice for neural networks
3. **Fast-path for extremes:** Skip computation for |x| > 4 (output ~0 or ~1)
4. **Pipelining:** Allow new input while previous computation completes

### Alternative Implementations
1. **CORDIC-based:** Could use CORDIC for exp, avoiding LUT
2. **Taylor series:** More accurate but higher latency
3. **Piece-wise LUT only:** Direct sigmoid LUT (faster, less accurate)

---

## References

- Sigmoid function: https://en.wikipedia.org/wiki/Sigmoid_function
- Newton-Raphson reciprocal: See `reciprocal_division_overflow_fixes.md`
- Exponential approximation: See `exp_approximator_debugging_lessons.md`

---

**Status:** Production-ready for neural network accelerator applications
