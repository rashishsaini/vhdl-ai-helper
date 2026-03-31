# Weight Update Mechanism Analysis

## Gradient Computation (Backward Pass)

At line 852-856 of eqeeqe.vhd:
```vhdl
grad_product := delta_reg * input_buffer(to_integer(grad_index));
weight_gradients(to_integer(grad_index)) <= resize(grad_product, GRAD_WIDTH);
```

- delta_reg: Q2.13 (16 bits) 
- input_buffer: Q2.13 (16 bits)
- grad_product: Q2.13 × Q2.13 = Q4.26 (32 bits)
- weight_gradients: Q4.26 (32 bits) ✓ CORRECT

## Bias Gradient (Fixed)

At line 865:
```vhdl
bias_gradient <= shift_left(resize(delta_reg, GRAD_WIDTH), FRAC_BITS);
```

- delta_reg: Q2.13 → shift left 13 bits → Q4.26 ✓ CORRECT (after our fix)

## Weight Update (Line 1010-1036)

```vhdl
lr_times_grad := learning_rate_latched * weight_gradients(to_integer(upd_index));
scaled_update := lr_times_grad(DATA_WIDTH + FRAC_BITS*2 - 1 downto FRAC_BITS*2);
new_weight := resize(weights(to_integer(upd_index)), DATA_WIDTH+1) -
              resize(scaled_update, DATA_WIDTH+1);
```

### Analysis:
- learning_rate: Q2.13 (16 bits)
- weight_gradients: Q4.26 (32 bits)
- lr_times_grad: Q2.13 × Q4.26 = Q6.39 (48-bit container)

### Bit Extraction:
- Extract bits [41:26] = 16 bits
- This is bits [41:26] from Q6.39 format
- Represents shifting right by 26 positions
- Result: Q2.13 format ✓ CORRECT

### Example Calculation:
- LR = 82 (0.01 in Q2.13)
- Gradient = 9664 * 8192 = 79,167,488 (Q4.26, represents ~1.18)
- Product = 82 * 79,167,488 = 6,491,734,016 (Q6.39)
- After shift right 26: 6,491,734,016 >> 26 ≈ 97
- In Q2.13: 97 represents 97/8192 ≈ 0.0118 ✓

## Conclusion

The weight update math appears CORRECT. The issue must be elsewhere:

### Possible Issues:
1. **Inputs might be zero/small** - causing zero gradients
2. **ReLU dying** - if neurons output 0, gradient is 0
3. **Weight initialization saturating activations**
4. **Error not propagating through layers correctly**
5. **Gradient vanishing through 3 layers**

### Next Steps:
1. Add assertions/debug to verify weights ARE changing
2. Check if Layer 1 outputs are all zeros (dead ReLU)
3. Verify error propagation through L3→L2→L1
4. Check if inputs to neurons are non-zero

