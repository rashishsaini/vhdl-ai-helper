# Neural Network Training Datapath Lessons

Lessons learned from implementing weight update, delta calculator, dot product, and vector accumulator modules for neural network training in VHDL.

## Overview

This document captures critical debugging insights and design patterns discovered during the implementation of the backward pass (backpropagation) datapath components.

---

## Key Lessons

### Lesson 1: Metavalue Warnings - Expected vs. Problematic

**Discovery:** During backward datapath simulation, metavalue warnings appeared when reading uninitialized gradient bank entries.

**Understanding:**
```
-- Metavalue warnings from reading uninitialized registers
-- are EXPECTED in certain cases:
-- 1. Gradients not yet computed (read before backprop writes)
-- 2. Unused array entries
-- 3. First cycle after reset before initialization
```

**When Metavalues are EXPECTED (Not Errors):**
- Reading gradient bank entries before backprop has written them
- First read from any register bank after power-on (before init)
- Unused portions of oversized arrays

**When Metavalues are ERRORS (Need Fixing):**
- Using a pipeline register (`product`, `sum`, etc.) before it has valid data
- Comparing against uninitialized saturation signals
- Using signals in arithmetic before they're assigned

**Key Diagnostic Question:** "Is this read intentional (design expects to handle it) or accidental (logic error)?"

---

### Lesson 2: Sub-cycle Timing in Multi-Phase State Machines

**Problem:** Weight update showed weights as 0 after update operation.

**Root Cause:** The sub_cycle timing caused a write-before-data-ready issue:
```vhdl
-- PROBLEMATIC: Data computed and write enable in same cycle
-- sub_cycle=0: new_weight_reg is computed
-- sub_cycle=1: wr_en goes high
-- But sub_cycle transitions on same clock edge!
-- Result: Write happens before new_weight_reg is stable
```

**The Critical Insight:**
```vhdl
-- When state machine uses sub_cycle phases:
-- Phase 0: Setup/compute
-- Phase 1: Execute action
--
-- If both phases happen on consecutive clock edges,
-- the "execute" sees the OLD computed value, not the new one
-- because register updates are concurrent
```

**Correct Pattern:**
```vhdl
-- Option A: Compute one cycle BEFORE the write
COMPUTE_STATE:
    new_weight_reg <= weight + delta * lr;  -- Compute
    -- Next cycle: transition to WRITE_STATE

WRITE_STATE:
    wr_en <= '1';  -- Write the already-computed value

-- Option B: Use sub_cycle with proper delays
if sub_cycle = 0 then
    new_weight_reg <= weight + delta * lr;
    sub_cycle <= 1;
elsif sub_cycle = 1 then
    -- new_weight_reg is NOW stable
    sub_cycle <= 2;  -- Wait one more cycle
elsif sub_cycle = 2 then
    wr_en <= '1';  -- Safe to write
end if;
```

**Key Rule:** Allow at least ONE clock cycle between computing a value and using it for a write operation.

---

### Lesson 3: Pipeline Timing - Valid Signal Propagation

**Problem:** Delta calculator testbench failures due to valid signal timing.

**Issue:** Valid signal only pulses for one cycle, but testbench samples at the wrong time.
```vhdl
-- WRONG: Testbench checks result immediately
start <= '1';
wait for CLK_PERIOD;
start <= '0';
wait for 5 * CLK_PERIOD;  -- Arbitrary wait
-- Check result - BUT valid may have already pulsed and gone low!
```

**Correct Pattern:** Wait for and sample on valid signal:
```vhdl
-- RIGHT: Wait for valid, then sample
start <= '1';
wait for CLK_PERIOD;
start <= '0';

-- Wait for valid to go high
wait until done = '1' and rising_edge(clk);
-- NOW sample the output
actual_result := output;

-- OR use a watchdog timeout
for i in 0 to MAX_CYCLES loop
    wait for CLK_PERIOD;
    if done = '1' then
        actual_result := output;
        exit;
    end if;
end loop;
```

**Pipeline-Aware Testbench Pattern:**
```vhdl
-- For multi-stage pipelines, track latency
constant PIPELINE_LATENCY : integer := 5;  -- Know your pipeline depth

-- Apply input
input <= test_value;
valid_in <= '1';
wait for CLK_PERIOD;
valid_in <= '0';

-- Wait for pipeline to flush
wait for PIPELINE_LATENCY * CLK_PERIOD;

-- Sample output when valid
if valid_out = '1' then
    check_result(output, expected);
end if;
```

---

### Lesson 4: Testbench Array Initialization

**Problem:** Metavalues appearing in saturation logic comparisons.

**Root Cause:** Testbench weight/gradient arrays not properly initialized before use.

**Anti-Pattern:**
```vhdl
signal weights : weight_array_t;  -- UNINITIALIZED - contains 'U'

-- Later in testbench...
-- First access reads 'U' values, causing metavalue errors
```

**Correct Patterns:**

**Pattern A: Default initialization in declaration:**
```vhdl
signal weights : weight_array_t := (others => (others => '0'));
```

