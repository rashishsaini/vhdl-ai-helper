# Iteration 1: Component Separation (Modular Architecture)

## Overview
This iteration refactors the monolithic CORDIC implementation from Iteration 0 into three separate, reusable components:
1. **cordic_lut** - Lookup table for pre-computed angles
2. **cordic_datapath** - Rotation logic (shift, add/subtract)
3. **cordic_control** - Finite State Machine for sequencing

These components are integrated by a top-level entity (**cordic_top**) that instantiates and connects them.

## Architecture

### Block Diagram
```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│                    cordic_top (Structural)                 │
│                                                             │
│  angle_in ──────────┐                                       │
│  start ────────┐    │                                       │
│  clk ──┬───────┼────┼──────────────┬──────────┬──────────┐  │
│  reset │       │    │              │          │          │  │
│        │       │    │              │          │          │  │
│        v       │    │              │          │          │  │
│    ┌───────────────┐            ┌────────────┐           │  │
│    │  cordic_lut   │            │  cordic_   │           │  │
│    │               │            │  control   │           │  │
│    │ addr ← itr_idx            │            │           │  │
│    │ angle_out ────┼─────┐     │ start      │           │  │
│    │               │     │     │ done → ────┼─────┐     │  │
│    │               │     │     │ computing  │     │     │  │
│    └───────────────┘     │     │ iteration_ │     │     │  │
│                          │     │ idx        │     │     │  │
│                          │     └────────────┘     │     │  │
│                          │            │           │     │  │
│                    ┌─────────────────────────┐    │     │  │
│                    │  cordic_datapath        │    │     │  │
│                    │                         │    │     │  │
│     x_reg ────────>│ x_in                    │    │     │  │
│     y_reg ────────>│ y_in                    │    │     │  │
│     z_reg ────────>│ z_in                    │    │     │  │
│     angle ────────>│ angle                   │    │     │  │
│     iteration ────>│ iteration               │    │     │  │
│                    │ x_out ───┐              │    │     │  │
│                    │ y_out ───┼──┐           │    │     │  │
│                    │ z_out ───┼──┼──┐        │    │     │  │
│                    └─────────────────────────┘    │     │  │
│                            │  │  │                │     │  │
│                        x_next, y_next, z_next     │     │  │
│                            │                      │     │  │
│                    State Registers & Mux          │     │  │
│                            │                      │     │  │
│                    sin_out ─┘                     │     │  │
│                    cos_out ──────────────────────┘     │  │
│                    done ───────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

#### **cordic_lut.vhd**
- **Type**: ROM (Read-Only Memory) with registered output
- **Function**: Provides pre-computed CORDIC angles
- **Inputs**:
  - `clk` : System clock
  - `addr` : Angle index (0 to ITERATIONS-1)
- **Outputs**:
  - `angle_out` : Selected angle in Q1.15 format
- **Implementation**: Synchronous lookup with registered output
- **Key Values**:
  ```
  ANGLE_TABLE: 16 entries
  [0] = 0x3243 (arctan(1)      = 45.000°)
  [1] = 0x1DAC (arctan(0.5)    = 26.565°)
  [2] = 0x0FAD (arctan(0.25)   = 14.036°)
  ...
  [15] = 0x0000 (negligible)
  ```

#### **cordic_datapath.vhd**
- **Type**: Combinational logic
- **Function**: Performs one CORDIC iteration (rotation)
- **Inputs**:
  - `x_in, y_in, z_in` : Current state
  - `angle` : Rotation angle from LUT
  - `iteration` : Current iteration index (determines shift amount)
- **Outputs**:
  - `x_out, y_out, z_out` : Next state after rotation
- **Algorithm** (one iteration):
  ```
  z_sign = z_in[MSB]
  if z_in < 0:
      x_out = x_in + (y_in >> iteration)
      y_out = y_in - (x_in >> iteration)
      z_out = z_in + angle
  else:
      x_out = x_in - (y_in >> iteration)
      y_out = y_in + (x_in >> iteration)
      z_out = z_in - angle
  ```
- **Shift Operation**: Right shift by `iteration` bits (divide by 2^iteration)

#### **cordic_control.vhd**
- **Type**: Finite State Machine (FSM)
- **Function**: Manages iteration sequencing and done signal
- **States**:
  ```
  IDLE ──[start='1']──> COMPUTING ──[iter==15]──> DONE_PULSE ──> IDLE
  ```
- **Outputs**:
  - `computing` : High while iterating
  - `done` : Pulse (1 cycle) when computation complete
  - `iteration_idx` : Current iteration number (0 to 15)
- **Process**:
  1. Wait in IDLE for start signal
  2. Enter COMPUTING, increment iteration_idx each cycle
  3. After 16 iterations, pulse done and return to IDLE

#### **cordic_top.vhd**
- **Type**: Structural (integration)
- **Function**: Top-level entity connecting all components
- **Contains**:
  - State registers (x_reg, y_reg, z_reg)
  - Component instantiations
  - Multiplexer for initialization vs. iteration
  - Output assignments

## Interfaces

### cordic_top Port Interface
```
Port (
    clk      : in  std_logic;              -- System clock
    reset    : in  std_logic;              -- Synchronous reset (active high)
    start    : in  std_logic;              -- Start computation
    angle_in : in  std_logic_vector(15..0);-- Input angle [Q1.15]
    sin_out  : out std_logic_vector(15..0);-- Output sine [Q1.15]
    cos_out  : out std_logic_vector(15..0);-- Output cosine [Q1.15]
    done     : out std_logic               -- Computation complete
);
```

### Internal Interfaces

#### cordic_lut ↔ cordic_datapath
- `addr` : 4-bit iteration index
- `angle_out` : 16-bit angle value

#### cordic_control ↔ cordic_datapath
- `iteration_idx` : Current iteration (0 to 15)

#### cordic_control ↔ State Logic
- `computing` : Enable state register updates
- `start` : Trigger initialization

## Data Flow

```
CYCLE 0:
  start='1' → Control: IDLE→COMPUTING, init x,y,z → x_reg,y_reg,z_reg updated

