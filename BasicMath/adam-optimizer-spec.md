# Adam Optimizer for FPGA Neural Network Accelerator

## Complete Design Specification Document

**Target Platform:** ZCU106 FPGA  
**Arithmetic Format:** Q2.13 Fixed-Point (16-bit signed)  
**Network Architecture:** 4-2-1 (13 trainable parameters)  
**Author:** FPGA Neural Network Project  
**Version:** 1.0

---

# Part 1: Theoretical Foundation

## 1.1 The Optimization Problem

Training a neural network means finding weights W that minimize a loss function L(W). This is an optimization problem in high-dimensional space. For your 4-2-1 network with 13 parameters, we're searching for the optimal point in 13-dimensional space.

The general approach is **iterative optimization**:

```
W(t+1) = W(t) - update(t)
```

Different optimizers compute `update(t)` differently.

---

## 1.2 Evolution of Optimizers

### 1.2.1 Vanilla Gradient Descent

**Formula:**
```
W(t+1) = W(t) - η · ∇L(W(t))
```

**Intuition:** Move in the direction of steepest descent.

**Problems:**
- Same learning rate η for all parameters
- Oscillates in ravines (high curvature directions)
- Gets stuck at saddle points
- Sensitive to learning rate choice

### 1.2.2 SGD with Momentum

**Formula:**
```
v(t) = γ · v(t-1) + η · ∇L(W(t))
W(t+1) = W(t) - v(t)
```

**Intuition:** Accumulate velocity; gradients in consistent directions build up speed.

**Improvement:** Dampens oscillations, accelerates through flat regions.

**Remaining problems:** Still uses uniform learning rate for all parameters.

### 1.2.3 AdaGrad (Adaptive Gradient)

**Formula:**
```
G(t) = G(t-1) + [∇L(W(t))]²
W(t+1) = W(t) - η · ∇L(W(t)) / √(G(t) + ε)
```

**Intuition:** Parameters with historically large gradients get smaller learning rates.

**Problem:** G accumulates forever, eventually making learning rate vanishingly small.

### 1.2.4 RMSprop (Root Mean Square Propagation)

**Formula:**
```
v(t) = β · v(t-1) + (1-β) · [∇L(W(t))]²
W(t+1) = W(t) - η · ∇L(W(t)) / √(v(t) + ε)
```

**Intuition:** Use exponential moving average instead of sum—forgets old gradients.

**Improvement:** Learning rate adapts but doesn't vanish over time.

### 1.2.5 Adam (Adaptive Moment Estimation)

**Combines the best of momentum and RMSprop:**
- First moment (mean) → Momentum effect
- Second moment (variance) → Adaptive learning rate

This is what we will implement.

---

## 1.3 Adam Algorithm: Complete Specification

### 1.3.1 State Variables

For each parameter W, Adam maintains:

| Variable | Symbol | Initialization | Description |
|----------|--------|----------------|-------------|
| First moment | m | 0 | Exponential moving average of gradients |
| Second moment | v | 0 | Exponential moving average of squared gradients |
| Timestep | t | 0 | Training iteration counter |

### 1.3.2 Hyperparameters

| Symbol | Name | Default | Range | Description |
|--------|------|---------|-------|-------------|
| η | Learning rate | 0.001 | [1e-5, 0.1] | Base step size |
| β₁ | First moment decay | 0.9 | [0.8, 0.99] | Momentum coefficient |
| β₂ | Second moment decay | 0.999 | [0.99, 0.9999] | Variance smoothing |
| ε | Epsilon | 1e-8 | [1e-10, 1e-6] | Numerical stability |

### 1.3.3 Algorithm Steps

**Input:** Gradient g(t) = ∂L/∂W at timestep t

**Step 1: Update biased first moment estimate**
```
m(t) = β₁ · m(t-1) + (1 - β₁) · g(t)
```

**Step 2: Update biased second moment estimate**
```
v(t) = β₂ · v(t-1) + (1 - β₂) · [g(t)]²
```

**Step 3: Compute bias-corrected first moment**
```
m̂(t) = m(t) / (1 - β₁ᵗ)
```

**Step 4: Compute bias-corrected second moment**
```
v̂(t) = v(t) / (1 - β₂ᵗ)
```

**Step 5: Update parameter**
```
W(t) = W(t-1) - η · m̂(t) / (√v̂(t) + ε)
```

### 1.3.4 Why Bias Correction?

At initialization, m(0) = v(0) = 0. After first update:
```
m(1) = 0.9 × 0 + 0.1 × g(1) = 0.1 × g(1)
```

The moment estimate is biased toward zero by factor of (1 - β₁) = 0.1.

**Correction factor derivation:**

Expected value of m(t) assuming constant gradient g:
```
E[m(t)] = (1 - β₁) · Σᵢ₌₁ᵗ β₁ᵗ⁻ⁱ · g = g · (1 - β₁ᵗ)
```

Dividing by (1 - β₁ᵗ) gives unbiased estimate:
```
E[m̂(t)] = E[m(t)] / (1 - β₁ᵗ) = g
```

**Practical note:** After ~1000 steps, β₁¹⁰⁰⁰ ≈ 0, so correction becomes negligible.

---

## 1.4 Mathematical Operations Analysis

### 1.4.1 Operations Per Parameter Update

| Operation | Count | Module Required |
|-----------|-------|-----------------|
| Multiplication | 7 | DSP block / mac_unit |
| Addition | 4 | Adder logic |
| Subtraction | 3 | Adder logic |
| Square (g²) | 1 | Multiply g × g |
| Square root | 1 | sqrt_unit |
| Division | 3 | division_unit |
| Power (βᵗ) | 2 | power_unit or LUT |

### 1.4.2 Detailed Operation Breakdown

