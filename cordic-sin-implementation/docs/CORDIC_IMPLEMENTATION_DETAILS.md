# CORDIC Implementation Details

## Architecture Overview

The CORDIC module is implemented as a single VHDL file (`cordic_sin_module.vhd`) containing integrated components:

```
┌─────────────────────────────────────────────────┐
│          cordic_sin Entity (RTL Architecture)   │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │ LUT: Lookup Table (Combinational)        │  │
│  │ • Angle lookup: arctan(2^-i)             │  │
│  │ • 16 pre-computed values in ROM         │  │
│  │ • Zero area cost (LUT-based)            │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │ CONTROL: FSM (Synchronous)               │  │
│  │ • 3 states: IDLE, COMPUTING, OUTPUT_VALID│  │
│  │ • Iteration counter (0 to 15)            │  │
│  │ • Ready/Valid signal generation         │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │ DATAPATH: Rotation Logic (Combinational) │  │
│  │ • Sign detection (z[MSB])                │  │
│  │ • Shift operations (2^-i)                │  │
│  │ • Add/subtract logic                    │  │
│  │ • Produces x_next, y_next, z_next       │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │ STATE REGISTERS (Synchronous)            │  │
│  │ • x_reg, y_reg, z_reg (16-bit)          │  │
│  │ • Load from inputs or datapath output    │  │
│  │ • Updated on clock edge                 │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Module Signals

### Clock & Reset

```vhdl
clk   : in  std_logic;     -- System clock (rising edge triggered)
reset : in  std_logic;     -- Synchronous reset (active high)
```

### Input Handshake (Ready/Request Protocol)

```vhdl
start : in  std_logic;     -- Request from user (1-cycle pulse)
ready : out std_logic;     -- Grant from module (high when ready)
```

When both `start='1'` AND `ready='1'` at rising clock edge:
- Input angle is latched into z_reg
- Module enters COMPUTING state
- Ready signal drops until computation complete

### Input Data

```vhdl
angle_in : in std_logic_vector(15 downto 0);   -- Input angle [Q1.15 format]
```

**Format Explanation:**
- Fixed-point Q1.15 format
- Range: -1.0 to +0.99997
- User conversion: `fixed = angle_in_radians * 2^15`
- Example: π/4 ≈ 0.785398 rad → 25736 decimal → 0x6488 hex

### Output Handshake

```vhdl
done  : out std_logic;     -- Output ready (1-cycle pulse)
valid : out std_logic;     -- Same as done (output valid)
```

Both signals pulse for exactly 1 clock cycle when results are ready.

### Output Data

```vhdl
sin_out : out std_logic_vector(15 downto 0);   -- sin(angle) [Q1.15]
cos_out : out std_logic_vector(15 downto 0);   -- cos(angle) [Q1.15]
```

**Format:** Q1.15 (same as input)
- Range: -1.0 to +0.99997
- User conversion: `real_result = sin_out / 2^15`

## FSM State Machine

### States

```
┌────────────────────────────────────────────┐
│ State: IDLE                                │
│ • ready = '1'                              │
│ • computing = '0'                          │
│ • done = '0', valid = '0'                  │
│ Transition: start='1' → COMPUTING          │
└────────────────────────────────────────────┘
           │
           │ start='1'
           ↓
┌────────────────────────────────────────────┐
│ State: COMPUTING                           │
│ • ready = '0'  (not accepting new input)   │
│ • computing = '1'                          │
│ • done = '0', valid = '0'                  │
│ Action: Increment iteration_count each cy  │
│ Transition: iter==15 → OUTPUT_VALID        │
└────────────────────────────────────────────┘
           │
           │ iteration_count == 15
           ↓
┌────────────────────────────────────────────┐
│ State: OUTPUT_VALID (1 cycle only!)        │
│ • ready = '1'  (accepting new input!)      │
│ • computing = '0'                          │
│ • done = '1', valid = '1' (1-cycle pulse)  │
│ • Results available on sin_out/cos_out     │
│ Transition: Always → IDLE (or COMPUTING)   │
└────────────────────────────────────────────┘
           │
           ├─→ start='0' → IDLE
           └─→ start='1' → COMPUTING (immediately)
```

### FSM Implementation

**Sequential Process (State Update):**
```vhdl
process(clk, reset)
  if reset = '1' then
    current_state <= IDLE;
  elsif rising_edge(clk) then
    current_state <= next_state;
    -- Also update iteration_count
  end if;
