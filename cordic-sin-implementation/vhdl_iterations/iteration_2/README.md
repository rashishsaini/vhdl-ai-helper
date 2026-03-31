# Iteration 2: Enhanced Done Signal & Handshake Protocol

## Overview
This iteration enhances the synchronization protocol from Iteration 1 by introducing **ready/valid handshake** semantics. This allows:
- Clear input/output handshaking for robust system integration
- Multiple back-to-back operations with proper synchronization
- Production-ready interface following industry-standard protocols

## Key Improvements Over Iteration 1

| Aspect | Iteration 1 | Iteration 2 |
|--------|-----------|-----------|
| Input interface | Simple `start` pulse | `start` + `ready` handshake |
| Output interface | Simple `done` pulse | `done` + `valid` signals |
| Back-to-back ops | Requires wait period | Can be pipelined if ready |
| State clarity | Implicit states | Explicit (IDLE, COMPUTING, OUTPUT_VALID) |
| Integration | Manual timing management | Automatic handshake |

## Architecture

### Enhanced State Machine (cordic_control_v2.vhd)

```
                    ┌──────────────────────────────────┐
                    │                                  │
                    v                                  │
    ┌──────────────────────────────────────────────────────┐
    │ IDLE                                                 │
    │ ready=1, computing=0, done=0, valid=0                │
    └──────────┬───────────────────────────────────────────┘
               │
        start='1' [handshake begins]
               │
               v
    ┌──────────────────────────────────────────────────────┐
    │ COMPUTING (16 cycles)                                │
    │ ready=0, computing=1, done=0, valid=0                │
    │ iteration_idx: 0 → 1 → 2 → ... → 15                 │
    └──────────┬───────────────────────────────────────────┘
               │
        iter_count == 15
               │
               v
    ┌──────────────────────────────────────────────────────┐
    │ OUTPUT_VALID (1 cycle)                               │
    │ ready=1, computing=0, done=1, valid=1                │
    │ Results valid on sin_out/cos_out                     │
    └──────────┬────────────────┬───────────────────────────┘
               │                │
          No start        start='1' [can immediately restart]
               │                │
               └────┬───────────┘
                    v
               Back to IDLE
```

### Ready/Valid Protocol

#### Input Handshake (ready/valid)
```
Definition: start is a request, ready is a grant

Timing: start and ready together = transaction occurs

Semantics:
  - ready='1' → CORDIC ready to accept new angle
  - When start='1' AND ready='1' → angle_in is latched, computation begins
  - When start='0' OR ready='0' → no transaction
```

#### Output Handshake (valid/ready - implicit)
```
Definition: done/valid indicate output is ready, system implicitly accepts

Timing: done='1' for exactly 1 cycle

Semantics:
  - done='1' AND valid='1' → sin_out/cos_out contain valid results
  - After 1 cycle: done='0', results remain in sin_out/cos_out
  - ready immediately becomes '1' for next operation
```

## Timing Diagram

```
         ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐
clk      ┤ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┤
         └──────────────────────────────────────────────┘

         ┌───────────────────────────────────────────────
ready    ┤                               ┌───────────────
         └───────────────────────────────┘

start    ┤   ┌──────┐                     ┌──────────────
         └───┘      └─────────────────────┘

computing┤       ┌──────────────────┐
         └───────┘                  └────────────────────

done     ┤                   ┌───┐           ┌───┐
         └───────────────────┘   └───────────┘   └───────

valid    ┤                   ┌───┐           ┌───┐
         └───────────────────┘   └───────────┘   └───────

sin_out  ┤ ────────────────────[RESULT 1]────────[RESULT 2]
         └───────────────────────────────────────────────

Event 1: start='1' AND ready='1' → angle_in latched, computation begins
Event 2: 17 cycles later → done/valid pulse, results ready
Event 3: ready='1' again → can accept next angle
Event 4: start='1' AND ready='1' → next computation begins
```

## New Component: cordic_control_v2

Enhanced FSM with additional signals:

### Ports
```vhdl
Port (
    clk         : in  std_logic;
    reset       : in  std_logic;
    start       : in  std_logic;      -- Request input (from testbench/system)
    ready       : out std_logic;      -- Grant (CORDIC ready)
    done        : out std_logic;      -- Output ready pulse
    valid       : out std_logic;      -- Output data valid
    computing   : out std_logic;      -- Currently iterating
    iteration_idx : out integer       -- Which iteration (0-15)
);
```

### State Descriptions

**IDLE State**:
- Duration: 1 cycle (or holds if no start)
- Outputs: ready='1', all others '0'
- Entry condition: None (always ready)
- Meaning: Ready to accept new computation request

**COMPUTING State**:
- Duration: 16 cycles
- Outputs: ready='0', computing='1'
- Entry condition: start='1' AND ready='1'
- Meaning: Performing 16 CORDIC iterations
- Action: iteration_idx increments from 0 to 15

**OUTPUT_VALID State**:
- Duration: 1 cycle
- Outputs: ready='1', done='1', valid='1', computing='0'
- Entry condition: iteration_idx reaches 15
- Meaning: Results are ready for consumption
- Action: Can immediately start next computation

## Interface Differences

### Iteration 1 Interface
```vhdl
start     : in  std_logic;     -- Pulse to start
done      : out std_logic;     -- Pulse when done
```

### Iteration 2 Interface
```vhdl
start     : in  std_logic;     -- Request (can hold high)
ready     : out std_logic;     -- Grant (clear when not ready)
done      : out std_logic;     -- 1-cycle pulse (same semantic meaning)
valid     : out std_logic;     -- Output valid flag (same as done)
```