```
┌────────────────────────────────────────────────────────────────┐
│ STEP 1: First Moment Update                                    │
│   m_new = β₁ × m_old + (1-β₁) × g                             │
│                                                                │
│   Operations:                                                  │
│     temp1 = β₁ × m_old        [1 MULTIPLY]                    │
│     temp2 = (1-β₁) × g        [1 MULTIPLY] (1-β₁ precomputed) │
│     m_new = temp1 + temp2     [1 ADD]                         │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│ STEP 2: Second Moment Update                                   │
│   v_new = β₂ × v_old + (1-β₂) × g²                            │
│                                                                │
│   Operations:                                                  │
│     g_squared = g × g         [1 MULTIPLY]                    │
│     temp3 = β₂ × v_old        [1 MULTIPLY]                    │
│     temp4 = (1-β₂) × g²       [1 MULTIPLY] (1-β₂ precomputed) │
│     v_new = temp3 + temp4     [1 ADD]                         │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│ STEP 3: Bias Correction                                        │
│   m_hat = m_new / (1 - β₁ᵗ)                                   │
│   v_hat = v_new / (1 - β₂ᵗ)                                   │
│                                                                │
│   Operations:                                                  │
│     bc1 = 1 - β₁ᵗ             [1 POWER, 1 SUBTRACT]           │
│     bc2 = 1 - β₂ᵗ             [1 POWER, 1 SUBTRACT]           │
│     m_hat = m_new / bc1       [1 DIVIDE]                      │
│     v_hat = v_new / bc2       [1 DIVIDE]                      │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│ STEP 4: Adaptive Update                                        │
│   update = η × m_hat / (√v_hat + ε)                           │
│                                                                │
│   Operations:                                                  │
│     sqrt_v = √v_hat           [1 SQRT]                        │
│     denom = sqrt_v + ε        [1 ADD]                         │
│     ratio = m_hat / denom     [1 DIVIDE]                      │
│     update = η × ratio        [1 MULTIPLY]                    │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│ STEP 5: Weight Update                                          │
│   W_new = W_old - update                                       │
│                                                                │
│   Operations:                                                  │
│     W_new = W_old - update    [1 SUBTRACT]                    │
└────────────────────────────────────────────────────────────────┘
```

---

# Part 2: Fixed-Point Implementation Considerations

## 2.1 Format Analysis

### 2.1.1 Value Ranges

| Quantity | Typical Range | Extreme Range | Notes |
|----------|---------------|---------------|-------|
| Weights W | [-2, 2] | [-4, 4] | After training |
| Gradients g | [-1, 1] | [-4, 4] | Depends on loss scale |
| First moment m | [-1, 1] | [-4, 4] | Smoothed gradients |
| Second moment v | [0, 1] | [0, 16] | Always non-negative |
| β₁, β₂ | [0.9, 0.999] | [0, 1] | Close to 1.0 |
| 1 - β₁ᵗ | [0.1, 1] | [0, 1] | Starts small, grows |
| √v | [0, 1] | [0, 4] | Square root of variance |
| Learning rate η | [0.0001, 0.01] | [0, 0.1] | Small values |

### 2.1.2 Recommended Formats

| Quantity | Format | Bits | Range | Precision |
|----------|--------|------|-------|-----------|
| Weights, gradients, moments | Q2.13 | 16 | [-4, 3.999] | 0.000122 |
| β coefficients | Q0.15 | 16 | [0, 0.99997] | 0.000031 |
| Bias correction terms | Q0.15 | 16 | [0, 0.99997] | 0.000031 |
| Learning rate | Q0.15 | 16 | [0, 0.99997] | 0.000031 |
| Epsilon | Q0.20 | 20 | [0, 0.000001] | 9.5e-7 |
| Intermediate products | Q4.26 | 32 | [-8, 7.999] | 1.49e-8 |

### 2.1.3 Critical Precision Points

**β₂ = 0.999 representation:**
```
Q0.15: 0.999 × 32768 = 32735.232 → 32735
Actual: 32735 / 32768 = 0.998993 (error: 0.0007%)
```

**1 - β₂ = 0.001 representation:**
```
Q0.15: 0.001 × 32768 = 32.768 → 33
Actual: 33 / 32768 = 0.001007 (error: 0.7%)
```

**ε = 1e-8 representation:**

This is too small for Q0.15. Options:
1. Use larger ε (1e-4 works in practice)
2. Use Q0.20 format for ε only
3. Add minimum threshold after sqrt

### 2.1.4 Overflow Prevention Strategy

**Moment updates:** Use Q4.26 intermediate then saturate to Q2.13
```
m_new (Q2.13) = saturate(β₁ × m_old + (1-β₁) × g)
                         \___ Q4.26 intermediate ___/
```

**Square operation:** g² can overflow if |g| > 2
```
g = 3.0 (Q2.13) → g² = 9.0 (exceeds Q2.13 range)
Solution: Saturate to Q2.13 max (3.999) or use Q4.12 for v
```

---

## 2.2 Simplified Adam (Recommended for Initial Implementation)

### 2.2.1 Simplifications

For FPGA efficiency, we implement **Adam without bias correction**:

```
m(t) = β₁ · m(t-1) + (1 - β₁) · g(t)
v(t) = β₂ · v(t-1) + (1 - β₂) · [g(t)]²
W(t) = W(t-1) - η · m(t) / (√v(t) + ε)
```

**Justification:**
- Bias correction mainly matters for first ~1000 steps
- Eliminates power computation (βᵗ)
- Eliminates 2 division operations
- Reduces latency by ~40%

**Tradeoff:** Slightly slower convergence initially, identical asymptotic behavior.

### 2.2.2 Simplified Operations Count

