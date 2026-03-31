# VHDL Neural Network Project - Verified Modules & Debugging Patterns

## Project Overview
Neural network hardware implementation in VHDL using Q2.13 fixed-point format.

---

## Verified Modules

### mac_unit.vhd (2025-11-27)
**Status**: Fully functional - No fixes required

**Design Characteristics**:
- 2-stage pipelined multiply-accumulate unit
- Stage 1: Multiplication (registered)
- Stage 2: Accumulation with saturation (registered)
- Format: Q2.13 (16-bit) inputs -> Q4.26 (32-bit) product -> Q10.26 (40-bit) accumulator

**Generics**:
- `DATA_WIDTH`: Input/weight width (default 16)
- `PRODUCT_WIDTH`: Multiplication result width (default 32)
- `ACCUM_WIDTH`: Accumulator width (default 40)
- `ENABLE_SAT`: Enable saturation logic (default true)

**Ports**:
- `clk`, `rst`, `clear`, `enable`: Control signals
- `data_in`, `weight`: Signed inputs
- `accum_out`: Accumulated result
- `valid`, `overflow`, `busy`: Status outputs

**Verification**:
- Compiled with GHDL (VHDL-2008)
- 13/13 testbench tests passed
- Tests covered: reset, single MAC, dot product, clear, negative values, mixed signs, zero handling, multiple sequential MACs

**Key Implementation Notes**:
- Overflow detection uses sign bit comparison: `sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1)`
- Saturation clamps to max positive or min negative on overflow
- Pipeline delay of 2 clock cycles from input to valid output
- `clear` signal propagates through pipeline via `clear_d1`

---

### vector_accumulator.vhd (2025-11-28)
**Status**: Fully functional - No fixes required

**Design Characteristics**:
- FSM-based vector accumulator for summing multiple elements
- States: IDLE -> ACCUM -> DONE_ST
- Format: Q2.13 (16-bit) inputs -> Q10.26 (40-bit) accumulator
- Streaming interface with valid/ready handshaking

**Generics**:
- `DATA_WIDTH`: Input element width (default 16)
- `ACCUM_WIDTH`: Accumulator width (default 40)
- `FRAC_BITS`: Input fractional bits (default 13)
- `MAX_ELEMENTS`: Maximum vector length (default 16)
- `ENABLE_SAT`: Enable saturation logic (default true)

**Ports**:
- `clk`, `rst`, `start`, `clear`: Control signals
- `num_elements`: Number of elements to accumulate
- `data_in`, `data_valid`, `data_ready`: Input streaming interface
- `accum_out`, `result_valid`, `out_ready`: Output handshaking interface
- `busy`, `done`, `overflow`, `elem_count`: Status outputs

**Verification**:
- Compiled with GHDL (VHDL-2008)
- Compiled with Vivado XVHDL (2025.1)
- Elaborated with XELAB
- 11/11 testbench tests passed (both GHDL and XSIM)

**Tests Covered**:
1. Single element accumulation
2. Multiple same values (4x0.5 = 2.0)
3. Mixed positive/negative values
4. Zero elements (immediate completion)
5. Clear during accumulation
6. Element count tracking
7. Busy signal behavior
8. Larger vector (8 elements)
9. Output ready handshaking
10. Reset behavior

**Key Implementation Notes**:
- Uses `resize()` for sign extension to accumulator width
- Overflow detection: `sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1)`
- Saturation clamps to MAX_ACCUM or MIN_ACCUM on overflow
- Zero elements case transitions directly to DONE_ST
- Holds result in DONE_ST until `out_ready` is asserted

**Use Cases**:
- Batch normalization (computing mean)
- Loss aggregation across samples
- Feature aggregation in neural networks
- Gradient accumulation across mini-batches

---

### delta_calculator.vhd (2025-11-28)
**Status**: Fully functional - No fixes required

**Design Characteristics**:
- Computes delta for backpropagation: delta = error x sigma'(z)
- Uses ReLU derivative: sigma'(z) = 1 if z > 0, else 0
- Optional output register for timing closure (REGISTERED generic)
- Format: Q2.13 (16-bit signed fixed-point)

**Generics**:
- `DATA_WIDTH`: Data width (default 16)
- `FRAC_BITS`: Fractional bits (default 13)
- `REGISTERED`: Enable output register (default true)

**Ports**:
- `clk`, `rst`: Clock and reset (used when REGISTERED=true)
- `error_in`: Error signal from error_calculator or error_propagator
- `z_in`: Pre-activation value from forward_cache
- `enable`: Enable computation
- `delta_out`: Computed delta value
- `valid`, `is_active`, `zero_delta`: Status outputs

**Dependencies**:
- `activation_derivative_unit`: Computes ReLU derivative (combinational)

