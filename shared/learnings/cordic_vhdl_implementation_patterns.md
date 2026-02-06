# CORDIC VHDL Implementation Patterns

**Date**: November 2025
**Based on**: CORDIC sine/cosine module implementation
**Focus**: Practical VHDL patterns, single-file architecture, signal organization

---

## Overview

The CORDIC sine/cosine module demonstrates effective VHDL patterns for implementing iterative algorithms without multipliers. Key lessons focus on structuring complex logic in a single file while maintaining clarity.

---

## Pattern 1: Single-File Architecture with Integrated Components

### Problem
Large designs split across multiple files can be difficult to manage. When is single-file appropriate?

### Solution
For algorithmic modules with 3-4 logical components, integrate into one file with clear section boundaries.

### Implementation in CORDIC

```vhdl
architecture RTL of cordic_sin is
    -- ========================================================================
    -- CONSTANTS (LUT - Logical Component 1)
    -- ========================================================================
    constant ANGLE_TABLE : angle_array := (...);
    constant K_CONSTANT : signed(...) := (...);

    -- ========================================================================
    -- TYPE DEFINITIONS (FSM - Logical Component 2)
    -- ========================================================================
    type state_type is (IDLE, COMPUTING, OUTPUT_VALID);

    -- ========================================================================
    -- SIGNALS: Control (FSM - Logical Component 2)
    -- ========================================================================
    signal current_state, next_state : state_type;
    signal iteration_count : integer range 0 to ITERATIONS;

    -- ========================================================================
    -- SIGNALS: Data Path (Rotation Logic - Logical Component 3)
    -- ========================================================================
    signal x_reg, y_reg, z_reg : signed(DATA_WIDTH-1 downto 0);
    signal x_next, y_next, z_next : signed(DATA_WIDTH-1 downto 0);

    -- ========================================================================
    -- SIGNALS: Output Control (Handshake - Logical Component 4)
    -- ========================================================================
    signal done_sig : std_logic;
    signal ready_sig : std_logic;

begin
    -- Process organized by component, not by type
    -- Control FSM (2 processes)
    -- Datapath (1 process)
    -- Output logic (2 processes)
end RTL;
```

### Benefits
✓ **Clarity**: Components visually separated with comment headers
✓ **Simplicity**: No component instantiation overhead
✓ **Debuggability**: All logic in one place, easy to trace
✓ **Maintainability**: Change one file, synthesize once

### When to Use
- Algorithmic kernels (FFT butterfly, matrix cell, etc.)
- Self-contained functions (sine, square root, etc.)
- Fixed-size operations (16-iteration CORDIC)

### When NOT to Use
- Large projects with multiple top-level modules
- Parameterized designs with many variants
- Highly reusable IP that goes into multiple projects

---

## Pattern 2: Constant-Based Lookup Tables

### Problem
VHDL can struggle with lookup tables in arrays. How to implement efficient LUTs?

### Solution
Use pre-computed constants in constant arrays, indexed combinationally.

### CORDIC Implementation

```vhdl
-- Define as constant array (synthesizes to distributed RAM/LUT)
constant ANGLE_TABLE : angle_array := (
    to_signed(16#3243#, DATA_WIDTH),  -- arctan(1)
    to_signed(16#1DAC#, DATA_WIDTH),  -- arctan(0.5)
    -- ... more values ...
    to_signed(16#0000#, DATA_WIDTH)   -- negligible
);

-- Access combinationally
architecture RTL of cordic_sin is
    signal current_angle : signed(DATA_WIDTH-1 downto 0);
begin
    -- Combinational lookup
    current_angle <= ANGLE_TABLE(iteration_count)
                    when iteration_count < ITERATIONS
                    else (others => '0');
end RTL;
```

### Hardware Result
- Synthesizes to LUT-based distributed RAM
- Zero additional delay vs. registered lookup
- ~256 bits = ~16 LUTs (negligible)
- No multiplier resources needed

