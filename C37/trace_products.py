#!/usr/bin/env python3
"""
Trace product generation and accumulation for first samples
"""

import sys
import re

def twos_complement(val, bits):
    """Convert two's complement to signed"""
    if val & (1 << (bits-1)):
        return val - (1 << bits)
    return val

def parse_products(filename):
    """Parse VCD and track product and accumulation"""

    signals = {
        'D': ('sample_counter', 8),
        'N': ('product_real_scaled', 32),
        'R': ('product_imag_scaled', 32),
        'S': ('accumulator_real', 48),
        'V': ('accumulate_enable', 1),
        'U': ('multiply_enable', 1),
        'G': ('sample_data_reg', 16),
        'H': ('cos_coeff_reg', 16),
        'I': ('sin_coeff_reg', 16),
        'J': ('data_valid_reg', 1),
    }

    current_time = 0
    signal_values = {}
    events = []

    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()

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
                                if signal_name in ['product_real_scaled', 'product_imag_scaled',
                                                   'accumulator_real', 'sample_data_reg',
                                                   'cos_coeff_reg', 'sin_coeff_reg']:
                                    value = twos_complement(value, width)
                            else:
                                value = 'X'
                        except:
                            value = value_str

                        old_value = signal_values.get(signal_name, 0)
                        signal_values[signal_name] = value

                        # Log key changes
                        if signal_name == 'product_real_scaled' and value != old_value:
                            events.append((current_time, 'PRODUCT_REAL_CHANGE', value, dict(signal_values)))

                        elif signal_name == 'accumulator_real' and value != old_value:
                            events.append((current_time, 'ACCUMULATOR_CHANGE', value, dict(signal_values)))

            elif line.startswith('0') or line.startswith('1'):
                value = int(line[0])
                signal_id = line[1]

                if signal_id in signals:
                    signal_name, _ = signals[signal_id]
                    old_value = signal_values.get(signal_name, 0)
                    signal_values[signal_name] = value

                    if signal_name == 'accumulate_enable' and value == 1 and old_value == 0:
                        events.append((current_time, 'ACCUMULATE_ENABLE', value, dict(signal_values)))

                    elif signal_name == 'multiply_enable' and value == 1 and old_value == 0:
                        events.append((current_time, 'MULTIPLY_ENABLE', value, dict(signal_values)))

    return events

def analyze_first_samples(events):
    """Analyze what happens with first few samples"""

    print("\n" + "="*120)
    print("PRODUCT AND ACCUMULATION TRACE - First 100 events")
    print("="*120)

    print(f"\n{'#':<5} {'Time(ns)':<10} {'Event':<25} {'Counter':<8} {'Product_Re':<12} {'Accum_Re':<15} {'AccEn':<6} {'MulEn':<6} {'Sample':<8} {'Cos':<8}")
    print("-"*120)

    for i, (time, event_type, value, snapshot) in enumerate(events[:100]):
        counter = snapshot.get('sample_counter', 0)
        product = snapshot.get('product_real_scaled', 0)
        accumulator = snapshot.get('accumulator_real', 0)
        accum_en = snapshot.get('accumulate_enable', 0)
        mul_en = snapshot.get('multiply_enable', 0)
        sample = snapshot.get('sample_data_reg', 0)
        cos_coeff = snapshot.get('cos_coeff_reg', 0)

        print(f"{i:<5} {time//1000000:<10} {event_type:<25} {counter:<8} {product:<12} {accumulator:<15} " +
              f"{accum_en:<6} {mul_en:<6} {sample:<8} {cos_coeff:<8}")

    # Focus on counter 0-5
    print("\n" + "="*120)
    print("Events for sample_counter 0-5:")
    print("="*120)

    print(f"\n{'#':<5} {'Time(ns)':<10} {'Event':<25} {'Counter':<8} {'Product_Re':<12} {'Accum_Re':<15} {'AccEn':<6} {'MulEn':<6}")
    print("-"*120)

    for i, (time, event_type, value, snapshot) in enumerate(events):
        counter = snapshot.get('sample_counter', 0)
        if counter <= 5:
            product = snapshot.get('product_real_scaled', 0)
            accumulator = snapshot.get('accumulator_real', 0)
            accum_en = snapshot.get('accumulate_enable', 0)
            mul_en = snapshot.get('multiply_enable', 0)

            print(f"{i:<5} {time//1000000:<10} {event_type:<25} {counter:<8} {product:<12} {accumulator:<15} " +
                  f"{accum_en:<6} {mul_en:<6}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 trace_products.py <vcd_file>")
        sys.exit(1)

    vcd_file = sys.argv[1]
    print(f"Parsing VCD file: {vcd_file}")

    events = parse_products(vcd_file)
    analyze_first_samples(events)

    print("\n" + "="*120)
    print("Analysis Complete")
    print("="*120)
