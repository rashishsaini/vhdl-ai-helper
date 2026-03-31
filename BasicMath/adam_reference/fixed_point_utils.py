"""
Fixed-Point Arithmetic Utilities for VHDL Adam Optimizer Testing

Provides Q2.13 and Q0.15 fixed-point conversion functions that exactly match
the behavior of VHDL implementations, including saturation and rounding.

Author: FPGA Neural Network Project
Date: December 2025
"""

import numpy as np


class FixedPointFormat:
    """Defines a fixed-point number format"""

    def __init__(self, total_bits, frac_bits):
        """
        Initialize fixed-point format

        Args:
            total_bits: Total number of bits (including sign bit)
            frac_bits: Number of fractional bits
        """
        self.total_bits = total_bits
        self.frac_bits = frac_bits
        self.int_bits = total_bits - frac_bits
        self.scale = 2 ** frac_bits

        # Saturation limits
        self.max_int = (2 ** (total_bits - 1)) - 1
        self.min_int = -(2 ** (total_bits - 1))
        self.max_val = self.max_int / self.scale
        self.min_val = self.min_int / self.scale

        # Resolution (LSB value)
        self.resolution = 1.0 / self.scale

    def to_fixed(self, value, round_mode='half_up'):
        """
        Convert floating-point to fixed-point integer representation

        Args:
            value: Floating-point value
            round_mode: 'half_up', 'half_down', 'floor', 'ceil', 'truncate'

        Returns:
            Integer representation (saturated to valid range)
        """
        # Scale
        scaled = value * self.scale

        # Round
        if round_mode == 'half_up':
            rounded = np.round(scaled)
        elif round_mode == 'half_down':
            rounded = np.floor(scaled + 0.499999)
        elif round_mode == 'floor':
            rounded = np.floor(scaled)
        elif round_mode == 'ceil':
            rounded = np.ceil(scaled)
        elif round_mode == 'truncate':
            rounded = np.trunc(scaled)
        else:
            raise ValueError(f"Unknown round_mode: {round_mode}")

        # Convert to integer
        int_val = int(rounded)

        # Saturate
        if int_val > self.max_int:
            return self.max_int
        elif int_val < self.min_int:
            return self.min_int
        else:
            return int_val

    def from_fixed(self, int_value):
        """
        Convert fixed-point integer representation to floating-point

        Args:
            int_value: Integer representation

        Returns:
            Floating-point value
        """
        return int_value / self.scale

    def saturate(self, value):
        """
        Saturate a floating-point value to the valid range

        Args:
            value: Floating-point value

        Returns:
            Saturated value
        """
        if value > self.max_val:
            return self.max_val
        elif value < self.min_val:
            return self.min_val
        else:
            return value

    def saturate_int(self, int_value):
        """
        Saturate an integer to the valid range

        Args:
            int_value: Integer value

        Returns:
            Saturated integer
        """
        if int_value > self.max_int:
            return self.max_int
        elif int_value < self.min_int:
            return self.min_int
        else:
            return int_value

    def __repr__(self):
        return (f"FixedPointFormat(Q{self.int_bits}.{self.frac_bits}, "
                f"range=[{self.min_val:.6f}, {self.max_val:.6f}], "
                f"resolution={self.resolution:.9f})")


# Standard formats used in Adam Optimizer
Q2_13 = FixedPointFormat(total_bits=16, frac_bits=13)    # Weights, gradients, moments
Q0_15 = FixedPointFormat(total_bits=16, frac_bits=15)    # Beta coefficients, learning rate
Q0_20 = FixedPointFormat(total_bits=20, frac_bits=20)    # Epsilon (high precision)
Q4_26 = FixedPointFormat(total_bits=32, frac_bits=26)    # Intermediate products


def multiply_fixed(a_int, b_int, format_a, format_b, format_out, round_mode='half_up'):
    """
    Multiply two fixed-point numbers with format conversion

    Example: Q2.13 × Q0.15 → Q2.13

    Args:
        a_int: Integer representation of first operand
        b_int: Integer representation of second operand
        format_a: Format of first operand
        format_b: Format of second operand
        format_out: Desired output format
        round_mode: Rounding mode for scaling

    Returns:
        Integer representation in output format
    """
    # Multiply (results in Q(a.int+b.int).(a.frac+b.frac))
    product = a_int * b_int

    # Determine shift amount
    product_frac_bits = format_a.frac_bits + format_b.frac_bits
    shift = product_frac_bits - format_out.frac_bits

    if shift > 0:
        # Need to shift right (scale down)
        if round_mode == 'half_up':
            # Add rounding constant before shift
            rounded = (product + (1 << (shift - 1))) >> shift
        else:
            rounded = product >> shift
    elif shift < 0:
        # Need to shift left (scale up)
        rounded = product << (-shift)
    else:
        rounded = product

    # Saturate
    return format_out.saturate_int(int(rounded))


