# VHDL Style Guide

Best practices for VHDL code generation and modification during iteration.

## Core Principles

1. **Preserve original style** - Don't reformat unless necessary
2. **Add comments** - Explain what was changed and why
3. **Minimal changes** - Fix only what's broken
4. **Maintain readability** - Code should be human-maintainable

## Naming Conventions

### Signals and Variables
```vhdl
-- Good: Descriptive lowercase with underscores
signal data_valid : std_logic;
signal byte_count : integer range 0 to 255;

-- Avoid: Camel case, single letters (except counters)
signal DataValid : std_logic;  -- Avoid
signal d : std_logic;  -- Avoid (unless loop counter)
```

### Constants
```vhdl
-- Good: Uppercase with underscores
constant DATA_WIDTH : integer := 32;
constant FIFO_DEPTH : integer := 256;

-- Acceptable: Use 'C_' prefix for clarity
constant C_MAX_COUNT : integer := 1000;
```

### Entities and Components
```vhdl
-- Good: Lowercase with underscores
entity uart_transmitter is
  ...
end entity uart_transmitter;

-- Acceptable: No underscores if short
entity fifo is
  ...
end entity fifo;
```

## Code Organization

### File Header (Always Preserve)
```vhdl
--------------------------------------------------------------------------------
-- Module: uart_tx
-- Description: UART transmitter with configurable baud rate
-- Author: Original Author Name
-- Date: 2025-01-15
-- Modified: 2025-11-21 by Claude (Added reset logic)
--------------------------------------------------------------------------------
```

### Entity Declaration
```vhdl
entity module_name is
  generic (
    G_DATA_WIDTH : integer := 8;  -- Use G_ prefix for generics
    G_CLOCK_FREQ : integer := 50_000_000
  );
  port (
    -- Clock and reset
    clk       : in  std_logic;
    rst       : in  std_logic;
    
    -- Input signals
    data_in   : in  std_logic_vector(G_DATA_WIDTH-1 downto 0);
    valid_in  : in  std_logic;
    
    -- Output signals
    data_out  : out std_logic_vector(G_DATA_WIDTH-1 downto 0);
    ready_out : out std_logic
  );
end entity module_name;
```

### Architecture Organization
```vhdl
architecture rtl of module_name is
  
  -- Component declarations
  component submodule is
    ...
  end component submodule;
  
  -- Type declarations
  type state_type is (IDLE, ACTIVE, DONE);
  
  -- Constants
  constant C_COUNTER_MAX : integer := 100;
  
  -- Signals (group by function)
  signal state      : state_type;
  signal next_state : state_type;
  
  signal counter    : integer range 0 to C_COUNTER_MAX;
  
  signal data_reg   : std_logic_vector(7 downto 0);
  signal valid_reg  : std_logic;
  
begin
  
  -- Instantiations
  
  -- Combinational processes
  
  -- Sequential processes
  
end architecture rtl;
```

## Process Coding

### Synchronous Reset (Preferred)
```vhdl
process(clk)
begin
  if rising_edge(clk) then
    if rst = '1' then
      -- Reset values
      counter <= 0;
      state <= IDLE;
    else
      -- Normal operation
      counter <= counter + 1;
    end if;
  end if;
end process;
```

### Asynchronous Reset (When Required)
```vhdl
process(clk, rst)
begin
  if rst = '1' then
    -- Reset values
    counter <= 0;
    state <= IDLE;
  elsif rising_edge(clk) then
    -- Normal operation
    counter <= counter + 1;
  end if;
end process;
```

### Combinational Process (VHDL-2008 preferred)
```vhdl
-- VHDL-2008: Use process(all)
process(all)
begin
  next_state <= state;
  
  case state is
    when IDLE =>
      if start = '1' then
        next_state <= ACTIVE;
      end if;
    
    when ACTIVE =>
      if done = '1' then
        next_state <= IDLE;
      end if;
  end case;
end process;

-- VHDL-93: Explicit sensitivity list
process(state, start, done)
begin
  ...
end process;
```

## Common Patterns

### FSM (Two-Process Style)
```vhdl
-- State register
process(clk)
begin
  if rising_edge(clk) then
    if rst = '1' then
      state <= IDLE;
    else
      state <= next_state;
    end if;
  end if;
end process;

-- Next state logic
process(all)
begin
  next_state <= state;
  
  case state is
    when IDLE =>
      if start = '1' then
        next_state <= ACTIVE;
      end if;
    
    when ACTIVE =>
      if done = '1' then
        next_state <= IDLE;
      end if;
  end case;
end process;

-- Output logic (if needed)
ready <= '1' when state = IDLE else '0';
```

### Counter with Enable
```vhdl
process(clk)
begin
  if rising_edge(clk) then
    if rst = '1' then
      counter <= 0;
    elsif enable = '1' then
      if counter = MAX_COUNT then
        counter <= 0;
      else
        counter <= counter + 1;
      end if;
    end if;
  end if;
end process;
```

### Shift Register
```vhdl
process(clk)
begin
  if rising_edge(clk) then
    if rst = '1' then
      shift_reg <= (others => '0');
    elsif shift_enable = '1' then
      shift_reg <= shift_reg(shift_reg'high-1 downto 0) & data_in;
    end if;
  end if;
end process;
```

## Comments

