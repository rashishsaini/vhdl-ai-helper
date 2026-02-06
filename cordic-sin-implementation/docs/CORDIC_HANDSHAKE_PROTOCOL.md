# CORDIC Handshake Protocol

## Overview

The CORDIC module uses an industry-standard **Ready/Valid Handshake Protocol** for input synchronization and a **Done/Valid Protocol** for output synchronization. These protocols ensure robust integration with other components.

## Ready/Valid Input Protocol

### Definition

The **Ready/Valid handshake** provides flow control between producer (user) and consumer (CORDIC):

- **ready**: CORDIC asserts when ready to accept new input
- **start**: User asserts when new input is valid
- **Handshake occurs**: When both signals are high at rising clock edge

### Timing Diagram

```
           ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐
Clock      └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘


Ready ┌──────────────────────┐                    ┌──────
      │                      │                    │
      └──────────────────────┘                    └──────
           IDLE state             COMPUTING      OUTPUT_VALID

Start      ┌────────┐                       ┌────────────
           │        │                       │
           └────────┘                       └────────────
                (1-cycle pulse)                (1-cycle)

             Handshake
             occurs!
```

### State Transitions

#### IDLE State
```
Condition: CORDIC is idle, not computing
Signals:   ready = '1'
           computing = '0'
           done = '0'

Action:    Waits for user to assert start
           No computation in progress
```

#### Handshake (Clock Edge)
```
Condition: rising_edge(clk) AND start='1' AND ready='1'
Action:    angle_in is latched into z_reg
           x_reg loaded with K constant
           y_reg loaded with 0
           FSM transitions to COMPUTING
           ready = '0'
```

#### COMPUTING State
```
Duration:  16 clock cycles (one per CORDIC iteration)
Signals:   ready = '0' (not accepting new input)
           computing = '1'
           done = '0'

Action:    x_reg, y_reg, z_reg updated every cycle
           Angle lookup from LUT
           Rotation logic evaluates
```

#### OUTPUT_VALID State
```
Duration:  1 clock cycle only
Signals:   ready = '1' (can accept new input!)
           computing = '0'
           done = '1'
           valid = '1'

Results:   sin_out = y_reg
           cos_out = x_reg
           Valid for this cycle only

Action:    Can immediately restart if start='1'
```

## Detailed Handshake Examples

### Example 1: Single Operation

```
Timeline:
┌──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐
│ Cy 0 │ Cy 1 │ Cy 2 │ Cy3  │ ...  │ Cy17 │ Cy18 │ Cy19 │ Cy20 │
└──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┘

ready  ├─────┴─────┬─────────────────────────────┬──────────────
       │ IDLE → 1  │      0 (computing)         │  1 (ready)
       └───────────┴─────────────────────────────┴──────────────

start  ├─────┬─────┴─────┐
       │  0  │  1 (pulse)│ 0
       └─────┴───────────┴─────────────────────────────────────

done   ├────────────────────────────────┬─────┴─────┐
       │              0                 │  1 (1cy) │ 0
       └────────────────────────────────┴───────────┴─────────────

angle  ├──[Input latched]─────────────────────────────────────
       │   (z_reg updated)
       └────────────────────────────────────────────────────────

sin/
cos    ├────────────────────────────────┬──[Valid result]──────
       │  (computing, intermediate)     │
       └────────────────────────────────┴──────────────────────

State: IDLE → COMPUTING (16cy) → OUTPUT_VALID (1cy) → IDLE
```

**Key Events:**
- Cy0: ready='1' (IDLE)
- Cy0: start='1' pulse detected
- Cy1: Handshake complete, angle latched, enter COMPUTING
- Cy2-17: 16 iterations
- Cy18: Enter OUTPUT_VALID, done='1', results valid
- Cy19: done='0', back to IDLE (ready='1')

### Example 2: Back-to-Back Operations

```
Operation 1: Cy0-18 (angle1)
Operation 2: Cy18-35 (angle2)  ← Starts immediately!
Operation 3: Cy35-52 (angle3)  ← Starts immediately!

Timeline:
┌──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐
│ Cy0  │ Cy1  │ ...  │Cy18  │ Cy19 │ ...  │Cy35  │ Cy36 │ ...  │
└──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┘

ready  ├──1──┴──────0─────────────┬──1──┴──────0──────────┬──1──
       │                          │                        │
       └──────────────────────────┴────────────────────────┴──────

start  ├──1──┐              ┌──────────1──┐        ┌──────────1──┐
       │ op1 │              │    op2      │        │    op3      │
       └─────┘              └─────────────┘        └─────────────┘

done   ├─────────────────────1──┬┐         ┌─1──┬┐
       │                        ││         │    ││
       └────────────────────────┘└────┐────┴────┘└────────────

Op1 Input: Cy0-1 (latched)
Op1 Result: Cy18
Op1 Done: Cy18 (1-cycle pulse)

Op2 Input: Cy18-19 (latched in OUTPUT_VALID!)
Op2 Result: Cy35
Op2 Done: Cy35 (1-cycle pulse)

Op3 Input: Cy35-36 (latched in OUTPUT_VALID!)
Op3 Result: Cy52
Op3 Done: Cy52 (1-cycle pulse)
```

