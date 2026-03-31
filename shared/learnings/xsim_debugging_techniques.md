# XSIM Debugging Techniques and Known Issues

**Date**: 2025-10-24
**Context**: Dealing with SIGSEGV and elaboration crashes in Vivado XSIM
**Source**: Real-world debugging experience with XSIM 2023.02

---

## Known XSIM Issues

### Issue #1: Component Instances Don't Work in XSIM 2023.02

**Problem**:
Using VHDL component declarations and instantiations causes SIGSEGV during elaboration.

**Symptoms**:
```
ERROR: [XSIM 43-3316] Signal SIGSEGV received
Starting static elaboration
ERROR: [XSIM 43-3321] Static elaboration ... failed
```

**Broken Code**:
```vhdl
architecture Behavioral of my_tb is
    component my_design
        port (
            clk : in std_logic;
            ...
        );
    end component;
begin
    uut: my_design
        port map (
            clk => clk,
            ...
        );
end architecture;
```

**Working Code** ✅:
```vhdl
architecture Behavioral of my_tb is
    -- No component declaration needed!
begin
    uut: entity work.my_design
        port map (
            clk => clk,
            ...
        );
end architecture;
```

**Note**: Direct entity instantiation cannot be configured (no `configuration` support), but it works in XSIM.

---

### Issue #2: Function Calls in Package Constants

**Problem**:
Using function calls like `to_signed()` in package-level constant declarations causes elaboration crashes.

**Broken Code**:
```vhdl
package my_pkg is
    constant MAX_VAL : signed(31 downto 0) := to_signed(1000, 32);  -- CRASH!
end package;
```

**Working Code** ✅:
```vhdl
package my_pkg is
    constant MAX_VAL_INT : integer := 1000;
    -- Use to_signed() at point of use in package body
end package;

package body my_pkg is
    function my_func return signed is
    begin
        return to_signed(MAX_VAL_INT, 32);  -- OK here
    end function;
end package body;
```

---

### Issue #3: Fixed/Floating Point Package Names

**Problem**:
XSIM uses different package names than Vivado synthesis for IEEE fixed/floating point.

**For Synthesis** (Vivado):
```vhdl
library ieee;
use ieee.fixed_pkg.all;
```

**For Simulation** (XSIM) ✅:
```vhdl
library ieee_proposed;
use ieee_proposed.fixed_pkg.all;
```

**Note**: This only applies to IEEE standard packages, not custom packages.

---

## Binary Search Debugging Technique

When facing SIGSEGV or mysterious elaboration failures:

### Step 1: Comment Out Everything

Use VHDL-2008 block comments to comment out the **entire architecture body**:

```vhdl
architecture Behavioral of my_design is
    -- signal declarations
    /*
    signal my_sig : std_logic;
    signal counter : integer;
    */
begin
    /*
    process(clk)
    begin
        ...
    end process;

    my_component_inst: entity work.my_component
        port map (...);
    */
end architecture;
```

**Test**: Try to build simulation.

- **If it fails**: Problem is in entity interface, compile process, or testbench connections
- **If it works**: Problem is inside the architecture

---

### Step 2: Binary Search

**Gradually uncomment sections** using binary search:

1. **Uncomment half** of the architecture
2. **Build and test**
3. If crash:
   - Problem is in that half
   - Comment it out again, uncomment half of that half
4. If no crash:
   - Problem is in other half
   - Uncomment that half

**Repeat** until you isolate the smallest section causing the crash.

---

### Step 3: Isolate Components/Processes

Once you've found the problematic section:

**For a component**:
```vhdl
my_inst: entity work.problematic_component
    port map (
        /* Comment out all port maps */
    );
```

**For a process**:
```vhdl
process(clk)
    /* Comment out declarative part */
begin
    /* Comment out sequential statements */
end process;
```

Continue binary search within that smaller unit.

---

## Example: Full Binary Search Session

### Start: Full Design Crashes
```vhdl
architecture Behavioral of my_design is
    signal sig1, sig2, sig3 : std_logic;
begin
    process1: process(clk) begin ... end process;
    inst1: entity work.comp1 port map (...);
    inst2: entity work.comp2 port map (...);
end architecture;
```
**Result**: SIGSEGV ❌

---

### Test 1: Comment Everything
```vhdl
architecture Behavioral of my_design is
    /*
    signal sig1, sig2, sig3 : std_logic;
    */
begin
    /*
    process1: process(clk) begin ... end process;
    inst1: entity work.comp1 port map (...);
    inst2: entity work.comp2 port map (...);
    */
end architecture;
```
**Result**: Works ✅ (Problem is in architecture body)