| Operation | Full Adam | Simplified Adam | Savings |
|-----------|-----------|-----------------|---------|
| Multiply | 7 | 7 | 0 |
| Add/Subtract | 7 | 5 | 2 |
| Divide | 3 | 1 | 2 |
| Sqrt | 1 | 1 | 0 |
| Power | 2 | 0 | 2 |
| **Total cycles** | ~45-50 | ~25-30 | ~40% |

---

# Part 3: Module Architecture

## 3.1 Module Hierarchy

```
adam_optimizer_top
│
├── EXISTING MODULES (reused)
│   ├── sqrt_unit
│   ├── division_unit
│   ├── reciprocal_unit (used by division_unit)
│   ├── saturation_unit
│   └── rounding_saturation
│
├── NEW STORAGE MODULES
│   ├── moment_register_bank (stores m, v for all parameters)
│   └── beta_coefficient_rom (stores β₁, β₂, 1-β₁, 1-β₂, η, ε)
│
├── NEW COMPUTATION MODULES
│   ├── moment_update_unit (computes m_new and v_new)
│   ├── adaptive_lr_unit (computes η·m/(√v+ε))
│   └── adam_update_unit (single parameter complete update)
│
└── TOP CONTROL
    └── adam_optimizer_fsm (sequences through all parameters)
```

## 3.2 Data Flow Diagram

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                   adam_optimizer_top                     │
                    │                                                          │
  gradient ────────►│  ┌──────────────┐    ┌──────────────┐                   │
  (from backprop)   │  │   moment_    │    │  adaptive_   │                   │
                    │  │ update_unit  │───►│   lr_unit    │                   │
  m_old ───────────►│  │              │    │              │                   │
  v_old ───────────►│  │ Computes:    │    │ Computes:    │                   │
                    │  │ m_new, v_new │    │ η·m/(√v+ε)   │                   │
                    │  └──────────────┘    └──────┬───────┘                   │
                    │                             │                            │
                    │                             ▼                            │
                    │                      ┌──────────────┐                   │
  W_old ───────────►│                      │   weight_    │────────►W_new     │
                    │                      │  subtract    │                   │
                    │                      └──────────────┘                   │
                    │                                                          │
                    │  ┌──────────────────────────────────────────────────┐   │
                    │  │              moment_register_bank                 │   │
                    │  │  Stores m[0..12], v[0..12] for all 13 params     │   │
                    │  └──────────────────────────────────────────────────┘   │
                    │                                                          │
                    └─────────────────────────────────────────────────────────┘
```

---

# Part 4: Module Specifications

## 4.1 Module: moment_register_bank

### 4.1.1 Purpose

Stores the first moment (m) and second moment (v) values for all trainable parameters. Similar in structure to `gradient_register_bank` but stores two values per address.

### 4.1.2 Mathematical Role

Maintains state between training iterations:
- m[i]: Running average of gradients for parameter i
- v[i]: Running average of squared gradients for parameter i

### 4.1.3 Interface Description

**Generics:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| DATA_WIDTH | integer | 16 | Moment value width (Q2.13) |
| NUM_PARAMS | integer | 13 | Number of parameters |
| ADDR_WIDTH | integer | 4 | Address bits (ceil(log2(13))) |

**Ports:**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| clk | in | 1 | System clock |
| rst | in | 1 | Synchronous reset (clears all to zero) |
| clear | in | 1 | Clear all moments (new training) |
| rd_en | in | 1 | Read enable |
| rd_addr | in | ADDR_WIDTH | Read address |
| m_rd_data | out | DATA_WIDTH | First moment output |
| v_rd_data | out | DATA_WIDTH | Second moment output |
| rd_valid | out | 1 | Read data valid |
| wr_en | in | 1 | Write enable |
| wr_addr | in | ADDR_WIDTH | Write address |
| m_wr_data | in | DATA_WIDTH | First moment input |
| v_wr_data | in | DATA_WIDTH | Second moment input |

### 4.1.4 Behavior

**Reset/Clear:** All m and v values set to zero (required by Adam initialization).

**Read:** Asynchronous (combinational) read. When rd_en='1' and address valid, m_rd_data and v_rd_data reflect stored values.

**Write:** Synchronous write on rising clock edge when wr_en='1'.

**Memory organization:**
```
Address 0:  m[0], v[0]   (Layer 1, weight 0)
Address 1:  m[1], v[1]   (Layer 1, weight 1)
...
Address 12: m[12], v[12] (Layer 2, bias)
```

### 4.1.5 Resource Estimate

- Storage: 13 × 2 × 16 bits = 416 bits (fits in distributed RAM)
- Logic: Minimal (address decode, mux)

---

## 4.2 Module: beta_coefficient_rom

### 4.2.1 Purpose

Stores Adam hyperparameters as fixed-point constants. Using ROM allows changing hyperparameters without redesign.

### 4.2.2 Contents

| Address | Symbol | Formula | Typical Value | Q0.15 Encoding |
|---------|--------|---------|---------------|----------------|
| 0 | β₁ | - | 0.9 | 29491 |
| 1 | β₂ | - | 0.999 | 32735 |
| 2 | 1-β₁ | - | 0.1 | 3277 |
| 3 | 1-β₂ | - | 0.001 | 33 |
| 4 | η | - | 0.001 | 33 |
| 5 | ε | - | 0.0001 | 3 |

### 4.2.3 Interface Description

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| addr | in | 3 | Coefficient address (0-5) |
| data_out | out | 16 | Coefficient value (Q0.15) |

### 4.2.4 Behavior

Pure combinational lookup. No clock required.

### 4.2.5 Alternative: External Ports

Instead of ROM, hyperparameters can be input ports to allow runtime adjustment:

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| beta1 | in | 16 | First moment decay |
| beta2 | in | 16 | Second moment decay |
| one_minus_beta1 | in | 16 | Precomputed 1-β₁ |
| one_minus_beta2 | in | 16 | Precomputed 1-β₂ |
| learning_rate | in | 16 | Step size η |
| epsilon | in | 16 | Stability constant ε |

---

## 4.3 Module: moment_update_unit

### 4.3.1 Purpose

Computes updated first and second moment values for one parameter.

### 4.3.2 Mathematical Formulas

**First moment update:**
```
m_new = β₁ × m_old + (1 - β₁) × g
```

**Second moment update:**
```
v_new = β₂ × v_old + (1 - β₂) × g²
```

### 4.3.3 Interface Description

**Ports:**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| clk | in | 1 | System clock |
| rst | in | 1 | Synchronous reset |
| start | in | 1 | Begin computation |
| gradient | in | 16 | Current gradient g (Q2.13) |
| m_old | in | 16 | Previous first moment (Q2.13) |
| v_old | in | 16 | Previous second moment (Q2.13) |
| beta1 | in | 16 | β₁ coefficient (Q0.15) |
| beta2 | in | 16 | β₂ coefficient (Q0.15) |
| one_minus_beta1 | in | 16 | 1-β₁ coefficient (Q0.15) |
| one_minus_beta2 | in | 16 | 1-β₂ coefficient (Q0.15) |
| m_new | out | 16 | Updated first moment (Q2.13) |
| v_new | out | 16 | Updated second moment (Q2.13) |
| done | out | 1 | Computation complete |
| busy | out | 1 | Computation in progress |
| overflow | out | 1 | Saturation occurred |

### 4.3.4 Computation Pipeline

```
Cycle 1: Compute g² = g × g
         Compute β₁ × m_old
         