**Verification**:
- Compiled with GHDL (VHDL-2008)
- 24/24 testbench tests passed
- Tests covered: active neurons (z>0), inactive neurons (z<=0), boundary cases, zero delta flag, valid signal behavior, reset behavior, fractional values

**Key Implementation Notes**:
- Full Q2.13 x Q2.13 multiplication produces Q4.26 result
- Scaling back to Q2.13 includes rounding (add 0.5 LSB before shift)
- Saturation prevents overflow: clamps to +/-32767/32768
- ReLU optimization: since derivative is 0 or 1, delta = error (active) or 0 (inactive)
- `is_active` flag indicates neuron was in active region (z > 0)
- `zero_delta` flag indicates delta is exactly zero

**Latency**:
- REGISTERED=true: 1 clock cycle
- REGISTERED=false: Combinational (0 cycles)

---

### activation_derivative_unit.vhd (2025-11-28)
**Status**: Fully functional - No fixes required

**Design Characteristics**:
- Pure combinational logic (no clock required)
- Computes ReLU derivative: sigma'(z) = 1 if z > 0, else 0
- Format: Q2.13 (16-bit signed fixed-point)

**Ports**:
- `z_in`: Pre-activation input
- `derivative`: Output (1.0 or 0.0 in Q2.13)
- `is_active`: Status flag ('1' if z > 0)

**Key Implementation Notes**:
- ONE constant = 8192 (2^13 = 1.0 in Q2.13)
- Active detection: sign bit = '0' AND value != 0
- At z = 0, derivative = 0 (subgradient convention)

---

## Fixed-Point Format Reference

| Type | Width | Format | Range |
|------|-------|--------|-------|
| Data/Weight | 16-bit | Q2.13 | +/-3.999... |
| Product | 32-bit | Q4.26 | +/-7.999... |
| Accumulator | 40-bit | Q10.26 | +/-511.999... |

**Conversion**: `FX_ONE = 8192` (2^13 = 1.0 in Q2.13)

---

## Testing Commands

```bash
# Analyze and elaborate
ghdl -a --std=08 mac_unit.vhd
ghdl -a --std=08 mac_unit_tb.vhd
ghdl -e --std=08 mac_unit_tb

# Run simulation
ghdl -r --std=08 mac_unit_tb --stop-time=10us
```

---

## Common Patterns

### Saturation Logic
```vhdl
if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
    -- Overflow detected
    if sum(ACCUM_WIDTH) = '0' then
        -- Positive overflow -> clamp to max positive
    else
        -- Negative overflow -> clamp to max negative
    end if;
end if;
```

### Sign Extension for Accumulation
```vhdl
product_ext := resize(mult_result, ACCUM_WIDTH);
sum := resize(accum_reg, ACCUM_WIDTH+1) + resize(product_ext, ACCUM_WIDTH+1);
```

---

### weight_updater.vhd (2025-11-28)
**Status**: Fully functional - No fixes required

**Design Characteristics**:
- 4-stage pipelined SGD weight update unit
- Stage 1: Input capture (registered)
- Stage 2: Multiply learning_rate x gradient (registered)
- Stage 3: Scale product and subtract from weight (registered)
- Stage 4: Saturation and output (registered)
- Format: Q2.13 (16-bit) weights, Q10.26 (40-bit) gradients

**Formula**: `W(t+1) = W(t) - lr x dL/dW`

**Generics**:
- `DATA_WIDTH`: Weight width (default 16, Q2.13)
- `GRAD_WIDTH`: Gradient width (default 40, Q10.26)
- `FRAC_BITS`: Fractional bits in weights (default 13)
- `GRAD_FRAC_BITS`: Fractional bits in gradients (default 26)
- `DEFAULT_LR`: Default learning rate (default 82 = 0.01 in Q2.13)

**Ports**:
- `clk`, `rst`: Clock and reset
- `learning_rate`: Signed Q2.13 learning rate input
- `weight_in`: Current weight (signed Q2.13)
- `gradient_in`: Gradient from backprop (signed Q10.26)
- `enable`: Start update computation
- `weight_out`: Updated weight (signed Q2.13)
- `valid`, `overflow`, `done`: Status outputs

**Verification**:
- Compiled with GHDL (VHDL-2008)
- 17/17 testbench tests passed
- Tests covered:
  - Basic SGD updates (4 tests)
  - Negative gradients / weight increase (2 tests)
  - Zero gradient / no change (2 tests)
  - Large learning rate (2 tests)
  - Saturation cases (2 tests)
  - Small updates / precision (2 tests)
  - Pipeline behavior (2 tests)
  - Reset behavior (1 test)

**Key Implementation Notes**:
- Full precision multiplication: Q2.13 x Q10.26 = Q12.39
- Scaling: shift right by 26 bits to convert back to Q2.13
- Rounding: adds 2^(SCALE_SHIFT-1) before shift for proper rounding
- Saturation: clamps to SAT_MAX (+32767) or SAT_MIN (-32768) on overflow
- Pipeline delay: 4 clock cycles from enable to valid output

