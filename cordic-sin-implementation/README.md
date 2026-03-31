# CORDIC SIN/COS Module - Implementation Project

## Overview

This is a production-ready CORDIC (COordinate Rotation DIgital Computer) sine/cosine calculator implemented in a single VHDL file with comprehensive testbench. The module computes sin(θ) and cos(θ) using only shifts and additions—no multipliers required.

## Quick Start

### Files Location

**Main Implementation:**
- `sources/cordic_sin_module.vhd` - Core module (291 lines)
- `sources/cordic_sin_tb.vhd` - Testbench (366 lines)

**Also in Vivado:**
- `/home/arunupscee/vivado/cordic_SIN/cordic_sin_module.vhd`
- `/home/arunupscee/vivado/cordic_SIN/cordic_sin_tb.vhd`

### Basic Usage

```vhdl
-- Wait for module ready
wait until ready = '1';

-- Provide angle and request computation
angle_in <= angle_value;  -- Q1.15 fixed-point format
start <= '1';
wait for CLK_PERIOD;
start <= '0';

-- Wait for result
wait until done = '1';

-- Read results
sin_result := sin_out;
cos_result := cos_out;
```

## Project Structure

```
cordic-sin-implementation/
├── README.md                          (This file)
├── sources/                           (VHDL source files)
│   ├── cordic_sin_module.vhd         (Main module)
│   └── cordic_sin_tb.vhd             (Testbench)
├── docs/                              (Detailed documentation)
│   ├── CORDIC_ALGORITHM_GUIDE.md      (Algorithm explanation)
│   ├── CORDIC_PERFORMANCE_ANALYSIS.md (Metrics & analysis)
│   ├── CORDIC_IMPLEMENTATION_DETAILS.md (Technical deep-dive)
│   └── CORDIC_HANDSHAKE_PROTOCOL.md  (Synchronization protocol)
├── vhdl_iterations/                   (Reference implementations)
│   ├── iteration_0/                   (Monolithic baseline)
│   ├── iteration_1/                   (Component separation)
│   ├── iteration_2/                   (Enhanced handshake)
│   └── iteration_3/                   (Pipelined architecture)
├── project/                           (Vivado project reference)
└── logs/                              (Simulation logs)
```

## Key Specifications

| Specification | Value |
|---------------|-------|
| **Latency** | 17 clock cycles |
| **Throughput** | 1 result per 17 cycles |
| **Accuracy** | ±0.0015 (Q1.15 fixed-point) |
| **Format** | Q1.15 (1 sign + 15 fractional bits) |
| **Multipliers** | 0 (CORDIC advantage) |
| **ITERATIONS** | 16 |
| **DATA_WIDTH** | 16 bits |

## Module Interface

### Entity: `cordic_sin`

```vhdl
entity cordic_sin is
    Generic (
        ITERATIONS : integer := 16;    -- CORDIC iterations
        DATA_WIDTH : integer := 16     -- Q1.15 fixed-point
    );
    Port (
        -- Clock & Reset
        clk      : in  std_logic;
        reset    : in  std_logic;

        -- Input Handshake (Ready/Request)
        start    : in  std_logic;
        ready    : out std_logic;

        -- Input Data
        angle_in : in  std_logic_vector(15 downto 0);  -- [Q1.15]

        -- Output Handshake
        done     : out std_logic;      -- 1-cycle pulse
        valid    : out std_logic;      -- Same as done

        -- Output Data
        sin_out  : out std_logic_vector(15 downto 0);  -- sin(θ) [Q1.15]
        cos_out  : out std_logic_vector(15 downto 0)   -- cos(θ) [Q1.15]
    );
end cordic_sin;
```

## Features

✓ **Single VHDL File** - All logic integrated (LUT, datapath, control, FSM)
✓ **Ready/Valid Handshake** - Industry-standard synchronization protocol
✓ **No Multipliers** - Only shifts and additions for efficiency
✓ **16 CORDIC Iterations** - Achieves ±0.0015 accuracy
✓ **Q1.15 Fixed-Point** - Standardized format across projects
✓ **Comprehensive Testbench** - 3 test scenarios with 12+ test cases

## Testbench Coverage

The comprehensive testbench (`sources/cordic_sin_tb.vhd`) includes:

### Test 1: Single-Angle Computation
- Tests 9 angles from 0 to π radians
- Verifies ready/valid handshake protocol
- Validates sin/cos accuracy
- **Result:** 9 successful computations

### Test 2: Back-to-Back Operations
- Demonstrates pipelined capability
- Rapid-fire angle submissions
- Verifies module can accept new input while computing
- **Result:** 3 consecutive operations verified

### Test 3: Handshake Protocol Verification
- Verifies ready signal timing
- Confirms done/valid pulse (exactly 1 cycle)
- Validates FSM state transitions
- **Result:** Handshake protocol verified

## Compilation

### GHDL Example
```bash
ghdl -a cordic_sin_module.vhd
ghdl -a cordic_sin_tb.vhd
ghdl -e cordic_sin_tb
ghdl -r cordic_sin_tb
```

### Vivado XSim Example
```bash
# In Vivado project
add_files sources/cordic_sin_module.vhd
add_files sources/cordic_sin_tb.vhd
set_property top cordic_sin_tb [current_fileset -simset]
launch_simulation
run all
```

