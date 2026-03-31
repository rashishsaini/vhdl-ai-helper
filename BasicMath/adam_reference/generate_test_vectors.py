"""
Test Vector Generation for Adam Optimizer VHDL Modules

Generates test vectors for validation against golden reference:
1. power_unit_vectors.txt - β^t for various t values
2. moment_update_vectors.txt - Random gradients with moment updates
3. bias_correction_vectors.txt - Bias correction at different timesteps
4. adaptive_lr_vectors.txt - Adaptive learning rate computation
5. adam_update_vectors.txt - Complete parameter updates
6. full_adam_13param_vectors.txt - Complete 13-parameter training sequence

Author: FPGA Neural Network Project
Date: December 2025
"""

import numpy as np
import sys
from adam_optimizer_golden import AdamOptimizerQ2_13
from fixed_point_utils import Q2_13, Q0_15, hex_str


def generate_power_unit_vectors(filename="test_vectors/power_unit_vectors.txt"):
    """Generate test vectors for power_unit.vhd (β^t computation)"""

    print(f"\nGenerating {filename}...")

    with open(filename, 'w') as f:
        f.write("# Power Unit Test Vectors\n")
        f.write("# Format: base(float) exponent(int) result_expected(float) result_hex\n")
        f.write("# Q0.15 format for base and result\n\n")

        # Test cases
        test_cases = [
            # (base, exponent_list)
            (0.9, [0, 1, 2, 3, 5, 10, 50, 100, 500, 1000]),
            (0.999, [0, 1, 2, 5, 10, 50, 100, 500, 1000]),
            (0.95, [0, 1, 10, 100]),
            (0.99, [0, 1, 10, 100]),
            (0.5, [0, 1, 5, 10]),
            (1.0, [0, 1, 10, 100, 1000])
        ]

        vector_count = 0
        for base, exponents in test_cases:
            base_int = Q0_15.to_fixed(base)
            base_hex = hex_str(base_int, 16)

            for exp in exponents:
                # Compute expected result
                result = base ** exp
                result_int = Q0_15.to_fixed(result)
                result_hex = hex_str(result_int, 16)

                f.write(f"{base:.6f} {exp:4d} {result:.9f} {result_hex}\n")
                vector_count += 1

        print(f"  Generated {vector_count} test vectors for power_unit")


def generate_moment_update_vectors(filename="test_vectors/moment_update_vectors.txt", num_vectors=100):
    """Generate test vectors for moment_update_unit.vhd"""

    print(f"\nGenerating {filename}...")

    # Initialize with fixed beta values
    beta1 = 0.9
    beta2 = 0.999
    beta1_int = Q0_15.to_fixed(beta1)
    beta2_int = Q0_15.to_fixed(beta2)
    one_minus_beta1_int = Q0_15.to_fixed(1.0 - beta1)
    one_minus_beta2_int = Q0_15.to_fixed(1.0 - beta2)

    with open(filename, 'w') as f:
        f.write("# Moment Update Unit Test Vectors\n")
        f.write("# Format: gradient m_old v_old m_new_expected v_new_expected\n")
        f.write(f"# Beta1={beta1}, Beta2={beta2}\n\n")

        np.random.seed(42)  # Reproducible

        for i in range(num_vectors):
            # Generate random inputs in Q2.13 range
            gradient = np.random.uniform(-2.0, 2.0)
            m_old = np.random.uniform(-1.0, 1.0)
            v_old = np.random.uniform(0.0, 1.0)  # v must be non-negative

            # Convert to fixed-point
            g_int = Q2_13.to_fixed(gradient)
            m_old_int = Q2_13.to_fixed(m_old)
            v_old_int = Q2_13.to_fixed(v_old)

            # Compute using golden reference (bit-accurate)
            from adam_optimizer_golden import AdamOptimizerQ2_13
            adam = AdamOptimizerQ2_13(num_params=1, beta1=beta1, beta2=beta2)
            m_new_int, v_new_int = adam.moment_update(g_int, m_old_int, v_old_int)

            # Convert back to float for readability
            gradient_back = Q2_13.from_fixed(g_int)
            m_old_back = Q2_13.from_fixed(m_old_int)
            v_old_back = Q2_13.from_fixed(v_old_int)
            m_new = Q2_13.from_fixed(m_new_int)
            v_new = Q2_13.from_fixed(v_new_int)

            f.write(f"{gradient_back:10.6f} {m_old_back:10.6f} {v_old_back:10.6f} "
                   f"{m_new:10.6f} {v_new:10.6f}\n")

        print(f"  Generated {num_vectors} test vectors for moment_update_unit")