### Key Insight
Use conditional assignment for bounds checking:
```vhdl
-- Protects against index out of bounds
signal <= ARRAY(index) when index < ARRAY'length else default_value;
```

### Benefits
✓ **Efficient**: Compiled into LUT hardware
✓ **Clear**: Constant values visible in code
✓ **Maintainable**: Easy to verify accuracy
✓ **Synthesizable**: Works with all tools

---

## Pattern 3: FSM with Combinational State Logic

### Problem
FSMs often have complex state transitions. How to keep them readable?

### Solution
Separate into sequential (state register) and combinational (next state + output logic) processes.

### CORDIC FSM Structure

```vhdl
-- Process 1: Sequential (state register update)
process(clk, reset) is
begin
    if reset = '1' then
        current_state <= IDLE;
        iteration_count <= 0;
    elsif rising_edge(clk) then
        current_state <= next_state;
        -- Update counters
        if current_state = COMPUTING then
            iteration_count <= iteration_count + 1;
        else
            iteration_count <= 0;
        end if;
    end if;
end process;

-- Process 2: Combinational (next state logic)
process(current_state, start, iteration_count) is
begin
    case current_state is
        when IDLE =>
            if start = '1' then
                next_state <= COMPUTING;
            else
                next_state <= IDLE;
            end if;
        when COMPUTING =>
            if iteration_count = ITERATIONS - 1 then
                next_state <= OUTPUT_VALID;
            else
                next_state <= COMPUTING;
            end if;
        when OUTPUT_VALID =>
            next_state <= IDLE;  -- or COMPUTING if start='1'
    end case;
end process;

-- Process 3: Combinational (output logic)
process(current_state) is
begin
    case current_state is
        when IDLE =>
            ready_sig <= '1';
            computing <= '0';
            done_sig <= '0';
        when COMPUTING =>
            ready_sig <= '0';
            computing <= '1';
            done_sig <= '0';
        when OUTPUT_VALID =>
            ready_sig <= '1';
            computing <= '0';
            done_sig <= '1';
    end case;
end process;
```

### Benefits
✓ **Readable**: Clear state transitions
✓ **Synthesizable**: Standard synthesis template
✓ **Debuggable**: Can trace state changes
✓ **Scalable**: Easy to add states

### Pattern for All FSMs
1. **Sequential process**: Update registers only
2. **Combinational process**: Compute next state
3. **Combinational process**: Compute outputs (alternative: use current_state)

---

## Pattern 4: Register Update with Multiplexing

### Problem
State registers need input during initialization, output from datapath during iteration. How to manage this?

### Solution
Use multiplexer logic controlled by FSM state.

### CORDIC Implementation

```vhdl
process(clk, reset) is
begin
    if reset = '1' then
        x_reg <= (others => '0');
        y_reg <= (others => '0');
        z_reg <= (others => '0');
    elsif rising_edge(clk) then
        -- Mux: initialization vs. iteration update
        if start = '1' and ready_sig = '1' then
            -- Initialization (handshake condition)
            x_reg <= K_CONSTANT;
            y_reg <= (others => '0');
            z_reg <= signed(angle_in);
        elsif computing = '1' then
            -- Iteration (datapath output)
            x_reg <= x_next;
            y_reg <= y_next;
            z_reg <= z_next;
        end if;
        -- Else: hold current value (implicit latch)
    end if;
end process;
```

### Hardware Implementation
- `x_reg <= (others => '0')` on reset
- `x_reg <= K_CONSTANT` on handshake
- `x_reg <= x_next` on iteration
- Otherwise holds value

### Key Insight
Use **conditional assignments** in sequential process:
```vhdl
if condition1 then
    output <= value1;
elsif condition2 then
    output <= value2;
end if;
-- Implicit else: hold (creates latch-free design)
```