**Learning Rate Reference**:

| Value | Q2.13 Representation |
|-------|---------------------|
| 0.01  | 82                  |
| 0.1   | 819                 |
| 1.0   | 8192                |

**Gradient Format Reference**:

| Value | Q10.26 Representation |
|-------|----------------------|
| 1.0   | 67108864 (2^26)      |
| 0.5   | 33554432             |
| -1.0  | -67108864            |

---

### error_propagator.vhd (2025-11-28)
**Status**: Fully functional - No fixes required

**Design Characteristics**:
- FSM-based backpropagation unit for neural networks
- Computes: delta[l-1] = (W[l]^T x delta[l]) * sigma'(z[l-1])
- States: IDLE -> LOAD_Z -> ACCUMULATE -> APPLY_DERIV -> OUTPUT_DELTA -> NEXT_NEURON -> DONE_ST
- Format: Q2.13 (16-bit) inputs -> Q10.26 (40-bit) accumulator
- Streaming interface with valid/ready handshaking for weights, deltas, and z-values

**Generics**:
- `DATA_WIDTH`: Input width (default 16, Q2.13)
- `ACCUM_WIDTH`: Accumulator width (default 40, Q10.26)
- `FRAC_BITS`: Fractional bits (default 13)
- `MAX_NEURONS`: Max neurons in target layer (default 8)
- `MAX_DELTAS`: Max deltas from source layer (default 8)

**Ports**:
- `clk`, `rst`, `start`, `clear`: Control signals
- `num_neurons`, `num_deltas`: Layer configuration
- `weight_in`, `weight_valid`, `weight_ready`: Weight streaming interface
- `delta_in`, `delta_valid`, `delta_ready`: Input delta streaming interface
- `z_in`, `z_valid`, `z_ready`: Pre-activation value interface
- `delta_out`, `delta_out_valid`, `delta_out_ready`: Output delta interface
- `neuron_index`: Current neuron being processed
- `busy`, `done`, `overflow`: Status outputs

**Verification**:
- Compiled with GHDL (VHDL-2008)
- Compiled with Vivado XVHDL (2025.1)
- Elaborated with XELAB
- 11/11 testbench tests passed (both GHDL and XSIM)

**Tests Covered**:
1. Single neuron, active (z > 0): delta = W x delta_in x 1 = 0.5
2. Single neuron, inactive (z <= 0): delta = W x delta_in x 0 = 0
3. Two neurons, one delta (output->hidden propagation)
4. One neuron, two deltas (multi-source accumulation): delta = (W0xdelta0 + W1xdelta1) x sigma'(z) = 0.625
5. Negative weights and deltas: (-0.5) x (-1.0) = 0.5
6. Zero neurons (immediate completion)
7. Zero deltas (output is zero)
8. Output ready handshaking (holds output until accepted)
9. Clear during operation
10. Reset behavior

**Key Implementation Notes**:
- Uses ReLU derivative: sigma'(z) = 1 if z > 0, else 0
- Weighted sum accumulation: Sum(W[i,j] x delta[j])
- Sign extension via `resize()` for accumulation
- Overflow detection: `sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1)`
- Saturation clamps to MAX_ACCUM or MIN_ACCUM on overflow
- Proper rounding when scaling from Q4.26 to Q2.13
- Processes neurons sequentially, accumulating all deltas per neuron

**Operation Sequence**:
1. Start -> Load z value for neuron 0
2. Compute ReLU derivative from z
3. Accumulate all (weight x delta) products
4. Scale and multiply by activation derivative
5. Output propagated delta
6. Repeat for remaining neurons
7. Done when all neurons processed

**Use Cases**:
- Backpropagation through hidden layers
- Computing delta for weight gradient calculation
- Multi-layer neural network training

---

### gradient_calculator.vhd (2025-11-28)
**Status**: Fully functional - No fixes required

**Design Characteristics**:
- FSM-based weight gradient calculator for backpropagation
- Computes: dL/dW[i,j] = delta[j] x a[i]
- States: IDLE -> LOAD_DELTA -> COMPUTE_GRAD -> OUTPUT_GRAD -> DONE_ST
- Format: Q2.13 (16-bit) x Q2.13 -> Q4.26 (32-bit) gradient
- Streaming interface with valid/ready handshaking

**Generics**:
- `DATA_WIDTH`: Input width (default 16, Q2.13)
- `PRODUCT_WIDTH`: Gradient width (default 32, Q4.26)
- `FRAC_BITS`: Fractional bits (default 13)
- `MAX_INPUTS`: Maximum inputs per neuron (default 8)