Cycle 2: Compute (1-β₁) × g
         Compute β₂ × v_old
         
Cycle 3: Compute (1-β₂) × g²
         Compute m_new = (β₁ × m_old) + ((1-β₁) × g)
         
Cycle 4: Compute v_new = (β₂ × v_old) + ((1-β₂) × g²)
         Apply saturation to m_new, v_new
         Assert done
```

**Total latency:** 4 clock cycles

### 4.3.5 FSM States

```
┌──────────────────────────────────────────────────────────────────┐
│                    moment_update_unit FSM                         │
└──────────────────────────────────────────────────────────────────┘

     ┌─────────┐
     │  IDLE   │◄────────────────────────────────┐
     └────┬────┘                                 │
          │ start='1'                            │
          ▼                                      │
     ┌─────────┐                                 │
     │ SQUARE  │  Compute g², β₁×m_old          │
     └────┬────┘                                 │
          │                                      │
          ▼                                      │
     ┌─────────┐                                 │
     │ MULT_1  │  Compute (1-β₁)×g, β₂×v_old    │
     └────┬────┘                                 │
          │                                      │
          ▼                                      │
     ┌─────────┐                                 │
     │ MULT_2  │  Compute (1-β₂)×g², sum for m  │
     └────┬────┘                                 │
          │                                      │
          ▼                                      │
     ┌─────────┐                                 │
     │ OUTPUT  │  Sum for v, saturate, done='1' │
     └────┬────┘                                 │
          │                                      │
          └──────────────────────────────────────┘
```

### 4.3.6 Arithmetic Details

**Format conversions:**

Multiply Q2.13 × Q0.15 → Q2.28 (30 bits used)
```
g (Q2.13) × (1-β₁) (Q0.15) = result (Q2.28)
Shift right by 15 to get Q2.13
```

Multiply Q0.15 × Q2.13 → Q2.28
```
β₁ (Q0.15) × m_old (Q2.13) = result (Q2.28)
Shift right by 15 to get Q2.13
```

**Saturation for v_new:**

Second moment v must be non-negative. If computation yields negative (due to numerical error), clamp to zero.

---

## 4.4 Module: adaptive_lr_unit

### 4.4.1 Purpose

Computes the adaptive learning rate term: `η × m / (√v + ε)`

This is the core innovation of Adam—scaling the update by the ratio of gradient mean to standard deviation.

### 4.4.2 Mathematical Formula

```
update = η × m / (√v + ε)
```

Expanded computation sequence:
```
Step 1: sqrt_v = √v
Step 2: denom = sqrt_v + ε
Step 3: ratio = m / denom
Step 4: update = η × ratio
```

### 4.4.3 Interface Description

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| clk | in | 1 | System clock |
| rst | in | 1 | Synchronous reset |
| start | in | 1 | Begin computation |
| m_in | in | 16 | First moment (Q2.13) |
| v_in | in | 16 | Second moment (Q2.13) |
| learning_rate | in | 16 | η (Q0.15) |
| epsilon | in | 16 | ε (Q0.15) |
| update_out | out | 16 | Computed update (Q2.13) |
| done | out | 1 | Computation complete |
| busy | out | 1 | Computation in progress |
| overflow | out | 1 | Saturation occurred |
| div_by_zero | out | 1 | Denominator too small |

### 4.4.4 FSM States

```
┌──────────────────────────────────────────────────────────────────┐
│                     adaptive_lr_unit FSM                          │
└──────────────────────────────────────────────────────────────────┘

     ┌─────────┐
     │  IDLE   │◄────────────────────────────────────────┐
     └────┬────┘                                         │
          │ start='1'                                    │
          ▼                                              │
     ┌──────────────┐                                    │
     │ START_SQRT   │  Assert sqrt_unit.start           │
     └──────┬───────┘                                    │
            │                                            │
            ▼                                            │
     ┌──────────────┐                                    │
     │  WAIT_SQRT   │  Wait for sqrt_unit.done          │
     └──────┬───────┘  (~5 cycles)                      │
            │ sqrt_unit.done='1'                        │
            ▼                                            │
     ┌──────────────┐                                    │
     │  ADD_EPSILON │  denom = sqrt_v + ε (1 cycle)     │
     └──────┬───────┘                                    │
            │                                            │
            ▼                                            │
     ┌──────────────┐                                    │
     │ START_DIV    │  Assert division_unit.start       │
     └──────┬───────┘  dividend=m, divisor=denom        │
            │                                            │
            ▼                                            │
     ┌──────────────┐                                    │
     │  WAIT_DIV    │  Wait for division_unit.done      │
     └──────┬───────┘  (~10 cycles)                     │
            │ division_unit.done='1'                    │
            ▼                                            │
     ┌──────────────┐                                    │
     │  SCALE_LR    │  update = η × ratio (1 cycle)     │
     └──────┬───────┘                                    │
            │                                            │
            ▼                                            │
     ┌──────────────┐                                    │
     │   OUTPUT     │  Saturate, assert done='1'        │
     └──────┬───────┘                                    │
            │                                            │
            └────────────────────────────────────────────┘
