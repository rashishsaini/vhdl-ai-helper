#!/usr/bin/env python3
"""
Trace state machine and accumulate_enable relationship
"""

import sys
import re

def parse_state_machine(filename):
    """Parse VCD and track state transitions with accumulate_enable"""

    # Just track key control signals
    signals = {
        'D': ('sample_counter', 8),
        'V': ('accumulate_enable', 1),
        'W': ('clear_accumulator', 1),
        'U': ('multiply_enable', 1),
        'Y': ('increment_counter', 1),
        'J': ('data_valid_reg', 1),
        'F': ('rom_wait_counter', 2),
    }

    current_time = 0
    signal_values = {'sample_counter': 0, 'accumulate_enable': 0}
    events = []
    prev_accumulate = 0
    prev_counter = 0

    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()

            if line.startswith('#'):
                current_time = int(line[1:])
                continue

            # Parse values
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
                            else:
                                value = 'X'
                        except:
                            value = value_str

                        old_value = signal_values.get(signal_name, 0)
                        signal_values[signal_name] = value

                        # Track changes
                        if signal_name == 'sample_counter' and value != old_value:
                            events.append((current_time, 'COUNTER_CHANGE', f"{old_value}->{value}"))

            elif line.startswith('0') or line.startswith('1'):
                value = int(line[0])
                signal_id = line[1]

                if signal_id in signals:
                    signal_name, _ = signals[signal_id]
                    old_value = signal_values.get(signal_name, 0)
                    signal_values[signal_name] = value

                    # Track transitions
                    if signal_name == 'accumulate_enable':
                        if value == 1 and old_value == 0:
                            counter_val = signal_values.get('sample_counter', 0)
                            events.append((current_time, 'ACCUMULATE_ENABLE_RISE', f"counter={counter_val}"))

                    elif signal_name == 'increment_counter':
                        if value == 1 and old_value == 0:
                            counter_val = signal_values.get('sample_counter', 0)
                            events.append((current_time, 'INCREMENT_COUNTER', f"counter={counter_val}"))

                    elif signal_name == 'clear_accumulator':
                        if value == 1:
                            events.append((current_time, 'CLEAR_ACCUMULATOR', ''))

    return events

def analyze_state_transitions(events):
    """Analyze state machine behavior"""

    print("\n" + "="*100)
    print("STATE MACHINE TRACE - Looking for accumulate_enable glitches")
    print("="*100)

    # Count accumulate_enable assertions per counter value
    accumulate_per_counter = {}

    for time, event_type, details in events:
        if event_type == 'ACCUMULATE_ENABLE_RISE':
            counter = int(details.split('=')[1])
            if counter not in accumulate_per_counter:
                accumulate_per_counter[counter] = 0
            accumulate_per_counter[counter] += 1

    # Show statistics
    print(f"\nTotal ACCUMULATE_ENABLE rising edges: {len([e for e in events if e[1] == 'ACCUMULATE_ENABLE_RISE'])}")
    print(f"Unique sample_counter values with accumulate: {len(accumulate_per_counter)}")

    # Check for multiple accumulates per counter
    multiple_accumulates = {k: v for k, v in accumulate_per_counter.items() if v > 1}

    if multiple_accumulates:
        print(f"\n[CRITICAL BUG FOUND] sample_counter values with MULTIPLE accumulate_enable assertions:")
        for counter, count in sorted(multiple_accumulates.items())[:20]:
            print(f"  Counter {counter}: {count} accumulate_enable assertions")

        print(f"\n[ROOT CAUSE] accumulate_enable is asserting {sum(multiple_accumulates.values())} extra times!")
        print(f"[ROOT CAUSE] This causes the accumulator to add the SAME product multiple times!")

    # Show sequence around first few samples
    print("\n" + "-"*100)
    print("First 50 events:")
    print("-"*100)
    for i, (time, event_type, details) in enumerate(events[:50]):
        print(f"{i:3} | Time: {time//1000000:6} ns | {event_type:25} | {details}")

    # Show events for sample_counter = 0
    print("\n" + "-"*100)
    print("Events for sample_counter = 0:")
    print("-"*100)
    counter_0_events = [(t, e, d) for t, e, d in events if 'counter=0' in d]
    for i, (time, event_type, details) in enumerate(counter_0_events[:30]):
        print(f"{i:3} | Time: {time//1000000:6} ns | {event_type:25} | {details}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 trace_state_machine.py <vcd_file>")
        sys.exit(1)

    vcd_file = sys.argv[1]
    print(f"Parsing VCD file: {vcd_file}")

    events = parse_state_machine(vcd_file)
    analyze_state_transitions(events)

    print("\n" + "="*100)
    print("Analysis Complete")
    print("="*100)