def add_fixed(a_int, b_int, format_common):
    """
    Add two fixed-point numbers (same format)

    Args:
        a_int: Integer representation of first operand
        b_int: Integer representation of second operand
        format_common: Format of both operands and result

    Returns:
        Integer representation (saturated)
    """
    result = a_int + b_int
    return format_common.saturate_int(result)


def subtract_fixed(a_int, b_int, format_common):
    """
    Subtract two fixed-point numbers (same format)

    Args:
        a_int: Integer representation of minuend
        b_int: Integer representation of subtrahend
        format_common: Format of both operands and result

    Returns:
        Integer representation (saturated)
    """
    result = a_int - b_int
    return format_common.saturate_int(result)


def hex_str(int_value, bits=16):
    """
    Convert integer to hex string (for VHDL comparison)

    Args:
        int_value: Integer value
        bits: Number of bits

    Returns:
        Hex string like "0x7FFF"
    """
    if int_value < 0:
        # Two's complement
        int_value = (1 << bits) + int_value
    return f"0x{int_value:0{bits//4}X}"


def binary_str(int_value, bits=16):
    """
    Convert integer to binary string (for VHDL comparison)

    Args:
        int_value: Integer value
        bits: Number of bits

    Returns:
        Binary string like "0111111111111111"
    """
    if int_value < 0:
        # Two's complement
        int_value = (1 << bits) + int_value
    return f"{int_value:0{bits}b}"


# Example usage and tests
if __name__ == "__main__":
    print("Fixed-Point Utilities Test\n")
    print("=" * 60)

    # Test Q2.13 format
    print(f"\nQ2.13 Format: {Q2_13}")
    test_vals = [0.0, 1.0, -1.0, 2.0, -2.0, 3.999, -4.0, 0.0001, -0.0001]

    print("\nQ2.13 Conversions:")
    print(f"{'Real':>10} | {'Int':>7} | {'Hex':>8} | {'Back':>10} | {'Error':>12}")
    print("-" * 60)
    for val in test_vals:
        int_val = Q2_13.to_fixed(val)
        back = Q2_13.from_fixed(int_val)
        error = abs(val - back)
        print(f"{val:10.6f} | {int_val:7d} | {hex_str(int_val, 16):>8} | "
              f"{back:10.6f} | {error:.9f}")

    # Test Q0.15 format (for beta coefficients)
    print(f"\n\nQ0.15 Format: {Q0_15}")
    test_betas = [0.9, 0.999, 0.1, 0.001, 1.0, 0.0]

    print("\nQ0.15 Conversions (Beta coefficients):")
    print(f"{'Real':>10} | {'Int':>7} | {'Hex':>8} | {'Back':>10} | {'Error':>12}")
    print("-" * 60)
    for val in test_betas:
        int_val = Q0_15.to_fixed(val)
        back = Q0_15.from_fixed(int_val)
        error = abs(val - back) if abs(val) > 1e-10 else abs(val - back)
        print(f"{val:10.6f} | {int_val:7d} | {hex_str(int_val, 16):>8} | "
              f"{back:10.6f} | {error:.9f}")

    # Test multiplication
    print("\n\nMultiplication Test: Q2.13 × Q0.15 → Q2.13")
    a_float = 1.5
    b_float = 0.5
    a_int = Q2_13.to_fixed(a_float)
    b_int = Q0_15.to_fixed(b_float)
    result_int = multiply_fixed(a_int, b_int, Q2_13, Q0_15, Q2_13)
    result_float = Q2_13.from_fixed(result_int)
    expected = a_float * b_float

    print(f"  {a_float} (Q2.13: {a_int}) × {b_float} (Q0.15: {b_int})")
    print(f"  = {result_float} (Q2.13: {result_int})")
    print(f"  Expected: {expected}, Error: {abs(expected - result_float):.9f}")

    # Test saturation
    print("\n\nSaturation Test:")
    overflow_vals = [5.0, -5.0, 10.0]
    for val in overflow_vals:
        int_val = Q2_13.to_fixed(val)
        back = Q2_13.from_fixed(int_val)
        print(f"  {val:6.2f} → {int_val:7d} (saturated to {back:.6f})")

    print("\n" + "=" * 60)
    print("Tests complete!\n")