## Usage Example

### Single Operation
```vhdl
-- Operation 1
wait until ready = '1';
start <= '1';
wait for CLK_PERIOD;
start <= '0';

wait until done = '1';
sin_result := sin_out;
cos_result := cos_out;
wait for CLK_PERIOD;
```

### Back-to-Back Operations
```vhdl
-- Operation 1
wait until ready = '1';
angle_in <= angle_1;
start <= '1';
wait for CLK_PERIOD;
start <= '0';

-- While operation 1 is computing, monitor ready
-- Operation 1 will complete in 17 cycles, ready=1 after that

-- Check if ready for operation 2 before operation 1 complete
wait for 10 * CLK_PERIOD;
angle_in <= angle_2;
wait until ready = '1';    -- Waits for operation 1 to finish
start <= '1';
wait for CLK_PERIOD;
start <= '0';

-- Get operation 1 result
wait until done = '1';
sin_result_1 := sin_out;
cos_result_1 := cos_out;
wait for CLK_PERIOD;

-- Get operation 2 result
wait until done = '1';
sin_result_2 := sin_out;
cos_result_2 := cos_out;
```

## Advantages

1. **Clear Semantics**: Ready/valid protocol is industry standard (AXI, Avalon, etc.)
2. **Robust Integration**: Works well with other handshake-based systems
3. **Pipelined Ready**: Can queue next operation while previous completes
4. **Error Prevention**: Handshake prevents data corruption from untimely inputs
5. **Documentation**: Signals explicitly show system state
6. **Testability**: Easy to verify handshake timing with assertions

## Latency & Throughput

### Single Operation Latency
```
Cycle 0:   User asserts start (waits for ready='1')
Cycle 1:   CORDIC latches angle, enters COMPUTING
Cycle 2-17: 16 iterations
Cycle 18:  OUTPUT_VALID, done='1', valid='1'
Cycle 19:  ready='1' again for next operation
```
**Total: 19 cycles from start to next ready**

### Continuous Stream (if operations back-to-back)
```
Operation 1: Cycles 1-17 (COMPUTING)
Operation 2: Cycles 18-34 (next COMPUTING after OUTPUT_VALID)
Result 1: Available at cycle 18
Result 2: Available at cycle 34
Throughput: 1 result per 17 cycles (after initial operation)
```

## Comparison with Iteration 1

| Metric | Iteration 1 | Iteration 2 |
|--------|-----------|-----------|
| Latency | 17 cycles | 19 cycles |
| Component Overhead | None | 1 state added to FSM |
| LUT/Register Count | Same | +1-2 for ready tracking |
| Testbench Complexity | Moderate | Easier (built-in handshake) |
| Production Ready | Mostly | Yes |

## Testing Strategy

The testbench (`tb_cordic_handshake.vhd`) demonstrates:

1. **Basic Operation**: Wait for ready, issue start, wait for done
2. **Back-to-Back**: Queue operations before previous completes
3. **Handshake Timing**: Verify ready/valid pulse timing
4. **Error Prevention**: Show that results are stable on done/valid

### Expected Output
```
=== CORDIC Test (Iteration 2: Handshake Protocol) ===
Testing ready/valid handshake protocol
------------------------------------------------------
TEST 1: Basic Angle Computation
  Angle: 0.000000 → sin: 0.000000 cos: 1.000000
  Angle: 0.392700 → sin: 0.383187 cos: 0.924078
  ...
TEST 2: Back-to-Back Operations
  Operation 0 started (angle: 0.00)
  Operation 1 started (angle: 0.79)
  Operation 2 started (angle: 1.57)
  Waiting for final result...
  Final result: sin: 1.000000 cos: -0.000015
======================================================
Test Complete
```

## Files in This Directory

- `cordic_control_v2.vhd` - Enhanced FSM with ready/valid
- `cordic_lut.vhd` - Same as Iteration 1
- `cordic_datapath.vhd` - Same as Iteration 1
- `cordic_top_v2.vhd` - Top-level with enhanced interface
- `tb_cordic_handshake.vhd` - Testbench demonstrating handshake
- `README.md` - This file

## Verification

All outputs identical to Iteration 0 and 1:
- Same CORDIC algorithm
- Same precision (Q1.15)
- Same 16 iterations
- Only interface protocol enhanced

## Key Learnings

1. **Handshake Protocols**: Essential for system integration
2. **Ready/Valid Standard**: Used in AXI, Avalon, and other standards
3. **Pulse vs. Flag**: done='1' for 1 cycle (pulse) vs. valid='1' until ack
4. **Pipelined Systems**: Understanding ready signal enables true pipelining
5. **Timing Diagrams**: Critical tool for verifying handshake behavior

## Next Step
→ See [Iteration 3](../iteration_3/README.md) for pipelined architecture with continuous throughput

## Design Decision Notes

- **Why ready when OUTPUT_VALID?**: Ready immediately available for next operation
- **Why done AND valid?**: done is pulse, valid persists (both useful semantically)
- **Why 19 cycles total?**: 1 (init) + 16 (compute) + 1 (output) + 1 (ready cycle)
- **Why not 1-cycle initialization?**: Synchronous design requires state register update

## References

- Avalon Memory-Mapped Interface: Altera Ready/Valid Protocol
- AXI Standard: ARM AMBA AXI Handshake Protocol
- CORDIC: See Iteration 0 for algorithm details
