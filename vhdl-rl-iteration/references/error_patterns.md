# VHDL Error Patterns Reference

Comprehensive catalog of common VHDL errors with categorization and solutions.

## Error Categories

- **FIXABLE**: Can be automatically corrected through code iteration
- **TESTBENCH**: Issues with test environment, not design
- **ARCHITECTURE**: Requires human design decisions
- **PHYSICS**: Hardware/timing constraints beyond code fixes

## FIXABLE Errors

### Syntax Errors

#### Missing Semicolon
```
ERROR: Line 42: syntax error near "signal"
```
**Pattern**: `missing semicolon|syntax error near`
**Solution**: Add semicolon to previous line
**Example Fix**:
```vhdl
-- Before
signal data : std_logic_vector(7 downto 0)
signal valid : std_logic;

-- After  
signal data : std_logic_vector(7 downto 0);
signal valid : std_logic;
```

#### Missing END Statement
```
ERROR: unexpected end of file, expecting 'end'
```
**Pattern**: `missing.*end|expecting.*end`
**Solution**: Add corresponding end statement
**Example Fix**:
```vhdl
-- Before
process(clk)
begin
  if rising_edge(clk) then
    counter <= counter + 1;
  end if;
-- Missing: end process;

-- After
process(clk)
begin
  if rising_edge(clk) then
    counter <= counter + 1;
  end if;
end process;
```

### Type Mismatches

#### Integer vs Std_Logic
```
ERROR: cannot match type 'integer' with type 'std_logic'
```
**Pattern**: `type mismatch|cannot match type`
**Solution**: Use type conversion
**Example Fix**:
```vhdl
-- Before
signal count : integer;
signal flag : std_logic;
flag <= count;  -- ERROR

-- After
signal count : integer;
signal flag : std_logic;
flag <= '1' when count > 0 else '0';
```

#### Vector Width Mismatch
```
ERROR: width mismatch, expected 8 bits, got 4
```
**Pattern**: `width mismatch|size mismatch`
**Solution**: Resize or select correct range
**Example Fix**:
```vhdl
-- Before
signal data_in : std_logic_vector(7 downto 0);
signal data_out : std_logic_vector(3 downto 0);
data_out <= data_in;  -- ERROR

-- After
data_out <= data_in(3 downto 0);  -- Select correct bits
```

### Signal Declaration Issues

#### Undeclared Signal
```
ERROR: 'enable' is not declared
```
**Pattern**: `not declared|undeclared identifier`
**Solution**: Add signal declaration
**Example Fix**:
```vhdl
-- Before
process(clk)
begin
  if enable = '1' then  -- ERROR: enable not declared
    ...
  end if;
end process;

-- After
signal enable : std_logic;

process(clk)
begin
  if enable = '1' then
    ...
  end if;
end process;
```

#### Multiple Drivers
```
ERROR: signal 'data' has multiple drivers
```
**Pattern**: `multiple drivers|driven by multiple`
**Solution**: Use single driver or variable
**Example Fix**:
```vhdl
-- Before
process(clk)
begin
  data <= '0';  -- Driver 1
end process;

process(rst)
begin
  data <= '1';  -- Driver 2 - ERROR
end process;

-- After
process(clk, rst)
begin
  if rst = '1' then
    data <= '0';
  elsif rising_edge(clk) then
    data <= '1';
  end if;
end process;
```

### Process Sensitivity Issues

#### Incomplete Sensitivity List
```
WARNING: signal 'rst' used but not in sensitivity list
```
**Pattern**: `not in sensitivity|incomplete sensitivity`
**Solution**: Add missing signals or use (all) in VHDL-2008
**Example Fix**:
```vhdl
-- Before
process(clk)  -- Missing rst
begin
  if rst = '1' then
    ...
  elsif rising_edge(clk) then
    ...
  end if;
end process;

-- After
process(clk, rst)
begin
  if rst = '1' then
    ...
  elsif rising_edge(clk) then
    ...
  end if;
end process;

-- Or VHDL-2008:
process(all)
begin
  if rst = '1' then
    ...
  elsif rising_edge(clk) then
    ...
  end if;
end process;
```

## TESTBENCH Errors

### Test Vector Issues

#### Assertion Failure
```
ERROR: Assertion failed at time 150 ns: expected 0xFF, got 0x00
```
**Pattern**: `assertion failed|test failed`
**Solution**: Fix test vectors or timing
**Example Fix**:
```vhdl
-- Before
data_in <= x"FF";
wait for 10 ns;
assert data_out = x"FF";  -- Fails if module has latency

-- After
data_in <= x"FF";
wait for 20 ns;  -- Allow for processing time
assert data_out = x"FF" report "Data mismatch" severity error;
```

### Timing Issues in Testbench

#### Clock Period Too Short
```
ERROR: Setup time violation in testbench
```
**Pattern**: `setup.*violation.*testbench|testbench.*timing`
**Solution**: Increase clock period or adjust timing
**Example Fix**:
```vhdl
-- Before
constant clk_period : time := 1 ns;  -- Too fast

-- After
constant clk_period : time := 10 ns;  -- More realistic
```

### Incomplete Test Coverage

