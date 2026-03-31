# DFT Simulation Debug Report
**Date**: 2025-11-29
**Analyzer**: Digital Design Verification Specialist
**DUT**: dft_complex_calculator (256-point DFT)

---

## Executive Summary

**Verdict**: DESIGN BUG - Pipeline timing hazard causing incorrect DFT computation

**Severity**: CRITICAL - Functional failure affecting all test cases

**Root Cause Category**: Design RTL bug (pipeline misalignment in multiplier datapath)

**Impact**: DFT produces incorrect magnitude for all frequency bins due to missing the first 3 sample contributions and accumulating wrong products for all samples

---

## Failure Analysis

### Timeline of Discovery

1. **Symptom Observed** (from user report):
   - Output magnitude = 0.502 for DC signal test
   - Expected magnitude ≈ 0 for K=1 (DC signal has no fundamental frequency component)
   - Actual magnitude = 1.002 (from waveform analysis)

2. **Initial Hypotheses**:
   - H1: sample_counter not reaching 255 ❌ (disproven - reaches 255)
   - H2: State machine stuck, only 1 accumulation ❌ (disproven - 256 accumulate_enable pulses)
   - H3: Accumulator cleared prematurely ❌ (disproven - accumulator grows correctly)

3. **Critical Discovery** (VCD analysis):
   - Only **252 accumulator value changes** instead of 256
   - First accumulator change occurs at **sample_counter = 3**, not 0
   - Last accumulator change occurs at **sample_counter = 0** (after wraparound from 255)

4. **Root Cause Identified**:
   - **Pipeline timing hazard** in multiplier process
   - `product_real_scaled` lags `product_real` by 1 clock cycle
   - Accumulation happens before scaled product is ready

---

## Root Cause Analysis

### Design Defect Location

**File**: `/home/arunupscee/Desktop/vhdl-ai-helper/C37/dft.vhd`
**Lines**: 226-279 (multiplier processes) and 281-309 (accumulator processes)
**Module**: `real_multiplier_process` and `imag_multiplier_process`

### Detailed Mechanism

The multiplier process implements a 2-stage pipeline:

```vhdl
-- Stage 1: Multiply (line 236-244)
if multiply_enable = '1' then
    product_real <= signed(sample_data_reg) * signed(cos_coeff_reg);
end if;

-- Stage 2: Scale (line 246-249) - UNCONDITIONAL, runs every clock
product_real_scaled <= resize(shift_right(product_real, 15), OUTPUT_WIDTH);
```

**The Bug**: Line 249 executes **every clock cycle** using the **current** value of `product_real`, not the newly computed value from line 243.

### Clock-by-Clock Propagation Path

#### Cycle N (State = MULTIPLY, sample_counter = 0):
```
multiply_enable = 1 (asserted by state machine)
  ↓
product_real <= sample[0] * cos[0]  (line 243 - registered on clock edge)
  ↓
[CLOCK EDGE] product_real latches to NEW value
  ↓
product_real_scaled <= scale(OLD product_real)  (line 249 - gets stale value = 0)
  ↓
[CLOCK EDGE] product_real_scaled = 0
```

#### Cycle N+1 (State = ACCUMULATE, sample_counter = 0):
```
accumulate_enable = 1
  ↓
accumulator_real <= accumulator_real + product_real_scaled  (line 291)
  ↓
accumulator_real += 0  ❌ WRONG! Should add sample[0] * cos[0]
  ↓
[CLOCK EDGE]
  ↓
product_real_scaled <= scale(product_real)  (line 249 - NOW gets sample[0] result)
  ↓
[CLOCK EDGE] product_real_scaled = sample[0] * cos[0] (TOO LATE!)
```

#### Cycle N+2 (State = FETCH_ADDR, sample_counter = 1):
```
State transitions to fetch next sample
product_real_scaled still holds sample[0] * cos[0] from previous cycle
```

#### Cycle N+3 (State = MULTIPLY, sample_counter = 1):
```
multiply_enable = 1
product_real <= sample[1] * cos[1]  (line 243)
[CLOCK EDGE]
product_real_scaled <= scale(OLD product_real = sample[0] * cos[0])  (line 249)
```

#### Cycle N+4 (State = ACCUMULATE, sample_counter = 1):
```
accumulate_enable = 1
accumulator_real += product_real_scaled
accumulator_real += sample[0] * cos[0]  ❌ WRONG! Should add sample[1] * cos[1]
```

### Result

Each accumulation adds the product from the **previous sample**, not the **current sample**:

