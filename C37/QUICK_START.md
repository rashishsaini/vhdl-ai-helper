# Quick Start Guide - 256-Point DFT System

## 🚀 Run All Tests (Recommended)

```bash
cd /home/arunupscee/Desktop/vhdl-ai-helper/C37
./run_all_tests.sh
```

This will:
- ✅ Compile all VHDL files
- ✅ Elaborate all testbenches
- ✅ Run all 3 testbenches (1,704 total tests)
- ✅ Report comprehensive results

**Expected Output:**
```
✓✓✓ ALL TESTBENCHES PASSED ✓✓✓
Testbenches Passed: 3/3
System Status: PRODUCTION READY ✓
```

---

## 📦 Individual Test Runs

### Cosine ROM (921 tests)
```bash
./run_simulation.sh
```

### Sine ROM (773 tests)
```bash
./run_sine_rom_tb.sh
```

### DFT Calculator (10 comprehensive tests)
```bash
ghdl -a --std=08 cos.vhd sine.vhd dft.vhd tb_dft_complex_calculator.vhd
ghdl -e --std=08 tb_dft_complex_calculator
ghdl -r --std=08 tb_dft_complex_calculator --stop-time=500us
```

---

## 📊 Generate Waveforms

### Cosine ROM
```bash
ghdl -r --std=08 tb_cosine_single_k_rom --vcd=cosine_rom.vcd --stop-time=15us
gtkwave cosine_rom.vcd
```

### Sine ROM
```bash
ghdl -r --std=08 tb_sine_single_k_rom --vcd=sine_rom.vcd --stop-time=10us
gtkwave sine_rom.vcd
```

### DFT Calculator
```bash
ghdl -r --std=08 tb_dft_complex_calculator --vcd=dft_calc.vcd --stop-time=500us
gtkwave dft_calc.vcd
```

---

## 🔍 Key Signals to Observe in Waveforms

### DFT Calculator (dft.vhd)
- `current_state` - State machine progression
- `sample_counter` - Should count 0 to 255
- `accumulator_real`, `accumulator_imag` - Accumulated DFT values
- `real_result`, `imag_result` - Final 32-bit outputs
- `done`, `result_valid` - Completion signals

### ROMs (cos.vhd, sine.vhd)
- `n_addr` - Input address (0-255)
- `cos_coeff` / `sin_coeff` - Q1.15 coefficient output
- `data_valid` - Output valid signal

---

## 📖 Documentation

| File | Description |
|------|-------------|
| **PROJECT_COMPLETE.md** | Complete upgrade summary and results |
| **TESTBENCH_GUIDE.md** | Cosine ROM testbench detailed guide |
| **TESTBENCH_README.md** | Sine ROM testbench detailed guide |
| **SIMULATION_SUMMARY.md** | Cosine ROM test results |
| **TESTBENCH_SUMMARY.md** | Sine ROM test results |
| **QUICK_START.md** | This file |

---

## 🎯 Verification Status

| Module | File | Samples | Tests | Status |
|--------|------|---------|-------|--------|
| Cosine ROM | cos.vhd | 256 | 921 | ✅ PASS |
| Sine ROM | sine.vhd | 256 | 773 | ✅ PASS |
| DFT Calc | dft.vhd | 256 | 10 | ✅ PASS |
| **TOTAL** | - | - | **1,704** | **✅ 100%** |

---

## 🔧 Integration Example

