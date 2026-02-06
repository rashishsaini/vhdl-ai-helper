# CORDIC FSM & Handshake Protocol Design

**Date**: November 2025
**Based on**: CORDIC sine/cosine module handshake implementation
**Focus**: FSM design for handshake protocols, testbench patterns, timing verification

---

## Overview

The CORDIC module uses a 3-state FSM with ready/valid handshake protocol. This document captures the design pattern and verification methodology applicable to any streaming/handshake interface.

---

## Pattern 1: 3-State FSM for Handshake Interfaces

### The Pattern

Every system with handshake input needs exactly 3 states:

```
┌─────────────────────┐
│ IDLE                │  ready='1'  (waiting for input)
└────────────────────┬┘
                     │ input request
                     ↓
            ┌─────────────────────┐
            │ COMPUTING (or BUSY) │  ready='0'  (processing)
            └────────────────────┬┘
                                 │ done computing
                                 ↓
                        ┌─────────────────────┐
                        │ OUTPUT_VALID (1cy) │  ready='1'  (result ready)
                        └────────────────────┘
                                 │
                                 └────→ back to IDLE
```

### Why 3 States?

| State | Duration | ready | Output | Next |
|-------|----------|-------|--------|------|
| IDLE | 1+ cycles | 1 | Not valid | COMPUTING if start |
| COMPUTING | N cycles | 0 | Intermediate | OUTPUT_VALID when done |
| OUTPUT_VALID | Exactly 1 cycle | 1 | **Valid result** | IDLE or COMPUTING |

### CORDIC Implementation

```vhdl
type state_type is (IDLE, COMPUTING, OUTPUT_VALID);
signal current_state, next_state : state_type;

-- Sequential: Update state on clock
process(clk, reset) is
begin
    if reset = '1' then
        current_state <= IDLE;
    elsif rising_edge(clk) then
        current_state <= next_state;
    end if;
end process;

-- Combinational: Compute next state
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
            -- KEY: Can immediately restart if start='1'
            if start = '1' then
                next_state <= COMPUTING;
            else
                next_state <= IDLE;
            end if;
    end case;
end process;
```

### Key Insight: OUTPUT_VALID Transition

```
Critical detail: OUTPUT_VALID state MUST transition to COMPUTING
directly if start='1' on the same clock edge.

This allows back-to-back operations without idle cycles:

Cycle 17: done='1' (OUTPUT_VALID)
Cycle 18: Already in COMPUTING for next operation

Latency: 17 cycles per operation (not 18)
Throughput: 1 result every 17 cycles
```

---

## Pattern 2: Ready Signal Management

### Ready Signal States

```vhdl
-- Process to compute ready signal
process(current_state) is
begin
    case current_state is
        when IDLE =>
            ready <= '1';           -- Waiting for input
        when COMPUTING =>
            ready <= '0';           -- Busy, don't send input
        when OUTPUT_VALID =>
            ready <= '1';           -- Can accept next input NOW
    end case;
end process;
```

### Ready Signal Behavior

```
Timeline:
Cycle 0:    ready='1' (IDLE)
Cycle 1:    start pulse detected, ready→'0' (COMPUTING begins)
Cycle 2-17: ready='0' (16 iterations)
Cycle 18:   ready='1' (OUTPUT_VALID, results ready)
Cycle 19:   ready can stay high if no new input
```

### Key Behavior: Ready in OUTPUT_VALID

```
Why ready='1' in OUTPUT_VALID?

Because we're transitioning OUT of this state next cycle anyway.
This allows:
1. External system sees done='1' (results ready)
2. At SAME CLOCK EDGE, ready='1' (can accept next input)
3. User can assert start_next without additional wait

Efficiency: Eliminates 1 cycle of idle time
```

---

## Pattern 3: Handshake Condition Implementation

### The Handshake

A transaction occurs when **both ready='1' AND start='1' at rising clock edge**.

### VHDL Implementation