```

### 4.4.5 Latency Analysis

| Stage | Cycles | Notes |
|-------|--------|-------|
| Start sqrt | 1 | Assert start signal |
| Wait sqrt | 5-6 | sqrt_unit Newton-Raphson iterations |
| Add epsilon | 1 | Simple addition |
| Start divide | 1 | Assert start signal |
| Wait divide | 8-10 | division_unit (uses reciprocal) |
| Scale by η | 1 | Single multiplication |
| Output | 1 | Register result |
| **Total** | **18-21** | Per parameter |

### 4.4.6 Submodule Instantiations

This module instantiates:
- `sqrt_unit` (1 instance) - from your existing modules
- `division_unit` (1 instance) - from your existing modules

### 4.4.7 Edge Cases

**v = 0 (no gradient history):**
```
√0 = 0
denom = 0 + ε = ε
ratio = m / ε (could be large!)
```
Solution: Ensure ε is large enough, or clamp ratio before scaling.

**m = 0 (no gradient direction):**
```
ratio = 0 / denom = 0
update = 0
```
This is correct behavior—no update when moment is zero.

**v very large:**
```
√v large → denom large → ratio small → small update
```
Correct: large gradient variance means uncertainty, so take smaller steps.

---

## 4.5 Module: adam_update_unit

### 4.5.1 Purpose

Performs complete Adam update for a single parameter. Combines moment_update_unit and adaptive_lr_unit, then computes final weight.

### 4.5.2 Complete Formula

```
m_new = β₁ × m_old + (1-β₁) × g
v_new = β₂ × v_old + (1-β₂) × g²
update = η × m_new / (√v_new + ε)
W_new = W_old - update
```

### 4.5.3 Interface Description

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| clk | in | 1 | System clock |
| rst | in | 1 | Synchronous reset |
| start | in | 1 | Begin update |
| gradient | in | 16 | Current gradient (Q2.13) |
| m_old | in | 16 | Previous first moment (Q2.13) |
| v_old | in | 16 | Previous second moment (Q2.13) |
| weight_old | in | 16 | Current weight (Q2.13) |
| beta1 | in | 16 | β₁ (Q0.15) |
| beta2 | in | 16 | β₂ (Q0.15) |
| one_minus_beta1 | in | 16 | 1-β₁ (Q0.15) |
| one_minus_beta2 | in | 16 | 1-β₂ (Q0.15) |
| learning_rate | in | 16 | η (Q0.15) |
| epsilon | in | 16 | ε (Q0.15) |
| m_new | out | 16 | Updated first moment (Q2.13) |
| v_new | out | 16 | Updated second moment (Q2.13) |
| weight_new | out | 16 | Updated weight (Q2.13) |
| done | out | 1 | Update complete |
| busy | out | 1 | Update in progress |
| overflow | out | 1 | Any saturation occurred |

### 4.5.4 FSM States

```
┌──────────────────────────────────────────────────────────────────┐
│                     adam_update_unit FSM                          │
└──────────────────────────────────────────────────────────────────┘

     ┌─────────┐
     │  IDLE   │◄──────────────────────────────────────────────┐
     └────┬────┘                                               │
          │ start='1'                                          │
          ▼                                                    │
     ┌────────────────┐                                        │
     │ START_MOMENTS  │  Start moment_update_unit              │
     └───────┬────────┘                                        │
             │                                                  │
             ▼                                                  │
     ┌────────────────┐                                        │
     │ WAIT_MOMENTS   │  Wait for m_new, v_new                 │
     └───────┬────────┘  (~4 cycles)                           │
             │ moment_update_unit.done='1'                     │
             ▼                                                  │
     ┌────────────────┐                                        │
     │ START_ADAPTIVE │  Start adaptive_lr_unit                │
     └───────┬────────┘  with m_new, v_new                     │
             │                                                  │
             ▼                                                  │
     ┌────────────────┐                                        │
     │ WAIT_ADAPTIVE  │  Wait for update value                 │
     └───────┬────────┘  (~18-21 cycles)                       │
             │ adaptive_lr_unit.done='1'                       │
             ▼                                                  │
     ┌────────────────┐                                        │
     │ COMPUTE_WEIGHT │  W_new = W_old - update                │
     └───────┬────────┘  (1 cycle)                             │
             │                                                  │
             ▼                                                  │
     ┌────────────────┐                                        │
     │    OUTPUT      │  Register outputs, done='1'            │
     └───────┬────────┘                                        │
             │                                                  │
             └──────────────────────────────────────────────────┘