### When to Comment
```vhdl
-- ✅ Good: Explain non-obvious logic
-- Calculate CRC using polynomial 0x1021
crc_next <= crc_current xor polynomial when data_bit = '1' else crc_current;

-- ✅ Good: Document changes during iteration
-- Fixed: Added reset condition (Iteration 3)
if rst = '1' then
  counter <= 0;
end if;

-- ❌ Avoid: Stating the obvious
counter <= counter + 1;  -- Increment counter (obvious)
```

### Iteration Change Comments
```vhdl
-- MODIFIED: Iteration 5 - Added synchronous reset
-- Previous version had asynchronous reset causing timing issues
process(clk)
begin
  if rising_edge(clk) then
    if rst = '1' then  -- Changed from async to sync reset
      data_reg <= (others => '0');
    else
      data_reg <= data_in;
    end if;
  end if;
end process;
```

## Type Usage

### Prefer Explicit Types
```vhdl
-- Good: Clear intent
signal address : unsigned(15 downto 0);
signal data : std_logic_vector(7 downto 0);

-- Avoid: Ambiguous types
signal address : integer;  -- Range unclear
```

### Use Subtypes for Ranges
```vhdl
subtype byte_t is std_logic_vector(7 downto 0);
subtype counter_t is integer range 0 to 255;

signal data : byte_t;
signal count : counter_t;
```

### Type Conversions
```vhdl
-- Unsigned to std_logic_vector
data_out <= std_logic_vector(unsigned_value);

-- Integer to unsigned
count_unsigned <= to_unsigned(count_int, 8);

-- std_logic to integer (with safety check)
if enable = '1' then
  count_int <= 1;
else
  count_int <= 0;
end if;
```

## Signal vs Variable

### Use Signals (Default)
```vhdl
-- Signals for registers and connections
process(clk)
begin
  if rising_edge(clk) then
    data_reg <= data_in;
  end if;
end process;
```

### Use Variables (For Intermediate Values)
```vhdl
-- Variables for calculations within process
process(clk)
  variable temp : integer;
begin
  if rising_edge(clk) then
    temp := a + b;  -- Immediate assignment
    result <= temp * c;
  end if;
end process;
```

## Avoiding Common Issues

### Multiple Drivers
```vhdl
-- ❌ Bad: Multiple drivers
process(clk)
begin
  output <= '0';  -- Driver 1
end process;

process(rst)
begin
  output <= '1';  -- Driver 2 - ERROR
end process;

-- ✅ Good: Single driver
process(clk, rst)
begin
  if rst = '1' then
    output <= '0';
  elsif rising_edge(clk) then
    output <= '1';
  end if;
end process;
```

### Incomplete Assignments
```vhdl
-- ❌ Bad: Latch inference
process(sel, data_a, data_b)
begin
  if sel = '1' then
    output <= data_a;
  -- Missing else - creates latch
  end if;
end process;

-- ✅ Good: Complete assignments
process(sel, data_a, data_b)
begin
  if sel = '1' then
    output <= data_a;
  else
    output <= data_b;
  end if;
end process;

-- ✅ Also good: Default assignment
process(sel, data_a, data_b)
begin
  output <= data_b;  -- Default
  if sel = '1' then
    output <= data_a;
  end if;
end process;
```

### Clock Domain Crossing (Mark Clearly)
```vhdl
-- WARNING: Clock domain crossing
-- Signal 'enable' crosses from clk_a to clk_b domain
-- Synchronizer required
process(clk_b)
begin
  if rising_edge(clk_b) then
    enable_sync1 <= enable;  -- First stage
    enable_sync2 <= enable_sync1;  -- Second stage
    enable_clk_b <= enable_sync2;  -- Use this
  end if;
end process;
```

## Formatting

### Indentation
- Use 2 spaces per level
- Align port declarations
- Align assignment operators when logical

### Line Length
- Prefer < 100 characters
- Break long lines logically

### Spacing
```vhdl
-- Good spacing
signal data : std_logic_vector(7 downto 0);
if rst = '1' then
  counter <= 0;
elsif enable = '1' then
  counter <= counter + 1;
end if;
```

## Iteration-Specific Guidelines

### Preserve Original Code
```vhdl
-- When fixing errors, preserve original structure
-- Don't reformat working code

-- ❌ Don't do this:
-- Original:
signal data:std_logic_vector(7 downto 0);
if enable='1' then

-- Your "fix" (unnecessary reformatting):
signal data : std_logic_vector(7 downto 0);
if enable = '1' then

-- ✅ Do this:
-- Only fix the actual error, keep original formatting
```

### Document All Changes
```vhdl
-- Every change should have a comment explaining:
-- 1. What was changed
-- 2. Why it was changed
-- 3. What iteration it was in

-- Example:
-- FIXED: Iteration 3 - Added missing semicolon
-- ERROR was: "syntax error near signal"
signal data : std_logic_vector(7 downto 0);  -- <-- Added semicolon here
```

### Minimal Edits
```vhdl
-- Change only what's necessary to fix the error
-- Don't "improve" working code during iteration

-- ❌ Don't do this:
-- Original (working):
if enable = '1' then
  counter <= counter + 1;
end if;

-- Your "improvement" (unnecessary):
-- "Better" counter with rollover
if enable = '1' then
  if counter = MAX_COUNT then
    counter <= 0;
  else
    counter <= counter + 1;
  end if;
end if;

-- ✅ Do this:
-- Only fix actual errors, don't add features
```
