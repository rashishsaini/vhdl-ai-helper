# basic-math-fpga

A reusable VHDL library of basic mathematical and ML-oriented hardware blocks for FPGA design.

## Goal
Build a structured set of synthesizable math blocks starting from core arithmetic and scaling up to vector, matrix, ML, and control-system modules.

## Repository Layout
- `rtl/` — synthesizable VHDL modules
- `tb/` — testbenches for simulation
- `examples/` — small demo designs
- `docs/` — design notes, block specs, and diagrams
- `scripts/` — simulation and synthesis scripts
- `sim/` — waveform and log outputs

## Build Philosophy
All higher-level blocks should be built from reusable primitives:
- adder
- subtractor
- comparator
- shifter
- register
- accumulator
- multiplier
- divider
- square root

## Implementation Order
1. Fixed-point package
2. Full adder
3. N-bit adder
4. Subtractor
5. Comparator
6. Shifter
7. Multiplier
8. Divider
9. Square root
10. MAC unit
11. Dot product
12. Matrix operations
13. CORDIC
14. ML blocks
15. Control-system blocks

## Design Rules
- Use `numeric_std`
- Keep modules parameterized by bit width
- Prefer fixed-point over floating-point
- Add a testbench for every block
- Document latency and assumptions for each module

## Status
This repository is under active development.