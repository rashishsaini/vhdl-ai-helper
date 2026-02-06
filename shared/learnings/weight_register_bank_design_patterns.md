# Weight Register Bank Design Patterns

A comprehensive guide to memory/register bank design patterns derived from the neural network weight storage implementation.

## Overview

The `weight_register_bank` module demonstrates best practices for:
- Parameterized register bank design
- Asynchronous read with synchronous write architecture
- Address validation and bounds checking
- Priority-based write port arbitration
- Q2.13 fixed-point weight storage for neural networks

---

## Key Design Patterns

### Pattern 1: Parameterized Generic Interface

**Problem:** Hard-coding dimensions limits reusability across different network topologies.

**Solution:** Use generics for all configurable parameters.

```vhdl
entity weight_register_bank is
    generic (
        DATA_WIDTH   : integer := 16;     -- Q2.13 format
        NUM_ENTRIES  : integer := 13;     -- Total weights + biases
        ADDR_WIDTH   : integer := 4       -- ceil(log2(NUM_ENTRIES))
    );
```

**Benefits:**
- Same module works for any layer size
- Easy to instantiate for different network configurations
- Compile-time configuration (no runtime overhead)

**Usage Example (4-2-1 Network):**
```
Layer 1: 8 weights (4 inputs x 2 neurons) + 2 biases = 10 values
Layer 2: 2 weights (2 inputs x 1 neuron)  + 1 bias   = 3 values
Total: 13 entries
```

---

### Pattern 2: Typed Port Declarations

**Problem:** Using `std_logic_vector` everywhere loses semantic meaning and allows type mismatches.

**Solution:** Use appropriate types from `numeric_std` for addresses and data.

```vhdl
-- Read Port (asynchronous/combinational)
rd_addr      : in  unsigned(ADDR_WIDTH-1 downto 0);
rd_data      : out signed(DATA_WIDTH-1 downto 0);

-- Write Port (synchronous)
wr_addr      : in  unsigned(ADDR_WIDTH-1 downto 0);
wr_data      : in  signed(DATA_WIDTH-1 downto 0);
```

**Key Points:**
- `unsigned` for addresses (always positive indices)
- `signed` for data (weights can be negative in neural networks)
- Enables compile-time type checking
- Makes intent clear in the code

---

### Pattern 3: Array Type with Aggregate Initialization

**Problem:** Individual signal initialization is verbose and error-prone.

**Solution:** Define array types and use aggregate initialization.

```vhdl
-- Type definition
type reg_array_t is array (0 to NUM_ENTRIES-1) of signed(DATA_WIDTH-1 downto 0);

-- Signal with aggregate initialization (all zeros)
signal registers : reg_array_t := (others => (others => '0'));
```

**Benefits:**
- Clean array access: `registers(index)`
- Automatic bounds checking in simulation
- Synthesizes to distributed RAM or registers based on size
- Consistent initialization across all elements

---

### Pattern 4: Address Validation with Bounded Integer Conversion

**Problem:** Out-of-bounds address access causes simulation errors or undefined behavior.

**Solution:** Validate addresses before conversion and clamp to valid range.

```vhdl
-- Internal signals with bounded range
signal rd_addr_int : integer range 0 to NUM_ENTRIES-1;

-- Safe conversion with clamping
rd_addr_int <= to_integer(rd_addr) when to_integer(rd_addr) < NUM_ENTRIES else 0;

-- Validity flag for downstream logic
rd_addr_valid <= '1' when to_integer(rd_addr) < NUM_ENTRIES else '0';
```

**Benefits:**
- Prevents array index out of bounds
- Provides validity signal for error handling
- Default to address 0 (safe fallback)
- Synthesizes efficiently (comparator + mux)

---

### Pattern 5: Priority-Based Write Arbitration

**Problem:** Multiple write sources can cause conflicts and race conditions.

**Solution:** Implement explicit priority ordering in synchronous write process.

```vhdl
process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' then
            -- Highest priority: Reset clears all
            registers <= (others => (others => '0'));
        elsif init_en = '1' and init_addr_valid = '1' then
            -- Second priority: Initialization (loading pre-trained weights)
            registers(init_addr_int) <= init_data;
        elsif wr_en = '1' and wr_addr_valid = '1' then
            -- Third priority: Normal write (training updates)
            registers(wr_addr_int) <= wr_data;
        end if;
    end if;
end process;
```

**Priority Order:**
1. `rst` - Reset clears everything
2. `init_en` - Weight initialization (batch loading)
3. `wr_en` - Normal training updates

**Benefits:**
- Deterministic behavior under all conditions
- Clear documentation of arbitration rules
- Safe operation during weight loading
- Single process avoids multiple driver issues

---

### Pattern 6: Asynchronous Read (Combinational)

**Problem:** Synchronous reads add latency and complicate pipeline timing.

**Solution:** Implement reads as pure combinational logic.