**Ports**:
- `clk`, `rst`, `start`, `clear`: Control signals
- `num_inputs`: Number of input activations to process
- `delta_in`, `delta_valid`, `delta_ready`: Delta streaming interface
- `activation_in`, `act_valid`, `act_ready`: Activation streaming interface
- `gradient_out`, `grad_valid`, `grad_ready`: Gradient output interface
- `grad_index`: Index of current weight gradient
- `bias_grad_out`, `bias_valid`: Bias gradient output (delta itself)
- `busy`, `done`, `grad_count`: Status outputs

**Verification**:
- Compiled with GHDL (VHDL-2008)
- Compiled with Vivado XVHDL (2025.1)
- Elaborated with XELAB
- 10/10 testbench tests passed (both GHDL and XSIM)

**Tests Covered**:
1. Single input (delta=1.0, a=0.5 -> grad=0.5)
2. Bias gradient equals delta
3. Four inputs with mixed values
4. Zero delta produces zero gradients
5. Negative delta handling
6. Zero inputs (immediate completion)
7. Grad ready handshaking (holds until accepted)
8. Grad ready handshaking (proceeds after accept)
9. Clear during operation
10. Reset behavior

**Key Implementation Notes**:
- Full Q2.13 x Q2.13 multiplication produces Q4.26 result
- Sequential processing: one delta, multiple activations
- Gradient index tracks which weight the gradient corresponds to
- Bias gradient is simply delta (dL/db = delta)
- Clear signal returns FSM to IDLE from any state
- Zero inputs case transitions directly to DONE_ST

**Operation Sequence**:
1. Start -> Wait for delta value
2. Load delta into register
3. For each activation: grad = delta x activation
4. Output gradient with index
5. Wait for grad_ready before next activation
6. Done when all inputs processed
7. Output bias gradient (= delta) when done

**Formula Reference**:
- Weight gradient: dL/dW[i,j] = delta[j] x a[i]
- Bias gradient: dL/db[j] = delta[j]

**Use Cases**:
- Computing weight gradients during backpropagation
- Layer-wise gradient calculation for SGD
- Mini-batch gradient accumulation (with external accumulator)

---

### dot_product_unit.vhd (2025-11-28)
**Status**: Fully functional - No fixes required

**Design Characteristics**:
- FSM-based dot product computation unit
- Computes: y = Sum(w[i] x x[i]) for i = 0 to N-1
- States: IDLE -> ACCUMULATE -> DONE_ST
- Format: Q2.13 (16-bit) inputs -> Q4.26 (32-bit) product -> Q10.26 (40-bit) accumulator
- Streaming interface with valid/ready handshaking
- Saturation on overflow

**Generics**:
- `DATA_WIDTH`: Input width (default 16, Q2.13)
- `ACCUM_WIDTH`: Accumulator width (default 40, Q10.26)
- `FRAC_BITS`: Fractional bits (default 13)
- `MAX_ELEMENTS`: Maximum vector length (default 16)

**Ports**:
- `clk`, `rst`, `start`, `clear`: Control signals
- `num_elements`: Vector length (unsigned 8-bit)
- `weight_in`, `data_in`: Signed Q2.13 inputs
- `data_valid`, `data_ready`: Input streaming interface
- `result_out`, `result_valid`, `out_ready`: Output handshaking interface
- `busy`, `done`, `overflow`: Status outputs

**Verification**:
- Compiled with GHDL (VHDL-2008)
- Compiled with Vivado XVHDL (2025.1)
- Elaborated with XELAB
- 11/11 testbench tests passed (both GHDL and XSIM)

**Tests Covered**:
1. Single element (1.0 x 1.0 = 1.0)
2. Two elements ([1,0.5].[0.5,1] = 1.0)
3. Four elements mixed signs (1 - 0.5 + 0.25 - 0.25 = 0.5)
4. Zero elements (immediate completion with result = 0)
5. All zeros (0 x anything = 0)
6. Negative result ([-1,-1].[1,1] = -2)
7. Larger vector (8 elements: 8 x 0.125 = 1.0)
8. Clear during operation
9. Output ready handshaking (holds result until accepted)
10. Reset behavior

**Key Implementation Notes**:
- Multiplication: Q2.13 x Q2.13 = Q4.26 (32-bit product)
- Sign extension via `resize()` for accumulation
- Overflow detection: `sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1)`
- Saturation clamps to MAX_ACCUM or MIN_ACCUM on overflow
- Zero elements case transitions directly to DONE_ST
- Holds result in DONE_ST until `out_ready` is asserted

**Operation Sequence**:
1. Assert `start` with `num_elements`
2. Provide weight/input pairs when `data_ready='1'`
3. Assert `data_valid` with each pair
4. Result available when `done='1'`
5. Assert `out_ready` to acknowledge and return to IDLE

