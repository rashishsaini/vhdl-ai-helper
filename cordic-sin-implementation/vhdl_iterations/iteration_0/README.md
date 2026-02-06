# Iteration 0: Monolithic Baseline CORDIC

## Overview
This is the baseline monolithic CORDIC implementation - a single self-contained module that performs sine/cosine computation using the CORDIC algorithm.

## Architecture

### Design Philosophy
All logic (angle lookup, rotation operations, control) is contained in a single entity. This provides a simple, direct implementation of the CORDIC algorithm.

### Top-Level Interface

```
Entity: cordic_processor

Generics:
  ITERATIONS : integer := 16    -- Number of CORDIC iterations
  DATA_WIDTH : integer := 16    -- Fixed-point data width (Q1.15)

Ports:
  clk        : in  std_logic    -- System clock
  reset      : in  std_logic    -- Synchronous reset (active high)
  start      : in  std_logic    -- Initiate computation
  angle_in   : in  std_logic_vector(15..0)  -- Input angle [Q1.15]
  sin_out    : out std_logic_vector(15..0)  -- Output sine [Q1.15]
  cos_out    : out std_logic_vector(15..0)  -- Output cosine [Q1.15]
  done       : out std_logic    -- Computation complete flag
```

## Algorithm Implementation

### CORDIC Rotation Mode

The module implements CORDIC in **rotation mode**, which directly computes sine and cosine:

```
Initial State:
  x₀ = K = 0.60725 (CORDIC gain in Q1.15 = 0x4DBA in hex)
  y₀ = 0
  z₀ = target_angle

For each iteration i from 0 to ITERATIONS-1:
  if z_i < 0:
    x_{i+1} = x_i + (y_i >> i)    // Right shift by i bits
    y_{i+1} = y_i - (x_i >> i)
    z_{i+1} = z_i + ANGLE_TABLE[i]
  else:
    x_{i+1} = x_i - (y_i >> i)
    y_{i+1} = y_i + (x_i >> i)
    z_{i+1} = z_i - ANGLE_TABLE[i]

Final Result:
  sin(angle) ≈ y_N
  cos(angle) ≈ x_N
```

### Control Flow

```
STATE MACHINE (FSM):
  IDLE -> START -> COMPUTING (16 cycles) -> DONE -> IDLE
```

**State Transitions**:
1. **IDLE**: Wait for `start` signal
2. **COMPUTING**: Perform 16 iterations (one per clock cycle)
   - Each cycle: shift, add/subtract, angle lookup
3. **DONE**: Hold `done='1'` for one cycle, then return to IDLE

### Angle Lookup Table (LUT)

Pre-computed angles for i=0 to 15:
```
ANGLE_TABLE: arctan(2^(-i)) in Q1.15 fixed-point

i=0:  arctan(1.0)      = 0.7854 rad = 45.000°  = 0x3243
i=1:  arctan(0.5)      = 0.4636 rad = 26.565°  = 0x1DAC
i=2:  arctan(0.25)     = 0.2450 rad = 14.036°  = 0x0FAD
i=3:  arctan(0.125)    = 0.1244 rad = 7.125°   = 0x07F5
i=4:  arctan(0.0625)   = 0.0624 rad = 3.576°   = 0x03FE
i=5:  arctan(0.03125)  = 0.0312 rad = 1.789°   = 0x01FF
i=6:  arctan(0.015625) = 0.0156 rad = 0.895°   = 0x00FF
i=7:  arctan(0.0078)   = 0.0078 rad = 0.447°   = 0x007F
i=8-15: Decreasing angles, negligible effect, approach zero
```

These angles enable rotation without explicit multiplication/division.

## Fixed-Point Arithmetic

### Q1.15 Format
- **1 sign bit** + **15 fractional bits** = 16-bit total
- **Range**: -1.0 to +0.99997
- **Resolution**: 1/2^15 ≈ 0.000030
- **Conversion**:
  - Real to Q1.15: `fixed = real_value * 2^15`
  - Q1.15 to Real: `real = fixed_value / 2^15`

### K Constant (CORDIC Gain)
```
K = ∏(1/√(1 + 2^(-2i))) for i=0 to ITERATIONS-1
K ≈ 0.607252935
In Q1.15: K ≈ 0.60725 * 2^15 = 19897 decimal = 0x4DBA hex
```
This constant is applied at initialization to compensate for the inherent CORDIC gain.