| sample_counter | Product Calculated        | Product Accumulated       | Status |
|----------------|---------------------------|---------------------------|--------|
| 0              | sample[0] * cos[0]       | 0 (uninitialized)         | ❌ LOST |
| 1              | sample[1] * cos[1]       | sample[0] * cos[0]       | ❌ OFF-BY-1 |
| 2              | sample[2] * cos[2]       | sample[1] * cos[1]       | ❌ OFF-BY-1 |
| 3              | sample[3] * cos[3]       | sample[2] * cos[2]       | ❌ OFF-BY-1 |
| ...            | ...                       | ...                       | ❌ OFF-BY-1 |
| 254            | sample[254] * cos[254]   | sample[253] * cos[253]   | ❌ OFF-BY-1 |
| 255            | sample[255] * cos[255]   | sample[254] * cos[254]   | ❌ OFF-BY-1 |
| 0 (wrap)       | (none)                    | sample[255] * cos[255]   | ❌ WRONG COUNTER |

**Net Effect**:
- Sample 0's contribution: **NEVER accumulated**
- Sample 1's contribution: **NEVER accumulated**
- Samples 2-255: Accumulated at wrong counter values (off-by-1)
- Sample 255's contribution: Accumulated when counter wraps to 0

---

## Evidence from Waveform Analysis

### VCD File: `/home/arunupscee/Desktop/vhdl-ai-helper/C37/dft_debug.vcd`

#### Test Configuration
- Input: DC signal (all 256 samples = 0.5 = 16384 in Q15 format)
- DFT Frequency Bin: K = 1 (fundamental frequency)
- Expected Result: Magnitude ≈ 0 (DC signal orthogonal to K=1)

#### Extracted Signal Traces

**First 6 Accumulation Events** (parsed from VCD):
```
Time(ns)  Counter  multiply_en  product_real_scaled  accumulate_en  accumulator_real  CORRECT?
--------  -------  -----------  -------------------  -------------  ----------------  --------
115       0        1            0                    0              0
125       0        0            0                    1              0                 ❌ Added 0
165       1        1            0                    0              0
175       1        0            0                    1              0                 ❌ Added 0
215       2        1            0                    0              0
225       2        1            16383                1              0                 ❌ Added 16383
235       3        0            16383                1              16383             ❌ Added sample[2]
285       4        0            16378                1              32761             ❌ Added sample[3]
335       5        0            16364                1              49125             ❌ Added sample[4]
```

**Last 3 Accumulation Events**:
```
Time(ns)  Counter  product_real_scaled  accumulator_real (before)  accumulator_real (after)
--------  -------  -------------------  -------------------------  -------------------------
12785     254      16260                -81712                     -65452  (added sample[253])
12835     255      16304                -65452                     -49148  (added sample[254])
12885     0        16339                -49148                     -32809  (added sample[255]) ❌
```

#### Quantitative Analysis

From waveform parsing:
- **Total accumulate_enable pulses**: 256 ✓ (correct)
- **Total accumulator value changes**: 252 ❌ (missing 4)
- **First accumulator change**: Counter = 3 ❌ (should be 0)
- **Last accumulator change**: Counter = 0 ❌ (should be 255)

**Manual product sum verification**:
```
Sum of all product_real_scaled values (from trace): -623,501
Final accumulator_real value:                       -32,809
Discrepancy:                                        590,692 ❌
```

This massive discrepancy confirms products are not accumulating correctly.

**Final Output Values**:
```
accumulator_real:  -32,809 (48-bit)
accumulator_imag:  -1,273 (48-bit)

Output (lower 32 bits extracted):
real_result:       -32,809 → Q16.15 = -1.001251
imag_result:       -1,273  → Q16.15 = -0.038849

Magnitude:         1.002005 ❌
Expected:          ≈0.000 (near zero for DC at K=1)
```

---

## Contributing Factors

### Secondary Issues Amplifying the Bug

1. **State Machine Timing**:
   - State sequence: MULTIPLY → ACCUMULATE requires product to be ready in **1 clock cycle**
   - Current implementation needs **2 clock cycles** (multiply + scale)
   - **Gap**: 1 clock cycle shortage

2. **Pipeline Documentation**:
   - Comment at line 246 says "Stage 2: Scale (always, so it's ready for accumulate_enable)"
   - This is **incorrect** - scaled product is ready 1 cycle AFTER multiply_enable
   - Misleading comment suggests design intent was violated during implementation

3. **Lack of Pipeline Registers**:
   - No explicit pipeline stage registers between multiply and accumulate
   - Direct connection from `product_real_scaled` to accumulator (line 291)
   - Should have intermediate holding register

### Testbench Limitations

While the testbench has excellent coverage with golden model verification, it does not:
- Check intermediate accumulator values during computation
- Verify sample_counter correlation with accumulated products
- Monitor pipeline stage timing (multiply_enable to product availability)

