--------------------------------------------------------------------------------
-- Testbench: activation_derivative_unit_tb
-- Description: Verifies activation_derivative_unit functionality
--              Tests ReLU derivative: σ'(z) = 1 if z > 0, else 0
--
-- Test Strategy:
--   1. Positive values (should return 1.0)
--   2. Negative values (should return 0.0)
--   3. Zero (should return 0.0)
--   4. Boundary conditions
--
-- No textio used - uses assertions and report statements
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity activation_derivative_unit_tb is
end entity activation_derivative_unit_tb;

architecture sim of activation_derivative_unit_tb is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant DATA_WIDTH : integer := 16;
    constant FRAC_BITS  : integer := 13;
    constant ONE_Q213   : integer := 8192;  -- 1.0 in Q2.13

    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal z_in        : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal derivative  : signed(DATA_WIDTH-1 downto 0);
    signal is_active   : std_logic;

    ---------------------------------------------------------------------------
    -- Test tracking
    ---------------------------------------------------------------------------
    signal test_count  : integer := 0;
    signal pass_count  : integer := 0;
    signal fail_count  : integer := 0;

begin

    ---------------------------------------------------------------------------
    -- Device Under Test
    ---------------------------------------------------------------------------
    DUT: entity work.activation_derivative_unit
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            FRAC_BITS  => FRAC_BITS
        )
        port map (
            z_in       => z_in,
            derivative => derivative,
            is_active  => is_active
        );

    ---------------------------------------------------------------------------
    -- Test Process
    ---------------------------------------------------------------------------
    test_proc: process
        
        -- Helper procedure to run a single test
        procedure run_test(
            z_value        : integer;
            expected_deriv : integer;
            expected_active: std_logic;
            test_name      : string
        ) is
            variable z_real : real;
        begin
            -- Apply input
            z_in <= to_signed(z_value, DATA_WIDTH);
            
            -- Wait for combinational logic to settle
            wait for 10 ns;
            
            -- Calculate real value for display
            z_real := real(z_value) / real(2**FRAC_BITS);
            
            -- Check output
            if to_integer(derivative) = expected_deriv and is_active = expected_active then
                report "PASS: " & test_name & 
                       " | z=" & integer'image(z_value) &
                       " | deriv=" & integer'image(to_integer(derivative)) &
                       " | active=" & std_logic'image(is_active)
                    severity note;
                pass_count <= pass_count + 1;
            else
                report "FAIL: " & test_name & 
                       " | z=" & integer'image(z_value) &
                       " | Expected deriv=" & integer'image(expected_deriv) &
                       " | Got deriv=" & integer'image(to_integer(derivative)) &
                       " | Expected active=" & std_logic'image(expected_active) &
                       " | Got active=" & std_logic'image(is_active)
                    severity error;
                fail_count <= fail_count + 1;
            end if;
            
            test_count <= test_count + 1;
            wait for 10 ns;
        end procedure;

    begin
        report "========================================" severity note;
        report "Starting activation_derivative_unit testbench" severity note;
        report "========================================" severity note;
        report "ReLU derivative: f'(z) = 1 if z > 0, else 0" severity note;
        report "1.0 in Q2.13 = 8192" severity note;
        
        wait for 20 ns;

        -----------------------------------------------------------------------
        -- Test Group 1: Positive values (derivative = 1)
        -----------------------------------------------------------------------
        report "--- Test Group 1: Positive z (derivative = 1.0) ---" severity note;
        
        run_test(1,      ONE_Q213, '1', "Smallest positive");
        run_test(100,    ONE_Q213, '1', "Small positive");
        run_test(4096,   ONE_Q213, '1', "0.5 in Q2.13");
        run_test(8192,   ONE_Q213, '1', "1.0 in Q2.13");
        run_test(16384,  ONE_Q213, '1', "2.0 in Q2.13");
        run_test(24576,  ONE_Q213, '1', "3.0 in Q2.13");
        run_test(32767,  ONE_Q213, '1', "Max positive (3.9999)");

        -----------------------------------------------------------------------
        -- Test Group 2: Negative values (derivative = 0)
        -----------------------------------------------------------------------
        report "--- Test Group 2: Negative z (derivative = 0.0) ---" severity note;
        
        run_test(-1,     0, '0', "Smallest negative");
        run_test(-100,   0, '0', "Small negative");
        run_test(-4096,  0, '0', "-0.5 in Q2.13");
        run_test(-8192,  0, '0', "-1.0 in Q2.13");
        run_test(-16384, 0, '0', "-2.0 in Q2.13");
        run_test(-24576, 0, '0', "-3.0 in Q2.13");
        run_test(-32768, 0, '0', "Min negative (-4.0)");

        -----------------------------------------------------------------------
        -- Test Group 3: Zero (derivative = 0 by convention)
        -----------------------------------------------------------------------
        report "--- Test Group 3: Zero (derivative = 0.0) ---" severity note;
        
        run_test(0, 0, '0', "Exact zero");

        -----------------------------------------------------------------------
        -- Test Group 4: Boundary and typical neural network values
        -----------------------------------------------------------------------
        report "--- Test Group 4: Typical NN values ---" severity note;
        
        -- Typical pre-activation values after Wx+b
        run_test(500,    ONE_Q213, '1', "Small positive pre-activation");
        run_test(-500,   0,        '0', "Small negative pre-activation");
        run_test(12000,  ONE_Q213, '1', "Moderate positive (~1.46)");
        run_test(-12000, 0,        '0', "Moderate negative (~-1.46)");

        -----------------------------------------------------------------------
        -- Test Group 5: Edge cases
        -----------------------------------------------------------------------
        report "--- Test Group 5: Edge cases ---" severity note;
        
        -- Values very close to zero
        run_test(1,  ONE_Q213, '1', "Just above zero (+0.0001)");
        run_test(-1, 0,        '0', "Just below zero (-0.0001)");

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