**Use Cases**:
- Forward pass: z = W x x (pre-activation computation)
- Backward pass: error propagation delta = W^T x delta_next
- Fully-connected layer neuron computation

---

### weight_update_datapath.vhd (2025-11-28)
**Status**: Fully functional - Fixed testbench bug and code quality issues

**Design Characteristics**:
- FSM-based weight update datapath for neural network training
- Applies SGD updates: W_new = W_old - lr x gradient
- States: IDLE -> READ_WEIGHT -> WAIT_WEIGHT -> READ_GRADIENT -> WAIT_GRADIENT -> COMPUTE_UPDATE -> WRITE_WEIGHT -> NEXT_PARAM -> CLEAR_GRADS -> DONE_ST
- Format: Q2.13 (16-bit) weights, Q10.26 (40-bit) gradients
- Interfaces with external weight_register_bank and gradient_register_bank
- Supports configurable learning rate (static or dynamic)

**Network Architecture Supported**:
- Layer 1: 8 weights + 2 biases = 10 parameters
- Layer 2: 2 weights + 1 bias = 3 parameters
- Total: 13 parameters per update cycle

**Memory Map**:
- Addr 0-7: Layer 1 weights
- Addr 8-9: Layer 1 biases
- Addr 10-11: Layer 2 weights
- Addr 12: Layer 2 bias

**Generics**:
- `DATA_WIDTH`: Weight width (default 16, Q2.13)
- `GRAD_WIDTH`: Gradient width (default 40, Q10.26)
- `FRAC_BITS`: Fractional bits in weights (default 13)
- `GRAD_FRAC_BITS`: Fractional bits in gradients (default 26)
- `NUM_PARAMS`: Total weights + biases (default 13)
- `ADDR_WIDTH`: Address width (default 4)
- `DEFAULT_LR`: Default learning rate (default 82 = 0.01 in Q2.13)

**Ports**:
- `clk`, `rst`, `start`, `clear`: Control signals
- `learning_rate`, `use_default_lr`: Learning rate configuration
- `weight_rd_data`, `weight_rd_addr`, `weight_rd_en`: Weight read interface
- `weight_wr_data`, `weight_wr_addr`, `weight_wr_en`: Weight write interface
- `grad_rd_data`, `grad_rd_addr`, `grad_rd_en`: Gradient read interface
- `grad_clear`: Signal to clear gradient accumulators after update
- `busy`, `done`, `param_count`, `overflow`: Status outputs

**Verification**:
- Compiled with GHDL (VHDL-2008)
- Compiled with Vivado XVHDL (2025.1)
- All testbench tests passed (both GHDL and XSIM)

**Tests Covered**:
1. Weight update with default LR (0.01) - all 13 parameters
2. Weight update with custom LR (0.1) - all 13 parameters
3. Clear signal behavior
4. Gradient clear assertion after update complete

**Issues Fixed During Review**:

1. **Testbench Multiple Drivers Bug (Critical)**:
   - Problem: Testbench had two processes driving `grad_mem` signal
   - `grad_mem_proc` wrote zeros when `grad_clear='1'`
   - `stim_proc` wrote new test values on lines 248-262
   - This caused metavalues ('X') during Test 2
   - Fix: Removed write from `grad_mem_proc`, kept only monitoring

2. **ROUND_CONST Integer Overflow Prevention**:
   - Problem: `to_signed(2**(SCALE_SHIFT-1), PRODUCT_WIDTH)` could overflow 32-bit integer
   - `2^25 = 33,554,432` exceeds VHDL integer range in some tools
   - Fix: Use `shift_left(to_signed(1, PRODUCT_WIDTH), SCALE_SHIFT-1)` instead

3. **Saturation Flag Logic (OR Logic)**:
   - Clarified that overflow is flagged if EITHER:
     - Update term saturates (scaled lr x gradient exceeds Q2.13 range)
     - Final weight result saturates (W_old - update exceeds Q2.13 range)
   - `sat_flag` uses OR logic across both saturation checks

4. **Documentation Update**:
   - Updated header pipeline comment to include all FSM states
   - Added WAIT_WEIGHT, WAIT_GRADIENT, CLEAR_GRADS states to documentation

**Key Implementation Notes**:
- Full precision multiplication: Q2.13 x Q10.26 = Q12.39 (56-bit)
- Scaling: shift right by 26 bits to convert back to Q2.13
- Rounding: adds ROUND_CONST (2^25) before shift for round-to-nearest
- Dual saturation: saturates both update term AND final weight result
- Overflow register is sticky: once set, stays set until cleared
- Sequential parameter processing with automatic gradient clearing

**Fixed-Point Arithmetic Detail**:
```
lr (Q2.13) x grad (Q10.26) = product (Q12.39)
product + ROUND_CONST -> rounded (Q12.39)
shift_right(rounded, 26) -> scaled (Q2.13)
weight - scaled -> new_weight (Q2.13 with saturation)
```

