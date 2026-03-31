# Error Calculator Module - Learnings

## Module Overview
- **File**: `error_calculator.vhd`
- **Purpose**: Computes output layer error for backpropagation (err = target - actual)
- **Type**: Pure combinational logic
- **Format**: Q2.13 fixed-point (16-bit signed)

## Interface
```vhdl
entity error_calculator is
    generic (
        DATA_WIDTH : integer := 16;
        SAT_MAX    : integer := 32767;
        SAT_MIN    : integer := -32768
    );
    port (
        target       : in  signed(DATA_WIDTH-1 downto 0);
        actual       : in  signed(DATA_WIDTH-1 downto 0);
        err_out      : out signed(DATA_WIDTH-1 downto 0);
        saturated    : out std_logic;
        zero_err     : out std_logic
    );
end entity;
```

## Design Patterns Used

### 1. Extended Precision for Overflow Detection
```vhdl
signal diff : signed(DATA_WIDTH downto 0);  -- 17 bits for 16-bit inputs
diff <= resize(target, DATA_WIDTH+1) - resize(actual, DATA_WIDTH+1);
```
- Uses 1 extra bit to detect overflow before it occurs
- Allows accurate comparison against saturation limits

### 2. Saturation Logic
- Checks if result exceeds representable range
- Clamps to SAT_MAX (32767) or SAT_MIN (-32768)
- Sets `saturated` flag when clamping occurs

### 3. Zero Detection
```vhdl
zero_err <= '1' when diff = 0 else '0';
```
- Concurrent signal assignment for combinational output
- Useful for convergence detection in training

## Verification Results
- **Date**: 2025-11-27
- **Tool**: GHDL (VHDL-2008)
- **Result**: 24/24 tests PASSED

### Test Categories Covered
| Category | Tests | Result |
|----------|-------|--------|
| Zero error | 4 | PASS |
| Positive errors | 4 | PASS |
| Negative errors | 4 | PASS |
| Positive overflow/saturation | 2 | PASS |
| Negative overflow/saturation | 2 | PASS |
| Boundary conditions | 3 | PASS |
| NN typical values | 5 | PASS |

## Known Behaviors

### Metavalue Warnings at Time Zero
```
NUMERIC_STD.">": metavalue detected, returning FALSE
```
- **Cause**: Uninitialized signals ('U') at simulation start
- **Impact**: None - normal VHDL behavior
- **Resolution**: Not required - signals initialize after first delta cycle

## Integration Notes

### For Neural Network Use
- Input `target`: Expected output (label) in Q2.13 format
- Input `actual`: Network output in Q2.13 format
- Output `err_out`: Error signal for backpropagation
- Output `saturated`: Indicates gradient clipping may be needed
- Output `zero_err`: Training convergence indicator

### Timing Considerations
- Pure combinational logic - no clock required
- Propagation delay: ~2-3 LUT levels
- Safe to use in single-cycle paths

## Synthesis Estimates (Xilinx 7-series)
- LUTs: ~20-30
- FFs: 0 (combinational)
- Critical path: Subtraction + comparison + mux

## Future Improvements (Optional)
1. Add configurable saturation values via generics (already implemented)
2. Consider pipelined version for higher clock frequencies
3. Add optional rounding modes for the resize operation