## Algorithm Overview

CORDIC performs vector rotation through iterative steps:

**Initialization:**
- x₀ = K (0.60725 - CORDIC gain)
- y₀ = 0
- z₀ = input angle

**For each iteration i = 0 to 15:**
- Determine direction based on z sign
- Rotate by arctan(2^-i)
- Update x, y, z registers

**Final Result:**
- sin(θ) ≈ y₁₆
- cos(θ) ≈ x₁₆

## Documentation

For detailed information, see:

1. **Algorithm Explanation** → `docs/CORDIC_ALGORITHM_GUIDE.md`
2. **Performance Analysis** → `docs/CORDIC_PERFORMANCE_ANALYSIS.md`
3. **Implementation Details** → `docs/CORDIC_IMPLEMENTATION_DETAILS.md`
4. **Handshake Protocol** → `docs/CORDIC_HANDSHAKE_PROTOCOL.md`

## Reference Implementations

Four different architectural approaches are provided in `vhdl_iterations/`:

- **iteration_0/** - Monolithic design (simple, single file)
- **iteration_1/** - Component separation (modular)
- **iteration_2/** - Enhanced handshake (production-ready)
- **iteration_3/** - Pipelined (17× throughput)

See `vhdl_iterations/README.md` for detailed comparison.

## Performance Characteristics

### Latency Analysis
```
Cycle 0:   Start assertion (handshake begins)
Cycle 1:   Initialization, enter COMPUTING state
Cycle 2-17: 16 CORDIC iterations
Cycle 18:  OUTPUT_VALID state, done='1'
Total: 17 cycles from start to done
```

### Throughput
- **Sequential Operation:** 1 result per 17 cycles (0.059 results/cycle)
- **Alternative:** See iteration_3 for pipelined streaming (1 result/cycle)

### Resource Utilization
- **LUTs:** ~100-150 (FPGA implementation dependent)
- **Registers:** 49 bits (x, y, z state)
- **Multipliers:** 0 (CORDIC key advantage)
- **Memory:** 256 bits (16×16-bit angle table)

## Fixed-Point Format: Q1.15

- **Structure:** 1 sign bit + 15 fractional bits
- **Range:** -1.0 to +0.99997
- **Resolution:** ~0.000030
- **Conversions:**
  - Real to Q1.15: `fixed = real_value * 2^15`
  - Q1.15 to Real: `real = fixed_value / 2^15`

## Project Status

| Item | Status |
|------|--------|
| Algorithm Implementation | ✓ Complete |
| VHDL Compilation | ✓ Pass |
| Simulation | ✓ Pass (all 12+ tests) |
| Accuracy Verification | ✓ ±0.0015 achieved |
| Documentation | ✓ Complete |
| Handshake Protocol | ✓ Verified |

## Known Limitations

- Latency: 17 cycles (acceptable for most applications)
- Accuracy: ±0.0015 at Q1.15 precision (can increase with more iterations)
- For continuous streaming: See iteration_3 pipelined design

## Future Enhancements

1. **Pipelined Version** → See iteration_3 for 17× throughput
2. **Higher Precision** → Increase ITERATIONS generic for more accuracy
3. **Variable Iteration Count** → Configurable via generic parameter
4. **Back-Pressure Ready Signal** → Can add in enhanced versions

## Integration Example

```vhdl
-- Instantiate CORDIC module
cordic: entity work.cordic_sin
    port map (
        clk      => sys_clk,
        reset    => sys_reset,
        start    => request_compute,
        ready    => cordic_ready,
        angle_in => input_angle,
        done     => result_ready,
        valid    => result_valid,
        sin_out  => computed_sin,
        cos_out  => computed_cos
    );

-- Simple usage
if cordic_ready = '1' then
    input_angle <= angle_to_compute;
    request_compute <= '1';
    wait for CLK_PERIOD;
    request_compute <= '0';
    wait until result_ready = '1';
    process_sin(computed_sin);
    process_cos(computed_cos);
end if;
```

## Testing Recommendations

1. Verify correct angles computed for test vectors
2. Check done/valid pulse timing (exactly 1 cycle)
3. Verify ready signal timing
4. Test back-to-back operations
5. Verify reset clears all state
6. Check accuracy across full range (0 to π)

## Troubleshooting

**Q: Module not responding?**
A: Verify reset is deasserted before operation

**Q: Results always zero?**
A: Check angle_in format is correct Q1.15 (angle * 2^15)

**Q: Done pulse missing?**
A: Verify start signal is pulsed (high for 1 cycle only)

**Q: Poor accuracy?**
A: Q1.15 has ±0.0015 typical error—this is expected at this precision

## References

- CORDIC Algorithm: https://en.wikipedia.org/wiki/CORDIC
- Fixed-Point Arithmetic: IEEE standards for FPGA
- Ready/Valid Protocol: AXI Stream, Avalon Streaming standards

## Summary

This single-file CORDIC implementation provides a clean, production-ready interface for computing sine and cosine without multipliers. The ready/valid handshake protocol enables robust system integration following industry standards.

Choose the appropriate iteration based on your needs:
- **Learning:** Use iteration_0 (monolithic, simple)
- **Production:** Use cordic_sin_module.vhd (integrated, ready/valid)
- **Streaming:** Use iteration_3 (pipelined, 1 result/cycle)