**Testbench Lesson Learned**:
- **Never have multiple processes driving the same signal** in VHDL testbenches
- Even if drivers are mutually exclusive in time, signal resolution causes metavalues
- Solution: Use a single process for all writes, or use shared variables with protected types

**Latency**:
- Per parameter: 7 clock cycles (READ -> WAIT -> READ -> WAIT -> COMPUTE -> WRITE -> NEXT)
- Total for 13 parameters: ~91 clock cycles + CLEAR_GRADS + DONE_ST

**Use Cases**:
- SGD weight updates during neural network training
- Batch gradient descent (accumulate gradients, then update)
- Online learning (update after each sample)
- Learning rate scheduling (via dynamic `learning_rate` input)

---

### forward_datapath.vhd (2025-11-28)
**Status**: Fixed and verified

**Design Characteristics**:
- Complete forward propagation datapath for 4-2-1 neural network
- Computes: z = Wxx + b, a = sigma(z) for all layers
- FSM-based with pipelined weight memory reads
- Format: Q2.13 (16-bit) data, Q10.26 (40-bit) accumulator

**Network Architecture**:
- Layer 1: 4 inputs -> 2 hidden neurons (8 weights + 2 biases)
- Layer 2: 2 hidden -> 1 output neuron (2 weights + 1 bias)
- Total: 13 weight/bias parameters

**Memory Map** (weight_register_bank):

| Address | Content |
|---------|---------|
| 0-3 | Layer 1, Neuron 0 weights [w00, w01, w02, w03] |
| 4-7 | Layer 1, Neuron 1 weights [w10, w11, w12, w13] |
| 8-9 | Layer 1 biases [b0, b1] |
| 10-11 | Layer 2 weights [w20, w21] |
| 12 | Layer 2 bias [b2] |

**FSM States**:
```
IDLE -> LOAD_INPUT -> L1_N0_ADDR -> L1_NEURON0_DOT -> L1_N0_BIAS_ADDR ->
L1_NEURON0_BIAS -> L1_NEURON0_ACT -> L1_N1_ADDR -> L1_NEURON1_DOT ->
L1_N1_BIAS_ADDR -> L1_NEURON1_BIAS -> L1_NEURON1_ACT -> L2_OUT_ADDR ->
L2_OUTPUT_DOT -> L2_OUT_BIAS_ADDR -> L2_OUTPUT_BIAS -> L2_OUTPUT_ACT ->
STORE_OUTPUT -> DONE_ST
```

**Generics**:
- `DATA_WIDTH`: Data width (default 16, Q2.13)
- `ACCUM_WIDTH`: Accumulator width (default 40, Q10.26)
- `FRAC_BITS`: Fractional bits (default 13)
- `NUM_INPUTS`: Input layer size (default 4)
- `NUM_HIDDEN`: Hidden layer size (default 2)
- `NUM_OUTPUTS`: Output layer size (default 1)

**Ports**:
- `clk`, `rst`, `start`, `clear`: Control signals
- `input_data`, `input_addr`, `input_valid`, `input_ready`: Input interface
- `weight_rd_data`, `weight_rd_addr`, `weight_rd_en`: Weight memory interface
- `cache_z_wr_*`, `cache_a_wr_*`: Forward cache write interface
- `output_data`, `output_valid`: Output interface
- `busy`, `done`, `layer_complete`, `current_layer`, `overflow`: Status

**Verification**:
- Compiled with GHDL (VHDL-2008)
- Compiled with Vivado XVHDL (2025.1)
- Elaborated with XELAB
- 2/2 testbench tests passed (both GHDL and XSIM)
- Output: 8068 (0.9849), Expected: 8069 (0.985) - 1 LSB rounding difference

**Bugs Fixed**:

1. **Weight Memory Pipeline Timing** (CRITICAL):
   - **Problem**: FSM consumed weight data on the same cycle it was requested, but weight memory has 1-cycle read latency (registered output)
   - **Symptom**: Dot products used wrong weights (e.g., weight[0] instead of weight[1])
   - **Fix**: Added address setup states (`L1_N0_ADDR`, `L1_N0_BIAS_ADDR`, etc.) to wait for memory data before consumption

2. **Address Bounds Overflow** (CRITICAL):
   - **Problem**: Weight index incremented one extra time on last dot product iteration, causing address 13 (out of bounds 0-12)
   - **Symptom**: `index (13) out of bounds (0 to 12)` runtime error
   - **Fix**: Added conditional `if dot_count < dot_target - 1 then weight_idx <= weight_idx + 1; end if;`