```vhdl
-- Combinational read - no clock dependency
rd_data <= registers(rd_addr_int) when (rd_en = '1' and rd_addr_valid = '1')
           else (others => '0');

rd_valid <= rd_en and rd_addr_valid;
```

**Benefits:**
- Zero-cycle read latency
- Simplifies neural network datapath timing
- Returns zero for invalid addresses (safe default)
- Read-during-write returns OLD value (read-first behavior)

**Trade-offs:**
- May increase critical path if register bank is large
- Consider registered read for timing closure if needed

---

### Pattern 7: Separate Init and Write Ports

**Problem:** Single write port complicates weight loading during initialization.

**Solution:** Dedicated initialization port with acknowledgment.

```vhdl
-- Initialization Port
init_en      : in  std_logic;
init_addr    : in  unsigned(ADDR_WIDTH-1 downto 0);
init_data    : in  signed(DATA_WIDTH-1 downto 0);
init_done    : out std_logic;

-- Simple acknowledgment
init_done <= init_en and init_addr_valid;
```

**Use Cases:**
- Loading pre-trained weights from host
- Batch weight updates from external memory
- Different timing requirements than normal writes

---

## Memory Map Design

For neural networks, organize the memory map by layer:

```
4-2-1 Network Memory Map:
--------------------------
Addr 0-7:   Layer 1 weights [w00, w01, w02, w03, w10, w11, w12, w13]
Addr 8-9:   Layer 1 biases  [b0, b1]
Addr 10-11: Layer 2 weights [w20, w21]
Addr 12:    Layer 2 bias    [b2]
```

**Benefits:**
- Sequential access patterns for each layer
- Easy to calculate offsets for different layers
- Clear mapping between network topology and addresses

---

## Testbench Patterns

### Self-Checking Procedures

```vhdl
procedure check_value(
    addr          : integer;
    expected      : integer;
    test_name     : string
) is
begin
    rd_en <= '1';
    rd_addr <= to_unsigned(addr, ADDR_WIDTH);
    wait for CLK_PERIOD;

    if to_integer(rd_data) = expected and rd_valid = '1' then
        report "PASS: " & test_name severity note;
        pass_count <= pass_count + 1;
    else
        report "FAIL: " & test_name severity error;
        fail_count <= fail_count + 1;
    end if;

    rd_en <= '0';
    test_count <= test_count + 1;
end procedure;
```

### Test Categories to Cover

1. **Reset Behavior** - All registers zero after reset
2. **Basic Write/Read** - Write then read back
3. **Initialization Port** - Init overrides normal values
4. **Negative Values** - Signed arithmetic correctness
5. **Boundary Values** - Max/min representable values
6. **Invalid Addresses** - Out-of-range handling
7. **Reset Clears Values** - Post-operation reset
8. **Typical NN Pattern** - Realistic weight patterns

---

## Performance Characteristics

| Metric | Value | Notes |
|--------|-------|-------|
| Read Latency | 0 cycles | Combinational |
| Write Latency | 1 cycle | Registered |
| Read Throughput | 1/cycle | Single port |
| Write Throughput | 1/cycle | Single port |
| Resources (13 entries) | ~208 FFs | 13 x 16-bit |

---

## Fixed-Point Considerations

For Q2.13 format (16-bit weights):
- Range: approximately [-4.0, +4.0)
- Resolution: ~0.000122 (1/8192)
- Typical initialized weights: ~[-0.5, +0.5]

**Common Q2.13 Values:**
```vhdl
-- Key constants
8192   -- +1.0
-8192  -- -1.0
4096   -- +0.5
-4096  -- -0.5
32767  -- Max positive (~3.99988)
-32768 -- Min negative (-4.0)
```

---

## Synthesis Results

When synthesized for Xilinx 7-series:

- Infers distributed RAM for small sizes (< 64 entries)
- Block RAM for larger sizes
- Address validation uses single LUT per address bit
- Priority logic minimal (2-3 LUTs)

---

## Key Takeaways

1. **Use Generics** - Parameterize everything configurable
2. **Type Your Ports** - Use `signed`/`unsigned` not just `std_logic_vector`
3. **Validate Addresses** - Always check bounds before array access
4. **Document Priority** - Clear write arbitration rules
5. **Combinational Reads** - Zero latency for neural network datapaths
6. **Comprehensive Testing** - Cover all edge cases including negative values
7. **Memory Map Documentation** - Clear address assignment for maintainability

---

## Related Documents

- `sigmoid_unit_design_patterns.md` - Activation function patterns
- `reciprocal_division_overflow_fixes.md` - Fixed-point overflow handling
- `COMPREHENSIVE_VHDL_XSIM_REFERENCE.md` - General VHDL reference

---

**Last Updated:** November 26, 2024
**Source:** Neuron project weight_register_bank.vhd analysis
**Status:** Complete - All tests passing