**Recommendation**: Add assertions to check `product_real_scaled` is non-zero when `accumulate_enable` asserts (except for samples that are actually zero).

---

## Design vs. Testbench Attribution

**Classification**: **DESIGN BUG** (RTL implementation error)

**Design Responsibility**:
- `/home/arunupscee/Desktop/vhdl-ai-helper/C37/dft.vhd` lines 226-279
- Pipeline staging incorrectly implemented
- State machine timing incompatible with multiplier latency

**Testbench Status**:
- `/home/arunupscee/Desktop/vhdl-ai-helper/C37/tb_dft_complex_calculator.vhd` - CORRECT
- Golden model computation is accurate
- Test stimulus properly configured
- Verification methodology sound (detected the failure correctly)

---

## Recommended Fixes

### Option 1: Add Pipeline Stage to State Machine (Recommended)

**Rationale**: Cleanest separation of concerns, preserves multiply pipeline

**Implementation**:

**File**: `/home/arunupscee/Desktop/vhdl-ai-helper/C37/dft.vhd`

**Line 46** - Modify state machine definition:
```vhdl
-- OLD:
type state_type is (IDLE, INIT, FETCH_ADDR, WAIT_ROM, MULTIPLY, ACCUMULATE, DONE_STATE);

-- NEW:
type state_type is (IDLE, INIT, FETCH_ADDR, WAIT_ROM, MULTIPLY, SCALE, ACCUMULATE, DONE_STATE);
```

**Line 128-141** - Update state transitions:
```vhdl
-- OLD:
when MULTIPLY =>
    multiply_enable <= '1';
    next_state <= ACCUMULATE;

when ACCUMULATE =>
    accumulate_enable <= '1';
    increment_counter <= '1';
    if sample_counter = WINDOW_SIZE - 1 then
        next_state <= DONE_STATE;
    else
        next_state <= FETCH_ADDR;
    end if;

-- NEW:
when MULTIPLY =>
    multiply_enable <= '1';
    next_state <= SCALE;        -- Wait 1 cycle for product to be scaled

when SCALE =>                   -- NEW STATE
    next_state <= ACCUMULATE;   -- product_real_scaled is now ready

when ACCUMULATE =>
    accumulate_enable <= '1';
    increment_counter <= '1';
    if sample_counter = WINDOW_SIZE - 1 then
        next_state <= DONE_STATE;
    else
        next_state <= FETCH_ADDR;
    end if;
```

**Impact**:
- Adds 1 clock cycle per sample (256 extra cycles total)
- Computation time increases from ~12.9 μs to ~15.5 μs @ 100 MHz
- **Benefit**: Preserves clean pipeline, minimal code changes

---

### Option 2: Immediate Scaling (Combinational)

**Rationale**: Eliminate pipeline by doing multiply+scale in 1 cycle

**Implementation**:

**File**: `/home/arunupscee/Desktop/vhdl-ai-helper/C37/dft.vhd`

**Lines 234-250** - Modify multiplier process:
```vhdl
-- OLD:
elsif rising_edge(clk) then
    if multiply_enable = '1' then
        multiplier_real_a <= signed(sample_data_reg);
        multiplier_real_b <= signed(cos_coeff_reg);
        product_real <= signed(sample_data_reg) * signed(cos_coeff_reg);
    end if;

    product_real_scaled <= resize(shift_right(product_real, 15), OUTPUT_WIDTH);
end if;

-- NEW:
elsif rising_edge(clk) then
    if multiply_enable = '1' then
        -- Perform multiply AND scale in same cycle
        product_real <= signed(sample_data_reg) * signed(cos_coeff_reg);
        product_real_scaled <= resize(shift_right(
            signed(sample_data_reg) * signed(cos_coeff_reg), 15), OUTPUT_WIDTH);
    end if;
    -- Remove unconditional scaling
end if;
```

**Impact**:
- No performance penalty (same cycle count)
- **Risk**: Long combinational path (16x16 multiply + 15-bit shift + resize) may fail timing
- Requires timing analysis to verify Fmax is met
- May reduce maximum clock frequency

**Verdict**: **NOT RECOMMENDED** unless timing closure is verified

---

### Option 3: Registered Pipeline with Extra Stage

**Rationale**: Proper 3-stage pipeline (multiply → scale → accumulate)

**Implementation**:

**File**: `/home/arunupscee/Desktop/vhdl-ai-helper/C37/dft.vhd`

**After Line 72** - Add pipeline register:
```vhdl
signal product_real_scaled_reg : signed(OUTPUT_WIDTH-1 downto 0);
signal product_imag_scaled_reg : signed(OUTPUT_WIDTH-1 downto 0);
```