3. **Testbench Synchronization** (in tb_forward_datapath.vhd):
   - **Problem**: `wait until input_ready = '1'` never triggered because input_ready was already high
   - **Symptom**: Testbench hung indefinitely, never sent input data
   - **Fix**: Added check `if input_ready /= '1' then wait until input_ready = '1'; end if;`

**Key Implementation Notes**:
- Weight address pipelining: Set address in cycle N, data available in cycle N+1, consume in cycle N+1
- Pre-fetch pattern: Increment address at end of MAC cycle so data is ready for next iteration
- Don't pre-fetch on last iteration to avoid bounds violation
- Bias needs its own address setup state due to non-sequential addressing (jump from weights to bias address)

**Pipeline Timing Pattern**:
```vhdl
-- Address setup state (wait 1 cycle for memory)
when L1_N0_ADDR =>
    weight_idx <= weight_idx + 1;  -- Pre-fetch for first MAC
    state <= L1_NEURON0_DOT;

-- Dot product state
when L1_NEURON0_DOT =>
    if dot_count < dot_target then
        -- Use weight_rd_data (valid for current dot_count)
        product := weight_rd_data * input_buffer(to_integer(dot_count));
        dot_count <= dot_count + 1;
        -- Pre-fetch next weight (skip on last iteration)
        if dot_count < dot_target - 1 then
            weight_idx <= weight_idx + 1;
        end if;
    else
        -- Move to bias
        weight_idx <= to_unsigned(BIAS_ADDR, 4);
        state <= BIAS_ADDR_STATE;
    end if;
```

**Testbench Wait Pattern** (for already-high signals):
```vhdl
-- Safe wait that handles already-high condition
if input_ready /= '1' then
    wait until input_ready = '1';
end if;
wait for CLK_PERIOD;  -- Align to clock edge
```

**Latency**: ~33 clock cycles for complete forward pass (4 inputs, 2 hidden, 1 output)

---

## Common Debugging Patterns

### Memory Pipeline Timing Issues
**Symptoms**:
- Wrong data being used in calculations
- Results off by one element
- Accumulator values don't match expected

**Root Cause**: Using memory data on same cycle as address assertion with registered memory

**Fix Pattern**:
1. Add "address setup" state that waits 1 cycle
2. Pre-increment address for pipelining
3. Don't increment on last iteration to avoid bounds overflow

### Testbench Synchronization Issues
**Symptoms**:
- Simulation hangs waiting for signal
- `wait until signal = '1'` never triggers

**Root Cause**: Signal is already at target value when wait statement executes

**Fix Pattern**:
```vhdl
if signal /= '1' then
    wait until signal = '1';
end if;
```

---

### backward_datapath.vhd (2025-11-28)
**Status**: Fixed and verified

**Design Characteristics**:
- Complete backward propagation datapath for 4-2-1 neural network
- Computes deltas and gradients for all layers
- FSM-based with 20 states (including wait states for memory latency)
- Format: Q2.13 (16-bit) data, Q4.26 (32-bit) gradients, Q10.26 (40-bit) accumulators
- Valid/ready handshaking for gradient output

**Backpropagation Flow**:
1. Output layer: delta_out = (target - actual) x sigma'(z_out)
2. Hidden layer: delta_hidden = (W_L2^T x delta_out) x sigma'(z_hidden)
3. Gradients: dL/dW = delta x a^T (outer product)

**Network Architecture**:
- Layer 1: 4 inputs -> 2 hidden neurons (8 weight grads + 2 bias grads)
- Layer 2: 2 hidden -> 1 output neuron (2 weight grads + 1 bias grad)

**Generics**:
- `DATA_WIDTH`: Data width (default 16, Q2.13)
- `GRAD_WIDTH`: Gradient width (default 32, Q4.26)
- `ACCUM_WIDTH`: Accumulator width (default 40, Q10.26)
- `FRAC_BITS`: Fractional bits (default 13)
- `NUM_INPUTS`: Input layer size (default 4)
- `NUM_HIDDEN`: Hidden layer size (default 2)
- `NUM_OUTPUTS`: Output layer size (default 1)

**Ports**:
- `clk`, `rst`, `start`, `clear`: Control signals
- `target_in`, `target_valid`: Target value for error computation
- `actual_in`: Actual output from forward pass
- `weight_rd_data`, `weight_rd_addr`, `weight_rd_en`: Weight memory read interface
- `cache_z_rd_data`, `cache_z_rd_addr`, `cache_z_rd_en`: Z cache read interface
- `cache_a_rd_data`, `cache_a_rd_addr`, `cache_a_rd_en`: Activation cache read interface
- `grad_out`, `grad_addr`, `grad_valid`, `grad_ready`: Gradient output interface
- `busy`, `done`, `current_layer`, `overflow`: Status outputs

