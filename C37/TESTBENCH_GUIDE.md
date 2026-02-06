# Cosine Single K ROM Testbench Guide

## Overview
This testbench (`tb_cosine_single_k_rom.vhd`) provides comprehensive verification of the `cosine_single_k_rom` ROM-based cosine coefficient generator.

## Files
- **DUT**: `/home/arunupscee/Desktop/vhdl-ai-helper/C37/cos.vhd`
- **Testbench**: `/home/arunupscee/Desktop/vhdl-ai-helper/C37/tb_cosine_single_k_rom.vhd`

## Test Coverage

### 1. Reset Behavior (Phase 1)
- Verifies `data_valid` is LOW during reset
- Confirms `cos_coeff` output is cleared to 0x0000
- Tests reset with non-zero addresses applied

### 2. Enable/Disable Control (Phase 2)
- Validates `data_valid` goes LOW when `enable='0'`
- Confirms `data_valid` goes HIGH when `enable='1'`
- Tests rapid enable toggling

### 3. Pipeline Latency (Phase 3)
- Verifies 1-cycle latency from address change to valid output
- Confirms synchronous ROM read behavior

### 4-6. Exhaustive Address Sweep (Phases 4-6)
- Tests all 256 memory locations (n_addr = 0 to 255)
- Runs for three DUT instances with K_VALUE = 1, 2, 3
- Validates Q1.15 fixed-point accuracy against golden model
- Total: 144 exhaustive tests (48 × 3)

### 7. Boundary Conditions (Phase 7)
- Address 0: cos(0) = +1.0 (0x7FFF in Q1.15)
- Address 255: Maximum valid address
- Address 64 (N/4): cos(π/2) ≈ 0
- Address 128 (N/2): cos(π) = -1.0 (0x8000 in Q1.15)

### 8. Back-to-Back Reads (Phase 8)
- Stress test with address changes every clock cycle
- Simultaneous testing of all three DUT instances
- Validates pipeline operates correctly under continuous load

### 9. Random Address Sequence (Phase 9)
- 50 random address reads using VHDL's `uniform` PRNG
- Confirms correct operation with non-sequential access patterns

### 10. Enable Toggling During Operation (Phase 10)
- Alternates enable HIGH/LOW while changing addresses
- Verifies `data_valid` tracks enable signal correctly

### 11. Symmetry Verification (Phase 11)
- Validates cosine symmetry: cos(θ) = cos(2π - θ)
- Tests 23 symmetric pairs

### 12. Special Value Verification (Phase 12)
- cos(0) = 1.0 for all K values
- cos(π) = -1.0 at appropriate N positions
- Mathematical correctness validation

### 13. Reset During Operation (Phase 13)
- Applies reset while DUT is actively reading
- Verifies immediate clearing of outputs
- Confirms proper recovery after reset release

## Verification Methodology

### Golden Model
The testbench includes a behavioral golden model:
```vhdl
function golden_cosine(n : integer; k : integer; window_size : integer) return real is
    variable angle : real;
    variable cos_val : real;
begin
    angle := 2.0 * PI * real(k) * real(n) / real(window_size);
    cos_val := cos(angle);
    return cos_val;
end function;
```

This computes the expected cosine value using VHDL's `MATH_REAL.cos()` function and compares it against DUT output.

### Tolerance Checking
- Maximum allowed error: **1 LSB** (1/32767 ≈ 0.000030518)
- Both real value comparison and exact bit-pattern matching are performed
- Any deviation triggers detailed error reporting

### Q1.15 Format
- 1 sign bit + 15 fractional bits
- Range: [-1.0, +0.99997]
- Scale factor: 2^15 = 32767
- Conversion: `real_value = signed_integer / 32767.0`

## Running the Simulation

### Using GHDL
```bash
# Analyze the DUT
ghdl -a /home/arunupscee/Desktop/vhdl-ai-helper/C37/cos.vhd

# Analyze the testbench
ghdl -a /home/arunupscee/Desktop/vhdl-ai-helper/C37/tb_cosine_single_k_rom.vhd

# Elaborate
ghdl -e tb_cosine_single_k_rom

# Run simulation
ghdl -r tb_cosine_single_k_rom --stop-time=15us

# Run with waveform generation (VCD format)
ghdl -r tb_cosine_single_k_rom --vcd=cosine_rom_tb.vcd --stop-time=15us

# Run with waveform generation (GHW format, for GTKWave)
ghdl -r tb_cosine_single_k_rom --wave=cosine_rom_tb.ghw --stop-time=15us
```

### Using ModelSim/QuestaSim
```tcl
# Create library
vlib work

# Compile DUT
vcom /home/arunupscee/Desktop/vhdl-ai-helper/C37/cos.vhd

# Compile testbench
vcom /home/arunupscee/Desktop/vhdl-ai-helper/C37/tb_cosine_single_k_rom.vhd

# Simulate
vsim tb_cosine_single_k_rom

# Run all
run -all
```

### Using Vivado Simulator
```tcl
# Add design files
add_files /home/arunupscee/Desktop/vhdl-ai-helper/C37/cos.vhd
add_files -fileset sim_1 /home/arunupscee/Desktop/vhdl-ai-helper/C37/tb_cosine_single_k_rom.vhd

# Set top module
set_property top tb_cosine_single_k_rom [get_filesets sim_1]

# Launch simulation
launch_simulation
run all
```

