# Iteration 3: Pipelined Architecture

## Overview
This iteration transforms the CORDIC from a **sequential** design to a **pipelined** design. Instead of performing 16 iterations sequentially, all 16 stages are instantiated in parallel, allowing:
- **Continuous throughput**: 1 result per clock cycle (after pipeline fill)
- **Low latency per result**: Each stage processes one iteration
- **High-performance streaming**: Ideal for DSP and signal processing applications

## Key Architecture Changes

### Sequential vs. Pipelined Comparison

**Sequential (Iterations 0-2)**:
```
Input Angle → [Iter 0] → [Iter 1] → ... → [Iter 15] → Output
  1 cycle    1 cycle    1 cycle          1 cycle    17 cycles total

Throughput: 1 result every 17 cycles
```

**Pipelined (Iteration 3)**:
```
[K, 0, θ₀] → [Stage 0] → [Stage 1] → ... → [Stage 15] → (x_N, y_N)
[K, 0, θ₁]    1 cycle      1 cycle          1 cycle     1 result/cycle
[K, 0, θ₂]
```

Throughput: 1 result per cycle (continuous)

## Architecture Components

### cordic_stage.vhd
Single pipeline stage that performs **one CORDIC iteration** with registered inputs/outputs.

**Design**:
- **Input**: x, y, z from previous stage
- **Combinational Logic**: One CORDIC rotation (shift, add/subtract)
- **Output Register**: Results latched at end of cycle
- **Valid Signal**: Propagates through pipeline (tracks data presence)

**Key Feature**: Angle hardcoded per stage (STAGE_NUM parameter)

```vhdl
entity cordic_stage
    Generic (
        STAGE_NUM  : integer;      -- 0 to 15 (which iteration)
        DATA_WIDTH : integer := 16
    );
    Port (
        clk       : in  std_logic;
        x_in, y_in, z_in : in signed;
        valid_in  : in  std_logic;
        x_out, y_out, z_out : out signed;
        valid_out : out std_logic
    );
```

### cordic_pipeline.vhd
Cascade of 16 `cordic_stage` instances connected in series.

**Structure**:
```
Input → Stage[0] → Stage[1] → ... → Stage[15] → Output

Uses generate statement to instantiate all stages:
  stages: for i in 0 to ITERATIONS-1 generate
      stage_inst: cordic_stage ...
  end generate;
```

**Interconnect**:
- Arrays of signals for x, y, z, valid at each stage boundary
- Automatic index progression through pipeline

### cordic_top_pipelined.vhd
Top-level streaming interface.

**Key Points**:
- Initialization every cycle: x=K, y=0, z=angle_in
- Every cycle, one new angle can enter while results exit
- `valid_in` and `valid_out` control data flow

**Interface**:
```vhdl
Port (
    angle_in  : in  std_logic_vector;
    valid_in  : in  std_logic;        -- New angle is valid
    sin_out   : out std_logic_vector;
    cos_out   : out std_logic_vector;
    valid_out : out std_logic;        -- Result is valid
);
```

## Data Flow Through Pipeline

```
CYCLE 0:
  Input: angle₁ (valid_in='1')
  → Stage 0 latches (K, 0, angle₁)
  Valid propagates: valid_out='0' (pipeline filling)

CYCLE 1:
  Input: angle₂ (valid_in='1')
  → Stage 0 processes angle₂, Stage 1 processes results from angle₁
  Valid still '0'

CYCLE 2-15:
  Angles 3-16 enter
  Pipeline fills further, valid_out still '0'

CYCLE 16:
  Input: angle₁₇ (if available)
  → Stage 15 outputs first result (from angle₁)
  valid_out='1' (first result ready!)

CYCLE 17:
  Input: angle₁₈
  → Stage 0-15: angle₁₈ → ... → result(angle₂)
  valid_out='1' (second result ready)

CYCLE 18+:
  Continuous: 1 new result per cycle
  Throughput = 1 result/cycle
```

## Latency Analysis

