# SINE_SINGLE_K_ROM Testbench Documentation

## Overview

This testbench provides comprehensive verification for the `sine_single_k_rom` entity, a ROM-based sine coefficient generator that outputs Q1.15 fixed-point sine values.

**Files:**
- **DUT:** `/home/arunupscee/Desktop/vhdl-ai-helper/C37/sine.vhd`
- **Testbench:** `/home/arunupscee/Desktop/vhdl-ai-helper/C37/tb_sine_single_k_rom.vhd`
- **Run Script:** `/home/arunupscee/Desktop/vhdl-ai-helper/C37/run_sine_rom_tb.sh`

---

## DUT Specification

### Entity: sine_single_k_rom

**Generics:**
- `WINDOW_SIZE`: Number of samples (default: 256)
- `COEFF_WIDTH`: Coefficient bit width (default: 16 for Q1.15)
- `K_VALUE`: Harmonic number/frequency multiplier (default: 1)

**Ports:**
- `clk`: System clock input
- `rst`: Synchronous reset (active high)
- `enable`: Enable signal (active high, default '1')
- `n_addr`: 8-bit address input (sample index 0-255)
- `sin_coeff`: 18-bit Q1.15 sine coefficient output
- `data_valid`: Output valid indicator

**Functionality:**
Computes sin(2π·K·n/N) where:
- K = K_VALUE (harmonic number)
- n = n_addr (sample index)
- N = WINDOW_SIZE (48)

**Output Format:** Q1.15 fixed-point
- Range: -1.0 to +0.99997
- Representation: -32768 to +32767
- Scaling: value / 32767 = real sine value

---

## Test Coverage

### 1. Reset Behavior Test
- Verifies synchronous reset functionality
- Confirms outputs are cleared during reset
- Validates data_valid goes low during reset
- Tests reset recovery

**Expected:**
- `sin_coeff = 0x0000` during reset
- `data_valid = '0'` during reset

### 2. Basic Address Sweep (K=1)
- Tests all 256 memory locations (addresses 0-255)
- Compares ROM output against golden model
- Validates Q1.15 conversion accuracy
- Tolerance: ±1 LSB

**Coverage:** 100% of ROM addresses for fundamental frequency

### 3. Enable/Disable Functionality
- Tests enable control behavior
- Verifies data_valid tracks enable signal
- Confirms output holds when disabled
- Tests re-enable functionality

**Expected:**
- `data_valid = '1'` when `enable = '1'`
- `data_valid = '0'` when `enable = '0'`

### 4. Boundary Conditions
- Address 0 (first location)
- Address 255 (last location)
- Address 63 (maximum 8-bit value, out-of-range test)
- Tests robustness against invalid addresses

### 5. Back-to-Back Reads
- Rapid consecutive address changes
- Pipeline behavior validation
- Verifies data_valid consistency
- Tests throughput capability

**Coverage:** 16 consecutive reads

### 6. Multiple K_VALUE Testing
- Three DUT instances with K=1, K=2, K=3
- Complete address sweeps for each harmonic
- Validates different frequency components
- Tests parallel operation

**Coverage:** 256 addresses × 3 harmonics = 144 unique test points

### 7. Corner Cases
- sin(0) = 0 verification
- sin(π/2) ≈ +1 verification (maximum positive)
- sin(3π/2) ≈ -1 verification (maximum negative)
- Simultaneous reads from multiple DUTs

---

## Testbench Architecture

### Structure

```
tb_sine_single_k_rom
├── Configuration Section
│   ├── Clock parameters (100 MHz, 10 ns period)
│   ├── DUT parameters (WINDOW_SIZE, COEFF_WIDTH)
│   └── Test parameters (tolerance, constants)
│
├── Component Declaration
│   └── sine_single_k_rom component
│
├── Signal Declarations
│   ├── Clock and control signals
│   ├── DUT K=1 interface signals
│   ├── DUT K=2 interface signals
│   ├── DUT K=3 interface signals
│   └── Test control and statistics
│
├── Golden Model Functions
│   ├── real_to_q15() - Convert real to Q1.15
│   ├── calculate_expected_sine() - Golden model
│   ├── q15_to_real() - Convert Q1.15 to real
│   └── within_tolerance() - Comparison checker
│
├── Test Procedures
│   ├── wait_cycles() - Synchronization
│   ├── apply_reset() - Reset sequence
│   └── verify_coeff() - Coefficient verification
│
├── DUT Instantiation (3 instances)
│   ├── DUT_K1 (K_VALUE=1)
│   ├── DUT_K2 (K_VALUE=2)
│   └── DUT_K3 (K_VALUE=3)
│
├── Clock Generation Process
│
├── Main Test Sequencer Process
│   ├── INIT phase
│   ├── RESET_TEST phase
│   ├── BASIC_SWEEP_K1 phase
│   ├── ENABLE_DISABLE_TEST phase
│   ├── BOUNDARY_TEST phase
│   ├── BACK_TO_BACK_TEST phase
│   ├── SWEEP_K2 phase
│   ├── SWEEP_K3 phase
│   ├── CORNER_CASES phase
│   └── FINAL_REPORT phase
│
└── Concurrent Assertions
    ├── Metastability detection
    ├── Enable/valid relationship
    └── Address stability monitoring
```