```

### 4.5.5 Latency Analysis

| Stage | Cycles | Cumulative |
|-------|--------|------------|
| Start moments | 1 | 1 |
| Wait moments | 4 | 5 |
| Start adaptive | 1 | 6 |
| Wait adaptive | 18-21 | 24-27 |
| Compute weight | 1 | 25-28 |
| Output | 1 | 26-29 |
| **Total** | **~27** | Per parameter |

### 4.5.6 Internal Structure

```
┌─────────────────────────────────────────────────────────────────────┐
│                        adam_update_unit                              │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                      FSM Controller                             │ │
│  └──────────────────────────┬─────────────────────────────────────┘ │
│                             │                                        │
│         ┌───────────────────┴───────────────────┐                   │
│         │                                       │                   │
│         ▼                                       ▼                   │
│  ┌──────────────────┐                  ┌──────────────────┐        │
│  │ moment_update_   │                  │  adaptive_lr_    │        │
│  │      unit        │─────────────────►│      unit        │        │
│  │                  │   m_new, v_new   │                  │        │
│  │ Computes:        │                  │ Computes:        │        │
│  │ m_new, v_new     │                  │ η×m/(√v+ε)       │        │
│  └──────────────────┘                  └────────┬─────────┘        │
│                                                 │ update           │
│                                                 ▼                  │
│                                        ┌──────────────────┐        │
│  weight_old ──────────────────────────►│    Subtractor    │        │
│                                        │  W_new = W - upd │        │
│                                        └────────┬─────────┘        │
│                                                 │                  │
│                                                 ▼                  │
│                                        ┌──────────────────┐        │
│                                        │   Saturation     │───────►│ weight_new
│                                        └──────────────────┘        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4.6 Module: adam_optimizer

### 4.6.1 Purpose

Top-level optimizer that iterates through all 13 parameters, performing Adam update on each. Replaces `weight_update_datapath` in your training system.

### 4.6.2 Operation Sequence

For each training step:
```
FOR param_idx = 0 TO 12:
    1. Read gradient[param_idx] from gradient_register_bank
    2. Read m[param_idx], v[param_idx] from moment_register_bank
    3. Read weight[param_idx] from weight_register_bank
    4. Compute Adam update via adam_update_unit
    5. Write m_new, v_new to moment_register_bank
    6. Write weight_new to weight_register_bank
NEXT param_idx
Clear gradient_register_bank
```

### 4.6.3 Interface Description

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| clk | in | 1 | System clock |
| rst | in | 1 | Synchronous reset |
| start | in | 1 | Begin optimization step |
| clear | in | 1 | Clear moments (new training) |
| beta1 | in | 16 | β₁ coefficient |
| beta2 | in | 16 | β₂ coefficient |
| learning_rate | in | 16 | η |
| epsilon | in | 16 | ε |
| grad_rd_data | in | 40 | Gradient from gradient_register_bank |
| grad_rd_addr | out | 4 | Gradient read address |
| grad_rd_en | out | 1 | Gradient read enable |
| grad_clear | out | 1 | Clear gradients after update |
| weight_rd_data | in | 16 | Weight from weight_register_bank |
| weight_rd_addr | out | 4 | Weight read address |
| weight_rd_en | out | 1 | Weight read enable |
| weight_wr_data | out | 16 | Updated weight |
| weight_wr_addr | out | 4 | Weight write address |
| weight_wr_en | out | 1 | Weight write enable |
| busy | out | 1 | Optimization in progress |
| done | out | 1 | All parameters updated |
| param_count | out | 4 | Current parameter index |
| overflow | out | 1 | Any overflow occurred |

### 4.6.4 FSM States

```
┌──────────────────────────────────────────────────────────────────┐
│                      adam_optimizer FSM                           │
└──────────────────────────────────────────────────────────────────┘

     ┌─────────┐
     │  IDLE   │◄─────────────────────────────────────────────────┐
     └────┬────┘                                                   │
          │ start='1'                                              │
          ▼                                                        │
     ┌─────────────┐                                               │
     │ INIT        │  param_idx = 0                                │
     └──────┬──────┘                                               │
            │                                                       │
            ▼                                                       │
     ┌─────────────┐                                               │
     │ READ_GRAD   │  Assert grad_rd_en, set addr                  │
     └──────┬──────┘                                               │
            │                                                       │
            ▼                                                       │
     ┌─────────────┐                                               │
     │ WAIT_GRAD   │  Wait 1 cycle for gradient data               │
     └──────┬──────┘                                               │
            │                                                       │
            ▼                                                       │
     ┌─────────────┐                                               │
     │READ_MOMENTS │  Read m, v from moment_register_bank          │
     └──────┬──────┘                                               │
            │                                                       │
            ▼                                                       │
     ┌─────────────┐                                               │
     │WAIT_MOMENTS │  Wait 1 cycle for moment data                 │
     └──────┬──────┘                                               │
            │                                                       │
            ▼                                                       │
     ┌─────────────┐                                               │
     │ READ_WEIGHT │  Read current weight                          │
     └──────┬──────┘                                               │
            │                                                       │
            ▼                                                       │
     ┌─────────────┐                                               │
     │ WAIT_WEIGHT │  Wait 1 cycle for weight data                 │
     └──────┬──────┘                                               │
            │                                                       │
            ▼                                                       │
     ┌─────────────┐                                               │
     │START_UPDATE │  Assert adam_update_unit.start                │
     └──────┬──────┘                                               │
            │                                                       │
            ▼                                                       │
     ┌─────────────┐                                               │
     │ WAIT_UPDATE │  Wait for adam_update_unit.done               │
     └──────┬──────┘  (~27 cycles)                                 │
            │ adam_update_unit.done='1'                            │
            ▼                                                       │
     ┌──────────────┐                                              │
     │WRITE_MOMENTS │  Write m_new, v_new to moment bank           │
     └──────┬───────┘                                              │
            │                                                       │
            ▼                                                       │
     ┌──────────────┐                                              │
     │ WRITE_WEIGHT │  Write weight_new to weight bank             │
     └──────┬───────┘                                              │
            │                                                       │
            ▼                                                       │
     ┌──────────────┐         param_idx < 12                       │
     │ NEXT_PARAM   │─────────────────────────────────┐            │
     └──────┬───────┘                                 │            │
            │ param_idx = 12                          │            │
            ▼                                         │            │
     ┌──────────────┐                                 │            │
     │ CLEAR_GRADS  │  Assert grad_clear             │            │
     └──────┬───────┘                                 │            │
            │                                         │            │
            ▼                                         │            │
     ┌──────────────┐                                 │            │
     │    DONE      │  Assert done='1'               │            │
     └──────┬───────┘                                 │            │
            │                                         │            │
            └─────────────────────────────────────────┴────────────┘
                              (back to IDLE)
```

