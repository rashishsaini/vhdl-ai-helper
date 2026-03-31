#!/usr/bin/env python3
"""
Trace accumulator value changes to find where data is lost
"""

import sys
import re

def twos_complement(val, bits):
    """Convert two's complement to signed"""
    if val & (1 << (bits-1)):
        return val - (1 << bits)
    return val

def parse_accumulator_trace(filename):
    """Parse VCD and track accumulator changes"""

    signals = {
        'D': ('sample_counter', 8),
        'S': ('accumulator_real', 48),
        'T': ('accumulator_imag', 48),
        'N': ('product_real_scaled', 32),
        'R': ('product_imag_scaled', 32),
        'V': ('accumulate_enable', 1),
        'W': ('clear_accumulator', 1),
    }

    current_time = 0
    signal_values = {}
    accumulator_changes = []
    prev_accum_real = 0
    prev_accum_imag = 0

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
                                if signal_name in ['accumulator_real', 'accumulator_imag',
                                                   'product_real_scaled', 'product_imag_scaled']:
                                    value = twos_complement(value, width)
                            else:
                                value = 'X'
                        except:
                            value = value_str

                        old_value = signal_values.get(signal_name, 0)
                        signal_values[signal_name] = value

                        # Track accumulator changes
                        if signal_name == 'accumulator_real' and value != old_value:
                            accumulator_changes.append({
                                'time': current_time,
                                'type': 'real',
                                'old': old_value,
                                'new': value,
                                'delta': value - old_value,
                                'product': signal_values.get('product_real_scaled', 0),
                                'accum_en': signal_values.get('accumulate_enable', 0),
                                'clear': signal_values.get('clear_accumulator', 0),
                                'counter': signal_values.get('sample_counter', 0)
                            })

                        elif signal_name == 'accumulator_imag' and value != old_value:
                            accumulator_changes.append({
                                'time': current_time,
                                'type': 'imag',
                                'old': old_value,
                                'new': value,
                                'delta': value - old_value,
                                'product': signal_values.get('product_imag_scaled', 0),
                                'accum_en': signal_values.get('accumulate_enable', 0),
                                'clear': signal_values.get('clear_accumulator', 0),
                                'counter': signal_values.get('sample_counter', 0)
                            })

            elif line.startswith('0') or line.startswith('1'):
                value = int(line[0])
                signal_id = line[1]

                if signal_id in signals:
                    signal_name, _ = signals[signal_id]
                    signal_values[signal_name] = value

    return accumulator_changes, signal_values

def analyze_accumulator_trace(changes):
    """Analyze accumulator changes"""

    print("\n" + "="*120)
    print("ACCUMULATOR VALUE TRACE")
    print("="*120)

    real_changes = [c for c in changes if c['type'] == 'real']
    imag_changes = [c for c in changes if c['type'] == 'imag']

    print(f"\nTotal accumulator_real changes: {len(real_changes)}")
    print(f"Total accumulator_imag changes: {len(imag_changes)}")

    # Show first 20 real accumulator changes
    print("\n" + "-"*120)
    print("First 20 accumulator_real changes:")
    print("-"*120)
    print(f"{'#':<4} {'Time(ns)':<10} {'Counter':<8} {'Old':<15} {'New':<15} {'Delta':<15} {'Product':<12} {'Match?':<8} {'AccEn':<6} {'Clear':<6}")

    for i, change in enumerate(real_changes[:20]):
        match = "YES" if change['delta'] == change['product'] else "NO"
        if change['clear'] == 1:
            match = "CLEAR"

        print(f"{i:<4} {change['time']//1000000:<10} {change['counter']:<8} " +
              f"{change['old']:<15} {change['new']:<15} {change['delta']:<15} " +
              f"{change['product']:<12} {match:<8} {change['accum_en']:<6} {change['clear']:<6}")

    # Show last 20 real accumulator changes
    print("\n" + "-"*120)
    print("Last 20 accumulator_real changes:")
    print("-"*120)
    print(f"{'#':<4} {'Time(ns)':<10} {'Counter':<8} {'Old':<15} {'New':<15} {'Delta':<15} {'Product':<12} {'Match?':<8} {'AccEn':<6} {'Clear':<6}")

    for i, change in enumerate(real_changes[-20:], start=len(real_changes)-20):
        match = "YES" if change['delta'] == change['product'] else "NO"
        if change['clear'] == 1:
            match = "CLEAR"

        print(f"{i:<4} {change['time']//1000000:<10} {change['counter']:<8} " +
              f"{change['old']:<15} {change['new']:<15} {change['delta']:<15} " +
              f"{change['product']:<12} {match:<8} {change['accum_en']:<6} {change['clear']:<6}")

    # Check for mismatches
    print("\n" + "="*120)
    print("ACCUMULATION VERIFICATION")
    print("="*120)

    mismatches = [c for c in real_changes if c['delta'] != c['product'] and c['clear'] != 1]

    if mismatches:
        print(f"\n[ERROR] Found {len(mismatches)} accumulator changes where delta != product!")
        print("\nFirst 10 mismatches:")
        for i, change in enumerate(mismatches[:10]):
            print(f"  Time {change['time']//1000000} ns: delta={change['delta']}, product={change['product']}, diff={change['delta'] - change['product']}")
    else:
        print("\n[OK] All accumulator changes match the product values (when not clearing)")

    # Check final value
    if real_changes:
        final_real = real_changes[-1]['new']
        final_imag = imag_changes[-1]['new'] if imag_changes else 0

        print(f"\nFinal accumulator values:")
        print(f"  accumulator_real: {final_real}")
        print(f"  accumulator_imag: {final_imag}")

        # Extract output (lower 32 bits)
        output_real = twos_complement(final_real & 0xFFFFFFFF, 32)
        output_imag = twos_complement(final_imag & 0xFFFFFFFF, 32)

        real_float = output_real / 32768.0
        imag_float = output_imag / 32768.0
        magnitude = (real_float**2 + imag_float**2)**0.5

        print(f"\nOutput (lower 32 bits in Q16.15):")
        print(f"  real: {real_float:.6f}")
        print(f"  imag: {imag_float:.6f}")
        print(f"  magnitude: {magnitude:.6f}")

        # Expected for DC signal with 256 samples of 0.5
        # DFT[k=1] should be near zero (orthogonal)
        # But let's calculate what we got
        print(f"\n[ANALYSIS] For Test 1 (DC signal, all samples = 0.5 = 16384 in Q15):")
        print(f"[ANALYSIS] Expected DFT[k=1] magnitude ≈ 0 (DC has no k=1 component)")
        print(f"[ANALYSIS] Actual magnitude = {magnitude:.6f}")

        if magnitude > 0.1:
            print(f"[ERROR] Magnitude too high! Expected near-zero for DC signal at k=1")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 trace_accumulator.py <vcd_file>")
        sys.exit(1)

    vcd_file = sys.argv[1]
    print(f"Parsing VCD file: {vcd_file}")

    changes, final_values = parse_accumulator_trace(vcd_file)
    analyze_accumulator_trace(changes)

    print("\n" + "="*120)
    print("Analysis Complete")
    print("="*120)
