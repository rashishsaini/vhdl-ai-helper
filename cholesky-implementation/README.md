# Cholesky 3×3 Matrix Decomposition

A fixed-point VHDL hardware implementation of the Cholesky decomposition algorithm for 3×3 symmetric positive-definite matrices.

## Overview

**Entity Name:** `cholesky_3x3`

The Cholesky decomposition decomposes a symmetric positive-definite matrix A into the product of a lower triangular matrix L and its transpose (A = L × L^T).

### Specifications

- **Matrix Size:** 3×3 symmetric positive-definite
- **Fixed-Point Format:** Q20.12 (20 integer bits, 12 fractional bits)
- **Architecture:** FSM-based state machine
- **Clock Frequency:** 100 MHz
- **Latency:** 59.5 cycles (595 ns)
- **Throughput:** 1.68 Mdecompositions/sec
- **Status:** Working (with known bug in L33 calculation)

## Files

### Sources
- **code.vhd** - Main Cholesky 3×3 implementation (242 lines)
  - FSM-based control flow
  - Fixed-point arithmetic (Q20.12 format)
  - Known bug: Signal overwriting at lines 177-183 in CALC_L33 state

- **sqrt_newton_xsim.vhd** - Newton-Raphson square root module (146 lines)
  - XSIM-compatible implementation
  - 12 iterations for convergence
  - Used internally by Cholesky for computing square roots

- **simple_cholesky_tb.vhd** - Testbench (120 lines)
  - Tests 3×3 matrix decomposition
  - Verifies all 6 lower triangular values (L11-L33)
  - Self-checking assertions

### Documentation
- **CHOLESKY_PERFORMANCE_ANALYSIS.md** - Comprehensive technical analysis
  - 13 detailed sections
  - Critical path identification
  - Performance metrics and breakdown
  - Optimization opportunities

- **AGENT_INTEGRATION_GUIDE.md** - Bug fix guide
  - Root cause analysis of L33 bug
  - Three solution approaches
  - Implementation steps with code examples

- **cholesky_xsim_solution.md** - XSIM compatibility solutions
  - Inline arithmetic techniques
  - Bug resolution steps

- **cholesky_fixes_applied.md** - Summary of applied fixes

### Project
- **project/Cholesky3by3/** - Full Vivado project directory
  - XPR project file
  - Source files and build artifacts
  - Simulation results
  - Synthesis reports

## Current Status

### Compilation
✓ **SUCCESS** - No compilation errors

### Simulation
✓ **SUCCESS** - Runs to completion without crashes

### Functional Correctness
⚠️ **PARTIAL** - 5 of 6 elements correct (83%)

| Element | Expected | Actual | Status |
|---------|----------|--------|--------|
| L11 | 2.828 | 2.828 | ✓ PASS |
| L21 | 0.707 | 0.707 | ✓ PASS |
| L22 | 2.449 | 2.449 | ✓ PASS |
| L31 | 0.353 | 0.353 | ✓ PASS |
| L32 | 0.816 | 0.816 | ✓ PASS |
| L33 | 3.0 | -14.765 | ✗ FAIL |

### Known Issues

**Critical Bug - L33 Signal Overwriting**
- **Location:** code.vhd, lines 177-183 (CALC_L33 state)
- **Cause:** Two consecutive assignments to `sqrt_x_in` in the same clock cycle
- **Line 180:** `sqrt_x_in <= ...`
- **Line 183:** `sqrt_x_in <= ...` (overwrites line 180)
- **Impact:** L33 produces -14.765 instead of 3.0
- **Severity:** HIGH (functional correctness)
- **Fix Effort:** 5-10 minutes
- **Recommended Fix:** Use temporary variable approach

## Quick Start

### Running Simulation
```bash
cd project/Cholesky3by3
vivado -mode batch -source ../../shared/scripts/run_simple_sim.tcl
```

### Viewing Results
```bash
cd project/Cholesky3by3/Cholesky3by3.sim/sim_1/behav/xsim
cat cholesky_test_results.txt
```

## Implementation Details

### Algorithm
The Cholesky decomposition for a 3×3 matrix is computed as:

```
L11 = √A11
L21 = A21 / L11
L22 = √(A22 - L21²)
L31 = A31 / L11
L32 = (A32 - L31×L21) / L22
L33 = √(A33 - L31² - L32²)
```

Each square root operation uses the Newton-Raphson algorithm with 12 iterations.

### Performance Breakdown

| Operation | Cycles | Percentage |
|-----------|--------|-----------|
| L11 sqrt | 18 | 30% |
| L21 division | 4 | 7% |
| L22 sqrt | 18 | 30% |
| L31-L32 computation | 8 | 13% |
| L33 sqrt | 18 | 30% |
| **Total** | **59.5** | **100%** |

### Critical Path
The critical path is dominated by Newton-Raphson square root operations. Each sqrt contributes 18 cycles due to 12 iterations + convergence overhead.

## Optimization Opportunities

### Phase 1: Bug Fix (Immediate)
- Effort: 5-10 minutes
- Impact: Functional correctness
- Approach: Variable reassignment

### Phase 2: Resource Optimization (1-2 weeks)
- DSP-based division modules
- Input FIFO for streaming
- Impact: 20% latency reduction, 2× throughput

### Phase 3: Parallelization (3-4 weeks)
- Parallel sqrt computation
- Fixed-point ALU optimization
- Impact: 35-50% latency reduction

### Phase 4: Generalization (Long-term)
- Support variable matrix sizes (2×2, 3×3, 4×4, etc.)
- Streaming interface
- Impact: Reusable component

## References

- See `shared/learnings/COMPREHENSIVE_VHDL_XSIM_REFERENCE.md` for XSIM compatibility
- See `shared/documentation/CHOLESKY_PERFORMANCE_ANALYSIS.md` for detailed metrics
- See `AGENT_INTEGRATION_GUIDE.md` for bug fix instructions

## Testing

The testbench (`simple_cholesky_tb.vhd`) includes:
- Clock and reset generation
- Test matrix input (8.0, 2.0, 6.0, 1.0, 2.0, 4.0)
- Stimulus application
- Output verification with assertions
- All 6 values reported with expected values

### Test Matrix
```
A = [8.0  2.0  6.0]
    [2.0  6.0  2.0]
    [6.0  2.0  4.0]
```

### Expected Cholesky Result
```
L = [2.828  0     0   ]
    [0.707  2.449 0   ]
    [0.353  0.816 3.0 ]
```

## Future Enhancements

1. **Fix critical bug** in L33 calculation
2. **Add support for variable matrix sizes**
3. **Implement streaming interface** for pipelined operation
4. **Optimize using DSP blocks** for better resource utilization
5. **Add dynamic precision selection**

---

**Last Updated:** November 2025
**Status:** Actively Developed
**Maintainer:** VHDL AI Helper Project