def generate_bias_correction_vectors(filename="test_vectors/bias_correction_vectors.txt"):
    """Generate test vectors for bias_correction_unit.vhd"""

    print(f"\nGenerating {filename}...")

    beta1 = 0.9
    beta2 = 0.999

    with open(filename, 'w') as f:
        f.write("# Bias Correction Unit Test Vectors\n")
        f.write("# Format: m v timestep m_hat_expected v_hat_expected\n")
        f.write(f"# Beta1={beta1}, Beta2={beta2}\n\n")

        # Test at various timesteps
        timesteps = [1, 2, 3, 5, 10, 20, 50, 100, 500, 1000]
        m_values = [0.1, 0.5, 1.0, -0.5]
        v_values = [0.01, 0.1, 0.5, 1.0]

        vector_count = 0
        adam = AdamOptimizerQ2_13(num_params=1, beta1=beta1, beta2=beta2)

        for t in timesteps:
            for m in m_values:
                for v in v_values:
                    m_int = Q2_13.to_fixed(m)
                    v_int = Q2_13.to_fixed(v)

                    # Compute bias correction
                    m_hat_int, v_hat_int = adam.bias_correction(m_int, v_int, t)

                    m_hat = Q2_13.from_fixed(m_hat_int)
                    v_hat = Q2_13.from_fixed(v_hat_int)

                    f.write(f"{m:8.4f} {v:8.4f} {t:4d} {m_hat:10.6f} {v_hat:10.6f}\n")
                    vector_count += 1

        print(f"  Generated {vector_count} test vectors for bias_correction_unit")


def generate_adaptive_lr_vectors(filename="test_vectors/adaptive_lr_vectors.txt", num_vectors=50):
    """Generate test vectors for adaptive_lr_unit.vhd"""

    print(f"\nGenerating {filename}...")

    lr = 0.001
    eps = 1e-4

    with open(filename, 'w') as f:
        f.write("# Adaptive Learning Rate Unit Test Vectors\n")
        f.write("# Format: m_hat v_hat update_expected\n")
        f.write(f"# learning_rate={lr}, epsilon={eps}\n\n")

        np.random.seed(43)
        adam = AdamOptimizerQ2_13(num_params=1, lr=lr, eps=eps)

        # Test cases covering edge cases
        test_cases = [
            # (m_hat, v_hat) - edge cases
            (0.0, 0.0),
            (0.0, 1.0),
            (1.0, 0.0),
            (1.0, 1.0),
            (0.5, 0.25),
            (-0.5, 0.25),
        ]

        # Add random cases
        for _ in range(num_vectors - len(test_cases)):
            m_hat = np.random.uniform(-1.0, 1.0)
            v_hat = np.random.uniform(0.0, 1.0)
            test_cases.append((m_hat, v_hat))

        for m_hat, v_hat in test_cases:
            m_hat_int = Q2_13.to_fixed(m_hat)
            v_hat_int = Q2_13.to_fixed(v_hat)

            # Compute update
            update_int = adam.adaptive_lr_computation(m_hat_int, v_hat_int)
            update = Q2_13.from_fixed(update_int)

            f.write(f"{m_hat:10.6f} {v_hat:10.6f} {update:12.8f}\n")

        print(f"  Generated {len(test_cases)} test vectors for adaptive_lr_unit")


