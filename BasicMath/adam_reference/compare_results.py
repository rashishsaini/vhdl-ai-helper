#!/usr/bin/env python3
"""
Result Comparison Tool for Adam Optimizer VHDL Implementation
Compares VHDL simulation outputs against golden reference test vectors
"""

import os
import sys
import re
from pathlib import Path
from typing import List, Tuple, Dict
from fixed_point_utils import Q2_13, Q0_15

# Directories
BASE_DIR = Path(__file__).parent.parent
VEC_DIR = BASE_DIR / "test_vectors"
GHDL_LOG_DIR = BASE_DIR / "simulation_results" / "ghdl" / "logs"
VIVADO_LOG_DIR = BASE_DIR / "simulation_results" / "vivado" / "logs"
COMP_DIR = BASE_DIR / "simulation_results" / "comparison"

# Tolerance (±2 LSB for Q2.13 = ±0.000244)
TOLERANCE_Q2_13 = 2  # LSBs
TOLERANCE_Q0_15 = 2  # LSBs


class ComparisonResult:
    """Stores comparison results for a single test vector"""
    def __init__(self, test_id: str):
        self.test_id = test_id
        self.expected_values: Dict[str, int] = {}
        self.actual_values: Dict[str, int] = {}
        self.errors: Dict[str, int] = {}
        self.passed = True

    def add_comparison(self, signal_name: str, expected: int, actual: int, tolerance: int):
        """Add a signal comparison"""
        self.expected_values[signal_name] = expected
        self.actual_values[signal_name] = actual
        error = abs(expected - actual)
        self.errors[signal_name] = error

        if error > tolerance:
            self.passed = False

    def __repr__(self):
        status = "PASS" if self.passed else "FAIL"
        return f"Test {self.test_id}: {status}"