```vhdl
-- In state logic:
if current_state = IDLE then
    if start = '1' then
        next_state <= COMPUTING;
    end if;
end if;

-- In initialization logic (sequential process):
if start = '1' and ready = '1' then  -- Handshake condition
    -- Latch input and initialize state
    x_reg <= K_CONSTANT;
    y_reg <= (others => '0');
    z_reg <= signed(angle_in);
elsif computing = '1' then
    -- Update state with datapath
    x_reg <= x_next;
    y_reg <= y_next;
    z_reg <= z_next;
end if;
```

### Explicit Handshake Checklist

1. **ready**: Module asserts when able to accept input
2. **start**: User asserts when input valid and ready high
3. **Clock edge**: Both sampled at rising clock edge
4. **Latching**: Input latched in same cycle
5. **Acknowledgment**: ready drops next cycle (during COMPUTING)

---

## Pattern 4: One-Cycle Output Pulse (done/valid)

### Why One-Cycle Pulse?

```vhdl
-- WRONG: Holding done signal high multiple cycles
if current_state = OUTPUT_VALID then
    done <= '1';
else
    done <= '0';
end if;
-- Result: done stays high for 1 cycle naturally because
-- OUTPUT_VALID state only lasts 1 cycle
```

### VHDL Implementation

```vhdl
-- Process: done is asserted only in OUTPUT_VALID state
process(current_state) is
begin
    case current_state is
        when IDLE =>
            done <= '0';
        when COMPUTING =>
            done <= '0';
        when OUTPUT_VALID =>
            done <= '1';  -- 1-cycle pulse (state lasts 1 cycle)
    end case;
end process;

-- KEY: OUTPUT_VALID transitions to IDLE/COMPUTING next cycle
-- So done automatically goes low
```

### Timing Verification

```
Cycle 18:
  - Rising edge: State becomes OUTPUT_VALID
  - Combinational: done='1' appears immediately
  - Results: sin_out, cos_out stable (from registered x_reg, y_reg)

Cycle 19:
  - Rising edge: State becomes IDLE/COMPUTING
  - Combinational: done='0' appears
  - Pulse duration: Exactly 1 cycle
```

### User's Perspective

```vhdl
-- To capture result during pulse:
wait until done = '1';
result_sin := sin_out;
result_cos := cos_out;
wait for CLK_PERIOD;
-- After this wait, done='0', but results still stable (latched)
```

---

## Pattern 5: Iteration Counter Management

### Counter Logic

```vhdl
-- Sequential process: Update counter based on state
process(clk, reset) is
begin
    if reset = '1' then
        iteration_count <= 0;
    elsif rising_edge(clk) then
        case current_state is
            when IDLE =>
                iteration_count <= 0;  -- Reset when idle
            when COMPUTING =>
                if iteration_count < ITERATIONS - 1 then
                    iteration_count <= iteration_count + 1;
                else
                    iteration_count <= 0;  -- Prepare for next op
                end if;
            when OUTPUT_VALID =>
                iteration_count <= 0;
        end case;
    end if;
end process;
```

### Key Points

1. **Increment**: Increment during COMPUTING state
2. **Bound**: Stop at ITERATIONS-1 (0-indexed)
3. **Reset**: Clear to 0 when done
4. **Transition**: When counter reaches max, transition to OUTPUT_VALID

### Counter as Datapath Control

```vhdl
-- In datapath, counter controls shift amount:
y_shifted := shift_right(y_reg, iteration_count);  -- Shift by counter

-- Iteration 0: shift by 0 bits
-- Iteration 1: shift by 1 bit
-- ...
-- Iteration 15: shift by 15 bits
-- Iteration 0 (next): shift by 0 bits again
```

---

## Pattern 6: Testbench Verification of Handshake

### Basic Testbench Pattern