#### Missing Reset Sequence
```
WARNING: signals not initialized properly
```
**Pattern**: `not initialized|missing reset`
**Solution**: Add proper reset sequence
**Example Fix**:
```vhdl
-- Before
stim_process : process
begin
  data_in <= x"FF";
  wait for 10 ns;
end process;

-- After
stim_process : process
begin
  rst <= '1';
  wait for 20 ns;
  rst <= '0';
  wait for 10 ns;
  
  data_in <= x"FF";
  wait for 10 ns;
end process;
```

## ARCHITECTURE Errors

### Design Issues (Human Intervention Required)

#### FSM State Encoding
```
WARNING: FSM states not optimally encoded
```
**Pattern**: `FSM|state.*encoding`
**Category**: ARCHITECTURE
**Rationale**: State encoding affects timing/area tradeoffs - requires design decision

#### Bus Width Selection
```
ERROR: data path width insufficient for operation
```
**Pattern**: `data path.*width|bus.*width.*insufficient`
**Category**: ARCHITECTURE
**Rationale**: Fundamental design parameter - not a code fix

#### Pipeline Depth
```
WARNING: critical path too long, consider pipelining
```
**Pattern**: `critical path|pipeline|pipelining`
**Category**: ARCHITECTURE
**Rationale**: Requires architectural redesign, not code tweaks

## PHYSICS Errors

### Timing Constraints (Cannot Fix with Code)

#### Setup Time Violation
```
ERROR: Setup time violation: path clk to data_out, slack -2.3 ns
```
**Pattern**: `setup.*violation|setup.*slack.*negative`
**Category**: PHYSICS
**Rationale**: Physics constraint - needs redesign or clock constraint change

#### Hold Time Violation
```
ERROR: Hold time violation on signal enable
```
**Pattern**: `hold.*violation|hold.*slack.*negative`
**Category**: PHYSICS
**Rationale**: Physical timing issue - cannot fix with code alone

### Resource Constraints

#### LUT Overflow
```
ERROR: Design requires 15000 LUTs, only 10000 available
```
**Pattern**: `LUT.*exceeded|insufficient.*LUT`
**Category**: PHYSICS
**Rationale**: Hardware limitation - need bigger device or redesign

#### BRAM Overflow
```
ERROR: Design requires 50 BRAM, only 40 available
```
**Pattern**: `BRAM.*exceeded|block.*RAM.*insufficient`
**Category**: PHYSICS
**Rationale**: Hardware constraint - architectural change needed

#### DSP Usage
```
ERROR: Design requires 100 DSP blocks, only 80 available
```
**Pattern**: `DSP.*exceeded|insufficient.*DSP`
**Category**: PHYSICS
**Rationale**: Must reduce complexity or change device

### Implementation Failures

#### Routing Failure
```
ERROR: Cannot route design, congestion too high
```
**Pattern**: `cannot route|routing failed|congestion`
**Category**: PHYSICS
**Rationale**: Floorplanning/architecture issue

#### Clock Distribution
```
ERROR: Clock skew exceeds limit
```
**Pattern**: `clock skew|clock distribution`
**Category**: PHYSICS
**Rationale**: Clock network issue - needs constraint/architecture change

## Pattern Matching Rules

### Priority Order
1. **PHYSICS** - Highest priority, immediate stop
2. **ARCHITECTURE** - High priority, stop iteration
3. **TESTBENCH** - Medium priority, fixable but different approach
4. **FIXABLE** - Low priority, continue iteration

### Confidence Scoring
- **90-100%**: Clear pattern match, high confidence category
- **75-89%**: Good match, likely correct category
- **60-74%**: Moderate match, may need verification
- **<60%**: Weak match, categorize as UNKNOWN

### Iteration Decision Logic

```python
if any_error_is(PHYSICS):
    STOP("Physical constraints - needs architectural redesign")
elif any_error_is(ARCHITECTURE):
    STOP("Design decisions required - human input needed")
elif all_errors_are(TESTBENCH):
    CONTINUE("Fix testbench issues")
elif all_errors_are(FIXABLE):
    CONTINUE("Apply code fixes")
else:
    EVALUATE("Mixed errors - assess individually")
```

## Common Error Combinations

### Syntax + Type Errors (Usually 2-3 iterations)
```
Iteration 1: Fix syntax errors
Iteration 2: Fix resulting type mismatches
Iteration 3: Verify and pass
```

### Testbench + Timing (Usually 3-5 iterations)
```
Iteration 1: Fix test vector generation
Iteration 2: Adjust timing
Iteration 3: Add missing test cases
Iteration 4-5: Refine and verify
```

### Hit Timing Wall (Stop immediately)
```
Iteration 1: Identify timing violation
Decision: STOP - Cannot fix timing with code changes alone
Action: Return to human for architectural review
```

## Usage in Iteration Loop

1. **Parse log** with parse_vivado_logs.py
2. **Match patterns** against this reference
3. **Categorize** each error
4. **Aggregate** category counts
5. **Decide** continue or stop based on:
   - Any PHYSICS errors → STOP
   - Any ARCHITECTURE errors → STOP
   - All FIXABLE/TESTBENCH → CONTINUE
   - Mixed or UNKNOWN → Evaluate case by case