**Key Insight:** New input can be accepted in OUTPUT_VALID state!
- Reduces idle time
- Enables pipelined input
- No wasted cycles between operations

### Example 3: Delayed Input

```
Scenario: User can't provide input immediately

┌──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐
│ Cy0  │ Cy1  │ Cy2  │ Cy3  │ Cy4  │ Cy5  │ Cy6  │ Cy7  │ ...  │
└──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┘

ready  ├──1─────────────────────────────────────────────────────
       │ (stays high while waiting for start)
       └──────────────────────────────────────────────────────────

start  ├─────────────────────┬──1──┐
       │                     │     │
       └─────────────────────┴─────┴──────────────────────────────
                    Waiting for input

Module remains in IDLE:
- ready stays '1'
- No computation
- No power wasted on unwanted computation
- User can assert start whenever ready
```

**Benefit:** Handshake prevents unwanted computation

## Done/Valid Output Protocol

### Definition

The **Done/Valid output protocol** indicates when results are ready:

- **done**: 1-cycle pulse when result is valid
- **valid**: Same as done (redundant, but useful)
- **sin_out, cos_out**: Stable when done='1'

### Characteristics

```
Done Signal:
  ├─ Asserted for exactly 1 clock cycle
  ├─ High when results are ready
  ├─ Low for all other times
  └─ Used as strobe signal

Valid Signal:
  ├─ Same as done (semantic alternative)
  ├─ Indicates output data validity
  ├─ Short pulse
  └─ For compatibility with existing designs

Output Data:
  ├─ sin_out, cos_out
  ├─ Stabilizes when done='1'
  ├─ Remains stable for 1 cycle after (can hold)
  └─ Valid until next operation completes
```

## Recommended User Implementation

### Basic Pattern

```vhdl
-- User process
process
begin
  -- Wait for module ready
  wait until cordic_ready = '1';

  -- Provide input and request
  angle <= angle_value;
  start_req <= '1';
  wait for CLK_PERIOD;
  start_req <= '0';

  -- Wait for result
  wait until cordic_done = '1';

  -- Read results (valid for this cycle)
  result_sin := cordic_sin;
  result_cos := cordic_cos;
  wait for CLK_PERIOD;

  -- Process results
  process_sine(result_sin);
  process_cosine(result_cos);

  wait;
end process;
```

### Pipelined Pattern (Back-to-Back)

```vhdl
-- For rapid-fire inputs
process
  variable angle : real;
begin
  -- Input 3 angles quickly
  for i in 0 to 2 loop
    angle := real(i) * PI / 4.0;

    wait until cordic_ready = '1';
    angle_in <= to_fixed(angle);
    start <= '1';
    wait for CLK_PERIOD;
    start <= '0';
  end loop;

  -- Collect 3 results
  for i in 0 to 2 loop
    wait until cordic_done = '1';
    wait for CLK_PERIOD;

    results(i).sin := signed(sin_out);
    results(i).cos := signed(cos_out);
  end loop;

  wait;
end process;
```

### Continuous Processing Pattern

```vhdl
-- For continuous stream
process
begin
  reset <= '1';
  wait for 100 ns;
  reset <= '0';
  wait for 20 ns;

  -- Main loop
  loop
    -- Provide input when ready
    wait until cordic_ready = '1';
    angle_in <= next_angle;  -- From stream
    start <= '1';
    wait for CLK_PERIOD;
    start <= '0';

    -- Wait for result and immediately provide next input
    wait until cordic_done = '1';
    process_result(sin_out, cos_out);

    -- Get next angle from stream
    get_next_angle(next_angle);
    wait for CLK_PERIOD;
  end loop;

  wait;
end process;
```

## Handshake Rules

### Rule 1: Start is a Pulse

```vhdl
-- CORRECT: 1-cycle pulse
start <= '1';
wait for CLK_PERIOD;
start <= '0';

-- WRONG: Holding start high
start <= '1';
wait for 5 * CLK_PERIOD;
start <= '0';  -- Only first cycle counts!
```

