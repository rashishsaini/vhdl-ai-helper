# VHDL Neural Network Implementation - Comprehensive Learnings

## Project Overview

**Project:** 4-2-1 Neural Network with On-Chip Training in VHDL
**Target:** FPGA deployment at 100 MHz
**Arithmetic:** Q2.13 Fixed-Point (16-bit signed)
**Completion:** 27/29 modules (93%)

---

## Table of Contents

1. [Fixed-Point Arithmetic](#1-fixed-point-arithmetic)
2. [Module Architecture Patterns](#2-module-architecture-patterns)
3. [FSM Design Best Practices](#3-fsm-design-best-practices)
4. [Testbench Development](#4-testbench-development)
5. [Common Errors and Solutions](#5-common-errors-and-solutions)
6. [Simulator Compatibility](#6-simulator-compatibility)
7. [Module-Specific Learnings](#7-module-specific-learnings)
8. [Performance Optimization](#8-performance-optimization)
9. [Verification Methodology](#9-verification-methodology)
10. [Code Templates](#10-code-templates)

---

## 1. Fixed-Point Arithmetic

### 1.1 Q2.13 Format Specification

```
Q2.13 Format (16-bit signed):
+-- Bit 15: Sign bit
+-- Bits 14-13: Integer bits (2 bits -> range [-4, +4))
+-- Bits 12-0: Fractional bits (13 bits -> resolution ~0.000122)

Key Constants:
- ONE   = 8192  (0x2000) = 1.0
- HALF  = 4096  (0x1000) = 0.5
- MAX   = 32767 (0x7FFF) = +3.9998779...
- MIN   = -32768 (0x8000) = -4.0
```

### 1.2 Format Hierarchy

| Format | Bits | Integer | Fractional | Use Case |
|--------|------|---------|------------|----------|
| Q2.13 | 16 | 2 | 13 | Inputs, weights, outputs |
| Q4.26 | 32 | 4 | 26 | Multiplication products |
| Q10.26 | 40 | 10 | 26 | Accumulators (prevent overflow) |

### 1.3 Multiplication Rules

```vhdl
-- Q2.13 x Q2.13 = Q4.26 (32-bit)
signal a, b : signed(15 downto 0);  -- Q2.13
signal product : signed(31 downto 0);  -- Q4.26
product <= a * b;

-- Scale back to Q2.13: shift right by FRAC_BITS with rounding
signal result : signed(15 downto 0);
result <= resize(shift_right(product + 4096, 13), 16);  -- 4096 = 0.5 LSB for rounding
```

### 1.4 Accumulation with Overflow Protection

```vhdl
-- Use wider accumulator to prevent overflow during summation
constant ACCUM_WIDTH : integer := 40;  -- Q10.26

-- Overflow detection pattern
variable sum : signed(ACCUM_WIDTH downto 0);  -- Extra bit for overflow
sum := resize(accum_reg, ACCUM_WIDTH+1) + resize(addend, ACCUM_WIDTH+1);

-- Check overflow: if MSB differs from sign bit, overflow occurred
if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
    overflow_flag <= '1';
    if sum(ACCUM_WIDTH) = '0' then
        accum_reg <= MAX_ACCUM;  -- Positive overflow -> saturate to max
    else
        accum_reg <= MIN_ACCUM;  -- Negative overflow -> saturate to min
    end if;
else
    accum_reg <= sum(ACCUM_WIDTH-1 downto 0);
end if;
```

### 1.5 Conversion Functions

```vhdl
-- Real to Q2.13
function to_fixed(val : real) return signed is
    variable temp : integer;
begin
    temp := integer(val * real(2**13));
    if temp > 32767 then temp := 32767; end if;
    if temp < -32768 then temp := -32768; end if;
    return to_signed(temp, 16);
end function;

-- Q2.13 to Real (for testbenches)
function to_real(val : signed) return real is
begin
    return real(to_integer(val)) / real(2**13);
end function;

-- Q4.26 Product to Real
function prod_to_real(val : signed(31 downto 0)) return real is
begin
    return real(to_integer(val)) / real(2**26);
end function;

-- Q10.26 Accumulator to Real
function accum_to_real(val : signed(39 downto 0)) return real is
begin
    return real(to_integer(val)) / real(2**26);
end function;
```

---

## 2. Module Architecture Patterns

### 2.1 Combinational Modules

**Use for:** Simple operations without state (activation, saturation, error calculation)

```vhdl
-- Pattern: Pure combinational logic
architecture rtl of combinational_module is
begin
    -- Direct signal assignments
    output <= input when condition else alternate;

    -- Or process without clock
    process(all_inputs)
    begin
        -- Combinational logic
    end process;
end architecture;
```

**Examples:** `activation_unit`, `saturation_unit`, `error_calculator`, `activation_derivative_unit`

### 2.2 Pipelined Modules

**Use for:** Multi-stage operations requiring timing closure

```vhdl
-- Pattern: Registered pipeline stages
architecture rtl of pipelined_module is
    signal stage1_data : data_type;
    signal stage1_valid : std_logic;
    signal stage2_data : data_type;
    signal stage2_valid : std_logic;
begin
    -- Stage 1
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                stage1_valid <= '0';
            elsif enable = '1' then
                stage1_data <= computation1(input);
                stage1_valid <= '1';
            else
                stage1_valid <= '0';
            end if;
        end if;
    end process;

    -- Stage 2
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                stage2_valid <= '0';
            elsif stage1_valid = '1' then
                stage2_data <= computation2(stage1_data);
                stage2_valid <= '1';
            else
                stage2_valid <= '0';
            end if;
        end if;
    end process;
end architecture;
```

**Examples:** `mac_unit`, `bias_adder`, `rounding_saturation`, `weight_updater`

### 2.3 FSM-Based Modules

**Use for:** Complex sequential operations with multiple steps

```vhdl
-- Pattern: FSM with state machine
architecture rtl of fsm_module is
    type state_t is (IDLE, STATE1, STATE2, DONE_ST);
    signal state : state_t;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                -- Reset all registers
            else
                case state is
                    when IDLE =>
                        if start = '1' then
                            state <= STATE1;
                        end if;
                    when STATE1 =>
                        -- Processing
                        state <= STATE2;
                    when STATE2 =>
                        -- More processing
                        state <= DONE_ST;
                    when DONE_ST =>
                        if out_ready = '1' then
                            state <= IDLE;
                        end if;
                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    -- Output assignments based on state
    busy <= '0' when state = IDLE else '1';
    done <= '1' when state = DONE_ST else '0';
end architecture;
```

**Examples:** `reciprocal_unit`, `sqrt_unit`, `dot_product_unit`, `error_propagator`

### 2.4 Storage Modules

**Use for:** Register banks, caches, buffers

```vhdl
-- Pattern: Register array with read/write ports
architecture rtl of storage_module is
    type reg_array_t is array (0 to NUM_ENTRIES-1) of signed(DATA_WIDTH-1 downto 0);
    signal registers : reg_array_t := (others => (others => '0'));
begin
    -- Synchronous write
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                registers <= (others => (others => '0'));
            elsif wr_en = '1' then
                registers(to_integer(wr_addr)) <= wr_data;
            end if;
        end if;
    end process;

    -- Asynchronous read (or synchronous if registered)
    rd_data <= registers(to_integer(rd_addr)) when rd_en = '1' else (others => '0');
end architecture;
```

**Examples:** `weight_register_bank`, `gradient_register_bank`, `forward_cache`, `input_buffer`

---

## 3. FSM Design Best Practices

### 3.1 State Naming Convention

```vhdl
type state_t is (
    IDLE,           -- Waiting for start
    INIT,           -- Initialization
    LOAD_xxx,       -- Loading data
    COMPUTE_xxx,    -- Computation phase
    ACCUMULATE,     -- Accumulation phase
    OUTPUT_xxx,     -- Output phase
    DONE_ST         -- Completion (use _ST suffix to avoid keyword conflicts)
);
```

### 3.2 Handshaking Patterns

```vhdl
-- Input handshaking (ready/valid)
data_ready <= '1' when state = WAITING_FOR_DATA else '0';

-- When data_valid = '1' and data_ready = '1', data transfer occurs

-- Output handshaking
result_valid <= '1' when state = DONE_ST else '0';

-- When result_valid = '1' and out_ready = '1', result is consumed
when DONE_ST =>
    if out_ready = '1' then
        state <= IDLE;
    end if;
```

### 3.3 Clear vs Reset

```vhdl
-- Reset: Asynchronous or synchronous, clears everything
if rst = '1' then
    state <= IDLE;
    all_registers <= (others => '0');

-- Clear: Synchronous, typically clears data but maintains configuration
elsif clear = '1' then
    accum_reg <= (others => '0');
    count <= (others => '0');
    state <= IDLE;
```

### 3.4 Iteration Counters

```vhdl
-- Newton-Raphson iteration pattern
signal iter_count : integer range 0 to NUM_ITERATIONS;

when ITERATE =>
    if iter_count < NUM_ITERATIONS then
        -- Perform iteration
        iter_count <= iter_count + 1;
    else
        -- Done iterating
        state <= OUTPUT_ST;
    end if;
```

---

## 4. Testbench Development

### 4.1 Standard Testbench Structure

```vhdl
entity tb_module_name is
end entity tb_module_name;

architecture sim of tb_module_name is
    constant CLK_PERIOD : time := 10 ns;

    -- DUT signals
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    -- ... other signals

    -- Test tracking
    signal test_count : integer := 0;
    signal error_count : integer := 0;
    signal sim_done : boolean := false;

begin
    -- Clock generation
    clk <= not clk after CLK_PERIOD/2 when not sim_done else '0';

    -- DUT instantiation
    dut : entity work.module_name
        port map (...);

    -- Test process
    test_proc : process
    begin
        -- Reset sequence
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- Test cases
        report "--- Test 1: Description ---";
        test_count <= test_count + 1;
        -- ... test code

        -- Summary
        report "Total tests: " & integer'image(test_count);
        report "Errors: " & integer'image(error_count);
        if error_count = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "SOME TESTS FAILED!" severity error;
        end if;

        sim_done <= true;
        wait;
    end process;
end architecture;
```

### 4.2 Waiting Patterns

```vhdl
-- Wait for signal with timeout (GHDL compatible)
wait until done = '1' for 1 us;
if done /= '1' then
    report "Timeout waiting for done" severity error;
end if;

-- Polling pattern (more portable across simulators)
for wait_loop in 0 to 100 loop
    wait until rising_edge(clk);
    exit when ready = '1';
end loop;
if ready /= '1' then
    report "Timeout waiting for ready" severity error;
end if;

-- Wait for next clock edge after signal
wait until rising_edge(clk);
wait for 1 ns;  -- Allow signal to settle
```

### 4.3 Test Result Verification

```vhdl
-- Floating-point comparison with tolerance
variable actual : real;
variable expected : real;
variable tolerance : real := 0.001;

actual := to_real(dut_output);
expected := 0.5;

if abs(actual - expected) < tolerance then
    report "PASS: result = " & real'image(actual) severity note;
else
    report "FAIL: expected " & real'image(expected) &
           ", got " & real'image(actual) severity warning;
    error_count <= error_count + 1;
end if;
```

### 4.4 Stimulus Generation

```vhdl
-- Provide input with valid handshaking
wait until ready = '1';
wait until rising_edge(clk);
data_in <= test_value;
data_valid <= '1';
wait until rising_edge(clk);
data_valid <= '0';

-- Sequence of inputs
for i in 0 to num_inputs-1 loop
    wait until ready = '1';
    wait until rising_edge(clk);
    data_in <= test_array(i);
    data_valid <= '1';
    wait until rising_edge(clk);
    data_valid <= '0';
end loop;
```

---

## 5. Common Errors and Solutions

### 5.1 GHDL-Specific Issues

#### Unicode Characters
```vhdl
-- ERROR: invalid character not allowed, even in a string
report "delta = 0.5";  -- Unicode delta

-- SOLUTION: Use ASCII only
report "delta = 0.5";
```

#### Aggregate with Non-Static Index
```vhdl
-- ERROR: aggregate with non-static choice
constant MAX_VAL : signed(WIDTH-1 downto 0) := (WIDTH-1 => '0', others => '1');

-- SOLUTION: Use function
function max_val return signed is
    variable result : signed(WIDTH-1 downto 0);
begin
    result := (others => '1');
    result(WIDTH-1) := '0';
    return result;
end function;
constant MAX_VAL : signed(WIDTH-1 downto 0) := max_val;
```

#### Integer Overflow in Constants
```vhdl
-- ERROR: overflow in constant calculation
constant BIG_VAL : integer := 2**38;  -- Exceeds 32-bit integer

-- SOLUTION: Use appropriate range or real conversion
constant BIG_VAL : signed(39 downto 0) := to_signed(integer(2.0**38), 40);
-- Or break into components
```

### 5.2 Vivado-Specific Issues

#### Wait Statement Timeouts
```vhdl
-- ISSUE: Different behavior in Vivado XSIM
wait until signal = '1' for 500 ns;

-- SOLUTION: Use polling loop
for i in 0 to 50 loop
    wait until rising_edge(clk);
    exit when signal = '1';
end loop;
```

#### Simulation Time
```tcl
# Default run may be too short
run 1000ns  # May not complete all tests

# Solution: Run longer or run all
run 2000ns
run -all
```

### 5.3 Signal Width Mismatches

```vhdl
-- ERROR: actual length does not match formal length
signal wide : signed(31 downto 0);
signal narrow : signed(15 downto 0);
narrow <= wide;  -- Error!

-- SOLUTION: Explicit resize
narrow <= resize(wide, 16);
-- Or extract bits
narrow <= wide(15 downto 0);
```

### 5.4 Sensitivity List Issues

```vhdl
-- VHDL-2008: Use 'all' for combinational processes
process(all)
begin
    -- Combinational logic
end process;

-- Pre-2008: List all read signals
process(input1, input2, input3)
begin
    output <= input1 and input2 or input3;
end process;
```

### 5.5 Reset and Initialization

```vhdl
-- Ensure all signals initialized
signal my_reg : signed(15 downto 0) := (others => '0');

-- In process, reset all registers
if rst = '1' then
    reg1 <= (others => '0');
    reg2 <= (others => '0');
    state <= IDLE;
    -- Don't forget flags!
    overflow_flag <= '0';
    valid_flag <= '0';
```

---

## 6. Simulator Compatibility

### 6.1 GHDL Configuration

```bash
# Analyze (compile) with VHDL-2008
ghdl -a --std=08 module.vhd

# Elaborate (link)
ghdl -e --std=08 tb_module

# Run simulation
ghdl -r --std=08 tb_module --stop-time=10us

# With waveform output
ghdl -r --std=08 tb_module --wave=output.ghw --stop-time=10us
```

### 6.2 Vivado TCL Commands

```tcl
# In Vivado XSIM console
run 1000ns       # Run for specific time
run -all         # Run until $finish or sim_done
restart          # Reset simulation
```

### 6.3 Portable Code Practices

| Feature | GHDL | Vivado | Portable Alternative |
|---------|------|--------|---------------------|
| `wait until X for T` | Yes | Partial | Polling loop |
| Unicode in strings | No | Yes | ASCII only |
| `process(all)` | Yes | Yes | Use for VHDL-2008 |
| Non-static aggregates | No | Yes | Use functions |
| `real'image()` | Yes | Yes | Both support |

---

## 7. Module-Specific Learnings

### 7.1 Reciprocal Unit (Newton-Raphson)

**Key Insight:** Normalization improves convergence

```vhdl
-- Normalize input to [0.5, 1.0) range
-- Track shift amount for denormalization
-- Use LUT for initial estimate
-- Formula: x_next = x * (2 - d * x)
```

**Iterations Required:** 3-4 for Q2.13 precision

### 7.2 Exponential Approximator

**Key Insight:** Piecewise linear approximation is efficient

```vhdl
-- Divide range into segments
-- Store slope and intercept for each segment
-- result = slope * x + intercept
-- Handle saturation for large |x|
```

**Segments:** 24 segments covering [-4, 2]

### 7.3 Sigmoid Unit

**Key Insight:** Use fast-path for extreme inputs

```vhdl
-- For |x| > 1.35: Use piecewise linear approximation
-- For |x| <= 1.35: Compute sigma(x) = 1/(1 + e^(-x))
-- Exploit symmetry: sigma(x) = 1 - sigma(-x)
```

### 7.4 Dot Product Unit

**Key Insight:** FSM simplifies variable-length vectors

```vhdl
-- States: IDLE -> ACCUMULATE -> DONE_ST
-- Accumulate in wider format (Q10.26)
-- Return to IDLE after handshake
```

### 7.5 Error Propagator

**Key Insight:** Process neurons sequentially

```vhdl
-- For each neuron in target layer:
--   1. Load z value, compute derivative
--   2. Accumulate weight x delta products
--   3. Apply derivative, output result
-- Move to next neuron
```

### 7.6 Weight Updater

**Key Insight:** Pipeline handles format conversion

```vhdl
-- Stage 1: Capture inputs
-- Stage 2: Multiply lr x gradient (Q2.13 x Q10.26 = Q12.39)
-- Stage 3: Scale to Q2.13, subtract from weight
-- Stage 4: Saturate and output
```

---

## 8. Performance Optimization

### 8.1 DSP Block Utilization

```vhdl
-- Multiplications map to DSP48 blocks
-- Keep operands at 18x25 or smaller for single DSP
-- Q2.13 x Q2.13 fits perfectly (16x16)
```

### 8.2 Pipeline Balancing

```vhdl
-- Balance pipeline stages for throughput
-- Insert registers to meet timing
-- Consider latency vs throughput tradeoffs
```

### 8.3 Resource Sharing

```vhdl
-- FSM-based modules can reuse multipliers across states
-- Pipelined modules use more resources but higher throughput
```

### 8.4 Memory Organization

```vhdl
-- Use distributed RAM for small arrays (< 64 entries)
-- Use Block RAM for larger storage
-- Consider read-during-write behavior
```

---

## 9. Verification Methodology

### 9.1 Test Categories

1. **Functional Tests**
   - Normal operation with typical values
   - Boundary values (0, +/-1, MAX, MIN)
   - Edge cases (zero inputs, single element)

2. **Control Tests**
   - Reset behavior
   - Clear during operation
   - Handshaking (ready/valid)

3. **Error Handling**
   - Overflow/saturation
   - Invalid inputs (e.g., division by zero)
   - Timeout conditions

### 9.2 Coverage Goals

- All FSM states visited
- All state transitions exercised
- Boundary conditions tested
- Error paths verified

### 9.3 Dual-Simulator Verification

```
1. GHDL (VHDL-2008)
   - Fast compilation
   - Strict standard compliance
   - Good for rapid iteration

2. Vivado XSIM
   - Target synthesis tool
   - Catches synthesis-specific issues
   - Required for final verification
```

---

## 10. Code Templates

### 10.1 Module Header Template

```vhdl
--------------------------------------------------------------------------------
-- Module: module_name
-- Description: Brief description of functionality
--
-- Features:
--   - Feature 1
--   - Feature 2
--
-- Format: Q2.13 input/output (16-bit signed)
-- Latency: X clock cycles
--
-- Author: FPGA Neural Network Project
-- Complexity: EASY/MEDIUM/HARD
-- Dependencies: List any dependencies
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
```

### 10.2 Generic Entity Template

```vhdl
entity module_name is
    generic (
        DATA_WIDTH   : integer := 16;
        ACCUM_WIDTH  : integer := 40;
        FRAC_BITS    : integer := 13
    );
    port (
        -- Clock and Reset
        clk          : in  std_logic;
        rst          : in  std_logic;

        -- Control
        start        : in  std_logic;
        clear        : in  std_logic;

        -- Input Interface
        data_in      : in  signed(DATA_WIDTH-1 downto 0);
        data_valid   : in  std_logic;
        data_ready   : out std_logic;

        -- Output Interface
        data_out     : out signed(DATA_WIDTH-1 downto 0);
        out_valid    : out std_logic;
        out_ready    : in  std_logic;

        -- Status
        busy         : out std_logic;
        done         : out std_logic;
        overflow     : out std_logic
    );
end entity module_name;
```

### 10.3 Saturation Helper Functions

```vhdl
-- Maximum positive value
function max_signed_val(width : integer) return signed is
    variable result : signed(width-1 downto 0);
begin
    result := (others => '1');
    result(width-1) := '0';
    return result;
end function;

-- Minimum negative value
function min_signed_val(width : integer) return signed is
    variable result : signed(width-1 downto 0);
begin
    result := (others => '0');
    result(width-1) := '1';
    return result;
end function;

-- Saturation check and clamp
function saturate(val : signed; width : integer) return signed is
    variable max_val : signed(width-1 downto 0) := max_signed_val(width);
    variable min_val : signed(width-1 downto 0) := min_signed_val(width);
begin
    if val > resize(max_val, val'length) then
        return max_val;
    elsif val < resize(min_val, val'length) then
        return min_val;
    else
        return resize(val, width);
    end if;
end function;
```

---

## Appendix A: Module Completion Status

| # | Module | Category | Status | Tests |
|---|--------|----------|--------|-------|
| 1 | weight_register_bank | Storage | Done | Verified |
| 2 | gradient_register_bank | Storage | Done | Verified |
| 3 | forward_cache | Storage | Done | Verified |
| 4 | input_buffer | Storage | Done | Verified |
| 5 | activation_unit | Combinational | Done | Verified |
| 6 | activation_derivative_unit | Combinational | Done | Verified |
| 7 | saturation_unit | Combinational | Done | Verified |
| 8 | rounding_saturation | Pipelined | Done | Verified |
| 9 | bias_adder | Pipelined | Done | Verified |
| 10 | accumulator | FSM | Done | Verified |
| 11 | reciprocal_unit | FSM | Done | Verified |
| 12 | sqrt_unit | FSM | Done | Verified |
| 13 | exp_approximator | Pipelined | Done | Verified |
| 14 | log_approximator | Pipelined | Done | Verified |
| 15 | division_unit | FSM | Done | Verified |
| 16 | sigmoid_unit | FSM | Done | Verified |
| 17 | tanh_unit | FSM | Done | Verified |
| 18 | mac_unit | Pipelined | Done | Verified |
| 19 | dot_product_unit | FSM | Done | 11/11 |
| 20 | vector_accumulator | FSM | Done | 11/11 |
| 21 | error_calculator | Combinational | Done | Verified |
| 22 | delta_calculator | Combinational | Done | 24/24 |
| 23 | gradient_calculator | FSM | Done | 10/10 |
| 24 | weight_updater | Pipelined | Done | 17/17 |
| 25 | error_propagator | FSM | Done | 11/11 |
| 26 | forward_datapath | Sub-Top | Pending | Pending |
| 27 | backward_datapath | Sub-Top | Pending | Pending |
| 28 | weight_update_datapath | Sub-Top | Pending | Pending |
| 29 | neuron_training_top | Top | Pending | Pending |

---

## Appendix B: Q2.13 Quick Reference

| Value | Decimal | Hex | Binary (MSB...LSB) |
|-------|---------|-----|-------------------|
| +3.999 | 32767 | 0x7FFF | 0111 1111 1111 1111 |
| +2.0 | 16384 | 0x4000 | 0100 0000 0000 0000 |
| +1.0 | 8192 | 0x2000 | 0010 0000 0000 0000 |
| +0.5 | 4096 | 0x1000 | 0001 0000 0000 0000 |
| +0.25 | 2048 | 0x0800 | 0000 1000 0000 0000 |
| +0.125 | 1024 | 0x0400 | 0000 0100 0000 0000 |
| 0 | 0 | 0x0000 | 0000 0000 0000 0000 |
| -0.125 | -1024 | 0xFC00 | 1111 1100 0000 0000 |
| -0.25 | -2048 | 0xF800 | 1111 1000 0000 0000 |
| -0.5 | -4096 | 0xF000 | 1111 0000 0000 0000 |
| -1.0 | -8192 | 0xE000 | 1110 0000 0000 0000 |
| -2.0 | -16384 | 0xC000 | 1100 0000 0000 0000 |
| -4.0 | -32768 | 0x8000 | 1000 0000 0000 0000 |

---

## Appendix C: Debugging Checklist

### When Tests Fail

1. **Check signal widths** - Ensure all operations use correct bit widths
2. **Verify timing** - Add wait statements, check FSM transitions
3. **Print intermediate values** - Use report statements
4. **Check reset initialization** - All registers properly reset?
5. **Verify handshaking** - Ready/valid protocol correct?

### When Simulation Hangs

1. **Check FSM transitions** - Is there a path to exit?
2. **Verify wait conditions** - Will the condition ever be true?
3. **Check for infinite loops** - Counter incrementing?
4. **Use timeout patterns** - Add `for X ns` to wait statements

### When Results Are Wrong

1. **Check fixed-point scaling** - Correct shift amounts?
2. **Verify rounding** - Adding 0.5 LSB before shift?
3. **Check overflow handling** - Saturation working?
4. **Verify sign extension** - Using resize() correctly?

---

*Document compiled from FPGA Neural Network Project development*
*Modules verified with GHDL 4.0.0 and Vivado 2025.1*