**FSM States** (20 total):
```
IDLE -> LOAD_TARGET -> COMPUTE_OUTPUT_ERROR -> LOAD_Z_OUTPUT -> WAIT_Z_OUTPUT ->
COMPUTE_OUTPUT_DELTA -> LOAD_A_HIDDEN -> WAIT_A_HIDDEN -> COMPUTE_L2_WEIGHT_GRAD ->
COMPUTE_L2_BIAS_GRAD -> LOAD_HIDDEN_Z -> WAIT_HIDDEN_Z -> LOAD_WEIGHT -> WAIT_WEIGHT ->
PROPAGATE_ERROR -> COMPUTE_HIDDEN_DELTA -> LOAD_INPUT_A -> WAIT_INPUT_A ->
COMPUTE_L1_WEIGHT_GRAD -> COMPUTE_L1_BIAS_GRAD -> DONE_ST
```

**Gradient Memory Map**:
| Address | Content |
|---------|---------|
| 0-7 | Layer 1 weight gradients |
| 8-9 | Layer 1 bias gradients |
| 10-11 | Layer 2 weight gradients |
| 12 | Layer 2 bias gradient |

**Verification**:
- Compiled with GHDL (VHDL-2008)
- Compiled with Vivado XVHDL (2025.1)
- 2/2 testbench tests passed:
  - Test 1: target=1.0, actual=0.985, error=+0.015 -> positive gradients
  - Test 2: target=0.0, actual=0.985, error=-0.985 -> negative gradients

**Bugs Fixed (2025-11-28)**:

1. **Memory Read Latency** (Critical):
   - **Problem**: Original code assumed zero-latency memory reads, reading data in same cycle as setting address
   - **Fix**: Added 8 wait states (`WAIT_Z_OUTPUT`, `WAIT_A_HIDDEN`, `WAIT_HIDDEN_Z`, `WAIT_WEIGHT`, `WAIT_INPUT_A`, etc.) to handle 1-cycle memory read latency
   - **Pattern**: Set address in LOAD_* state, transition to WAIT_* state, read data in next state

2. **Handshaking Protocol** (Critical):
   - **Problem**: Gradient output asserted `grad_valid` every cycle while waiting for `grad_ready`, potentially corrupting data
   - **Fix**: Only compute and assert valid when `grad_valid_reg = '0'`, deassert after handshake completes
   - **Pattern**:
   ```vhdl
   if grad_valid_reg = '0' then
       -- Compute and set valid
       grad_valid_reg <= '1';
   end if;
   if grad_ready = '1' and grad_valid_reg = '1' then
       grad_valid_reg <= '0';
       -- Proceed to next state
   end if;
   ```

3. **Bias Gradient Format** (Critical):
   - **Problem**: Bias gradients were in Q2.13 format while weight gradients were Q4.26
   - **Fix**: Changed `resize(delta, GRAD_WIDTH)` to `shift_left(resize(delta, GRAD_WIDTH), FRAC_BITS)` for format consistency
   - **Why**: Weight gradients are delta x a (Q2.13 x Q2.13 = Q4.26), bias gradients should match

4. **Magic Numbers**:
   - **Problem**: Hardcoded values like "10", "100", "01" scattered in code
   - **Fix**: Added named constants: `Z_OUTPUT_ADDR`, `A_HIDDEN_BASE`, `LAYER_OUTPUT`, `LAYER_HIDDEN`

**Key Implementation Notes**:
- Uses `cached_a` signal to store activation value read from cache for use in gradient computation
- ReLU derivative computed inline: `if z > 0 then ONE_Q213 else ZERO_Q213`
- Error saturation: clamps to SAT_MAX/SAT_MIN when difference overflows
- Proper bit slicing for Q4.26 to Q2.13: `product(DATA_WIDTH+FRAC_BITS-1 downto FRAC_BITS)`

**Lessons Learned**:
1. Always account for memory read latency in FSM designs - real block RAMs have 1-cycle latency
2. Valid/ready handshaking must only assert valid once per transaction
3. Keep gradient formats consistent across weight and bias gradients
4. Use named constants instead of magic numbers for addresses and layer encodings
5. Cache data read from memory into local registers before using in computations

### Proper Valid/Ready Handshaking Pattern
```vhdl
when OUTPUT_STATE =>
    if valid_reg = '0' then
        -- Compute output once
        output_reg <= computed_value;
        valid_reg <= '1';
    end if;

    if ready = '1' and valid_reg = '1' then
        valid_reg <= '0';
        state <= NEXT_STATE;
    end if;
```

### Q2.13 to Q4.26 Bias Gradient Conversion
```vhdl
-- Wrong: just resize (stays in Q2.13 range)
grad_reg <= resize(delta, GRAD_WIDTH);

-- Correct: shift to match Q4.26 format
grad_reg <= shift_left(resize(delta, GRAD_WIDTH), FRAC_BITS);
```