### 4.6.5 Latency Analysis

**Per parameter:**
| Stage | Cycles |
|-------|--------|
| Read gradient | 2 |
| Read moments | 2 |
| Read weight | 2 |
| Adam update | 27 |
| Write moments | 1 |
| Write weight | 1 |
| Next param | 1 |
| **Subtotal** | **~36** |

**Total for 13 parameters:**
```
13 × 36 + overhead ≈ 470-500 cycles
```

**Comparison with your current SGD:**
| Optimizer | Cycles per step | Ratio |
|-----------|-----------------|-------|
| SGD (current) | ~100 | 1× |
| Adam | ~500 | 5× |

The 5× overhead is typical and worthwhile for the faster convergence Adam provides.

### 4.6.6 Internal Structure

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           adam_optimizer                                  │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                         FSM Controller                               │ │
│  │   Manages: param_idx, memory read/write sequencing                  │ │
│  └──────────────────────────────┬──────────────────────────────────────┘ │
│                                 │                                         │
│                                 ▼                                         │
│                    ┌────────────────────────┐                            │
│                    │    adam_update_unit    │                            │
│                    │                        │                            │
│                    │  ┌──────────────────┐  │                            │
│                    │  │moment_update_unit│  │                            │
│                    │  └──────────────────┘  │                            │
│                    │  ┌──────────────────┐  │                            │
│                    │  │ adaptive_lr_unit │  │                            │
│                    │  │  ┌────────────┐  │  │                            │
│                    │  │  │ sqrt_unit  │  │  │                            │
│                    │  │  └────────────┘  │  │                            │
│                    │  │  ┌────────────┐  │  │                            │
│                    │  │  │division_   │  │  │                            │
│                    │  │  │   unit     │  │  │                            │
│                    │  │  └────────────┘  │  │                            │
│                    │  └──────────────────┘  │                            │
│                    └────────────────────────┘                            │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                   moment_register_bank                              │  │
│  │              m[0..12], v[0..12] storage                             │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  External connections to:                                                 │
│    - gradient_register_bank (read gradients)                             │
│    - weight_register_bank (read/write weights)                           │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

---

# Part 5: Integration with Existing System

## 5.1 Modified Training Flow

Current flow with SGD:
```
FORWARD → BACKWARD → WEIGHT_UPDATE (SGD) → NEXT_SAMPLE
```

New flow with Adam:
```
FORWARD → BACKWARD → WEIGHT_UPDATE (Adam) → NEXT_SAMPLE
```

The interface remains the same—only the weight_update module changes.

## 5.2 Memory Map Extension

**Current system:**
| Bank | Contents | Size |
|------|----------|------|
| weight_register_bank | W[0..12] | 13 × 16 = 208 bits |
| gradient_register_bank | ∂L/∂W[0..12] | 13 × 40 = 520 bits |
| forward_cache | z, a values | 10 × 16 = 160 bits |

**With Adam:**
| Bank | Contents | Size |
|------|----------|------|
| weight_register_bank | W[0..12] | 13 × 16 = 208 bits |
| gradient_register_bank | ∂L/∂W[0..12] | 13 × 40 = 520 bits |
| forward_cache | z, a values | 10 × 16 = 160 bits |
| **moment_register_bank** | **m[0..12], v[0..12]** | **13 × 32 = 416 bits** |

**Total additional storage:** 416 bits (~52 bytes)

## 5.3 Resource Utilization Estimate

**New modules:**
| Module | LUTs | FFs | DSPs | BRAM |
|--------|------|-----|------|------|
| moment_register_bank | ~50 | ~450 | 0 | 0 |
| moment_update_unit | ~150 | ~100 | 4 | 0 |
| adaptive_lr_unit | ~100 | ~80 | 2 | 0 |
| adam_update_unit | ~80 | ~60 | 0 | 0 |
| adam_optimizer | ~200 | ~150 | 0 | 0 |
| **Total new** | **~580** | **~840** | **6** | **0** |

**Reused modules:**
| Module | Already exists |
|--------|----------------|
| sqrt_unit | ✓ |
| division_unit | ✓ |
| reciprocal_unit | ✓ |
| saturation_unit | ✓ |

## 5.4 Interface to neuron_training_top

Replace instantiation of `weight_update_datapath` with `adam_optimizer`:

**Removed signals:**
- (none—interface is compatible)

**Added signals:**
| Signal | Width | Description |
|--------|-------|-------------|
| beta1 | 16 | β₁ hyperparameter |
| beta2 | 16 | β₂ hyperparameter |
| epsilon | 16 | ε hyperparameter |
| moment_clear | 1 | Clear moments for new training |

**Modified timing:**
- Weight update phase takes ~500 cycles instead of ~100
- Overall training step: ~700 cycles instead of ~300

---

# Part 6: Verification Strategy

## 6.1 Unit Test Cases

### 6.1.1 moment_update_unit Tests