**Lines 234-250** - Add register stage:
```vhdl
elsif rising_edge(clk) then
    -- Stage 1: Multiply
    if multiply_enable = '1' then
        product_real <= signed(sample_data_reg) * signed(cos_coeff_reg);
    end if;

    -- Stage 2: Scale
    product_real_scaled <= resize(shift_right(product_real, 15), OUTPUT_WIDTH);

    -- Stage 3: Register for accumulation
    product_real_scaled_reg <= product_real_scaled;
end if;
```

**Line 291** - Accumulate from registered product:
```vhdl
-- OLD:
accumulator_real <= accumulator_real + resize(product_real_scaled, ACCUMULATOR_WIDTH);

-- NEW:
accumulator_real <= accumulator_real + resize(product_real_scaled_reg, ACCUMULATOR_WIDTH);
```

**Line 46** - Add 2 wait states:
```vhdl
type state_type is (IDLE, INIT, FETCH_ADDR, WAIT_ROM, MULTIPLY, SCALE1, SCALE2, ACCUMULATE, DONE_STATE);

-- State machine:
when MULTIPLY => next_state <= SCALE1;
when SCALE1 => next_state <= SCALE2;
when SCALE2 => next_state <= ACCUMULATE;
```

**Impact**:
- Adds 2 clock cycles per sample (512 extra cycles)
- Cleanest pipeline implementation
- Best timing characteristics
- **Most robust solution**

---

## Verification Enhancements

### Immediate Checks to Add

1. **Product Validity Assertion**:

   **File**: `/home/arunupscee/Desktop/vhdl-ai-helper/C37/dft.vhd`

   **After Line 309** - Add assertion:
   ```vhdl
   -- Assertion: product must be valid when accumulating
   assert not (accumulate_enable = '1' and product_real_scaled = 0 and
               sample_data_reg /= 0 and cos_coeff_reg /= 0)
       report "ASSERTION FAILED: Accumulating zero product from non-zero inputs!"
       severity error;
   ```

2. **Accumulation Count Check**:

   **File**: `/home/arunupscee/Desktop/vhdl-ai-helper/C37/tb_dft_complex_calculator.vhd`

   Add counter to verify 256 accumulations occur:
   ```vhdl
   signal accumulation_count : integer := 0;

   process(clk)
   begin
       if rising_edge(clk) then
           if DUT.accumulate_enable = '1' then
               accumulation_count <= accumulation_count + 1;
           end if;

           if DUT.calculation_done = '1' then
               assert accumulation_count = 256
                   report "ASSERTION: Expected 256 accumulations, got " &
                          integer'image(accumulation_count)
                   severity error;
               accumulation_count <= 0;
           end if;
       end if;
   end process;
   ```

3. **Pipeline Timing Monitor**:

   Monitor time between multiply_enable and when product_real_scaled becomes valid:
   ```vhdl
   process(clk)
       variable mult_time : time;
   begin
       if rising_edge(clk) then
           if multiply_enable = '1' then
               mult_time := now;
           end if;

           if product_real_scaled /= 0 and mult_time > 0 ns then
               assert (now - mult_time) <= 20 ns  -- 2 clock cycles
                   report "WARNING: Product took too long to compute"
                   severity warning;
           end if;
       end if;
   end process;
   ```

---

## Simulation Tool Notes

**Simulator**: XSIM (Xilinx Vivado)
**Version**: Detected from log path structure

**Tool-Specific Behavior**: None observed - this is a pure design bug, not simulator-dependent

---

## Summary

| Aspect | Details |
|--------|---------|
| **Root Cause** | Pipeline timing hazard in multiplier datapath |
| **Affected Lines** | dft.vhd:243-249, 271-277, 291, 306 |
| **Symptom** | Incorrect DFT magnitude (1.002 vs expected ~0) |
| **Samples Lost** | Samples 0, 1 never accumulated; all others off-by-1 |
| **Recommended Fix** | Option 1 - Add SCALE state to state machine |
| **Verification Gap** | No pipeline timing assertions |
| **Severity** | CRITICAL - all DFT results are wrong |

---

## Next Steps

1. **Immediate**: Implement Option 1 fix (add SCALE state)
2. **Verify**: Re-run testbench and confirm magnitude is correct
3. **Validate**: Check timing closure with synthesis tools
4. **Enhance**: Add pipeline timing assertions to prevent regression
5. **Document**: Update design documentation to clearly specify pipeline stages

---

**Report Generated**: 2025-11-29
**Analysis Time**: 12.9 μs of simulation time analyzed
**VCD Files Processed**: dft_debug.vcd (primary evidence)
**Lines of Code Analyzed**: 341 (dft.vhd) + 963 (testbench)