```vhdl
-- Test process
process
begin
    reset <= '1';
    wait for 100 ns;
    reset <= '0';
    wait for 20 ns;

    -- Wait for ready (should be immediate)
    wait until ready = '1';

    -- Provide input and pulse start
    angle_in <= angle_value;
    start <= '1';
    wait for CLK_PERIOD;
    start <= '0';

    -- Monitor ready (should drop)
    assert ready = '0' report "Ready should be low during compute"
        severity ERROR;

    -- Wait for done
    wait until done = '1';

    -- Capture result
    result := sin_out;

    -- Verify result...
    assert result = expected report "Result mismatch" severity ERROR;

    wait for CLK_PERIOD;
    assert done = '0' report "Done should pulse only 1 cycle"
        severity ERROR;

    wait;
end process;
```

### Verification Checklist

- [ ] `ready='1'` before operation
- [ ] `ready='0'` during COMPUTING
- [ ] `ready='1'` in OUTPUT_VALID
- [ ] `done='1'` for exactly 1 cycle
- [ ] Results stable when `done='1'`
- [ ] Can immediately start next operation after done

### Advanced: Testbench Procedure

```vhdl
-- Reusable procedure for test
procedure compute_angle(
    angle : real;
    signal angle_in : out std_logic_vector;
    signal start : out std_logic;
    signal done : in std_logic;
    signal ready : in std_logic;
    signal clk : in std_logic
) is
begin
    -- Convert angle to fixed-point
    angle_in <= to_fixed(angle);

    -- Wait for ready
    wait until ready = '1';

    -- Pulse start
    start <= '1';
    wait for CLK_PERIOD;
    start <= '0';

    -- Wait for done
    wait until done = '1';
    wait for CLK_PERIOD;
end procedure;

-- Usage in test:
compute_angle(0.785398, angle_in, start, done, ready, clk);
sin_result := sin_out;
```

### Timing Diagram in Testbench

```vhdl
-- Procedural timing check
procedure check_ready_timing is
    variable ready_first_cycle : std_logic;
begin
    wait for CLK_PERIOD;
    assert ready = '1' report "Ready should be high at start" severity ERROR;

    wait until done = '1';
    ready_first_cycle := ready;
    assert ready_first_cycle = '1' report "Ready should be high during OUTPUT_VALID"
        severity ERROR;

    wait for CLK_PERIOD;
    assert ready = '1' report "Ready should stay high after OUTPUT_VALID"
        severity ERROR;
end procedure;
```

---

## Pattern 7: Back-to-Back Operation Verification

### Test Scenario

```vhdl
procedure test_back_to_back is
begin
    -- Operation 1
    wait until ready = '1';
    angle_in <= angle1;
    start <= '1';
    wait for CLK_PERIOD;
    start <= '0';

    -- Operation 2 (queue while operation 1 computing)
    wait for 10 * CLK_PERIOD;  -- Partial delay
    angle_in <= angle2;

    wait until ready = '1';    -- Wait for ready (will be in OUTPUT_VALID)
    start <= '1';
    wait for CLK_PERIOD;
    start <= '0';

    -- Collect results
    wait until done = '1';
    result1 := sin_out;
    wait for CLK_PERIOD;

    wait until done = '1';
    result2 := sin_out;
    wait for CLK_PERIOD;

    -- Verify both
    verify_result(result1, expected1);
    verify_result(result2, expected2);
end procedure;
```

### Expected Timeline

```
Cycle 0:   ready='1' (IDLE)
Cycle 1:   start pulse, angle1 latched, COMPUTING
Cycle 2-17: Computing angle1
Cycle 18:  done='1' (OUTPUT_VALID), ready='1'
Cycle 18:  start pulse for angle2 (in OUTPUT_VALID!)
Cycle 19:  angle2 latched, COMPUTING
Cycle 20-35: Computing angle2
Cycle 36:  done='1', result1 available
Cycle 37:  done='0', but result1 stable
...
Cycle 35:  done='1', result2 available
```

### Key Verification

```vhdl
assert cycles_between_operations = 17
    report "Back-to-back should have 17 cycle latency" severity ERROR;
```

