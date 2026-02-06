# Input Buffer Design Patterns

**Source Module:** `input_buffer.vhd`
**Project:** Neuron (4-2-1 Neural Network)
**Date:** November 26, 2024
**Complexity:** EASY

---

## Overview

The input buffer module demonstrates several clean VHDL design patterns for implementing a simple register bank with load tracking. These patterns are applicable to many buffering and storage scenarios.

---

## Pattern 1: Bitmask Load Tracking

**Problem:** Need to track which addresses have been written in any order.

**Solution:** Use a bitmask (`std_logic_vector`) where each bit represents an address.

```vhdl
-- Track which addresses have been written (bitmask)
signal loaded_mask : std_logic_vector(NUM_INPUTS-1 downto 0) := (others => '0');

-- Update loaded mask when writing
new_mask := loaded_mask;
new_mask(load_addr_int) := '1';
loaded_mask <= new_mask;
```

**Benefits:**
- Works for sequential or random-order loading
- Single-cycle update
- Easy to check completion: `and_reduce(loaded_mask) = '1'`
- Allows re-writing same address (mask already set)

**Use Cases:**
- Input buffers with random-access loading
- Configuration register banks
- Sparse matrix storage
- Packet assembly buffers

---

## Pattern 2: Address Validation with Default

**Problem:** Need to handle out-of-range addresses gracefully without errors.

**Solution:** Conditional assignment with bounds check and safe default.

```vhdl
load_addr_int <= to_integer(load_addr) when to_integer(load_addr) < NUM_INPUTS else 0;
load_addr_valid <= '1' when to_integer(load_addr) < NUM_INPUTS else '0';
```

**Benefits:**
- Prevents array out-of-bounds access
- No simulation errors from invalid indices
- Valid signal allows conditional processing
- Synthesizes to simple comparator logic

**Key Point:** Always provide a valid default (0 in this case) even when the address is invalid.

---

## Pattern 3: Population Count in Process

**Problem:** Need to count how many bits are set in a mask.

**Solution:** Loop through mask bits with counter variable.

```vhdl
process(clk)
    variable cnt : integer;
begin
    if rising_edge(clk) then
        -- Count loaded values
        cnt := 0;
        for i in 0 to NUM_INPUTS-1 loop
            if new_mask(i) = '1' then
                cnt := cnt + 1;
            end if;
        end loop;
        load_count <= to_unsigned(cnt, ADDR_WIDTH+1);
    end if;
end process;
```

**Benefits:**
- Synthesizes efficiently (parallel logic)
- Works for any mask size
- Variable ensures combinational evaluation before register

**Alternative:** For larger masks, consider tree-based popcount or dedicated IP.

---

## Pattern 4: Parameterized Array Types

**Problem:** Need storage that scales with generics.

**Solution:** Define array type locally using generic parameters.

```vhdl
type buffer_t is array (0 to NUM_INPUTS-1) of signed(DATA_WIDTH-1 downto 0);
signal buffer_reg : buffer_t := (others => (others => '0'));
```

**Benefits:**
- Automatically scales with generic changes
- Clear, self-documenting type
- Proper initialization with nested aggregates
- Type-safe indexing

---

## Pattern 5: Clear vs Reset Handling

**Problem:** Need both power-on reset and operational clear functionality.

**Solution:** Combine in single condition with same behavior.

```vhdl
if rising_edge(clk) then
    if rst = '1' or clear = '1' then
        -- Same behavior for both
        buffer_reg  <= (others => (others => '0'));
        loaded_mask <= (others => '0');
        load_count  <= (others => '0');
        all_loaded  <= '0';
    elsif load_en = '1' and load_addr_valid = '1' then
        -- Normal operation
    end if;
end if;
```

**Benefits:**
- Unified reset/clear logic
- No code duplication
- Clear precedence: rst/clear > load
- Synchronous operation for both

---

## Pattern 6: Combinational Read with Enable

**Problem:** Need read output that's gated by enable signal.

**Solution:** Conditional expression with zero default.

```vhdl
rd_data <= buffer_reg(rd_addr_int) when (rd_en = '1' and rd_addr_valid = '1')
           else (others => '0');
```

**Benefits:**
- Zero output when not reading (reduces switching activity)
- Address validation prevents invalid access
- Pure combinational - no clock cycle delay
- Clear default behavior

---

## Pattern 7: Self-Checking Testbench Procedures

**Problem:** Need reusable test operations with automatic pass/fail reporting.

**Solution:** Procedures that encapsulate stimulus, checking, and reporting.

```vhdl
procedure check_value(
    addr     : integer;
    expected : integer;
    test_name: string
) is
begin
    rd_en <= '1';
    rd_addr <= to_unsigned(addr, ADDR_WIDTH);
    wait for CLK_PERIOD;

    if to_integer(rd_data) = expected then
        report "PASS: " & test_name severity note;
        pass_count <= pass_count + 1;
    else
        report "FAIL: " & test_name severity error;
        fail_count <= fail_count + 1;
    end if;

    rd_en <= '0';
    test_count <= test_count + 1;
    wait for CLK_PERIOD;
end procedure;
```

**Benefits:**
- Reusable across many tests
- Automatic pass/fail counting
- Consistent reporting format
- Encapsulates timing

---

## Pattern 8: Status Output Aggregation

**Problem:** Need ready signal based on completion of all operations.

**Solution:** Separate internal tracking signal from output port.

```vhdl
signal all_loaded : std_logic := '0';
...
-- In process: set when complete
if cnt = NUM_INPUTS then
    all_loaded <= '1';
end if;
...
-- Output assignment
ready <= all_loaded;
```

**Benefits:**
- Internal signal can be used in process logic
- Clean separation of concerns
- Easy to add additional ready conditions later
- Registered output (stable)

---

## Testbench Patterns Demonstrated

### Test Organization
```
Test Group 1: Reset behavior
Test Group 2: Sequential loading
Test Group 3: Clear functionality
Test Group 4: Random order loading
Test Group 5: Overwrite values
Test Group 6: NN input pattern
Test Group 7: Boundary values
Test Group 8: Reset vs Clear
```

### Summary Report Pattern
```vhdl
report "Test Summary:" severity note;
report "  Total tests: " & integer'image(test_count) severity note;
report "  Passed:      " & integer'image(pass_count) severity note;
report "  Failed:      " & integer'image(fail_count) severity note;

if fail_count = 0 then
    report "ALL TESTS PASSED!" severity note;
else
    report "SOME TESTS FAILED!" severity error;
end if;
```

---

## Key Takeaways

1. **Bitmask tracking** is elegant for random-order load detection
2. **Always validate addresses** before array access
3. **Variables in processes** enable combinational intermediate calculations
4. **Self-checking testbenches** make verification reliable
5. **Parameterized types** scale with generic changes
6. **Clear signal design** separates operational clear from power-on reset (but can share logic)
7. **Enable-gated outputs** reduce power and simplify downstream logic

---

## Applicability

These patterns apply to:
- FIFO buffers
- Register banks
- Configuration storage
- Packet buffers
- Memory interfaces
- Neural network weight/activation storage
- Any addressable storage element

---

**Last Updated:** November 26, 2024