### First Result Latency
```
Cycle 0: Input angle₁
Cycle 16: Output result(angle₁)
Latency = 16 cycles (pipeline depth = ITERATIONS)
```

### Sustained Latency
After first result emerges, results appear every cycle with 16-cycle delay:
- Input angle at cycle N
- Result available at cycle N+16

## Throughput Analysis

### vs. Sequential Design
```
Sequential:
  Throughput = 1 result / 17 cycles = 0.059 results/cycle

Pipelined:
  Throughput = 1 result / 1 cycle = 1.0 results/cycle

Speedup = 17× for continuous operation
```

### Practical Example
Computing 100 angles:

**Sequential**:
- Time = 100 × 17 cycles = 1700 cycles

**Pipelined**:
- Pipeline fill: 16 cycles
- Output 100 results: 100 cycles
- Total: ~116 cycles
- **Speedup: 14.7×**

## Resource Utilization

### Memory
```
LUTs: 16 instances of cordic_stage
  Each stage contains:
  - Shifter logic
  - Adder/subtractor
  - AND gate for sign check
  Total: ~100-150 LUTs per stage

Pipelined total: ~1600-2400 LUTs
Sequential total: ~100-150 LUTs
Overhead: ~10-16× more logic
```

### Registers
```
Each stage registers x, y, z (3×16 bits) + valid (1 bit)
Registers per stage: 49 bits
Total for 16 stages: 784 bits (~98 bytes)

Sequential: ~49 bits
Overhead: ~16× more registers
```

### Multipliers
**Zero** (same as sequential - CORDIC advantage maintained)

## Valid Signal Propagation

The `valid` signal flows through pipeline indicating data presence:

```
Cycle 0: Input valid → Stage 0 valid_out
Cycle 1: Stage 0 valid → Stage 1 valid_out
...
Cycle 16: Stage 15 valid_out → Result output valid

This creates a "wave" of valid signals through pipeline
```

## Input/Output Interface

### Streaming Input
```
Every cycle, user can provide new angle:
  angle_in <= new_angle;
  valid_in <= '1';
  wait for CLK_PERIOD;
```

### Streaming Output
```
Every cycle (after fill), system produces result:
  if valid_out = '1' then
    read sin_out, cos_out;
  end if;
  wait for CLK_PERIOD;
```

### Back-Pressure Handling
```
If system can't accept results fast enough:
  - No ready signal in this basic design
  - Results continuously stream out
  - External system must buffer/manage flow

Enhanced version could add ready handshake:
  if ready_in = '1' and valid_out = '1' then
    [result accepted]
  end if;
```

## Comparison with Iterations 0-2

| Metric | Iter 0-1 | Iter 2 | Iter 3 |
|--------|----------|--------|---------|
| Architecture | Sequential | Sequential + Handshake | Pipelined |
| Latency | 17 cycles | 19 cycles | 16 cycles |
| Throughput | 0.059 res/cy | 0.053 res/cy | 1.0 res/cy |
| Registers | ~49 bits | ~49 bits | ~784 bits |
| LUTs | ~100-150 | ~100-150 | ~1600-2400 |
| Ideal Use | Low throughput | Integration | High throughput |

## Timing Characteristics

### Clock Speed
- Each stage is combinational + register
- Critical path = 1 CORDIC iteration logic
- Should meet same clock as sequential versions
- No additional timing constraints

### Setup/Hold
- Pipelined stages have local setup/hold
- No cross-stage critical paths
- Easier to close timing in FPGA

## Testing

The testbench demonstrates:
1. Multiple angles input in succession
2. Pipeline filling (no output initially)
3. First result emerging after 16 cycles
4. Continuous results thereafter
5. Valid signal propagation