### Golden Model

The testbench includes a golden model that exactly replicates the DUT's sine calculation:

```vhdl
function calculate_expected_sine(n : integer; k : integer) return integer is
    angle := 2.0 * PI * real(k) * real(n) / real(WINDOW_SIZE);
    sin_val := sin(angle);
    return real_to_q15(sin_val);
end function;
```

This ensures bit-accurate comparison with the ROM contents.

### Self-Checking Mechanism

**verify_coeff() procedure:**
- Compares DUT output with golden model
- Checks tolerance (±1 LSB)
- Validates data_valid signal
- Reports mismatches with detailed information
- Updates pass/fail statistics

**Assertion Format:**
```
[PHASE_NAME] ERROR_TYPE: Description | Details | Expected: X | Actual: Y
```

---

## Running the Testbench

### Prerequisites
- GHDL simulator (IEEE VHDL-2008 support required)
- GTKWave (optional, for waveform viewing)

### Quick Start

```bash
cd /home/arunupscee/Desktop/vhdl-ai-helper/C37
./run_sine_rom_tb.sh
```

### Manual Execution

```bash
# Analysis
ghdl -a --std=08 sine.vhd
ghdl -a --std=08 tb_sine_single_k_rom.vhd

# Elaboration
ghdl -e --std=08 tb_sine_single_k_rom

# Simulation
ghdl -r --std=08 tb_sine_single_k_rom --vcd=sine_rom_tb.vcd --stop-time=30us

# View waveforms
gtkwave sine_rom_tb.vcd
```

### Expected Output

```
========================================
  SINE_SINGLE_K_ROM TESTBENCH START
========================================
Window Size: 48
Coeff Width: 16 bits (Q1.15)
Tolerance: ±1 LSB
----------------------------------------
[RESET_TEST] Testing reset behavior...
[RESET_TEST] Reset test completed
[BASIC_SWEEP_K1] Testing all 256 addresses for K=1...
[BASIC_SWEEP_K1] Completed sweep of all 256 addresses
[ENABLE_DISABLE] Testing enable/disable control...
[ENABLE_DISABLE] Enable/disable test completed
[BOUNDARY] Testing boundary conditions...
[BOUNDARY] Boundary test completed
[BACK_TO_BACK] Testing consecutive reads...
[BACK_TO_BACK] Back-to-back read test completed
[SWEEP_K2] Testing all 256 addresses for K=2...
[SWEEP_K2] Completed K=2 sweep
[SWEEP_K3] Testing all 256 addresses for K=3...
[SWEEP_K3] Completed K=3 sweep
[CORNER_CASES] Testing special values...
[CORNER_CASES] Corner case testing completed
========================================
  TESTBENCH FINAL REPORT
========================================
Total Tests:  XXX
Passed:       XXX
Failed:       0
----------------------------------------
*** ALL TESTS PASSED ***
========================================
  SIMULATION COMPLETE
========================================
```

---

## Waveform Analysis

### Key Signals to Observe

**Clock and Control:**
- `clk` - System clock
- `rst` - Reset signal
- `enable` - Enable control

**DUT K=1 Interface:**
- `n_addr_k1[5:0]` - Address input
- `sin_coeff_k1[15:0]` - Sine output (Q1.15)
- `data_valid_k1` - Valid indicator

**DUT K=2 Interface:**
- `n_addr_k2[5:0]` - Address input
- `sin_coeff_k2[15:0]` - Sine output (Q1.15)
- `data_valid_k2` - Valid indicator

**DUT K=3 Interface:**
- `n_addr_k3[5:0]` - Address input
- `sin_coeff_k3[15:0]` - Sine output (Q1.15)
- `data_valid_k3` - Valid indicator

**Test Status:**
- `current_phase` - Current test phase
- `test_count` - Number of tests executed
- `pass_count` - Tests passed
- `fail_count` - Tests failed

### Timing Diagram

```
Clock:     __‾‾__‾‾__‾‾__‾‾__‾‾__‾‾__‾‾__
           0   1   2   3   4   5   6

n_addr:    [  A0  ][  A1  ][  A2  ]

enable:    ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

sin_coeff: [  X   ][D(A0) ][D(A1) ][D(A2)]

data_valid:________‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
```

**Pipeline Latency:** 1 clock cycle from address input to valid output

---

## Verification Metrics

### Test Statistics (Expected)

| Test Phase          | Test Count | Coverage                    |
|---------------------|------------|-----------------------------|
| RESET_TEST          | 3          | Reset behavior              |
| BASIC_SWEEP_K1      | 48         | All addresses, K=1          |
| ENABLE_DISABLE      | 3          | Enable control              |
| BOUNDARY_TEST       | 2          | Edge addresses              |
| BACK_TO_BACK_TEST   | 0          | Pipeline verification       |
| SWEEP_K2            | 48         | All addresses, K=2          |
| SWEEP_K3            | 48         | All addresses, K=3          |
| CORNER_CASES        | 0          | Special values              |
| **TOTAL**           | **~152**   | **Comprehensive coverage**  |

