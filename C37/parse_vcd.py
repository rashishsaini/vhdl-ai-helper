#!/usr/bin/env python3
"""
VCD Parser to extract DFT simulation signals for debugging
"""

import sys
import re

def parse_vcd(filename):
    """Parse VCD file and extract key signals"""

    # Signal mappings from VCD header
    signals = {
        'D': 'sample_counter',
        'E': 'address_reg',
        'S': 'accumulator_real',
        'T': 'accumulator_imag',
        'V': 'accumulate_enable',
        'W': 'clear_accumulator',
        'X': 'calculation_done',
        'Y': 'increment_counter',
        'U': 'multiply_enable',
        '8': 'done',
        '$': 'done_tb',
        'J': 'data_valid_reg'
    }

    current_time = 0
    signal_values = {}
    events = []

    with open(filename, 'r') as f:
        in_dumpvars = False

        for line in f:
            line = line.strip()

            # Track timestamp
            if line.startswith('#'):
                current_time = int(line[1:])
                continue

            # Parse value changes
            if line.startswith('b'):
                # Binary value: b<value> <id>
                match = re.match(r'b([01x]+)\s+(\S+)', line)
                if match:
                    value_str = match.group(1)
                    signal_id = match.group(2)

                    if signal_id in signals:
                        # Convert binary to decimal
                        try:
                            if 'x' not in value_str.lower():
                                value = int(value_str, 2)
                            else:
                                value = 'X'
                        except:
                            value = value_str

                        signal_name = signals[signal_id]
                        signal_values[signal_name] = value

                        # Log important events
                        if signal_name == 'sample_counter':
                            events.append((current_time, signal_name, value))
                        elif signal_name in ['accumulate_enable', 'calculation_done'] and value == 1:
                            events.append((current_time, signal_name, value))
                        elif signal_name in ['accumulator_real', 'accumulator_imag'] and signal_values.get('calculation_done') == 1:
                            events.append((current_time, signal_name, value))

            elif line.startswith('0') or line.startswith('1'):
                # Single bit value: <value><id>
                value = int(line[0])
                signal_id = line[1]

                if signal_id in signals:
                    signal_name = signals[signal_id]
                    signal_values[signal_name] = value

                    # Log important control signals
                    if signal_name in ['accumulate_enable', 'calculation_done', 'done', 'multiply_enable'] and value == 1:
                        events.append((current_time, signal_name, value))

    return events, signal_values

def analyze_events(events):
    """Analyze extracted events to identify the bug"""

    print("\n" + "="*80)
    print("DFT SIMULATION ANALYSIS - Critical Events")
    print("="*80)

    # Count accumulate cycles
    accumulate_count = 0
    max_sample_counter = 0
    final_accum_real = None
    final_accum_imag = None
    done_time = None

    sample_counter_values = []

    for time, signal, value in events:
        if signal == 'accumulate_enable' and value == 1:
            accumulate_count += 1

        if signal == 'sample_counter':
            max_sample_counter = max(max_sample_counter, value)
            sample_counter_values.append((time, value))

        if signal == 'calculation_done' and value == 1:
            done_time = time

        if signal == 'accumulator_real' and done_time and abs(time - done_time) < 1000:
            final_accum_real = value

        if signal == 'accumulator_imag' and done_time and abs(time - done_time) < 1000:
            final_accum_imag = value

    print(f"\n[CRITICAL] Accumulate Enable Count: {accumulate_count}")
    print(f"[CRITICAL] Maximum sample_counter value: {max_sample_counter}")
    print(f"[EXPECTED] Should be 256 accumulates with sample_counter reaching 255")

    if accumulate_count < 256:
        print(f"\n[ROOT CAUSE] Only {accumulate_count} accumulations occurred!")
        print(f"[ROOT CAUSE] Expected 256 accumulations (one per sample)")

    if max_sample_counter < 255:
        print(f"\n[ROOT CAUSE] sample_counter only reached {max_sample_counter}!")
        print(f"[ROOT CAUSE] Expected sample_counter to reach 255 (0-indexed)")

    # Print last 10 sample_counter transitions
    print("\n" + "-"*80)
    print("Last 20 sample_counter transitions:")
    print("-"*80)
    for time, value in sample_counter_values[-20:]:
        print(f"Time: {time:10} fs | sample_counter = {value:3}")

    if final_accum_real is not None:
        print(f"\n[INFO] Final accumulator_real at done: {final_accum_real} (0x{final_accum_real:012X})")
    if final_accum_imag is not None:
        print(f"[INFO] Final accumulator_imag at done: {final_accum_imag} (0x{final_accum_imag:012X})")

    # Print all events around calculation done
    print("\n" + "-"*80)
    print("Events around calculation_done:")
    print("-"*80)
    for time, signal, value in events:
        if done_time and abs(time - done_time) < 100000:
            print(f"Time: {time:10} fs | {signal:20} = {value}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 parse_vcd.py <vcd_file>")
        sys.exit(1)

    vcd_file = sys.argv[1]
    print(f"Parsing VCD file: {vcd_file}")

    events, final_values = parse_vcd(vcd_file)
    analyze_events(events)

    print("\n" + "="*80)
    print("Analysis Complete")
    print("="*80)
