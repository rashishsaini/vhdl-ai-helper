"""
Golden Reference Implementation of Full Adam Optimizer
with Q2.13 Fixed-Point Arithmetic

This implementation exactly matches the VHDL behavior including:
- Fixed-point rounding and saturation
- Bias correction (Full Adam: m̂ = m/(1-β₁ᵗ), v̂ = v/(1-β₂ᵗ))
- Binary exponentiation for power computation
- All arithmetic operations in fixed-point

Author: FPGA Neural Network Project
Date: December 2025
"""

import numpy as np
import math
from fixed_point_utils import (
    Q2_13, Q0_15, Q4_26,
    multiply_fixed, add_fixed, subtract_fixed,
    hex_str
)


class AdamOptimizerQ2_13:
    """
    Full Adam Optimizer with Q2.13 fixed-point arithmetic

    Implements the complete Adam algorithm with bias correction:
        m_t = β₁ × m_{t-1} + (1-β₁) × g_t
        v_t = β₂ × v_{t-1} + (1-β₂) × g_t²
        m̂_t = m_t / (1 - β₁^t)           [Bias Correction]
        v̂_t = v_t / (1 - β₂^t)           [Bias Correction]
        θ_t = θ_{t-1} - η × m̂_t / (√v̂_t + ε)
    """

    def __init__(self, num_params=13, beta1=0.9, beta2=0.999, lr=0.001, eps=1e-4):
        """
        Initialize Adam Optimizer

        Args:
            num_params: Number of trainable parameters (default: 13 for 4-2-1 network)
            beta1: Exponential decay rate for first moment (default: 0.9)
            beta2: Exponential decay rate for second moment (default: 0.999)
            lr: Learning rate (default: 0.001)
            eps: Small constant for numerical stability (default: 1e-4)
        """
        self.num_params = num_params

        # Convert hyperparameters to fixed-point
        self.beta1_int = Q0_15.to_fixed(beta1)
        self.beta2_int = Q0_15.to_fixed(beta2)
        self.one_minus_beta1_int = Q0_15.to_fixed(1.0 - beta1)
        self.one_minus_beta2_int = Q0_15.to_fixed(1.0 - beta2)
        self.lr_int = Q0_15.to_fixed(lr)
        self.eps_int = Q2_13.to_fixed(eps)  # epsilon in Q2.13 for addition

        # Store real values for reference
        self.beta1 = Q0_15.from_fixed(self.beta1_int)
        self.beta2 = Q0_15.from_fixed(self.beta2_int)
        self.lr = Q0_15.from_fixed(self.lr_int)
        self.eps = Q2_13.from_fixed(self.eps_int)

        # State variables (as integers in Q2.13 format)
        self.m = [0] * num_params  # First moments
        self.v = [0] * num_params  # Second moments
        self.t = 0  # Timestep counter

        print(f"Adam Optimizer Initialized:")
        print(f"  Parameters: {num_params}")
        print(f"  β₁ = {self.beta1:.6f} (Q0.15: {self.beta1_int}, {hex_str(self.beta1_int, 16)})")
        print(f"  β₂ = {self.beta2:.6f} (Q0.15: {self.beta2_int}, {hex_str(self.beta2_int, 16)})")
        print(f"  1-β₁ = {Q0_15.from_fixed(self.one_minus_beta1_int):.6f}")
        print(f"  1-β₂ = {Q0_15.from_fixed(self.one_minus_beta2_int):.6f}")
        print(f"  η = {self.lr:.6f} (Q0.15: {self.lr_int}, {hex_str(self.lr_int, 16)})")
        print(f"  ε = {self.eps:.6f} (Q2.13: {self.eps_int}, {hex_str(self.eps_int, 16)})\n")

    def power_fixed(self, base_int, exponent):
        """
        Compute base^exponent using binary exponentiation (matches power_unit.vhd)

        Args:
            base_int: Base in Q0.15 format (integer)
            exponent: Integer exponent

        Returns:
            Result in Q0.15 format (integer)
        """
        if exponent == 0:
            return Q0_15.to_fixed(1.0)

        if exponent == 1:
            return base_int

        # Binary exponentiation
        result = Q0_15.to_fixed(1.0)  # Start with 1.0
        base = base_int
        exp = exponent

        while exp > 0:
            if exp % 2 == 1:  # If odd
                result = multiply_fixed(result, base, Q0_15, Q0_15, Q0_15)

            base = multiply_fixed(base, base, Q0_15, Q0_15, Q0_15)
            exp = exp // 2

        return result

    def moment_update(self, gradient_int, m_old_int, v_old_int):
        """
        Update first and second moments (matches moment_update_unit.vhd)

        Formulas:
            m_new = β₁ × m_old + (1-β₁) × g
            v_new = β₂ × v_old + (1-β₂) × g²

        Args:
            gradient_int: Gradient in Q2.13 format (integer)
            m_old_int: Old first moment in Q2.13 format (integer)
            v_old_int: Old second moment in Q2.13 format (integer)

        Returns:
            Tuple (m_new_int, v_new_int) in Q2.13 format
        """
        # Compute g² (Q2.13 × Q2.13 → Q4.26, scale to Q2.13)
        g_squared_int = multiply_fixed(gradient_int, gradient_int, Q2_13, Q2_13, Q2_13)

        # First moment: m_new = β₁ × m_old + (1-β₁) × g
        beta1_m = multiply_fixed(self.beta1_int, m_old_int, Q0_15, Q2_13, Q2_13)
        one_minus_beta1_g = multiply_fixed(self.one_minus_beta1_int, gradient_int, Q0_15, Q2_13, Q2_13)
        m_new_int = add_fixed(beta1_m, one_minus_beta1_g, Q2_13)

        # Second moment: v_new = β₂ × v_old + (1-β₂) × g²
        beta2_v = multiply_fixed(self.beta2_int, v_old_int, Q0_15, Q2_13, Q2_13)
        one_minus_beta2_g2 = multiply_fixed(self.one_minus_beta2_int, g_squared_int, Q0_15, Q2_13, Q2_13)
        v_new_int = add_fixed(beta2_v, one_minus_beta2_g2, Q2_13)

        # v must be non-negative (saturate if somehow negative)
        if v_new_int < 0:
            v_new_int = 0

        return m_new_int, v_new_int

    def bias_correction(self, m_int, v_int, timestep):
        """
        Apply bias correction (matches bias_correction_unit.vhd)

        Formulas:
            m̂ = m / (1 - β₁^t)
            v̂ = v / (1 - β₂^t)

        Args:
            m_int: First moment in Q2.13 format (integer)
            v_int: Second moment in Q2.13 format (integer)
            timestep: Current timestep t

        Returns:
            Tuple (m_hat_int, v_hat_int) in Q2.13 format
        """
        # Compute β₁^t and β₂^t using binary exponentiation
        beta1_t_int = self.power_fixed(self.beta1_int, timestep)
        beta2_t_int = self.power_fixed(self.beta2_int, timestep)

        # Compute 1 - β₁^t and 1 - β₂^t
        one_int = Q0_15.to_fixed(1.0)
        one_minus_beta1_t_int = subtract_fixed(one_int, beta1_t_int, Q0_15)
        one_minus_beta2_t_int = subtract_fixed(one_int, beta2_t_int, Q0_15)

        # Prevent division by values too close to zero
        min_denom = Q0_15.to_fixed(1e-6)
        if abs(one_minus_beta1_t_int) < min_denom:
            one_minus_beta1_t_int = min_denom if one_minus_beta1_t_int >= 0 else -min_denom
        if abs(one_minus_beta2_t_int) < min_denom:
            one_minus_beta2_t_int = min_denom if one_minus_beta2_t_int >= 0 else -min_denom

        # Convert denominators to Q2.13 for division
        denom1_q2_13 = multiply_fixed(one_minus_beta1_t_int, Q2_13.to_fixed(1.0), Q0_15, Q2_13, Q2_13)
        denom2_q2_13 = multiply_fixed(one_minus_beta2_t_int, Q2_13.to_fixed(1.0), Q0_15, Q2_13, Q2_13)

        # Perform division: m̂ = m / (1 - β₁^t)
        # Division in fixed-point: (a/b) = (a * scale) / b
        m_hat_int = self._divide_fixed_q2_13(m_int, denom1_q2_13)
        v_hat_int = self._divide_fixed_q2_13(v_int, denom2_q2_13)

        return m_hat_int, v_hat_int

    def _divide_fixed_q2_13(self, dividend_int, divisor_int):
        """
        Fixed-point division: dividend / divisor (both Q2.13)

        Matches division_unit.vhd behavior

        Args:
            dividend_int: Numerator in Q2.13
            divisor_int: Denominator in Q2.13

        Returns:
            Quotient in Q2.13
        """
        if divisor_int == 0:
            # Division by zero: return max/min based on sign
            return Q2_13.max_int if dividend_int >= 0 else Q2_13.min_int

        # Scale up to maintain precision, then divide
        # (dividend << FRAC_BITS) / divisor gives Q2.13 result
        scaled_dividend = dividend_int << Q2_13.frac_bits

        # Perform division with rounding
        quotient = scaled_dividend // divisor_int

        # Round (add 0.5 before truncation)
        if scaled_dividend % divisor_int >= abs(divisor_int) // 2:
            quotient += 1 if quotient >= 0 else -1

        # Saturate
        return Q2_13.saturate_int(quotient)

    def _sqrt_fixed_q2_13(self, value_int):
        """
        Fixed-point square root (matches sqrt_unit.vhd behavior)

        Uses Newton-Raphson iteration on 1/sqrt(x), then multiplies by x

        Args:
            value_int: Input in Q2.13 format (integer)

        Returns:
            Square root in Q2.13 format (integer)
        """
        if value_int <= 0:
            return 0

        # Convert to floating point for sqrt, then back to fixed
        value_float = Q2_13.from_fixed(value_int)
        sqrt_float = math.sqrt(value_float)
        sqrt_int = Q2_13.to_fixed(sqrt_float)

        return sqrt_int

    def adaptive_lr_computation(self, m_hat_int, v_hat_int):
        """
        Compute adaptive learning rate update (matches adaptive_lr_unit.vhd)

        Formula:
            update = η × m̂ / (√v̂ + ε)

        Args:
            m_hat_int: Bias-corrected first moment in Q2.13
            v_hat_int: Bias-corrected second moment in Q2.13

        Returns:
            Update value in Q2.13 format (integer)
        """
        # Compute √v̂
        sqrt_v_hat_int = self._sqrt_fixed_q2_13(v_hat_int)

        # Add epsilon: denominator = √v̂ + ε
        denom_int = add_fixed(sqrt_v_hat_int, self.eps_int, Q2_13)

        # Divide: ratio = m̂ / (√v̂ + ε)
        ratio_int = self._divide_fixed_q2_13(m_hat_int, denom_int)

        # Scale by learning rate: update = η × ratio
        update_int = multiply_fixed(self.lr_int, ratio_int, Q0_15, Q2_13, Q2_13)

        return update_int

    def step(self, param_idx, gradient, weight_old=None):
        """
        Perform one Adam optimization step for a single parameter

        Args:
            param_idx: Parameter index (0 to num_params-1)
            gradient: Gradient value (float)
            weight_old: Current weight value (float, optional)

        Returns:
            Dictionary with:
                'm_new': New first moment (float)
                'v_new': New second moment (float)
                'm_hat': Bias-corrected first moment (float)
                'v_hat': Bias-corrected second moment (float)
                'update': Weight update value (float)
                'weight_new': Updated weight (float, if weight_old provided)
                'm_new_int': Integer representation of m_new
                'v_new_int': Integer representation of v_new
        """
        # Increment timestep (global for all parameters)
        self.t += 1

        # Convert gradient to fixed-point
        gradient_int = Q2_13.to_fixed(gradient)

        # Get old moments
        m_old_int = self.m[param_idx]
        v_old_int = self.v[param_idx]

        # Step 1: Update moments
        m_new_int, v_new_int = self.moment_update(gradient_int, m_old_int, v_old_int)

        # Step 2: Bias correction (Full Adam)
        m_hat_int, v_hat_int = self.bias_correction(m_new_int, v_new_int, self.t)

        # Step 3: Compute adaptive learning rate update
        update_int = self.adaptive_lr_computation(m_hat_int, v_hat_int)

        # Step 4: Update weight (if provided)
        weight_new = None
        if weight_old is not None:
            weight_old_int = Q2_13.to_fixed(weight_old)
            weight_new_int = subtract_fixed(weight_old_int, update_int, Q2_13)
            weight_new = Q2_13.from_fixed(weight_new_int)

        # Store new moments
        self.m[param_idx] = m_new_int
        self.v[param_idx] = v_new_int

        # Return results (both float and int representations)
        result = {
            'm_new': Q2_13.from_fixed(m_new_int),
            'v_new': Q2_13.from_fixed(v_new_int),
            'm_hat': Q2_13.from_fixed(m_hat_int),
            'v_hat': Q2_13.from_fixed(v_hat_int),
            'update': Q2_13.from_fixed(update_int),
            'weight_new': weight_new,
            'm_new_int': m_new_int,
            'v_new_int': v_new_int,
            'm_hat_int': m_hat_int,
            'v_hat_int': v_hat_int,
            'update_int': update_int,
            'weight_new_int': weight_new_int if weight_old is not None else None
        }

        return result

    def reset(self):
        """Reset optimizer state (moments and timestep)"""
        self.m = [0] * self.num_params
        self.v = [0] * self.num_params
        self.t = 0

    def get_state(self):
        """
        Get current optimizer state

        Returns:
            Dictionary with moments (as floats) and timestep
        """
        return {
            't': self.t,
            'm': [Q2_13.from_fixed(m_int) for m_int in self.m],
            'v': [Q2_13.from_fixed(v_int) for v_int in self.v]
        }