### Assertion Coverage

- **Reset assertions:** 2
- **Enable/disable assertions:** 3
- **Coefficient accuracy checks:** 144 (48×3)
- **Protocol assertions:** 2
- **Concurrent monitors:** 3

### Code Coverage Goals

- **Statement coverage:** 100% (all DUT statements executed)
- **Branch coverage:** 100% (reset/enable branches)
- **Condition coverage:** 100% (all enable/reset combinations)
- **FSM coverage:** N/A (no FSM in DUT)

---

## Troubleshooting

### Common Issues

**1. Simulation doesn't start**
- Check GHDL installation: `ghdl --version`
- Verify VHDL-2008 support: `--std=08` flag
- Ensure files exist in correct directory

**2. Coefficient mismatch errors**
- Expected: ±1 LSB tolerance due to rounding
- Check Q1.15 conversion: value / 32767
- Verify golden model matches DUT implementation

**3. Waveform file not generated**
- Ensure `--vcd=` flag is used
- Check write permissions in directory
- Verify simulation completes successfully

**4. Compilation errors**
- Use VHDL-2008 standard: `--std=08`
- Check IEEE library support (MATH_REAL)
- Verify component/entity names match

### Debugging Tips

**Enable verbose output:**
```bash
ghdl -r --std=08 tb_sine_single_k_rom --vcd=sine_rom_tb.vcd --stop-time=30us --ieee-asserts=disable-at-0
```

**Check specific test phase:**
- Add breakpoints in testbench at phase transitions
- Monitor `current_phase` signal in waveform viewer
- Review assertion messages for failure location

**Analyze coefficient values:**
- Convert Q1.15 to decimal: `signed_value / 32767.0`
- Example: 0x4000 = 16384 / 32767 = 0.5
- Example: 0x8000 = -32768 / 32767 = -1.0

---

## Extensions and Customization

### Modify Test Parameters

**Change clock frequency:**
```vhdl
constant CLK_PERIOD : time := 20 ns;  -- 50 MHz instead of 100 MHz
```

**Adjust tolerance:**
```vhdl
constant TOLERANCE_LSB : integer := 2;  -- Allow ±2 LSB error
```

**Test different window sizes:**
Modify DUT generic in instantiation:
```vhdl
DUT_K1: sine_single_k_rom
    generic map (
        WINDOW_SIZE => 64,  -- Changed from 48
        COEFF_WIDTH => 16,
        K_VALUE     => 1
    )
```

### Add More Test Scenarios

**Test additional K values:**
```vhdl
-- Add DUT_K4 instance with K_VALUE => 4
-- Add SWEEP_K4 test phase
```

**Stress testing:**
```vhdl
-- Rapid enable/disable toggling
-- Random address patterns
-- Extended runtime tests
```

**Protocol violation tests:**
```vhdl
-- Address changes during reset
-- Enable glitches
-- Metastability injection
```

---

## References

### Q1.15 Fixed-Point Format
- **Range:** -1.0 to +0.99997
- **Resolution:** 1/32768 ≈ 0.0000305
- **Representation:** Two's complement signed integer
- **Conversion to real:** `real_value = integer_value / 32767.0`
- **Conversion from real:** `integer_value = round(real_value × 32767.0)`

### Sine Wave Properties
- **Period:** 2π radians (360 degrees)
- **For K=1, N=48:** One complete cycle over 48 samples
- **For K=2, N=48:** Two complete cycles over 48 samples
- **For K=3, N=48:** Three complete cycles over 48 samples

### Key Formulas
```
Angle(n,k) = 2π × k × n / N
sin_value(n,k) = sin(Angle(n,k))
Q15_value = round(sin_value × 32767)
```

---

## Success Criteria

✓ All 48 ROM locations verified for K=1, K=2, K=3
✓ Coefficient values within ±1 LSB of golden model
✓ Reset properly clears outputs and data_valid
✓ Enable/disable controls data_valid correctly
✓ Pipeline latency is exactly 1 clock cycle
✓ Boundary addresses (0, 47) handled correctly
✓ Back-to-back reads maintain data_valid
✓ Corner cases (sin=0, sin=±1) verified
✓ Zero simulation failures
✓ Complete test coverage report generated

**Expected Result:** 100% pass rate with 0 failures

---

## Contact and Support

For issues or questions about this testbench:
- Review simulation transcript for assertion messages
- Check waveforms for timing violations
- Verify DUT implementation matches specification
- Ensure GHDL version supports VHDL-2008 and MATH_REAL

**Testbench Version:** 1.0
**Last Updated:** 2025-11-29
**Compatible DUT:** sine_single_k_rom (behavioral architecture)