### Expected Output
```
=== CORDIC Pipelined Test ===
Inputting 5 angles in succession...
Cycle 0: Input angle = 0.0000
Cycle 1: Input angle = 0.7854
Cycle 2: Input angle = 1.5708
Cycle 3: Input angle = 2.3562
Cycle 4: Input angle = 3.1416

Waiting for results...
Cycle 16: Output valid - sin: 0.0000 cos: 1.0000
Cycle 17: Output valid - sin: 0.7071 cos: 0.7071
Cycle 18: Output valid - sin: 1.0000 cos: 0.0000
Cycle 19: Output valid - sin: 0.7071 cos: -0.7071
Cycle 20: Output valid - sin: 0.0000 cos: -1.0000
```

## Design Decisions

### Why STAGE_NUM Parameter?
- Each stage needs different angle (arctan(2^-i))
- Hardcoded per stage avoids multiplexer overhead
- Simple, efficient synthesis

### Why Valid Propagation?
- Tracks data presence through pipeline
- Allows variable latency designs
- Needed for back-pressure/ready signals
- Standard in streaming protocols (AXI, Avalon)

### Why No Ready Input?
- This is basic streaming
- Enhancement: Add ready handshake for flow control
- Current design: System must manage output buffering

### Why Continuous Initialization?
- Every cycle: x=K, y=0, z=angle_in
- Enables one new angle per cycle
- No need to wait or gate angle_in

## Performance Improvement Path

### Current Iteration 3
- Throughput: 1 result/cycle
- Latency: 16 cycles

### Future Enhancements
1. **Unrolled Initialization** (2 more stages in series)
   - Overlap angle load with first iteration
   - Reduce latency to ~14 cycles

2. **Ready Handshake** (add back-pressure)
   - Flow control: only compute when output ready
   - Reduces unnecessary computation

3. **Wider Pipeline** (multiple parallel pipelines)
   - Process multiple angles simultaneously
   - Throughput: N results/cycle
   - Trade: N× area

4. **SIMD/Super-scalar** (parallel path expansion)
   - Multiple shifts/adds in parallel
   - Reduce iteration count
   - Higher clock frequency requirement

## Applications

### Ideal For
- Real-time signal processing (continuous sine/cosine)
- CORDIC-based coordinate transforms at high sample rate
- Phase modulation/demodulation
- DDS (Direct Digital Synthesis)
- Radar/Sonar signal processing

### Not Ideal For
- Single angle computation
- Ultra-low latency requirement (<16 cycles)
- Extreme resource constraints
- Irregular input pattern (mostly valid_in='0')

## Files in This Directory

- `cordic_stage.vhd` - Single pipeline stage
- `cordic_pipeline.vhd` - 16-stage pipeline cascade
- `cordic_top_pipelined.vhd` - Top-level streaming interface
- `tb_cordic_pipeline.vhd` - Streaming testbench
- `README.md` - This file

## Verification

Output values identical to sequential versions (same algorithm, different timing):
- sin(0°) ≈ 0.0000, cos(0°) ≈ 1.0000
- sin(90°) ≈ 1.0000, cos(90°) ≈ 0.0000
- sin(180°) ≈ 0.0000, cos(180°) ≈ -1.0000

## Key Learning Points

1. **Pipeline Principles**: Breaking computation into stages for parallelism
2. **Throughput vs. Latency**: Pipelining trades latency for throughput
3. **Valid Signals**: Critical for streaming/pipelined designs
4. **Resource Trade-offs**: More area for better performance
5. **Critical Path**: Simplified in pipelined designs
6. **Scalability**: Can extend to wider pipelines or more stages

## References

- Pipeline architecture: Computer Organization & Design (Patterson & Hennessy)
- CORDIC algorithm: See Iteration 0
- Streaming protocols: AXI Stream, Avalon Streaming
- DSP pipelining: FPGA signal processing best practices

## Summary

**Iteration 3** demonstrates the transformation from **sequential** to **pipelined** processing. The same fundamental CORDIC algorithm achieves **17× throughput improvement** by exploiting parallelism across iterations. This is achieved by instantiating all stages in hardware—a feasible approach for fixed 16-iteration CORDIC, but a design trade-off in terms of area utilization.

The pipelined design is the architecture of choice for **high-performance, streaming applications** where continuous data flow is expected.
