#!/usr/bin/env python3
"""
Detailed VCD Parser to trace DFT accumulation process
"""

import sys
import re

def twos_complement(val, bits):
    """Convert two's complement binary to signed integer"""
    if val & (1 << (bits-1)):
        return val - (1 << bits)
    return val

def parse_vcd_detailed(filename):
    """Parse VCD and track accumulation process"""

    # Signal mappings
    signals = {
        'D': ('sample_counter', 8),
        'S': ('accumulator_real', 48),
        'T': ('accumulator_imag', 48),
        'M': ('product_real', 32),
        'Q': ('product_imag', 32),
        'N': ('product_real_scaled', 32),
        'R': ('product_imag_scaled', 32),
        'G': ('sample_data_reg', 16),
        'H': ('cos_coeff_reg', 16),
        'I': ('sin_coeff_reg', 16),
        'V': ('accumulate_enable', 1),
        'U': ('multiply_enable', 1),
        'W': ('clear_accumulator', 1),
        'X': ('calculation_done', 1),
        'J': ('data_valid_reg', 1),
    }

    current_time = 0
    signal_values = {}
    accumulation_log = []

    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()

            # Track timestamp
            if line.startswith('#'):
                current_time = int(line[1:])
                continue

            # Parse binary values
            if line.startswith('b'):
                match = re.match(r'b([01x]+)\s+(\S+)', line)
                if match:
                    value_str = match.group(1)
                    signal_id = match.group(2)

                    if signal_id in signals:
                        signal_name, width = signals[signal_id]

                        try:
                            if 'x' not in value_str.lower():
                                value = int(value_str, 2)
                                # Convert to signed for signed signals
                                if signal_name in ['product_real', 'product_imag', 'product_real_scaled',
                                                   'product_imag_scaled', 'accumulator_real', 'accumulator_imag',
                                                   'sample_data_reg', 'cos_coeff_reg', 'sin_coeff_reg']:
                                    value = twos_complement(value, width)
                            else:
                                value = 'X'
                        except:
                            value = value_str

                        signal_values[signal_name] = value

            elif line.startswith('0') or line.startswith('1'):
                value = int(line[0])
                signal_id = line[1]

                if signal_id in signals:
                    signal_name, _ = signals[signal_id]
                    signal_values[signal_name] = value

            # Log accumulation events
            if signal_values.get('accumulate_enable') == 1:
                accumulation_log.append({
                    'time': current_time,
                    'sample_counter': signal_values.get('sample_counter', 0),
                    'sample_data': signal_values.get('sample_data_reg', 0),
                    'cos_coeff': signal_values.get('cos_coeff_reg', 0),
                    'sin_coeff': signal_values.get('sin_coeff_reg', 0),
                    'product_real_scaled': signal_values.get('product_real_scaled', 0),
                    'product_imag_scaled': signal_values.get('product_imag_scaled', 0),
                    'accum_real_before': signal_values.get('accumulator_real', 0),
                    'accum_imag_before': signal_values.get('accumulator_imag', 0),
                })

    return accumulation_log, signal_values