```vhdl
-- Instantiate DFT system
signal clk : std_logic;
signal rst : std_logic;
signal start : std_logic;
signal done : std_logic;
signal real_result : std_logic_vector(31 downto 0);
signal imag_result : std_logic_vector(31 downto 0);
signal result_valid : std_logic;

-- Sample buffer (you provide this)
type sample_buffer_type is array (0 to 255) of std_logic_vector(15 downto 0);
signal samples : sample_buffer_type;

-- ROM instances
COS_ROM: cosine_single_k_rom
    generic map (
        WINDOW_SIZE => 256,
        K_VALUE => 1  -- Change for different harmonics
    )
    port map (
        clk => clk,
        rst => rst,
        enable => '1',
        n_addr => cos_addr,
        cos_coeff => cos_coeff,
        data_valid => cos_valid
    );

SIN_ROM: sine_single_k_rom
    generic map (
        WINDOW_SIZE => 256,
        K_VALUE => 1  -- Must match cosine ROM
    )
    port map (
        clk => clk,
        rst => rst,
        enable => '1',
        n_addr => sin_addr,
        sin_coeff => sin_coeff,
        data_valid => sin_valid
    );

DFT: dft_complex_calculator
    generic map (
        WINDOW_SIZE => 256,
        SAMPLE_WIDTH => 16,
        COEFF_WIDTH => 16,
        ACCUMULATOR_WIDTH => 48,
        OUTPUT_WIDTH => 32
    )
    port map (
        clk => clk,
        rst => rst,
        start => start,
        done => done,
        sample_data => samples(to_integer(unsigned(sample_addr))),
        sample_addr => sample_addr,
        cos_coeff => cos_coeff,
        cos_addr => cos_addr,
        cos_valid => cos_valid,
        sin_coeff => sin_coeff,
        sin_addr => sin_addr,
        sin_valid => sin_valid,
        real_result => real_result,
        imag_result => imag_result,
        result_valid => result_valid
    );

-- Usage:
-- 1. Load 256 Q15 samples into 'samples' array
-- 2. Assert 'start' for 1 clock cycle
-- 3. Wait for 'done' to go high (~1,550 cycles @ 100 MHz = 15.5 µs)
-- 4. Read real_result and imag_result when result_valid = '1'
-- 5. Compute magnitude: sqrt(real^2 + imag^2)
-- 6. Compute phase: atan2(imag, real)
```

---

## ⚡ Performance

| Metric | Value |
|--------|-------|
| **Clock Frequency** | 100 MHz (scalable) |
| **DFT Latency** | ~15.5 µs (1,550 cycles) |
| **Throughput** | ~64,500 DFTs/second |
| **Accumulator Precision** | 48-bit (Q33.15) |
| **Output Precision** | 32-bit (Q16.15) |
| **Magnitude Accuracy** | ±2% + 1 LSB |
| **Phase Accuracy** | ±5° (strong signals) |

---

## 💡 Tips

1. **Clock Speed:** Design is tested at 100 MHz but should work at higher frequencies with timing analysis

2. **K Value:** Change `K_VALUE` generic in ROMs to compute different frequency bins (K=0 to K=23 for 256-point DFT)

3. **Sample Format:** Input samples must be in Q15 format (-32768 to +32767)

4. **Output Scaling:** DFT output is 128x input amplitude for sinusoids. Account for this in your system.

5. **Accumulator Headroom:** 48-bit accumulator has 23 bits of headroom - no overflow risk for normal signals

---

## 🆘 Troubleshooting

**Compilation errors?**
```bash
# Ensure GHDL supports VHDL-2008
ghdl --version

# Use --std=08 flag
ghdl -a --std=08 yourfile.vhd
```

**Tests failing?**
```bash
# Check individual test output
ghdl -r --std=08 tb_dft_complex_calculator --stop-time=500us 2>&1 | less

# Look for FAIL messages
ghdl -r --std=08 tb_dft_complex_calculator --stop-time=500us 2>&1 | grep FAIL
```

**Need to debug?**
```bash
# Generate waveform and inspect in GTKWave
ghdl -r --std=08 tb_dft_complex_calculator --vcd=debug.vcd --stop-time=500us
gtkwave debug.vcd

# Key signals to watch:
# - current_state (should cycle through all states)
# - sample_counter (should reach 255)
# - accumulator_real/imag (should accumulate 256 products)
```

---

## ✅ Success Criteria

You know the system is working when:
- ✅ `./run_all_tests.sh` reports "ALL TESTBENCHES PASSED"
- ✅ 1,704 total tests execute with 0 failures
- ✅ DFT Test 3 shows magnitude ≈ 128 for K=1 sinusoid
- ✅ State machine cycles IDLE → INIT → (FETCH → WAIT → MULTIPLY → SCALE → ACC) × 256 → DONE

---

**Ready to use! 🚀**

For complete technical details, see **PROJECT_COMPLETE.md**
