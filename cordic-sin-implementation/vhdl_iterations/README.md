# CORDIC Algorithm Implementation Iterations

This directory contains progressive refinements of the CORDIC (COordinate Rotation DIgital Computer) module, demonstrating the evolution from monolithic design to fully modular architecture.

## Overview

Each iteration builds upon previous learnings, introducing better modularity, cleaner interfaces, and enhanced signaling protocols. The fundamental CORDIC algorithm remains the same, but the architectural approach becomes increasingly sophisticated.

## Iteration Structure

### [iteration_0/](./iteration_0/README.md) - Monolithic Baseline
**Status**: Baseline implementation
- Single monolithic module: `cordic_processor`
- All logic in one entity (LUT, datapath, control)
- Working done signal but tightly coupled
- Fixed 16 iterations, 16-bit data width
- **Purpose**: Establishes correct algorithm behavior

**Key Files**:
- `cordic_processor.vhd` - Monolithic CORDIC implementation
- `tb_cordic.vhd` - Basic testbench
- `README.md` - Detailed explanation of baseline

---

### [iteration_1/](./iteration_1/README.md) - Component Separation
**Status**: Modular design with 3 primary components
- Separation of concerns: LUT, Datapath, Control
- Clean component interfaces with well-defined signals
- Improved maintainability and testability
- Ready for reuse in different architectures
- **Purpose**: Demonstrate modularity benefits

**Key Files**:
- `cordic_lut.vhd` - Angle lookup table (read-only component)
- `cordic_datapath.vhd` - Rotation logic (shift, add/subtract operations)
- `cordic_control.vhd` - Iteration control and state machine
- `cordic_top.vhd` - Top-level integration
- `tb_cordic_modular.vhd` - Testbench for modular design
- `README.md` - Architecture explanation, interface definitions

**Key Improvements**:
- Each module has single responsibility
- Easier to test individual components
- Interfaces clearly defined with full signal documentation

---

### [iteration_2/](./iteration_2/README.md) - Enhanced Done Signal & Handshake
**Status**: Advanced synchronization with ready/valid protocol
- Refined done signal semantics and timing
- Introduction of ready/valid handshake interface
- Support for pipelined input (back-to-back operations)
- Improved testbench with wait utilities
- **Purpose**: Production-ready synchronization protocol

**Key Files**:
- `cordic_lut.vhd` - Enhanced LUT with registered outputs
- `cordic_datapath.vhd` - Unchanged from iteration_1
- `cordic_control.vhd` - Enhanced with ready/valid signals
- `cordic_top.vhd` - Top-level with handshake protocol
- `tb_cordic_done_signals.vhd` - Advanced testbench with timing verification
- `README.md` - Timing diagrams, handshake protocol explanation

**Key Improvements**:
- Ready/valid protocol for proper handshaking
- Multiple operations can be queued
- Done signal timing characteristics documented
- Example: back-to-back angle computations

---

### [iteration_3/](./iteration_3/README.md) - Pipelined Architecture
**Status**: Continuous streaming throughput
- Pipeline stages for parallel processing
- Configurable pipeline depth (PIPELINE_STAGES)
- High throughput after initial latency
- Suitable for continuous streaming applications
- **Purpose**: Demonstrate alternative high-performance architecture

**Key Files**:
- `cordic_stage.vhd` - Single pipeline stage (one CORDIC iteration)
- `cordic_pipeline.vhd` - Multi-stage pipeline assembly
- `cordic_top_pipelined.vhd` - Top-level pipelined interface
- `tb_cordic_pipeline.vhd` - Testbench comparing throughput
- `README.md` - Pipeline architecture, latency/throughput analysis

**Key Improvements**:
- One result per cycle after pipeline fill
- Latency = ITERATIONS cycles
- Throughput = 1 result/cycle (after fill)
- Trade-off: Area vs speed

---

## Algorithm Verification

All iterations compute identical trigonometric values using the same CORDIC algorithm. Test vectors are consistent across iterations to verify equivalence.

**Test Angles**:
```
0 to π radians in π/8 increments
(9 test points: 0, π/8, π/4, 3π/8, π/2, 5π/8, 3π/4, 7π/8, π)
```

**Accuracy**:
- Q1.15 fixed-point format (16-bit)
- ±0.0015 maximum error (typical)
- Error decreases with more iterations

---

## Performance Comparison

| Iteration | Latency | Throughput | Area | Done Signal |
|-----------|---------|------------|------|-------------|
| 0 | 16 cycles | 1 in / 16 out | Minimal | Basic |
| 1 | 16 cycles | 1 in / 16 out | Small | Basic |
| 2 | 16 cycles | 1 in / 16 out | Small | Enhanced |
| 3 | 17 cycles | 1 result/cycle | Larger | Stream-based |

---

## How to Use Each Iteration

### Testing an Iteration
```bash
# Navigate to iteration directory
cd iteration_X

# Run Vivado simulation (example for iteration_0)
vivado -mode batch -source run_simulation.tcl

# Or examine VHDL files directly in your editor
```

### Choosing an Iteration for Your Project

- **Learning CORDIC**: Start with `iteration_0` - simple, clear
- **Production (low latency)**: Use `iteration_1` or `iteration_2`
- **Production (streaming)**: Use `iteration_3`
- **Understanding Modularity**: Compare `iteration_0` vs `iteration_1`
- **Understanding Pipelining**: Study `iteration_3`

---

## Key Lessons Across Iterations

1. **Iteration 0→1**: Modularity enables reuse and testing
2. **Iteration 1→2**: Handshake protocols enable robust interfaces
3. **Iteration 2→3**: Pipelining trades area for throughput
4. **All Iterations**: Algorithm correctness is preserved through refactoring

---

## Fixed-Point Format

All iterations use **Q1.15 fixed-point** representation:
- 1 sign bit + 15 fractional bits = 16 bits total
- Range: -1.0 to 0.99997
- Resolution: ~0.000030
- K constant (CORDIC scaling): 0.60725 fixed-point

---

## Next Steps

1. Review `iteration_0/README.md` for algorithm understanding
2. Compare `iteration_0` and `iteration_1` VHDL files side-by-side
3. Study `iteration_2` for production synchronization patterns
4. Analyze `iteration_3` for high-performance requirements

Each README provides detailed technical explanation and timing diagrams where relevant.