### Rule 2: Check Ready Before Asserting Start

```vhdl
-- CORRECT: Always check ready
wait until cordic_ready = '1';
start <= '1';

-- RISKY: May miss handshake if not ready
start <= '1';
wait for CLK_PERIOD;

-- SAFE: But wastes cycles
loop
  wait for CLK_PERIOD;
  exit when cordic_ready = '1';
end loop;
start <= '1';
```

### Rule 3: Results Valid Only During Done Pulse

```vhdl
-- CORRECT: Latch during done pulse
wait until cordic_done = '1';
sin_result := sin_out;
cos_result := cos_out;
wait for CLK_PERIOD;

-- WRONG: Assuming valid after done
wait until cordic_done = '1';
wait for CLK_PERIOD;
sin_result := sin_out;  -- May be stale!
```

### Rule 4: Ready Returns After Done

```vhdl
-- After done='1' for one cycle:
-- ready = '1' at the same clock edge (OUTPUT_VALID state)

Timeline:
  done = '1' ──┐
  ready = '0' ├─ Both change on same rising edge
              └─ So: can assert start in OUTPUT_VALID

-- This is valid and efficient:
if cordic_done = '1' and new_angle_available then
  start <= '1';  -- Can start next operation immediately
end if;
```

## Timing Compliance

### Setup Time (User → CORDIC)

```
Before rising clock edge:
  angle_in must be stable: 2 ns minimum
  start must be high: 2 ns minimum

Recommendation: Set inputs 1/4 clock period before rising edge
```

### Hold Time (User → CORDIC)

```
After rising clock edge:
  angle_in can change: 2 ns minimum hold
  start can change: 2 ns minimum hold

Recommendation: Keep stable until 1/4 clock period after edge
```

### Output Valid Time (CORDIC → User)

```
After rising clock edge (result of done pulse):
  sin_out, cos_out stable: 5 ns (registered output)
  ready stable: 5 ns

Recommendation: Latch results within 1 clock period
```

## Error Prevention

### What Can Go Wrong?

1. **Holding start high** → Only first cycle recognized
   - Fix: Use 1-cycle pulse

2. **Not checking ready** → May overwrite in-progress computation
   - Fix: Always `wait until ready = '1'`

3. **Reading output after done** → Stale data
   - Fix: Read during done='1' cycle

4. **Ignoring done signal** → May read intermediate values
   - Fix: Use done as gating signal

### Safety Checklist

- [ ] start signal is 1-cycle pulse
- [ ] Check ready before asserting start
- [ ] Read outputs during done='1'
- [ ] Wait for ready between operations
- [ ] Handle reset properly (ready='0' during reset)
- [ ] FSM state matches output signals

## Performance Implications

### Throughput with This Protocol

```
Best case (back-to-back):
  Input Op1: Cycle 0-1
  Result Op1: Cycle 18
  Input Op2: Cycle 18-19 (in OUTPUT_VALID!)
  Result Op2: Cycle 35

  Throughput: 1 operation every 17 cycles (after first)

Worst case (delayed input):
  Input Op1: Cycle 0
  Result Op1: Cycle 18
  Ready again: Cycle 19
  Input Op2: Cycle 25 (user was busy)
  Result Op2: Cycle 42

  Throughput: 1 operation every 25 cycles
```

### Latency

```
From user asserting start to result valid:
  18 clock cycles minimum
  180 ns @ 100 MHz
```

## Alternative Protocols (Not Implemented)

### Stop-When-Full Protocol
```
ready = '1' while module accepting inputs
ready = '0' while full (computation ongoing)

Advantage: Can queue multiple operations
Disadvantage: Requires input buffer
```

### AXI Protocol
```
Extra signals: tvalid, tready, tlast
More complex but industry standard

Not needed for single-operation module
```

## Summary Table

| Aspect | Details |
|--------|---------|
| **Input Handshake** | ready/start (request/grant) |
| **Output Handshake** | done/valid (1-cycle pulse) |
| **Initialization Time** | 1 cycle (handshake) |
| **Computation Time** | 16 cycles (CORDIC iterations) |
| **Result Readiness** | 1 cycle (OUTPUT_VALID) |
| **Total Latency** | 18 cycles |
| **Ready Assertion** | IDLE and OUTPUT_VALID states |
| **Done Duration** | Exactly 1 cycle |
| **Back-to-Back Support** | Yes (ready in OUTPUT_VALID) |

## References

- Industry Standard: AXI Handshake Protocols
- IEEE 1801: Power Intent Format
- Verification Best Practices: SystemVerilog Assertions
