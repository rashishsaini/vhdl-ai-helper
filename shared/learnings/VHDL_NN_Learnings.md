# VHDL Neural Network Module Development Learnings

## Compiled from Iterative Development of 29-Module FPGA Neural Network Training System

---

## Table of Contents
1. [Fixed-Point Arithmetic Patterns](#1-fixed-point-arithmetic-patterns)
2. [FSM Design Patterns](#2-fsm-design-patterns)
3. [Testbench Best Practices](#3-testbench-best-practices)
4. [Common VHDL Pitfalls & Solutions](#4-common-vhdl-pitfalls--solutions)
5. [Module Interface Conventions](#5-module-interface-conventions)
6. [Timing & Synchronization Patterns](#6-timing--synchronization-patterns)
7. [Saturation & Overflow Handling](#7-saturation--overflow-handling)
8. [Memory Module Patterns](#8-memory-module-patterns)
9. [Pipelined Module Patterns](#9-pipelined-module-patterns)
10. [Module-Specific Learnings](#10-module-specific-learnings)
11. [Debugging Techniques](#11-debugging-techniques)
12. [GHDL vs Vivado Differences](#12-ghdl-vs-vivado-differences)

---

## 1. Fixed-Point Arithmetic Patterns

### 1.1 Q2.13 Format (Primary Data Format)
```
Width: 16 bits signed
Integer bits: 2 (plus sign)
Fractional bits: 13
Range: [-4.0, +3.9998779296875]
Resolution: 1/8192 ≈ 0.000122
```

**Key Constants:**
```vhdl
constant ONE      : signed(15 downto 0) := to_signed(8192, 16);   -- 1.0
constant HALF     : signed(15 downto 0) := to_signed(4096, 16);   -- 0.5
constant SAT_MAX  : signed(15 downto 0) := to_signed(32767, 16);  -- +3.9999
constant SAT_MIN  : signed(15 downto 0) := to_signed(-32768, 16); -- -4.0
```

### 1.2 Format Progression Through Operations
```
Input/Weight:  Q2.13  (16-bit) - Primary format
Product:       Q4.26  (32-bit) - After Q2.13 × Q2.13
Accumulator:   Q10.26 (40-bit) - After accumulating many products
```

**Why 40-bit accumulator?**
- Accumulating 256 products of max values: 256 × 16.0 = 4096.0
- Q10.26 range: ±512.0 with 26 fractional bits
- Prevents overflow during dot products of typical neural network sizes

### 1.3 Multiplication Pattern
```vhdl
-- Q2.13 × Q2.13 = Q4.26 (32-bit product)
signal a, b : signed(15 downto 0);
signal product : signed(31 downto 0);

product <= a * b;  -- VHDL automatically produces 32-bit result
```

### 1.4 Scaling Back After Multiplication
```vhdl
-- Convert Q4.26 back to Q2.13: shift right by 13 with rounding
constant FRAC_BITS : integer := 13;
variable rounded : signed(31 downto 0);
variable scaled  : signed(15 downto 0);

-- Add 0.5 LSB for rounding before shift
rounded := product + to_signed(2**(FRAC_BITS-1), 32);
scaled := rounded(FRAC_BITS + 15 downto FRAC_BITS);  -- Extract Q2.13 portion
```

### 1.5 Accumulator Width Selection Formula
```
ACCUM_WIDTH = max(PRODUCT_WIDTH, ceil(log2(MAX_ELEMENTS × MAX_PRODUCT)))

For 4-element dot product with Q2.13 inputs:
- Max product: 4.0 × 4.0 = 16.0 (in Q4.26)
- Max accumulation: 4 × 16.0 = 64.0
- Required integer bits: 7 (for ±64)
- ACCUM_WIDTH = 7 + 26 = 33 bits minimum
- Use 40 bits for safety margin
```

---

## 2. FSM Design Patterns

### 2.1 Standard FSM Template
```vhdl
type state_t is (IDLE, PROCESS, DONE_ST);
signal state : state_t;

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
                        -- Initialize
                        state <= PROCESS;
                    end if;
                
                when PROCESS =>
                    -- Do work
                    if condition_met then
                        state <= DONE_ST;
                    end if;
                
                when DONE_ST =>
                    -- Assert done for one cycle
                    state <= IDLE;
                
                when others =>
                    state <= IDLE;
            end case;
        end if;
    end if;
end process;
```

### 2.2 Done Signal Patterns

**CRITICAL LEARNING:** Done signals should pulse for exactly ONE clock cycle.

```vhdl
-- CORRECT: Done pulses in dedicated state
when DONE_ST =>
    state <= IDLE;  -- Immediately return to IDLE

done <= '1' when state = DONE_ST else '0';

-- INCORRECT: Done stays high while in state
when OUTPUT =>
    if consumer_ready = '1' then
        state <= IDLE;
    end if;
-- This keeps done='1' for multiple cycles!
```

### 2.3 Multi-Cycle Operations with Newton-Raphson
```vhdl
-- Pattern for iterative algorithms (reciprocal, sqrt)
type state_t is (IDLE, INIT, ITERATE, OUTPUT);
signal iter_count : integer range 0 to NUM_ITERATIONS;

when ITERATE =>
    if iter_count < NUM_ITERATIONS then
        -- Perform iteration computation
        y_reg <= y_next;
        iter_count <= iter_count + 1;
    else
        state <= OUTPUT;
    end if;
```

### 2.4 Handshaking FSM Pattern
```vhdl
-- For modules that need flow control
type state_t is (IDLE, WAIT_INPUT, PROCESS, WAIT_OUTPUT);

when WAIT_INPUT =>
    if data_valid = '1' then
        data_reg <= data_in;
        state <= PROCESS;
    end if;

when WAIT_OUTPUT =>
    if out_ready = '1' then
        state <= IDLE;
    end if;
```

---

## 3. Testbench Best Practices

### 3.1 Standard Testbench Structure
```vhdl
entity module_tb is
end entity module_tb;

architecture sim of module_tb is
    constant CLK_PERIOD : time := 10 ns;
    
    -- DUT signals
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    
    -- Test tracking
    signal test_count : integer := 0;
    signal pass_count : integer := 0;
    signal fail_count : integer := 0;
begin
    -- Clock generation
    clk <= not clk after CLK_PERIOD/2;
    
    -- DUT instantiation
    DUT: entity work.module_name port map (...);
    
    -- Test process
    test_proc: process
    begin
        -- Reset sequence
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Tests here
        
        -- Summary
        report "Total: " & integer'image(test_count) & 
               " Pass: " & integer'image(pass_count) &
               " Fail: " & integer'image(fail_count);
        wait;
    end process;
end architecture;
```

### 3.2 Test Procedure Pattern
```vhdl
procedure check_result(
    test_name : string;
    expected  : signed;
    actual    : signed
) is
begin
    test_count <= test_count + 1;
    if actual = expected then
        report "PASS: " & test_name severity note;
        pass_count <= pass_count + 1;
    else
        report "FAIL: " & test_name & 
               " Expected=" & integer'image(to_integer(expected)) &
               " Got=" & integer'image(to_integer(actual)) severity warning;
        fail_count <= fail_count + 1;
    end if;
end procedure;
```

### 3.3 Waiting for Done Signal
```vhdl
-- CORRECT: Wait in loop, then one more cycle for result to stabilize
start <= '1';
wait for CLK_PERIOD;
start <= '0';

while done = '0' loop
    wait for CLK_PERIOD;
end loop;
wait for CLK_PERIOD;  -- Extra cycle for output to be valid

-- Now check result
```

### 3.4 Providing Test Data to Address-Based Modules
```vhdl
-- For modules that output an address and expect data
type data_array_t is array (0 to MAX_LEN-1) of signed(15 downto 0);
signal test_data : data_array_t;

-- COMBINATORIAL data feeding (immediate response)
data_out <= test_data(to_integer(addr_out));

-- REGISTERED data feeding (one cycle delay) - often causes test failures!
process(clk)
begin
    if rising_edge(clk) then
        data_out <= test_data(to_integer(addr_out));
    end if;
end process;
```

**CRITICAL LEARNING:** Match the testbench data timing to what the DUT expects. Most simple DUTs expect combinatorial (immediate) data response.

### 3.5 Test Categories to Include
1. **Reset behavior** - All outputs zero/default after reset
2. **Basic operations** - Simple cases with known results
3. **Boundary values** - MAX, MIN, zero, near-overflow
4. **Negative values** - Both inputs negative, mixed signs
5. **Overflow/saturation** - Verify saturation behavior
6. **Typical use case** - Neural network realistic values
7. **Edge cases** - Single element, empty input, etc.

---

## 4. Common VHDL Pitfalls & Solutions

### 4.1 Non-Static Aggregate in Reset
```vhdl
-- INCORRECT: Non-static aggregate
constant MAX_VAL : signed(39 downto 0) := (ACCUM_WIDTH-1 => '0', others => '1');

-- CORRECT: Use function or variable
function max_accum_val return signed is
    variable result : signed(ACCUM_WIDTH-1 downto 0);
begin
    result := (others => '1');
    result(ACCUM_WIDTH-1) := '0';
    return result;
end function;

constant MAX_ACCUM : signed(ACCUM_WIDTH-1 downto 0) := max_accum_val;
```

### 4.2 Signal vs Variable Timing
```vhdl
-- INCORRECT: Signal assignment not visible until next delta
process(clk)
begin
    if rising_edge(clk) then
        temp_signal <= a + b;
        result <= temp_signal * c;  -- Uses OLD value of temp_signal!
    end if;
end process;

-- CORRECT: Use variable for immediate value
process(clk)
    variable temp : signed(31 downto 0);
begin
    if rising_edge(clk) then
        temp := a + b;
        result <= temp * c;  -- Uses NEW value
    end if;
end process;
```

### 4.3 Metavalue Warnings at Simulation Start
```
-- These warnings at @0ms are NORMAL:
-- "NUMERIC_STD.TO_INTEGER: metavalue detected, returning 0"

-- Cause: Signals are 'U' (uninitialized) before first clock edge
-- Solution: Initialize signals in declaration or ignore if they resolve after reset
signal my_signal : unsigned(3 downto 0) := (others => '0');
```

### 4.4 Integer Range Constraints
```vhdl
-- INCORRECT: May cause overflow during simulation
signal counter : integer;

-- CORRECT: Constrain range
signal counter : integer range 0 to MAX_VALUE;
```

### 4.5 Resize vs Type Casting
```vhdl
-- For signed extension (preserves sign)
signal small : signed(15 downto 0);
signal large : signed(39 downto 0);

large <= resize(small, 40);  -- Sign-extends correctly

-- INCORRECT: Concatenation loses sign
large <= (others => '0') & small;  -- Wrong for negative numbers!
```

### 4.6 Comparison with Different Widths
```vhdl
-- INCORRECT: May not work as expected
if narrow_signal > wide_constant then ...

-- CORRECT: Resize to same width first
if resize(narrow_signal, WIDE_WIDTH) > wide_constant then ...
-- OR
if narrow_signal > resize(wide_constant, NARROW_WIDTH) then ...
```

---

## 5. Module Interface Conventions

### 5.1 Standard Port Categories
```vhdl
entity standard_module is
    port (
        -- Clock and Reset (always first)
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Control Interface
        start        : in  std_logic;
        clear        : in  std_logic;
        enable       : in  std_logic;
        
        -- Data Input Interface
        data_in      : in  signed(DATA_WIDTH-1 downto 0);
        data_valid   : in  std_logic;
        data_ready   : out std_logic;
        
        -- Data Output Interface
        data_out     : out signed(DATA_WIDTH-1 downto 0);
        out_valid    : out std_logic;
        out_ready    : in  std_logic;
        
        -- Status Interface
        busy         : out std_logic;
        done         : out std_logic;
        overflow     : out std_logic;
        error        : out std_logic
    );
end entity;
```

### 5.2 Signal Naming Conventions
```
*_in      : Input signals
*_out     : Output signals
*_reg     : Registered/state signals
*_next    : Combinational next-state signals
*_valid   : Data validity indicator
*_ready   : Ready to accept data
*_en      : Enable signals
*_addr    : Address signals
*_cnt     : Counter signals
```

### 5.3 Generic Parameters
```vhdl
generic (
    -- Width parameters
    DATA_WIDTH   : integer := 16;
    ACCUM_WIDTH  : integer := 40;
    ADDR_WIDTH   : integer := 4;
    
    -- Size parameters
    NUM_ENTRIES  : integer := 13;
    MAX_ELEMENTS : integer := 4;
    
    -- Feature enables
    ENABLE_SAT   : boolean := true;
    REGISTERED   : boolean := true;
    
    -- Algorithm parameters
    NUM_ITERATIONS : integer := 3;
    FRAC_BITS      : integer := 13
);
```

---

## 6. Timing & Synchronization Patterns

### 6.1 Single-Cycle Combinational Module
```vhdl
-- No clock needed, output changes immediately with input
entity comb_module is
    port (
        data_in  : in  signed(15 downto 0);
        data_out : out signed(15 downto 0)
    );
end entity;

architecture rtl of comb_module is
begin
    data_out <= some_function(data_in);
end architecture;
```

### 6.2 Single-Cycle Registered Module
```vhdl
-- One clock cycle latency
process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' then
            data_out <= (others => '0');
            valid <= '0';
        elsif enable = '1' then
            data_out <= compute(data_in);
            valid <= '1';
        else
            valid <= '0';
        end if;
    end if;
end process;
```

### 6.3 Multi-Cycle FSM Module
```vhdl
-- Variable latency, uses done signal
-- Latency = N cycles where N depends on operation

-- Caller must:
-- 1. Assert start for one cycle
-- 2. Wait for done = '1'
-- 3. Read result on same cycle done is high
```

### 6.4 Pipelined Module
```vhdl
-- Fixed latency, continuous throughput
-- New input accepted every cycle

-- Stage 1: Input registration
process(clk)
begin
    if rising_edge(clk) then
        stage1_data <= data_in;
        stage1_valid <= enable;
    end if;
end process;

-- Stage 2: Computation
process(clk)
begin
    if rising_edge(clk) then
        stage2_data <= compute(stage1_data);
        stage2_valid <= stage1_valid;
    end if;
end process;

-- Output
data_out <= stage2_data;
valid <= stage2_valid;
-- Total latency: 2 cycles
```

### 6.5 Clear Signal Propagation in Pipelines
```vhdl
-- CRITICAL: Clear must propagate through pipeline stages
signal clear_d1 : std_logic := '0';
signal clear_d2 : std_logic := '0';

process(clk)
begin
    if rising_edge(clk) then
        clear_d1 <= clear;
        clear_d2 <= clear_d1;
        
        if rst = '1' or clear = '1' or clear_d1 = '1' then
            stage1_reg <= (others => '0');
        end if;
        
        if rst = '1' or clear = '1' or clear_d1 = '1' or clear_d2 = '1' then
            stage2_reg <= (others => '0');
        end if;
    end if;
end process;
```

---

## 7. Saturation & Overflow Handling

### 7.1 Addition with Saturation
```vhdl
-- Extend by 1 bit, check MSBs for overflow
variable sum : signed(WIDTH downto 0);  -- WIDTH+1 bits
variable result : signed(WIDTH-1 downto 0);

sum := resize(a, WIDTH+1) + resize(b, WIDTH+1);

if sum(WIDTH) /= sum(WIDTH-1) then
    -- Overflow occurred (MSBs differ)
    if sum(WIDTH) = '0' then
        -- Positive overflow
        result := MAX_VAL;
    else
        -- Negative overflow
        result := MIN_VAL;
    end if;
    overflow_flag <= '1';
else
    result := sum(WIDTH-1 downto 0);
    overflow_flag <= '0';
end if;
```

### 7.2 Multiplication Overflow (Q2.13 × Q2.13)
```vhdl
-- Q2.13 × Q2.13 = Q4.26 (32 bits) - no overflow possible in multiply
-- Overflow possible when converting back to Q2.13

signal product : signed(31 downto 0);
signal scaled : signed(31 downto 0);

product <= a * b;
scaled := shift_right(product + 4096, 13);  -- Round and scale

-- Check if result fits in Q2.13 range
if scaled > 32767 then
    result <= to_signed(32767, 16);
    overflow <= '1';
elsif scaled < -32768 then
    result <= to_signed(-32768, 16);
    overflow <= '1';
else
    result <= scaled(15 downto 0);
    overflow <= '0';
end if;
```

### 7.3 Constructing Max/Min Values
```vhdl
-- CORRECT: Using variables (avoids non-static aggregate issues)
variable max_val : signed(WIDTH-1 downto 0);
variable min_val : signed(WIDTH-1 downto 0);

max_val := (others => '1');
max_val(WIDTH-1) := '0';  -- Clear sign bit: 0111...1111

min_val := (others => '0');
min_val(WIDTH-1) := '1';  -- Set sign bit: 1000...0000
```

---

## 8. Memory Module Patterns

### 8.1 Register Bank with Async Read
```vhdl
-- Write: Synchronous
-- Read: Combinational (same cycle)

type reg_array_t is array (0 to NUM_ENTRIES-1) of signed(WIDTH-1 downto 0);
signal registers : reg_array_t := (others => (others => '0'));

-- Synchronous write
process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' then
            registers <= (others => (others => '0'));
        elsif wr_en = '1' and addr < NUM_ENTRIES then
            registers(to_integer(wr_addr)) <= wr_data;
        end if;
    end if;
end process;

-- Combinational read
rd_data <= registers(to_integer(rd_addr)) when rd_en = '1' and rd_addr < NUM_ENTRIES
           else (others => '0');
```

### 8.2 Address Validation Pattern
```vhdl
-- Always validate addresses to prevent simulation errors
signal addr_int : integer range 0 to NUM_ENTRIES-1;
signal addr_valid : std_logic;

addr_int <= to_integer(addr) when to_integer(addr) < NUM_ENTRIES else 0;
addr_valid <= '1' when to_integer(addr) < NUM_ENTRIES else '0';

-- Use addr_valid to gate operations
if wr_en = '1' and addr_valid = '1' then
    registers(addr_int) <= wr_data;
end if;
```

### 8.3 Gradient Accumulator Pattern
```vhdl
-- Wider accumulator to prevent overflow during batch accumulation
-- Input: 32-bit (Q4.26), Accumulator: 40-bit (Q10.26)

process(clk)
    variable sum : signed(ACCUM_WIDTH downto 0);
    variable data_ext : signed(ACCUM_WIDTH-1 downto 0);
begin
    if rising_edge(clk) then
        if rst = '1' or clear = '1' then
            accumulators <= (others => (others => '0'));
        elsif accum_en = '1' then
            data_ext := resize(accum_data, ACCUM_WIDTH);
            sum := resize(accumulators(addr), ACCUM_WIDTH+1) + 
                   resize(data_ext, ACCUM_WIDTH+1);
            
            -- Saturation check and store
            if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
                -- Saturate
            else
                accumulators(addr) <= sum(ACCUM_WIDTH-1 downto 0);
            end if;
        end if;
    end if;
end process;
```

---

## 9. Pipelined Module Patterns

### 9.1 MAC Unit (2-Stage Pipeline)
```vhdl
-- Stage 1: Multiply
-- Stage 2: Accumulate

-- Critical: Clear must affect both stages
signal clear_d1 : std_logic := '0';

-- Stage 1
process(clk)
begin
    if rising_edge(clk) then
        clear_d1 <= clear;
        if rst = '1' then
            mult_result <= (others => '0');
            mult_valid <= '0';
        elsif enable = '1' then
            mult_result <= data_in * weight;
            mult_valid <= '1';
        else
            mult_valid <= '0';
        end if;
    end if;
end process;

-- Stage 2
process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' or clear = '1' or clear_d1 = '1' then
            accum_reg <= (others => '0');
        elsif mult_valid = '1' then
            -- Accumulate with saturation
        end if;
    end if;
end process;
```

### 9.2 LUT-Based Approximation (exp, log, sigmoid)
```vhdl
-- Piecewise linear: y = slope * x + intercept

constant NUM_SEGMENTS : integer := 16;

type slope_array_t is array (0 to NUM_SEGMENTS-1) of signed(15 downto 0);
type intercept_array_t is array (0 to NUM_SEGMENTS-1) of signed(15 downto 0);

constant SLOPES : slope_array_t := (...);
constant INTERCEPTS : intercept_array_t := (...);

-- Pipeline stages:
-- 1. Segment index calculation
-- 2. LUT fetch (slope, intercept)
-- 3. Multiply: slope * x
-- 4. Add intercept, saturate
```

---

## 10. Module-Specific Learnings

### 10.1 Reciprocal Unit (Newton-Raphson)
```
Algorithm: x_{n+1} = x_n * (2 - d * x_n)

Key learnings:
- Normalize input to [0.5, 1.0) range for LUT initial estimate
- Track shift amount for denormalization
- Handle sign separately (compute reciprocal of absolute value)
- Division by zero must be detected early
- 3-4 iterations sufficient for Q2.13 precision
- Use Q4.28 internal format for better intermediate precision
```

### 10.2 Square Root Unit (Newton-Raphson for 1/√x)
```
Algorithm: y_{n+1} = y * (1.5 - 0.5 * d * y²)
Result: sqrt(d) = d * y

Key learnings:
- Computing 1/√x then multiplying by x avoids division
- Negative input must return error (sqrt undefined)
- Zero input returns zero immediately
- Initial estimate critical for convergence
- Adaptive initial estimate based on input magnitude
```

### 10.3 Sigmoid Unit
```
Formula: σ(x) = 1 / (1 + e^(-x))

Key learnings:
- For |x| > 1.5, use piecewise linear approximation (fast path)
- For |x| <= 1.5, use exp + reciprocal computation
- Exploit symmetry: σ(x) = 1 - σ(-x)
- Output always in (0, 1) range
- e^(-x) overflows for x < -1.38 in Q2.13 - must handle!
```

### 10.4 Dot Product Unit
```
Key learnings:
- Combinatorial data feeding from testbench (not registered!)
- Address output + data input must be synchronized
- Done signal must pulse for exactly one cycle
- Result valid on same cycle as done
- Clear must reset accumulator immediately
```

### 10.5 Error Calculator
```
Formula: error = target - actual

Key learnings:
- Pure combinational is fine (zero latency on critical path)
- Saturation prevents wraparound that causes training instability
- Zero error detection useful for early termination
```

### 10.6 MAC Unit
```
Key learnings:
- 2-stage pipeline matches FPGA DSP block architecture
- Clear signal must propagate through both stages
- Overflow flag should be sticky (once set, stays set until clear)
- Enable signal gates the multiply, not just the accumulate
```

---

## 11. Debugging Techniques

### 11.1 Simulation Debugging Checklist
1. **Check reset behavior first** - Are all signals properly initialized?
2. **Verify clock timing** - Is data sampled at right edge?
3. **Check signal widths** - Any truncation or extension issues?
4. **Trace FSM states** - Is state machine progressing correctly?
5. **Verify handshaking** - Are valid/ready signals aligned?
6. **Check for metavalues** - Any 'U' or 'X' propagating?

### 11.2 Common Simulation Failures

**Test expects wrong value:**
- Check fixed-point scaling (forgot to shift?)
- Check signed vs unsigned interpretation
- Verify expected value calculation

**Done never asserts:**
- FSM stuck in wrong state
- Condition for transition never met
- Counter comparison using wrong operator (< vs <=)

**Result one cycle late:**
- Pipeline depth mismatch
- Reading result before it's valid
- Registered vs combinational output confusion

### 11.3 Waveform Debugging Signals
```vhdl
-- Add internal signals to entity for debugging (remove for synthesis)
debug_state : out state_t;
debug_counter : out unsigned(7 downto 0);
debug_accum : out signed(39 downto 0);
```

---

## 12. GHDL vs Vivado Differences

### 12.1 GHDL-Specific
```
- Stricter about VHDL-2008 compliance
- Reports metavalue warnings at time 0
- Uses --std=08 flag for VHDL-2008
- Faster compilation for simulation
- Good for initial verification
```

### 12.2 Vivado-Specific
```
- More lenient with some constructs
- Better synthesis optimization
- Shows resource utilization estimates
- Required for FPGA implementation
- May accept code GHDL rejects and vice versa
```

### 12.3 Code Portable to Both
```vhdl
-- Use VHDL-2008 standard consistently
-- Avoid textio for testbenches (use report statements)
-- Use numeric_std, not std_logic_arith
-- Initialize all signals in declarations
-- Use explicit type conversions
-- Avoid vendor-specific constructs
```

---

## Summary: Key Principles

1. **Fixed-point discipline**: Always track Q format through operations
2. **Overflow protection**: Extend width before operations, saturate after
3. **FSM clarity**: One state per function, clear transitions
4. **Pipeline consistency**: Track latency, propagate control signals
5. **Testbench completeness**: Cover normal, boundary, and error cases
6. **Interface consistency**: Use standard port naming and handshaking
7. **Reset completeness**: Initialize ALL state elements
8. **Timing awareness**: Know if module is combinational, registered, or multi-cycle

---

## Quick Reference: Format Conversions

```
Q2.13 to float:  float_val = int_val / 8192.0
float to Q2.13:  int_val = round(float_val * 8192)

Q4.26 to Q2.13:  result = (val + 4096) >> 13  (with rounding)
Q2.13 to Q4.26:  result = val  (just interpret differently, or << 13 for actual scaling)

40-bit Q10.26 to 16-bit Q2.13:  result = (val + 4096) >> 13, then saturate
```

---

*Document compiled from iterative VHDL development of FPGA Neural Network Training System*
*29 modules, Q2.13 fixed-point, targeting 4-2-1 network topology*