## Expected Output

### Console Reports
The testbench generates detailed reports for each test phase:
```
========================================
PHASE 1: RESET BEHAVIOR TEST
========================================
[RESET] Reset behavior verified successfully
========================================
PHASE 4: EXHAUSTIVE SWEEP - ALL 48 LOCATIONS (K=1)
========================================
[SWEEP_K1] PASS | n=0 k=1 | Expected: 1.0 | Actual: 0.99997 | Error: 3.05e-5
[SWEEP_K1] PASS | n=1 k=1 | Expected: 0.99144 | Actual: 0.99142 | Error: 2.1e-5
...
========================================
SIMULATION COMPLETE - FINAL SUMMARY
========================================
Total Tests:  XXX
Tests Passed: XXX
Tests Failed: 0
*** ALL TESTS PASSED ***
```

### Pass Criteria
- All assertions pass (severity error)
- `fail_count = 0` at end of simulation
- All 48×3 = 144 exhaustive tests pass
- All boundary and special value tests pass

### Simulation Time
- Expected duration: **~15 µs**
- Clock period: 10 ns (100 MHz)
- Total clock cycles: ~1500

## Key Features

### Multi-Instance Testing
The testbench instantiates **three separate DUT instances**:
- **DUT_K1**: K_VALUE = 1 (fundamental frequency)
- **DUT_K2**: K_VALUE = 2 (second harmonic)
- **DUT_K3**: K_VALUE = 3 (third harmonic)

This validates correct generic parameterization and tests multiple harmonics simultaneously.

### Self-Checking Architecture
- Automated pass/fail determination
- No manual waveform inspection required
- Detailed failure messages with expected vs. actual values
- Statistical summary at end

### Assertion Strategy
1. **Concurrent assertions**: Monitor critical invariants continuously
2. **Procedural checks**: Verify specific test scenarios
3. **Golden model comparison**: Mathematical correctness validation
4. **Protocol compliance**: Timing and handshake verification

### Helper Procedures
```vhdl
-- Main verification procedure
procedure check_cosine_value(
    constant n_val          : in integer;
    constant k_val          : in integer;
    signal   cos_output     : in std_logic_vector(15 downto 0);
    signal   data_valid_sig : in std_logic;
    constant test_name      : in string;
    signal   test_counter   : inout integer;
    signal   pass_counter   : inout integer;
    signal   fail_counter   : inout integer
);
```

### Conversion Functions
```vhdl
function q15_to_real(q15_val : std_logic_vector(15 downto 0)) return real;
function golden_cosine(n : integer; k : integer; window_size : integer) return real;
function real_to_q15(real_val : real) return std_logic_vector;
function within_tolerance(actual, expected, tolerance : real) return boolean;
```

## Debugging Tips

### Viewing Waveforms
Key signals to observe:
- `clk_tb`: Clock
- `rst_tb`: Reset
- `n_addr_1/2/3`: Address inputs
- `cos_coeff_1/2/3`: Cosine outputs (view as signed decimal or hex)
- `data_valid_1/2/3`: Valid indicators
- `enable_1/2/3`: Enable controls

### Common Issues
1. **Timing violations**: Ensure wait statements allow signals to settle
2. **Tolerance errors**: Check Q1.15 conversion matches DUT implementation
3. **Reset issues**: Verify reset is held for sufficient cycles
4. **Enable timing**: Confirm 1-cycle pipeline delay is accounted for

### Customization

To modify test parameters:
```vhdl
-- In CONFIGURATION SECTION:
constant CLK_PERIOD     : time := 10 ns;     -- Change clock frequency
constant MAX_TOLERANCE  : real := 1.0 / 32767.0;  -- Adjust tolerance
```

To test different K values:
```vhdl
-- In DUT INSTANTIATION section, add more instances:
DUT_K4: cosine_single_k_rom
    generic map (
        K_VALUE => 4  -- Fourth harmonic
    )
    ...
```

## Mathematical Background

### Cosine Computation
The DUT computes: **cos(2π·K·n/N)**

Where:
- **K**: Harmonic number (generic parameter)
- **n**: Sample index (0 to N-1)
- **N**: Window size (48 samples)

### Examples
For K=1, N=48:
- n=0:  cos(0) = +1.0 → 0x7FFF
- n=12: cos(π/2) = 0.0 → 0x0000
- n=24: cos(π) = -1.0 → 0x8001 (due to asymmetric Q1.15 range)
- n=36: cos(3π/2) = 0.0 → 0x0000

For K=2, N=48:
- n=0:  cos(0) = +1.0 → 0x7FFF
- n=6:  cos(π/2) = 0.0 → 0x0000
- n=12: cos(π) = -1.0 → 0x8001
- n=18: cos(3π/2) = 0.0 → 0x0000

## Success Criteria Summary

✓ All 144 exhaustive address tests pass (256 addresses × 3 K values)
✓ All boundary conditions verified
✓ Reset behavior correct
✓ Enable control functional
✓ Pipeline latency = 1 clock cycle
✓ Q1.15 accuracy within 1 LSB
✓ Cosine symmetry validated
✓ Special values correct (±1, 0)
✓ No timing violations
✓ No assertion failures
✓ Final report shows 0 failures

## Contact & Support
For issues or questions about this testbench, refer to the inline comments or the VHDL verification methodology documentation.