**Pattern B: Explicit initialization in test process:**
```vhdl
test_proc: process
begin
    -- Initialize ALL array elements before any test
    for i in weights'range loop
        weights(i) <= to_signed(0, DATA_WIDTH);
    end loop;
    wait for CLK_PERIOD;  -- Let initialization settle

    -- NOW run tests...
end process;
```

**Pattern C: Write-before-read sequencing:**
```vhdl
-- Always write test values before reading them back
-- Test 1: Write weight to address 0
wr_addr <= 0;
wr_data <= test_value;
wr_en <= '1';
wait for CLK_PERIOD;
wr_en <= '0';

-- Test 2: Now safe to read address 0
rd_addr <= 0;
wait for CLK_PERIOD;
check_value(rd_data, test_value);
```

---

### Lesson 5: GHDL Iteration Methodology

**Workflow for Systematic Debugging:**

1. **Syntax Analysis First:**
```bash
ghdl -a --std=08 file.vhd
# Fix ALL syntax errors before proceeding
```

2. **Elaborate to Check Binding:**
```bash
ghdl -e --std=08 testbench_name
# Catches missing components, port mismatches
```

3. **Run Simulation:**
```bash
ghdl -r --std=08 testbench_name --stop-time=1ms
# Watch for runtime errors
```

4. **Categorize Failures:**
   - **SYNTAX errors:** Fix immediately
   - **ELABORATION errors:** Usually port/component mismatches
   - **SIMULATION errors:** Logic bugs, timing issues
   - **METAVALUE warnings:** Evaluate if expected or error

5. **Iterate:**
   - Fix one category at a time
   - Re-run full test after each fix
   - Don't chase metavalue warnings until logic is correct

---

### Lesson 6: Clear/Reset State Machine Interaction

**Problem:** Dot product unit clear doesn't properly reset state.

**Issue:** Clear signal doesn't reset all internal registers:
```vhdl
-- INCOMPLETE: Only resets accumulator
if clear = '1' then
    accumulator <= (others => '0');
end if;
-- But index counter, valid flags, partial products still have old values!
```

**Complete Reset Pattern:**
```vhdl
if rst = '1' or clear = '1' then
    accumulator <= (others => '0');
    index <= 0;
    valid <= '0';
    partial_product <= (others => '0');
    state <= IDLE;
    -- Reset ALL state-carrying signals
end if;
```

**Key Rule:** `clear` should reset the same signals as `rst` (except maybe configuration registers).

---

### Lesson 7: Vector Accumulator Maximum Length

**Problem:** Vector accumulator fails for maximum vector lengths.

**Root Cause:** Counter overflow or off-by-one errors:
```vhdl
-- BUG: Counter wraps at 2^N, not at NUM_ELEMENTS
signal count : unsigned(3 downto 0);  -- Wraps at 16
constant NUM_ELEMENTS : integer := 16;  -- Off-by-one possible

-- FIXED: Explicit comparison
if count = NUM_ELEMENTS - 1 then
    done <= '1';
    count <= (others => '0');
end if;
```

**Additional Issue:** Accumulator width must accommodate worst-case sum:
```vhdl
-- For N elements of W-bit signed values:
-- Worst case: N * (max_value)
-- Need: W + ceil(log2(N)) bits to avoid overflow

-- Example: 16 elements of 16-bit values
-- Need: 16 + 4 = 20 bits minimum for accumulator
```

---

## Component-Specific Notes

### Weight Update Datapath
- Uses multi-cycle state machine with sub_cycle phases
- Critical timing: new_weight computation to wr_en assertion
- Must handle learning rate multiplication overflow

### Delta Calculator
- Pipeline with fixed latency
- Valid signal pulses for exactly one cycle
- Testbench must synchronize to valid output

### Dot Product Unit
- Iterative MAC (multiply-accumulate)
- Clear must reset index AND accumulator
- Accumulator needs extra bits for sum growth

### Vector Accumulator
- Length parameterized via generic
- Counter must handle length=1 edge case
- Done signal timing critical for chained operations

---

## Summary of Key Rules

1. **Metavalues:** Distinguish expected (design intent) from errors (bugs)
2. **Sub-cycles:** Allow full clock cycle between compute and use
3. **Pipeline timing:** Wait for valid, don't assume fixed latency
4. **Array init:** Initialize arrays in testbenches before any access
5. **Clear vs Reset:** Both should reset ALL state, not just some
6. **Counter bounds:** Explicit comparison, not rollover reliance
7. **Accumulator width:** Account for worst-case sum growth

---

## Related Documents

- `weight_register_bank_design_patterns.md` - Register bank patterns
- `sigmoid_unit_design_patterns.md` - Activation pipeline patterns
- `input_buffer_design_patterns.md` - Buffer initialization patterns
- `COMPREHENSIVE_VHDL_XSIM_REFERENCE.md` - General VHDL reference

---

**Last Updated:** November 28, 2025
**Source:** Weight update, delta calculator, dot product, and vector accumulator implementation sessions
**Status:** Lessons extracted from debugging sessions