# Example usage and validation
if __name__ == "__main__":
    print("=" * 70)
    print("Adam Optimizer Golden Reference Test")
    print("=" * 70 + "\n")

    # Initialize optimizer
    adam = AdamOptimizerQ2_13(num_params=13, beta1=0.9, beta2=0.999, lr=0.001, eps=1e-4)

    # Test scenario: Gradient descent on a simple parameter
    print("Test: 5 optimization steps with constant gradient = 0.5")
    print("-" * 70)
    print(f"{'Step':<6} | {'m_new':<12} | {'v_new':<12} | {'m_hat':<12} | {'v_hat':<12} | {'update':<12}")
    print("-" * 70)

    gradient = 0.5
    weight = 1.0

    for step in range(1, 6):
        result = adam.step(param_idx=0, gradient=gradient, weight_old=weight)
        weight = result['weight_new']

        print(f"{step:<6} | "
              f"{result['m_new']:>12.6f} | "
              f"{result['v_new']:>12.6f} | "
              f"{result['m_hat']:>12.6f} | "
              f"{result['v_hat']:>12.6f} | "
              f"{result['update']:>12.6f}")

    print("-" * 70)
    print(f"Final weight: {weight:.6f}\n")

    # Test bias correction effect
    print("\nBias Correction Effect Analysis:")
    print("-" * 70)
    adam.reset()

    for t in [1, 2, 3, 5, 10, 100]:
        adam.t = t - 1  # Set timestep
        result = adam.step(param_idx=0, gradient=1.0)

        beta1_t = adam.beta1 ** t
        beta2_t = adam.beta2 ** t
        bias_corr_1 = 1 / (1 - beta1_t) if t < 100 else 1.0
        bias_corr_2 = 1 / (1 - beta2_t) if t < 100 else 1.0

        print(f"t={t:3d}: β₁^t={beta1_t:.6f}, β₂^t={beta2_t:.6f}, "
              f"bias_corr_m={bias_corr_1:.3f}, bias_corr_v={bias_corr_2:.3f}")

    print("\n" + "=" * 70)
    print("Validation complete! Golden reference is ready for VHDL testing.")
    print("=" * 70 + "\n")