### Benefits
✓ **Clear**: Conditions show when update happens
✓ **Latch-free**: No unwanted latches created
✓ **Efficient**: Direct mux logic

---

## Pattern 5: Combinational Datapath with Shift Operations

### Problem
CORDIC needs efficient shifts for every power of 2. How to implement?

### Solution
Use VHDL's `shift_right()` function—synthesizes directly to wiring.

### CORDIC Datapath

```vhdl
-- Datapath is fully combinational
process(x_reg, y_reg, z_reg, current_angle, iteration_count) is
    variable direction : std_logic;
    variable y_shifted, x_shifted : signed(DATA_WIDTH-1 downto 0);
begin
    -- Determine rotation direction
    direction := z_reg(z_reg'high);  -- MSB = sign bit

    -- Compute shifts
    if iteration_count <= 15 then
        y_shifted := shift_right(y_reg, iteration_count);  -- y >> i
        x_shifted := shift_right(x_reg, iteration_count);  -- x >> i
    else
        y_shifted := (others => '0');
        x_shifted := (others => '0');
    end if;

    -- Perform rotation (select add or subtract based on direction)
    if direction = '1' then
        x_next <= x_reg + y_shifted;
        y_next <= y_reg - x_shifted;
        z_next <= z_reg + current_angle;
    else
        x_next <= x_reg - y_shifted;
        y_next <= y_reg + x_shifted;
        z_next <= z_reg - current_angle;
    end if;
end process;
```

### Hardware Implementation
- `shift_right(signal, amount)` → Barrel shifter (wired, zero delay cost)
- Synthesizes to simple wire rearrangement
- No additional gates or delay

### Key Insight
Shifts are **free** in hardware:
```vhdl
y >> 0  →  No wiring change
y >> 1  →  Shift wires by 1
y >> 2  →  Shift wires by 2
-- All implemented as wiring, not arithmetic logic
```

### VHDL Shift Functions
- `shift_right(sig, n)` - Logical right shift, fill with 0s
- `shift_left(sig, n)` - Logical left shift, fill with 0s
- `rotate_right(sig, n)` - Circular rotation
- `rotate_left(sig, n)` - Circular rotation

### Benefits
✓ **Efficient**: Zero-cost in hardware
✓ **Clear**: Direct representation of algorithm
✓ **Portable**: Works in simulation and synthesis

---

## Pattern 6: Fixed-Point Arithmetic Organization

### Problem
Fixed-point calculations need careful precision management. How to organize?

### CORDIC Approach: Q1.15 Format

```vhdl
entity cordic_sin is
    Generic (
        ITERATIONS : integer := 16;    -- Precision control
        DATA_WIDTH : integer := 16     -- Q1.15 format
    );
    Port (
        angle_in : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        sin_out  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        -- ...
    );
end entity;

architecture RTL of cordic_sin is
    -- Pre-computed constant in Q1.15 format
    constant K_CONSTANT : signed(DATA_WIDTH-1 downto 0)
        := to_signed(19897, DATA_WIDTH);  -- 0.60725 in Q1.15

    -- Angle table in Q1.15 format
    constant ANGLE_TABLE : angle_array := (
        to_signed(16#3243#, DATA_WIDTH),  -- 0.7854 rad (π/4)
        -- ...
    );
begin
    -- All arithmetic stays in Q1.15 range [-1.0, +1.0]
    -- No overflow risk due to algorithm properties
end RTL;
```

### Key Points
- **Q1.15**: 1 sign bit + 15 fractional bits
- **Range**: -1.0 to +0.99997 (perfect for sin/cos)
- **Precision**: ~0.00003 per bit
- **Constants**: Pre-computed and hardcoded

### Benefits
✓ **Predictable**: Fixed-point range known
✓ **Overflow-safe**: Algorithm keeps values bounded
✓ **Efficient**: No conversion logic needed
✓ **Clear**: Format documented in generics

---