---

## Pattern 8: State Machine Assertions

### Assert Valid Transitions

```vhdl
-- VHDL-2019: Use assert statements in testbench
process is
begin
    wait until rising_edge(clk);

    -- Only valid transitions
    if current_state = IDLE then
        assert next_state = IDLE or next_state = COMPUTING
            report "Invalid transition from IDLE" severity ERROR;
    elsif current_state = COMPUTING then
        assert next_state = COMPUTING or next_state = OUTPUT_VALID
            report "Invalid transition from COMPUTING" severity ERROR;
    elsif current_state = OUTPUT_VALID then
        assert next_state = IDLE or next_state = COMPUTING
            report "Invalid transition from OUTPUT_VALID" severity ERROR;
    end if;
end process;

-- Alternative: Create formal properties
-- property valid_fsm;
--     (current_state = IDLE) -> ((start = '1') -> (next_state = COMPUTING));
-- endproperty;
```

### Assert Output Consistency

```vhdl
-- ready/done signals must match state
process is
begin
    wait until rising_edge(clk);

    if current_state = IDLE then
        assert ready = '1' and done = '0'
            report "IDLE state signals incorrect" severity ERROR;
    elsif current_state = COMPUTING then
        assert ready = '0' and done = '0'
            report "COMPUTING state signals incorrect" severity ERROR;
    elsif current_state = OUTPUT_VALID then
        assert ready = '1' and done = '1'
            report "OUTPUT_VALID state signals incorrect" severity ERROR;
    end if;
end process;
```

---

## Best Practices for Handshake Design

| Practice | Benefit | Implementation |
|----------|---------|-----------------|
| 3-state FSM | Clear semantics | IDLE, COMPUTING, OUTPUT_VALID |
| Ready management | Prevents overwriting | ready based on state |
| Handshake condition | Robust synchronization | start AND ready at clock edge |
| One-cycle pulse | Simple detection | done=current_state=OUTPUT_VALID |
| Counter reset | Clean state | Reset when transitioning out |
| Testbench verification | Correctness | Check timing, assertions |
| Back-to-back testing | Efficiency | Verify immediate restart |

---

## Lessons for Other Projects

### Apply This Pattern When:
1. **Designing streaming interfaces** (FFT input/output buffers)
2. **Building bus slave interfaces** (AXI, Avalon)
3. **Implementing pipelined stages** (handshake between stages)
4. **Creating reusable modules** (clean, standard interface)

### Common Pitfalls to Avoid:

1. **Missing ready in OUTPUT_VALID**
   - ❌ ready='0' during OUTPUT_VALID state
   - ✅ ready='1' in OUTPUT_VALID to enable back-to-back ops

2. **Holding done for multiple cycles**
   - ❌ done stays high until user acknowledges
   - ✅ done=1-cycle pulse (state-based)

3. **Not resetting iteration counter**
   - ❌ Counter keeps running after operation
   - ✅ Reset counter to 0 when idle

4. **Incorrect transition from OUTPUT_VALID**
   - ❌ Always go back to IDLE
   - ✅ Go to COMPUTING if start='1' (no extra latency)

---

## Testing Checklist

- [ ] Handshake correctly detected (ready AND start)
- [ ] ready signal follows state machine
- [ ] done pulse is exactly 1 cycle
- [ ] Results stable when done='1'
- [ ] Back-to-back operations work (17-cycle latency)
- [ ] Reset clears all state
- [ ] Counter increments correctly
- [ ] No undefined state transitions
- [ ] All outputs match expected state
- [ ] Edge cases tested (multiple back-to-back, delays, etc.)

---

## References

- Handshake Protocol: See `CORDIC_HANDSHAKE_PROTOCOL.md`
- FSM Design: See `cordic_vhdl_implementation_patterns.md`
- Algorithm Details: See `CORDIC_ALGORITHM_GUIDE.md`
- Complete Example: CORDIC module (`sources/cordic_sin_module.vhd`)