class ModuleComparison:
    """Compares a module's simulation output against golden reference"""

    def __init__(self, module_name: str):
        self.module_name = module_name
        self.results: List[ComparisonResult] = []

    def load_test_vectors(self, vector_file: Path) -> List[Dict]:
        """Load test vectors from file"""
        vectors = []

        with open(vector_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue

                # Parse line based on module type
                parts = line.split()
                if self.module_name == "power_unit":
                    # Format: base exponent result_expected
                    vectors.append({
                        'base': float(parts[0]),
                        'exponent': int(parts[1]),
                        'result': float(parts[2])
                    })
                elif self.module_name == "moment_update_unit":
                    # Format: gradient m_old v_old m_new_expected v_new_expected
                    vectors.append({
                        'gradient': float(parts[0]),
                        'm_old': float(parts[1]),
                        'v_old': float(parts[2]),
                        'm_new': float(parts[3]),
                        'v_new': float(parts[4])
                    })
                elif self.module_name == "bias_correction_unit":
                    # Format: m v timestep m_hat_expected v_hat_expected
                    vectors.append({
                        'm': float(parts[0]),
                        'v': float(parts[1]),
                        'timestep': int(parts[2]),
                        'm_hat': float(parts[3]),
                        'v_hat': float(parts[4])
                    })
                elif self.module_name == "adaptive_lr_unit":
                    # Format: m_hat v_hat update_expected
                    vectors.append({
                        'm_hat': float(parts[0]),
                        'v_hat': float(parts[1]),
                        'update': float(parts[2])
                    })
                elif self.module_name == "adam_update_unit":
                    # Format: timestep gradient weight_old m_new v_new weight_new
                    vectors.append({
                        'timestep': int(parts[0]),
                        'gradient': float(parts[1]),
                        'weight_old': float(parts[2]),
                        'm_new': float(parts[3]),
                        'v_new': float(parts[4]),
                        'weight_new': float(parts[5])
                    })

        return vectors

    def parse_simulation_log(self, log_file: Path) -> List[Dict]:
        """Parse VHDL simulation log to extract results"""
        results = []

        with open(log_file, 'r') as f:
            content = f.read()

        # Extract result lines based on module type
        # This is a simplified parser - actual implementation depends on testbench output format
        # Expected format: "TEST <id>: <signal>=<value> <signal>=<value> ..."

        pattern = r"TEST\s+(\d+):\s+(.+)"
        matches = re.findall(pattern, content)

        for test_id, values_str in matches:
            result = {'test_id': int(test_id)}

            # Parse signal=value pairs
            pairs = values_str.split()
            for pair in pairs:
                if '=' in pair:
                    signal, value = pair.split('=')
                    result[signal] = float(value)

            results.append(result)

        return results

    def compare(self, vector_file: Path, log_file: Path):
        """Compare test vectors against simulation log"""
        # Load expected values
        vectors = self.load_test_vectors(vector_file)

        if not log_file.exists():
            print(f"ERROR: Log file not found: {log_file}")
            return

        # Parse simulation results
        sim_results = self.parse_simulation_log(log_file)

        # Compare
        for idx, (expected, actual) in enumerate(zip(vectors, sim_results)):
            result = ComparisonResult(f"{idx+1}")

            # Compare based on module type
            if self.module_name == "power_unit":
                exp_result = Q0_15.to_fixed(expected['result'])
                act_result = Q0_15.to_fixed(actual.get('result', 0))
                result.add_comparison('result', exp_result, act_result, TOLERANCE_Q0_15)

            elif self.module_name == "moment_update_unit":
                exp_m = Q2_13.to_fixed(expected['m_new'])
                act_m = Q2_13.to_fixed(actual.get('m_new', 0))
                result.add_comparison('m_new', exp_m, act_m, TOLERANCE_Q2_13)

                exp_v = Q2_13.to_fixed(expected['v_new'])
                act_v = Q2_13.to_fixed(actual.get('v_new', 0))
                result.add_comparison('v_new', exp_v, act_v, TOLERANCE_Q2_13)

            # Add more module types as needed...

            self.results.append(result)

    def generate_report(self, output_file: Path):
        """Generate comparison report"""
        passed = sum(1 for r in self.results if r.passed)
        failed = sum(1 for r in self.results if not r.passed)
        total = len(self.results)

        with open(output_file, 'w') as f:
            f.write("="*60 + "\n")
            f.write(f"Comparison Report: {self.module_name}\n")
            f.write("="*60 + "\n")
            f.write(f"Total tests:   {total}\n")
            f.write(f"Passed:        {passed}\n")
            f.write(f"Failed:        {failed}\n")
            f.write(f"Pass rate:     {100*passed/total:.1f}%\n")
            f.write("="*60 + "\n\n")

            if failed > 0:
                f.write("FAILED TESTS:\n")
                f.write("-"*60 + "\n")
                for result in self.results:
                    if not result.passed:
                        f.write(f"\nTest {result.test_id}:\n")
                        for signal in result.expected_values:
                            exp = result.expected_values[signal]
                            act = result.actual_values[signal]
                            err = result.errors[signal]
                            f.write(f"  {signal}:\n")
                            f.write(f"    Expected: {exp:6d} (0x{exp:04X})\n")
                            f.write(f"    Actual:   {act:6d} (0x{act:04X})\n")
                            f.write(f"    Error:    {err:6d} LSBs\n")
            else:
                f.write("ALL TESTS PASSED!\n")

            # Statistics
            if total > 0:
                f.write("\n" + "="*60 + "\n")
                f.write("ERROR STATISTICS:\n")
                f.write("-"*60 + "\n")

                for signal in self.results[0].expected_values.keys():
                    errors = [r.errors[signal] for r in self.results]
                    max_err = max(errors)
                    avg_err = sum(errors) / len(errors)

                    f.write(f"\n{signal}:\n")
                    f.write(f"  Max error:  {max_err} LSBs\n")
                    f.write(f"  Avg error:  {avg_err:.2f} LSBs\n")

        print(f"Report generated: {output_file}")
        print(f"  Total: {total}, Passed: {passed}, Failed: {failed}")


def main():
    """Main comparison routine"""
    # Modules to compare
    modules = [
        "power_unit",
        "moment_update_unit",
        "bias_correction_unit",
        "adaptive_lr_unit",
        "adam_update_unit"
    ]

    # Create comparison directory
    COMP_DIR.mkdir(parents=True, exist_ok=True)

    print("="*60)
    print("VHDL Simulation Result Comparison Tool")
    print("="*60)
    print()

    for module in modules:
        print(f"Comparing {module}...")

        vector_file = VEC_DIR / f"{module}_vectors.txt"
        ghdl_log = GHDL_LOG_DIR / f"{module}_ghdl.log"
        report_file = COMP_DIR / f"{module}_comparison.txt"

        if not vector_file.exists():
            print(f"  ⚠ Skipping (no test vectors): {vector_file}")
            continue

        if not ghdl_log.exists():
            print(f"  ⚠ Skipping (no simulation log): {ghdl_log}")
            continue

        comparison = ModuleComparison(module)
        comparison.compare(vector_file, ghdl_log)
        comparison.generate_report(report_file)
        print()

    print("="*60)
    print("Comparison complete!")
    print(f"Reports saved to: {COMP_DIR}")
    print("="*60)


if __name__ == "__main__":
    main()