def analyze_accumulation(log, final_values):
    """Analyze accumulation process"""

    print("\n" + "="*100)
    print("DFT ACCUMULATION TRACE")
    print("="*100)

    print(f"\nTotal accumulation events logged: {len(log)}")

    # Show first 5 accumulations
    print("\n" + "-"*100)
    print("First 5 accumulations:")
    print("-"*100)
    print(f"{'Time':<12} {'Counter':<8} {'Sample':<8} {'Cos':<8} {'Sin':<8} {'Prod_Re':<12} {'Prod_Im':<12} {'Accum_Re':<15}")

    for i, entry in enumerate(log[:5]):
        print(f"{entry['time']//1000000:<12} " +
              f"{entry['sample_counter']:<8} " +
              f"{entry['sample_data']:<8} " +
              f"{entry['cos_coeff']:<8} " +
              f"{entry['sin_coeff']:<8} " +
              f"{entry['product_real_scaled']:<12} " +
              f"{entry['product_imag_scaled']:<12} " +
              f"{entry['accum_real_before']:<15}")

    # Show last 5 accumulations
    print("\n" + "-"*100)
    print("Last 5 accumulations:")
    print("-"*100)
    print(f"{'Time':<12} {'Counter':<8} {'Sample':<8} {'Cos':<8} {'Sin':<8} {'Prod_Re':<12} {'Prod_Im':<12} {'Accum_Re':<15}")

    for i, entry in enumerate(log[-5:]):
        print(f"{entry['time']//1000000:<12} " +
              f"{entry['sample_counter']:<8} " +
              f"{entry['sample_data']:<8} " +
              f"{entry['cos_coeff']:<8} " +
              f"{entry['sin_coeff']:<8} " +
              f"{entry['product_real_scaled']:<12} " +
              f"{entry['product_imag_scaled']:<12} " +
              f"{entry['accum_real_before']:<15}")

    # Calculate expected vs actual
    print("\n" + "="*100)
    print("FINAL ACCUMULATOR VALUES")
    print("="*100)

    final_accum_real = final_values.get('accumulator_real', 0)
    final_accum_imag = final_values.get('accumulator_imag', 0)

    print(f"Final accumulator_real: {final_accum_real} (0x{final_accum_real & 0xFFFFFFFFFFFF:012X})")
    print(f"Final accumulator_imag: {final_accum_imag} (0x{final_accum_imag & 0xFFFFFFFFFFFF:012X})")

    # Extract lower 32 bits (Q16.15 format)
    output_real = final_accum_real & 0xFFFFFFFF
    output_imag = final_accum_imag & 0xFFFFFFFF

    # Convert to signed 32-bit
    output_real = twos_complement(output_real, 32)
    output_imag = twos_complement(output_imag, 32)

    print(f"\nOutput (lower 32 bits):")
    print(f"  real_result: {output_real} (0x{output_real & 0xFFFFFFFF:08X})")
    print(f"  imag_result: {output_imag} (0x{output_imag & 0xFFFFFFFF:08X})")

    # Convert to float (Q16.15)
    real_float = output_real / 32768.0
    imag_float = output_imag / 32768.0
    magnitude = (real_float**2 + imag_float**2)**0.5

    print(f"\nConverted to real values (Q16.15):")
    print(f"  real: {real_float:.6f}")
    print(f"  imag: {imag_float:.6f}")
    print(f"  magnitude: {magnitude:.6f}")

    # Analyze if only 1 sample was accumulated
    if len(log) > 0:
        first_product = log[0]['product_real_scaled']
        print(f"\n[DIAGNOSTIC] First product_real_scaled: {first_product}")
        print(f"[DIAGNOSTIC] If magnitude = {magnitude:.6f} ≈ 0.5, this suggests only 1 sample effect")

        # Sum all products manually
        sum_real = sum(e['product_real_scaled'] for e in log)
        sum_imag = sum(e['product_imag_scaled'] for e in log)
        print(f"\n[VERIFICATION] Sum of all product_real_scaled: {sum_real}")
        print(f"[VERIFICATION] Sum of all product_imag_scaled: {sum_imag}")
        print(f"[VERIFICATION] This should match final accumulator values!")

        if abs(sum_real - final_accum_real) > 10:
            print(f"\n[ERROR] Mismatch detected! Sum ({sum_real}) != Accumulator ({final_accum_real})")
            print(f"[ERROR] Difference: {abs(sum_real - final_accum_real)}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 parse_vcd_detailed.py <vcd_file>")
        sys.exit(1)

    vcd_file = sys.argv[1]
    print(f"Parsing VCD file: {vcd_file}")

    log, final_values = parse_vcd_detailed(vcd_file)
    analyze_accumulation(log, final_values)

    print("\n" + "="*100)
    print("Analysis Complete")
    print("="*100)