---

### Test 2: Uncomment First Half
```vhdl
architecture Behavioral of my_design is
    signal sig1, sig2, sig3 : std_logic;
begin
    process1: process(clk) begin ... end process;
    inst1: entity work.comp1 port map (...);
    /*
    inst2: entity work.comp2 port map (...);
    */
end architecture;
```
**Result**: SIGSEGV ❌ (Problem is in first half: signals, process1, or inst1)

---

### Test 3: Uncomment Signals + Process Only
```vhdl
architecture Behavioral of my_design is
    signal sig1, sig2, sig3 : std_logic;
begin
    process1: process(clk) begin ... end process;
    /*
    inst1: entity work.comp1 port map (...);
    inst2: entity work.comp2 port map (...);
    */
end architecture;
```
**Result**: Works ✅ (Problem is in inst1)

---

### Test 4: Uncomment inst1 Ports One by One
```vhdl
inst1: entity work.comp1
    port map (
        clk => clk,
        /* rst => rst, */
        /* data => sig1, */
        ...
    );
```
**Result**: SIGSEGV on specific port ❌

**Found It!** The problem is with that specific port mapping or the signal connected to it.

---

## Understanding SIGSEGV Crashes

### What SIGSEGV Usually Means

**In General**: Segmentation fault = accessing invalid memory
**In XSIM Context**:
- Simulator hit unimplemented/buggy feature
- Uninitialized variable in simulator code
- C pointer pointing to invalid memory
- Out-of-bounds array access in simulator internals

### Do NOT Expect Useful Information From:
❌ Stack traces (they're in simulator internals, not your VHDL)
❌ Error messages (usually just "SIGSEGV received")
❌ Elaborate.log (rarely has useful details)

### DO Pay Attention To:
✅ What you last changed
✅ What specific construct triggers it
✅ Whether it's reproducible
✅ Patterns (e.g., always fails with component instances)

---

## Filing Bug Reports

If you isolate a small, reproducible case:

### Where to Report:
1. **Xilinx FAE** (Field Application Engineer) - if you have one
2. **Xilinx Forums** - https://support.xilinx.com/s/topic/0TO2E000000YKYAWA4/vivado
3. **AMD Support** - https://www.xilinx.com/support.html

### What to Include:
1. **Minimal reproducible example** (smallest VHDL that crashes)
2. **Vivado version** (e.g., 2023.2, 2025.1)
3. **Steps to reproduce**
4. **Expected behavior**
5. **Actual behavior** (crash with SIGSEGV)
6. **Workaround** (if you found one)

---

## Workarounds Summary

| Issue | Workaround |
|-------|-----------|
| Component instances crash | Use direct entity instantiation |
| Function in package constant | Use integer constant, convert at use |
| Fixed/floating pkg not found | Use `ieee_proposed.fixed_pkg` |
| Mysterious SIGSEGV | Binary search with `/* */` comments |
| Can't isolate issue | Start with empty architecture |

---

## Prevention Strategies

### 1. Start Simple
- Begin with minimal testbench
- Add complexity incrementally
- Test after each addition

### 2. Use Direct Entity Instantiation
```vhdl
-- Always do this in testbenches:
uut: entity work.my_design
    generic map (...)
    port map (...);
```

### 3. Avoid Package-Level Complexity
```vhdl
-- Simple constants only:
package my_pkg is
    constant WIDTH : integer := 32;
    constant DEPTH : integer := 1024;
    -- NOT: constant MAX : signed := to_signed(100, 32);
end package;
```

### 4. Keep Backup Versions
When something works, **save it**:
```bash
cp my_design.vhd my_design_working.vhd
```

### 5. Isolate New Features
Add one new feature at a time, test immediately.

---

## Resources

- **Vivado Simulator User Guide (UG900)**: Official documentation
- **VHDL-2008 Support**: Not all features work in XSIM
- **Xilinx Forums**: Search for "SIGSEGV" or your specific error

---

## Lessons Applied: Cholesky3by3 Project

**Issues Encountered**:
1. ✅ String length mismatch (39 vs 40) - Fixed with padding
2. ✅ Function in package constants - Fixed with integer constants
3. ✅ Component instance - Fixed with direct entity instantiation

**Final Working Configuration**:
- Direct entity instantiation in testbench
- Integer constants in package
- Minimal complexity in declarations

---

**Document Version**: 1.0
**Project**: XSIM Debugging Guide
**Status**: Working techniques for XSIM 2023.02 / 2025.1
