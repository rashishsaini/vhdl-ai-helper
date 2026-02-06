--------------------------------------------------------------------------------
-- Testbench: saturation_unit_tb
-- Description: Verifies saturation_unit functionality
--              Tests positive overflow, negative overflow, and pass-through
--
-- Test Strategy:
--   1. Values within range (should pass through)
--   2. Values above maximum (should clamp to +32767)
--   3. Values below minimum (should clamp to -32768)
--   4. Boundary conditions
--
-- No textio used - uses assertions and report statements
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity saturation_unit_tb is
end entity saturation_unit_tb;

architecture sim of saturation_unit_tb is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant INPUT_WIDTH  : integer := 20;
    constant OUTPUT_WIDTH : integer := 16;
    constant SAT_MAX      : integer := 32767;
    constant SAT_MIN      : integer := -32768;

    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal data_in       : signed(INPUT_WIDTH-1 downto 0) := (others => '0');
    signal data_out      : signed(OUTPUT_WIDTH-1 downto 0);
    signal saturated_pos : std_logic;
    signal saturated_neg : std_logic;
    signal saturated     : std_logic;

    ---------------------------------------------------------------------------
    -- Test tracking
    ---------------------------------------------------------------------------
    signal test_count    : integer := 0;
    signal pass_count    : integer := 0;
    signal fail_count    : integer := 0;

begin

    ---------------------------------------------------------------------------
    -- Device Under Test
    ---------------------------------------------------------------------------
    DUT: entity work.saturation_unit
        generic map (
            INPUT_WIDTH  => INPUT_WIDTH,
            OUTPUT_WIDTH => OUTPUT_WIDTH,
            SAT_MAX      => SAT_MAX,
            SAT_MIN      => SAT_MIN
        )
        port map (
            data_in       => data_in,
            data_out      => data_out,
            saturated_pos => saturated_pos,
            saturated_neg => saturated_neg,
            saturated     => saturated
        );

    ---------------------------------------------------------------------------
    -- Test Process
    ---------------------------------------------------------------------------
    test_proc: process
        
        -- Helper procedure to run a single test
        procedure run_test(
            input_val      : integer;
            expected_out   : integer;
            expected_sat   : std_logic;
            expected_pos   : std_logic;
            expected_neg   : std_logic;
            test_name      : string
        ) is
        begin
            -- Apply input
            data_in <= to_signed(input_val, INPUT_WIDTH);
            
            -- Wait for combinational logic to settle
            wait for 10 ns;
            
            -- Check output value
            if to_integer(data_out) = expected_out then
                if saturated = expected_sat and 
                   saturated_pos = expected_pos and 
                   saturated_neg = expected_neg then
                    report "PASS: " & test_name & 
                           " | Input=" & integer'image(input_val) &
                           " | Output=" & integer'image(to_integer(data_out))
                        severity note;
                    pass_count <= pass_count + 1;
                else
                    report "FAIL: " & test_name & 
                           " | Flags mismatch" &
                           " | sat=" & std_logic'image(saturated) &
                           " | pos=" & std_logic'image(saturated_pos) &
                           " | neg=" & std_logic'image(saturated_neg)
                        severity error;
                    fail_count <= fail_count + 1;
                end if;
            else
                report "FAIL: " & test_name & 
                       " | Input=" & integer'image(input_val) &
                       " | Expected=" & integer'image(expected_out) &
                       " | Got=" & integer'image(to_integer(data_out))
                    severity error;
                fail_count <= fail_count + 1;
            end if;
            
            test_count <= test_count + 1;
            wait for 10 ns;
        end procedure;

    begin
        report "========================================" severity note;
        report "Starting saturation_unit testbench" severity note;
        report "========================================" severity note;
        
        wait for 20 ns;

        -----------------------------------------------------------------------
        -- Test Group 1: Values within range (no saturation)
        -----------------------------------------------------------------------
        report "--- Test Group 1: Pass-through (no saturation) ---" severity note;
        
        run_test(0,      0,      '0', '0', '0', "Zero");
        run_test(1,      1,      '0', '0', '0', "Small positive");
        run_test(-1,     -1,     '0', '0', '0', "Small negative");
        run_test(8192,   8192,   '0', '0', '0', "1.0 in Q2.13");
        run_test(-8192,  -8192,  '0', '0', '0', "-1.0 in Q2.13");
        run_test(16384,  16384,  '0', '0', '0', "2.0 in Q2.13");
        run_test(-16384, -16384, '0', '0', '0', "-2.0 in Q2.13");
        run_test(32767,  32767,  '0', '0', '0', "Max Q2.13 (boundary)");
        run_test(-32768, -32768, '0', '0', '0', "Min Q2.13 (boundary)");

        -----------------------------------------------------------------------
        -- Test Group 2: Positive overflow (clamp to max)
        -----------------------------------------------------------------------
        report "--- Test Group 2: Positive overflow ---" severity note;
        
        run_test(32768,  32767,  '1', '1', '0', "Just above max");
        run_test(40000,  32767,  '1', '1', '0', "Moderate overflow");
        run_test(65536,  32767,  '1', '1', '0', "Large overflow (8.0)");
        run_test(100000, 32767,  '1', '1', '0', "Very large overflow");
        run_test(524287, 32767,  '1', '1', '0', "Max 20-bit positive");

        -----------------------------------------------------------------------
        -- Test Group 3: Negative overflow (clamp to min)
        -----------------------------------------------------------------------
        report "--- Test Group 3: Negative overflow ---" severity note;
        
        run_test(-32769,  -32768, '1', '0', '1', "Just below min");
        run_test(-40000,  -32768, '1', '0', '1', "Moderate underflow");
        run_test(-65536,  -32768, '1', '0', '1', "Large underflow (-8.0)");
        run_test(-100000, -32768, '1', '0', '1', "Very large underflow");
        run_test(-524288, -32768, '1', '0', '1', "Max 20-bit negative");

        -----------------------------------------------------------------------
        -- Test Group 4: Typical neural network values
        -----------------------------------------------------------------------
        report "--- Test Group 4: Typical NN values ---" severity note;
        
        -- Activation outputs (typically 0 to 1)
        run_test(4096,   4096,   '0', '0', '0', "0.5 (activation)");
        run_test(6144,   6144,   '0', '0', '0', "0.75 (activation)");
        
        -- Accumulator outputs that might overflow
        run_test(50000,  32767,  '1', '1', '0', "Large acc overflow");
        run_test(-50000, -32768, '1', '0', '1', "Large acc underflow");
        
        -- Gradient values (typically small)
        run_test(100,    100,    '0', '0', '0', "Small gradient");
        run_test(-100,   -100,   '0', '0', '0', "Small neg gradient");

        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        wait for 20 ns;
        report "========================================" severity note;
        report "Test Summary:" severity note;
        report "  Total tests: " & integer'image(test_count) severity note;
        report "  Passed:      " & integer'image(pass_count) severity note;
        report "  Failed:      " & integer'image(fail_count) severity note;
        report "========================================" severity note;
        
        if fail_count = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "SOME TESTS FAILED!" severity error;
        end if;

        wait;
    end process;

end architecture sim;