## Pattern 7: Signal Naming Conventions

### CORDIC Signal Organization

```vhdl
-- Data path signals (current and next)
signal x_reg, y_reg, z_reg : signed(...);      -- Current state
signal x_next, y_next, z_next : signed(...);   -- Next state

-- Control signals (action-oriented)
signal computing : std_logic;                   -- Currently computing
signal iteration_count : integer;               -- Current iteration

-- Handshake signals (direction-aware)
signal start : std_logic;  -- Input: user request
signal ready : std_logic;  -- Output: module ready
signal done : std_logic;   -- Output: result ready
signal valid : std_logic;  -- Output: result valid

-- Internal state
signal current_angle : signed(...);             -- From LUT
```

### Naming Pattern
- **`*_reg`**: Registered signals (state registers)
- **`*_next`**: Combinational outputs (next state)
- **`*_sig`**: Internal signals
- **Input/output suffix**: Removed in entity (direction clear from port)
- **Boolean signals**: Active-high (='1' means true)

### Benefits
✓ **Readable**: Naming shows intent
✓ **Clear**: Prefix indicates origin
✓ **Maintainable**: Consistent across files

---

## Pattern 8: Generics for Configurability

### CORDIC Customization via Generics

```vhdl
entity cordic_sin is
    Generic (
        ITERATIONS : integer := 16;    -- Accuracy control
        DATA_WIDTH : integer := 16     -- Precision control
    );
    Port ( ... );
end entity;
```

### Why Generics?

| Generic | Use Case | Trade-off |
|---------|----------|-----------|
| **ITERATIONS** | Higher = more accurate | Longer latency, more area |
| **DATA_WIDTH** | Wider = higher precision | More area, slower clock |

### Example: Different Precisions

```vhdl
-- Standard: 16-bit, 16 iterations
u1: entity work.cordic_sin
    generic map (ITERATIONS => 16, DATA_WIDTH => 16)

-- High precision: 32-bit, 32 iterations
u2: entity work.cordic_sin
    generic map (ITERATIONS => 32, DATA_WIDTH => 32)

-- Low precision: 8-bit, 8 iterations (fast, small)
u3: entity work.cordic_sin
    generic map (ITERATIONS => 8, DATA_WIDTH => 8)
```

### Benefits
✓ **Flexible**: Reuse same entity for multiple needs
✓ **Clear**: Parameters visible at instantiation
✓ **Maintainable**: Change once, use everywhere

---

## Best Practices Summary

| Practice | Benefit | Implementation |
|----------|---------|-----------------|
| Single-file architecture | Clarity, simplicity | Clear section comments |
| Constant LUTs | Efficiency | Pre-computed arrays |
| FSM with 3 processes | Readability | Separate state, next, output |
| Shift operations | Zero-cost | shift_right(), shift_left() |
| Fixed-point bounds | Overflow-safe | Documented format (Q1.15) |
| Signal naming | Clarity | Consistent suffixes |
| Generics | Reusability | Data width, iteration count |

---

## Lessons for Other Projects

### Apply These Patterns When:
1. **Implementing iterative algorithms** (FFT, Newton-Raphson, Cholesky)
2. **Building DSP modules** (filters, transforms, etc.)
3. **Designing FSM-based controllers** (handshake, bus interfaces)
4. **Working with fixed-point math** (signal processing, embedded systems)

### Adapt for Your Needs:
- Single-file: Keep for small modules (<500 lines)
- Multi-file: Split at 1000+ lines or multiple top-level entities
- Generics: Add for configurable precision/iterations
- Naming: Adjust to match project conventions

---

## References

- VHDL Shift Operations: IEEE 1076-2019 standard
- Fixed-Point Arithmetic: See `cordic_vhdl_implementation_patterns.md`
- FSM Design: See `cordic_fsm_handshake_design.md`
- Algorithm Details: See `CORDIC_ALGORITHM_GUIDE.md`