| Test | Input | Expected Output |
|------|-------|-----------------|
| Zero gradient | g=0, m=0, v=0 | m=0, v=0 |
| First step | g=1.0, m=0, v=0 | m=0.1, v=0.001 |
| Momentum buildup | g=1.0 repeated | m approaches 1.0 |
| Negative gradient | g=-0.5, m=0, v=0 | m=-0.05, v=0.00025 |
| Saturation | g=3.9 (max) | v saturates appropriately |

### 6.1.2 adaptive_lr_unit Tests

| Test | Input | Expected Output |
|------|-------|-----------------|
| Unit case | m=1.0, v=1.0, η=1.0 | update ≈ 1/(1+ε) ≈ 1.0 |
| Large variance | m=1.0, v=4.0, η=0.01 | update ≈ 0.005 |
| Small variance | m=1.0, v=0.01, η=0.01 | update ≈ 0.1 |
| Zero moment | m=0, v=1.0, η=0.01 | update = 0 |
| Near-zero v | m=1.0, v≈0, η=0.01 | update = η×m/ε |

### 6.1.3 Full Adam Update Tests

Compare against floating-point reference:
```
Given: g=0.5, m_old=0.1, v_old=0.01, W_old=1.0
       β₁=0.9, β₂=0.999, η=0.001, ε=1e-8

Expected (float):
  m_new = 0.9×0.1 + 0.1×0.5 = 0.14
  v_new = 0.999×0.01 + 0.001×0.25 = 0.01024
  sqrt_v = 0.1012
  update = 0.001 × 0.14 / (0.1012 + 1e-8) = 0.001383
  W_new = 1.0 - 0.001383 = 0.998617

Verify fixed-point result within tolerance.
```

## 6.2 System Integration Tests

1. **Convergence test:** Train XOR problem, verify loss decreases
2. **Comparison test:** Same problem with SGD vs Adam, verify Adam converges faster
3. **Numerical stability:** Train for 10000 steps, verify no overflow
4. **Moment accumulation:** Verify m, v values evolve correctly over training

---

# Part 7: Implementation Roadmap

## 7.1 Recommended Build Order

```
Week 1: Storage and Coefficients
├── Day 1-2: moment_register_bank
│            (similar to gradient_register_bank)
├── Day 3: beta_coefficient_rom (or parameter ports)
└── Day 4-5: Unit tests for storage

Week 2: Core Computation Modules
├── Day 1-2: moment_update_unit
│            (4-stage pipeline)
├── Day 3-4: moment_update_unit testbench
└── Day 5: Integration check

Week 3: Adaptive Learning Rate
├── Day 1-2: adaptive_lr_unit
│            (integrates sqrt_unit, division_unit)
├── Day 3-4: adaptive_lr_unit testbench
└── Day 5: Verify against floating-point reference

Week 4: Complete Adam Update
├── Day 1-2: adam_update_unit
│            (combines moment + adaptive_lr)
├── Day 3: adam_update_unit testbench
└── Day 4-5: Numerical accuracy verification

Week 5: Top-Level Optimizer
├── Day 1-2: adam_optimizer FSM
├── Day 3-4: Full system integration
└── Day 5-6: Training tests (XOR, simple patterns)

Week 6: Optimization and Verification
├── Day 1-2: Performance profiling
├── Day 3-4: Edge case testing
└── Day 5: Documentation and cleanup
```

## 7.2 Module Dependencies

```
                    ┌─────────────────────┐
                    │   adam_optimizer    │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
    ┌─────────────────┐ ┌─────────────┐ ┌──────────────────┐
    │adam_update_unit │ │moment_reg_  │ │(existing banks)  │
    └────────┬────────┘ │   bank      │ │gradient_reg_bank │
             │          └─────────────┘ │weight_reg_bank   │
    ┌────────┴────────┐                 └──────────────────┘
    │                 │
    ▼                 ▼
┌──────────┐   ┌──────────────┐
│moment_   │   │adaptive_lr_  │
│update_   │   │    unit      │
│  unit    │   └──────┬───────┘
└──────────┘          │
                ┌─────┴─────┐
                │           │
                ▼           ▼
          ┌──────────┐ ┌──────────┐
          │sqrt_unit │ │division_ │
          │(existing)│ │  unit    │
          └──────────┘ │(existing)│
                       └──────────┘
```

---

# Part 8: Summary

## 8.1 What We're Building

| Module | Lines (est.) | Complexity | Dependencies |
|--------|--------------|------------|--------------|
| moment_register_bank | ~80 | ⭐ Easy | None |
| beta_coefficient_rom | ~40 | ⭐ Easy | None |
| moment_update_unit | ~150 | ⭐⭐ Medium | None |
| adaptive_lr_unit | ~200 | ⭐⭐⭐ Hard | sqrt_unit, division_unit |
| adam_update_unit | ~180 | ⭐⭐ Medium | moment_update, adaptive_lr |
| adam_optimizer | ~300 | ⭐⭐⭐ Hard | adam_update_unit, moment_bank |
| **Total** | **~950** | | |

## 8.2 Performance Comparison

| Metric | SGD (current) | Adam |
|--------|---------------|------|
| Cycles per weight update | ~100 | ~500 |
| Storage per parameter | 16 bits | 48 bits |
| Convergence speed | Baseline | 2-10× faster |
| Learning rate sensitivity | High | Low |
| Hyperparameter tuning | Difficult | Easier |

## 8.3 Key Design Decisions

1. **Simplified Adam:** No bias correction (eliminates power computation)
2. **Sequential processing:** One parameter at a time (simpler, sufficient for 13 params)
3. **Reuse existing modules:** sqrt_unit, division_unit already verified
4. **Q2.13 throughout:** Consistent with existing datapath
5. **Separate moment bank:** Clean separation of optimizer state

---

## Ready to Implement?

Start with `moment_register_bank`—it's the simplest module and provides the foundation for storing Adam's state. Once that's working, move to `moment_update_unit` for the core exponential moving average computation.