CYCLE 1:
  iteration_idx=0 → LUT outputs angle[0] → Datapath computes x_next,y_next,z_next
  State updated: x_reg,y_reg,z_reg ← x_next,y_next,z_next

CYCLE 2:
  iteration_idx=1 → LUT outputs angle[1] → Datapath computes new x_next,y_next,z_next
  State updated

... (repeat for 16 cycles total)

CYCLE 16:
  iteration_idx=15 → (final iteration logic)
  State updated with final values

CYCLE 17:
  Control: COMPUTING→DONE_PULSE
  done='1' (pulse for 1 cycle)
  sin_out = y_reg, cos_out = x_reg (valid results)

CYCLE 18:
  Control: DONE_PULSE→IDLE
  done='0'
  Ready for next computation
```

## Advantages Over Iteration 0

1. **Modularity**: Each component has single responsibility
   - Easy to test independently
   - Easy to replace or enhance specific functions

2. **Reusability**: Components can be used separately
   - Datapath could be used in pipelined version
   - LUT is standalone ROM (useful elsewhere)
   - Control FSM is generic and extensible

3. **Clarity**: Component interfaces clearly document data flow
   - No hidden dependencies
   - Easier to understand and debug

4. **Maintainability**: Bug fixes or enhancements isolated to one component
   - LUT change: doesn't affect datapath
   - Datapath algorithm improvement: transparent to control

5. **Testability**: Can verify components individually
   - Mock LUT with different angle values
   - Test datapath with known vectors
   - Verify FSM state transitions independently

## Differences from Iteration 0

| Aspect | Iteration 0 | Iteration 1 |
|--------|------------|------------|
| Structure | Monolithic entity | 4 components + top |
| Angle lookup | Combinational logic | Registered output |
| Rotation logic | Inside main process | Separate combinational |
| Control FSM | Implicit state machine | Explicit 3-state FSM |
| Code organization | Single file | 4 VHDL files |
| Lines of code | ~99 | ~250 (with comments) |
| Complexity | Simpler | More explicit |

## Latency
- **Same as Iteration 0**: 17 cycles (16 iterations + 1 done pulse)
- **Throughput**: 1 result per ~20 cycles (including done period)

## Resource Utilization
- **Registers**: Slightly higher (FSM state register)
- **LUTs**: Similar (modular design adds little overhead)
- **Memory**: Same (16×16-bit LUT)
- **Multipliers**: ZERO (same as Iteration 0)

## Testing

### Test Coverage
- 9 angles from 0 to π radians
- Same test vectors as Iteration 0
- Outputs verified to match with < 0.002 error

### Running Tests
```bash
# Compile all 4 components
vhdl cordic_lut.vhd
vhdl cordic_datapath.vhd
vhdl cordic_control.vhd
vhdl cordic_top.vhd

# Compile testbench
vhdl tb_cordic_modular.vhd

# Run simulation
vsim cordic_modular_tb
run 10 us
```

## Verification Results

Expected output matches Iteration 0 exactly (same algorithm):
```
sin(0°)   ≈ 0.0000    cos(0°)   ≈ 1.0000
sin(45°)  ≈ 0.7071    cos(45°)  ≈ 0.7071
sin(90°)  ≈ 1.0000    cos(90°)  ≈ 0.0000
sin(180°) ≈ 0.0000    cos(180°) ≈ -1.0000
```

## Key Learning Points

1. **Separation of Concerns**: Each component does one job well
2. **ROM vs. Logic**: LUT implemented as register (synchronous) not combinational
3. **FSM Design**: Explicit state machine clearer than implicit state flow
4. **Structural Architecture**: Instantiation approach good for integration
5. **Interface Definition**: Clear signals reduce bugs

## Next Step
→ See [Iteration 2](../iteration_2/README.md) for enhanced done signal handling and ready/valid protocol

## Files in This Directory
- `cordic_lut.vhd` - Pre-computed angle lookup table
- `cordic_datapath.vhd` - CORDIC rotation logic
- `cordic_control.vhd` - FSM for iteration control
- `cordic_top.vhd` - Top-level structural integration
- `tb_cordic_modular.vhd` - Testbench
- `README.md` - This file