end process;
```

**Combinational Process (Next State Logic):**
```vhdl
process(current_state, start, iteration_count)
  case current_state is
    when IDLE =>
      if start = '1' then
        next_state <= COMPUTING;
      else
        next_state <= IDLE;
      end if;
    when COMPUTING =>
      if iteration_count = ITERATIONS-1 then
        next_state <= OUTPUT_VALID;
      else
        next_state <= COMPUTING;
      end if;
    when OUTPUT_VALID =>
      if start = '1' then
        next_state <= COMPUTING;  -- Can restart immediately
      else
        next_state <= IDLE;
      end if;
  end case;
end process;
```

**Output Logic (Combinational):**
```vhdl
case current_state is
  when IDLE =>
    ready <= '1';
    computing <= '0';
    done <= '0';
    valid <= '0';
  when COMPUTING =>
    ready <= '0';
    computing <= '1';
    done <= '0';
    valid <= '0';
  when OUTPUT_VALID =>
    ready <= '1';
    computing <= '0';
    done <= '1';
    valid <= '1';
end case;
```

## Lookup Table (LUT)

### Storage

```vhdl
constant ANGLE_TABLE : angle_array := (
  to_signed(16#3243#, 16),  -- i=0:  arctan(1)      = 0.7854 rad
  to_signed(16#1DAC#, 16),  -- i=1:  arctan(0.5)    = 0.4636 rad
  to_signed(16#0FAD#, 16),  -- i=2:  arctan(0.25)   = 0.2450 rad
  ...
  to_signed(16#0000#, 16)   -- i=15: Zero (no effect)
);
```

### Access

```vhdl
-- Combinational lookup (instantaneous access)
current_angle <= ANGLE_TABLE(iteration_count)
                when iteration_count < ITERATIONS
                else (others => '0');
```

### Synthesis

- Stored in distributed RAM (LUT on FPGA)
- Zero additional multiplier resources
- Negligible area impact (~256 bits ≈ 16 LUTs)

## Datapath: CORDIC Rotation Logic

### Direction Detection

```vhdl
-- Signed arithmetic: MSB is sign bit
-- z < 0: MSB = '1'
-- z >= 0: MSB = '0'
direction := z_reg(z_reg'high);  -- '1' = rotate CCW, '0' = rotate CW
```

### Shift Operations

```vhdl
if iteration_count <= 15 then
  y_shifted := shift_right(y_reg, iteration_count);  -- y >> i
  x_shifted := shift_right(x_reg, iteration_count);  -- x >> i
else
  y_shifted := (others => '0');
  x_shifted := (others => '0');
end if;
```

**Hardware:** Barrel shifter (wired, zero additional delay beyond LUT)

### Rotation Logic

```vhdl
if direction = '1' then
  -- z < 0: Rotate counterclockwise (add angle)
  x_next <= x_reg + y_shifted;           -- x += y>>i
  y_next <= y_reg - x_shifted;           -- y -= x>>i
  z_next <= z_reg + current_angle;       -- z += angle[i]
else
  -- z >= 0: Rotate clockwise (subtract angle)
  x_next <= x_reg - y_shifted;           -- x -= y>>i
  y_next <= y_reg + x_shifted;           -- y += x>>i
  z_next <= z_reg - current_angle;       -- z -= angle[i]
end if;
```

**Hardware:** 3 adder/subtractors (could be reduced to 2 with careful design)

## State Registers

### Initialization

When `start='1' AND ready='1'`:
```vhdl
x_reg <= K_CONSTANT;           -- 19897 in decimal (0x4DBA)
y_reg <= (others => '0');      -- Zero
z_reg <= signed(angle_in);     -- Input angle in Q1.15
```

**Timing:**
- K_CONSTANT is a pre-computed constant
- Zero has no computation
- angle_in is directly assigned
- All assignments happen on rising clock edge

### Iteration Updates

When `computing='1'`:
```vhdl
x_reg <= x_next;
y_reg <= y_next;
z_reg <= z_next;
```

These values come from the datapath (combination of current state and angle table lookup).

### Output Assignment

```vhdl
sin_out <= std_logic_vector(y_reg);
cos_out <= std_logic_vector(x_reg);
```

Combinational assignment (no delay).

## Timing Details

### Clock-to-Clock Timing

```
Cycle N:
  Rising edge: State updated, registers loaded
  LUT lookup begins combinationally
  Datapath evaluates combinationally

Cycle N+1:
  Results from cycle N available at x_reg, y_reg, z_reg
  Datapath evaluates new rotation
  New results ready at cycle N+2
```

### Critical Path

```
Clock → Mux (init vs. datapath) → Adder → Register setup
         ├─ Datapath critical path
         │   Shift → Adder → Register
         │   Estimated: 4-5 ns
         └─ Total: ~5 ns on 7-series
```

## Generics & Customization

### ITERATIONS

```vhdl
Generic (ITERATIONS : integer := 16)
```

**Impact of changing:**
- N=8:  Reduces latency, lower accuracy (±0.006)
- N=16: Balanced accuracy (±0.0015)
- N=32: Higher accuracy (±0.000002), doubles latency

### DATA_WIDTH

```vhdl
Generic (DATA_WIDTH : integer := 16)
```

**Impact of changing:**
- 16: Standard (current)
- 32: Q31.32 format, much higher precision
- 8:  Very limited (not recommended)

## Reset Behavior

### On Reset ('1')

```vhdl
x_reg <= (others => '0');
y_reg <= (others => '0');
z_reg <= (others => '0');
current_state <= IDLE;
iteration_count <= 0;
```

All state cleared, ready for operation.

### After Reset ('0')

```
Cycle 0: reset='0' asserted
Cycle 1: FSM in IDLE, ready='1'
```

Module ready for first operation 1 cycle after reset deassertion.

## Synthesis Considerations

### VHDL Constructs Used

- ✓ `shift_right()` - Synthesizes to barrel shifter (zero delay cost)
- ✓ `to_signed()` - Implicit type conversion (free)
- ✓ Named constant literals - Optimized in synthesis
- ✓ Synchronous FSM - Standard template (synthesis-friendly)
- ✓ Rising edge detection - No special handling needed

### Vendor-Specific Optimizations

**Xilinx:**
- Shift operations map to LUT cascades
- Adders use CARRY propagation chains
- DSP slices: None needed (good!)

**Altera/Intel:**
- Similar LUT-based shifters
- ALM blocks for arithmetic
- No special optimizations needed

## Simulation vs. Synthesis

### Simulation Considerations

The VHDL uses standard constructs compatible with:
- ✓ GHDL (open-source)
- ✓ Vivado XSim
- ✓ ModelSim/QuestaSim
- ✓ IUS/VCS

No vendor-specific directives needed.

### Synthesis Considerations

The design is synthesis-clean:
- ✓ No latches (all clocked logic)
- ✓ No race conditions
- ✓ No combinational loops
- ✓ Deterministic behavior

Recommended synthesis settings:
- Optimization: Balanced (area/speed)
- Retiming: Enabled (may improve frequency)
- FSM encoding: Auto (tool decides)

## Verification & Testing

### Unit Test Points

Within the module, testable signals:
- `current_state` - FSM state (test via output behavior)
- `iteration_count` - Iteration number (implicit test)
- `x_reg, y_reg, z_reg` - State values (check via outputs)
- `computing` - Computation in progress (verify timing)
- `ready` - Ready signal timing (verify handshake)

### Interface Test Points

External testable signals:
- `ready` - Asserted in IDLE/OUTPUT_VALID
- `done` - 1-cycle pulse
- `sin_out, cos_out` - Valid when done='1'

## Scalability

### For Different Precisions

**Lower Precision (±0.01 error):**
- Use ITERATIONS=8
- Reduces latency to 9 cycles
- Same area

**Higher Precision (±0.0001):**
- Use ITERATIONS=24
- Increases latency to 25 cycles
- Minimal area increase

### For Different Data Widths

**32-bit Fixed-Point:**
- Change DATA_WIDTH to 32
- Use Q31.32 format for ~2×10^-10 precision
- ~2× area increase
- Same latency (still 16-17 cycles per ITERATIONS)

## Power & Thermal

### Dynamic Power

Power mainly from:
1. **State registers** - 48 bits switching every cycle
2. **Shifters** - Switching proportional to shifts
3. **Adders** - Switching on arithmetic results

Optimization: Gating unused shifts (advanced)

### Low-Power Operation

- Can clock-gate when ready='1' and start='0'
- Or reduce clock frequency (power ∝ f)
- Or use lower voltage if timing permits

## Document References

Related documents:
- `CORDIC_ALGORITHM_GUIDE.md` - Mathematical foundation
- `CORDIC_PERFORMANCE_ANALYSIS.md` - Timing/throughput
- `CORDIC_HANDSHAKE_PROTOCOL.md` - Interface spec