def generate_adam_update_vectors(filename="test_vectors/adam_update_vectors.txt", num_steps=100):
    """Generate test vectors for adam_update_unit.vhd (complete updates)"""

    print(f"\nGenerating {filename}...")

    adam = AdamOptimizerQ2_13(num_params=1, beta1=0.9, beta2=0.999, lr=0.001, eps=1e-4)

    with open(filename, 'w') as f:
        f.write("# Adam Update Unit Test Vectors (Complete Updates)\n")
        f.write("# Format: timestep gradient weight_old m_new v_new weight_new\n\n")

        np.random.seed(44)
        weight = 1.0

        for t in range(1, num_steps + 1):
            # Random gradient
            gradient = np.random.uniform(-0.5, 0.5)

            # Perform step
            result = adam.step(param_idx=0, gradient=gradient, weight_old=weight)

            # Update weight for next iteration
            weight = result['weight_new']

            f.write(f"{t:4d} {gradient:10.6f} {weight:10.6f} "
                   f"{result['m_new']:10.6f} {result['v_new']:10.6f} "
                   f"{result['weight_new']:10.6f}\n")

        print(f"  Generated {num_steps} test vectors for adam_update_unit")


def generate_full_13param_vectors(filename="test_vectors/full_adam_13param_vectors.txt", num_epochs=10):
    """Generate test vectors for complete 13-parameter Adam optimizer"""

    print(f"\nGenerating {filename}...")

    adam = AdamOptimizerQ2_13(num_params=13, beta1=0.9, beta2=0.999, lr=0.001, eps=1e-4)

    with open(filename, 'w') as f:
        f.write("# Full Adam Optimizer Test Vectors (13 parameters)\n")
        f.write("# Format: epoch param_idx gradient weight_old weight_new m_new v_new\n\n")

        np.random.seed(45)

        # Initialize weights
        weights = np.random.uniform(-1.0, 1.0, 13)

        vector_count = 0
        for epoch in range(1, num_epochs + 1):
            # Generate gradients for all 13 parameters
            gradients = np.random.uniform(-0.3, 0.3, 13)

            # Update all parameters
            for param_idx in range(13):
                result = adam.step(param_idx=param_idx,
                                 gradient=gradients[param_idx],
                                 weight_old=weights[param_idx])

                f.write(f"{epoch:3d} {param_idx:2d} "
                       f"{gradients[param_idx]:10.6f} "
                       f"{weights[param_idx]:10.6f} "
                       f"{result['weight_new']:10.6f} "
                       f"{result['m_new']:10.6f} "
                       f"{result['v_new']:10.6f}\n")

                # Update weight for next iteration
                weights[param_idx] = result['weight_new']
                vector_count += 1

        print(f"  Generated {vector_count} test vectors for full adam_optimizer")


def main():
    """Generate all test vectors"""

    print("=" * 70)
    print("Adam Optimizer Test Vector Generation")
    print("=" * 70)

    # Create test_vectors directory if it doesn't exist
    import os
    os.makedirs("../test_vectors", exist_ok=True)

    # Generate all vector files
    generate_power_unit_vectors("../test_vectors/power_unit_vectors.txt")
    generate_moment_update_vectors("../test_vectors/moment_update_vectors.txt", num_vectors=100)
    generate_bias_correction_vectors("../test_vectors/bias_correction_vectors.txt")
    generate_adaptive_lr_vectors("../test_vectors/adaptive_lr_vectors.txt", num_vectors=50)
    generate_adam_update_vectors("../test_vectors/adam_update_vectors.txt", num_steps=100)
    generate_full_13param_vectors("../test_vectors/full_adam_13param_vectors.txt", num_epochs=10)

    print("\n" + "=" * 70)
    print("Test vector generation complete!")
    print("All vectors saved to ../test_vectors/")
    print("=" * 70 + "\n")


if __name__ == "__main__":
    main()