## Data Flow

```
INPUT: angle_in (Q1.15)
  |
  v
[Initialize: x=K, y=0, z=angle]
  |
  +---> Iteration 0: shift by 0, add/sub angles[0]
  |
  +---> Iteration 1: shift by 1, add/sub angles[1]
  |
  +---> Iteration 2: shift by 2, add/sub angles[2]
  |
  ...16 iterations total...
  |
  +---> sin_out = y_final (Q1.15)
  |---> cos_out = x_final (Q1.15)
  |---> done signal asserted for 1 cycle
```

## Timing

### Computation Latency
- **Pipeline depth**: 16 cycles
- **Latency**: 16 clock cycles from `start` to `done`

### Done Signal Behavior
```
Cycle    | start | computing | done | description
---------|-------|-----------|------|------------------
N        | '1'   | '0'       | '0'  | Start asserted
N+1      | 'X'   | '1'       | '0'  | Iteration 0 begins
N+2      | 'X'   | '1'       | '0'  | Iteration 1
...      | ...   | ...       | ...  | ...
N+16     | 'X'   | '1'       | '0'  | Iteration 15
N+17     | 'X'   | '0'       | '1'  | Done asserted
N+18     | 'X'   | '0'       | '0'  | Done cleared, ready for next

Total latency: 17 cycles after start assertion
```

## Testing

### Test Vector
Nine angles spanning 0 to π radians:
```
Angle Index | Radians | Degrees | sin(θ)   | cos(θ)
------------|---------|---------|----------|----------
0           | 0.0000  | 0.000°  | 0.0000   | 1.0000
1           | 0.3927  | 22.500° | 0.3827   | 0.9239
2           | 0.7854  | 45.000° | 0.7071   | 0.7071
3           | 1.1781  | 67.500° | 0.9239   | 0.3827
4           | 1.5708  | 90.000° | 1.0000   | 0.0000
5           | 1.9635  | 112.500°| 0.9239   | -0.3827
6           | 2.3562  | 135.000°| 0.7071   | -0.7071
7           | 2.7489  | 157.500°| 0.3827   | -0.9239
8           | 3.1416  | 180.000°| 0.0000   | -1.0000
```

### Expected Accuracy
- **Error magnitude**: ±0.0015 (0.15% for values near 1.0)
- **Root cause**: Limited iterations (16) and quantization in Q1.15
- **Improvement**: More iterations → better accuracy (each iteration adds ~1 bit)

### Test Execution
```bash
# Run testbench
vivado -mode batch -source tb_cordic.vhd

# Expected output: 9 computed (sin, cos) pairs matching table above
# Success criteria: All errors < 0.002
```

## Implementation Details

### Key Signals (Internal)
- `x_reg, y_reg, z_reg`: State registers (signed 16-bit)
- `x_next, y_next, z_next`: Next-state values
- `iteration_count`: Iteration counter (0 to 15)
- `computing`: Computation in-progress flag

### Behavioral Processes

1. **Sequential Process** (CLK-driven):
   - Initialization on start
   - State register updates
   - Iteration counting
   - Done signal generation

2. **Combinational Process**:
   - CORDIC rotation logic
   - Shift operations (via shift_right)
   - Angle selection
   - Direction determination (sign of z)

### Resource Utilization
- **Registers**: 3×16-bit state + iteration counter + flags ≈ 52 bits
- **Combinational Logic**: Shift-and-add hardware ≈ 100-150 LUTs
- **Memory**: 16×16-bit LUT for angles ≈ 256 bits
- **Multipliers**: ZERO (key CORDIC advantage!)

## Strengths
✓ Simple, monolithic design - easy to understand
✓ Minimal resource usage
✓ Accurate sine/cosine computation
✓ Works correctly in FPGA synthesis
✓ Includes proper done signal for synchronization

## Limitations
✗ All logic in single entity - hard to test components separately
✗ Limited configurability (hardcoded 16 iterations/width)
✗ No ready/valid handshake - can't queue inputs
✗ Sequential iteration only - lower throughput

## Next Step
→ See [Iteration 1](../iteration_1/README.md) for component modularization

## References
- CORDIC algorithm: [https://en.wikipedia.org/wiki/CORDIC](https://en.wikipedia.org/wiki/CORDIC)
- Fixed-point arithmetic: IEEE 754 alternatives for FPGA
- VHDL shift_right: IEEE.NUMERIC_STD package
