--------------------------------------------------------------------------------
-- Testbench: swish_unit_tb
-- Description: Comprehensive testbench for Swish activation unit
--              Tests across full input range and verifies against expected values
--
-- Test Categories:
--   1. Zero input
--   2. Positive inputs
--   3. Negative inputs
--   4. Boundary cases
--   5. Special points (minimum, inflection)
--   6. Back-to-back operations
--   7. Reset behavior
--
-- Expected Results:
--   Swish(x) = x * sigmoid(x) = x / (1 + e^(-x))
--
--   Swish(-4)   ≈ -0.072
--   Swish(-2)   ≈ -0.238
--   Swish(-1.278) ≈ -0.278 (minimum point)
--   Swish(-1)   ≈ -0.269
--   Swish(0)    = 0
--   Swish(1)    ≈ 0.731
--   Swish(2)    ≈ 1.762
--   Swish(4)    ≈ 3.928
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity swish_unit_tb is
end entity swish_unit_tb;

architecture sim of swish_unit_tb is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : integer := 16;
    constant FRAC_BITS  : integer := 13;
    constant SCALE      : real := 8192.0;

    ---------------------------------------------------------------------------
    -- DUT Signals
    ---------------------------------------------------------------------------
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal data_in      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal start        : std_logic := '0';
    signal data_out     : signed(DATA_WIDTH-1 downto 0);
    signal done         : std_logic;
    signal busy         : std_logic;
    signal overflow     : std_logic;

    ---------------------------------------------------------------------------
    -- Test Control
    ---------------------------------------------------------------------------
    signal test_done    : boolean := false;
    signal test_num     : integer := 0;
    signal pass_count   : integer := 0;
    signal fail_count   : integer := 0;

    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    function real_to_q213(val : real) return signed is
        variable temp : integer;
    begin
        temp := integer(val * SCALE);
        if temp > 32767 then
            temp := 32767;
        elsif temp < -32768 then
            temp := -32768;
        end if;
        return to_signed(temp, DATA_WIDTH);
    end function;

    function q213_to_real(val : signed) return real is
    begin
        return real(to_integer(val)) / SCALE;
    end function;

    function sigmoid(x : real) return real is
    begin
        return 1.0 / (1.0 + exp(-x));
    end function;

    function expected_swish(x : real) return real is
    begin
        return x * sigmoid(x);
    end function;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD/2 when not test_done else '0';

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : entity work.swish_unit
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            FRAC_BITS  => FRAC_BITS
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_in      => data_in,
            start        => start,
            data_out     => data_out,
            done         => done,
            busy         => busy,
            overflow     => overflow
        );

    ---------------------------------------------------------------------------
    -- Main Test Process
    ---------------------------------------------------------------------------
    test_proc : process
        variable output_real   : real;
        variable expected_real : real;
        variable error_pct     : real;
        variable error_abs     : real;
        variable cycle_count   : integer;
        
        procedure run_test(
            x_val       : real;
            test_name   : string;
            max_error   : real := 3.0
        ) is
        begin
            test_num <= test_num + 1;
            
            data_in <= real_to_q213(x_val);
            
            wait until rising_edge(clk);
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';
            
            cycle_count := 0;
            while done /= '1' and cycle_count < 100 loop
                wait until rising_edge(clk);
                cycle_count := cycle_count + 1;
            end loop;
            
            if cycle_count >= 100 then
                report "TIMEOUT: " & test_name severity error;
                fail_count <= fail_count + 1;
                return;
            end if;
            
            output_real   := q213_to_real(data_out);
            expected_real := expected_swish(x_val);
            error_abs     := abs(output_real - expected_real);
            
            if abs(expected_real) > 0.01 then
                error_pct := error_abs / abs(expected_real) * 100.0;
            else
                error_pct := error_abs * 100.0;
            end if;
            
            report test_name & 
                   ": x=" & real'image(x_val) &
                   ", out=" & real'image(output_real) &
                   ", exp=" & real'image(expected_real) &
                   ", err=" & real'image(error_pct) & "%" &
                   ", cycles=" & integer'image(cycle_count);
            
            if error_pct < max_error or error_abs < 0.02 then
                pass_count <= pass_count + 1;
                report "  PASS" severity note;
            else
                fail_count <= fail_count + 1;
                report "  FAIL: Error exceeds " & real'image(max_error) & "%" severity warning;
            end if;
            
            wait until rising_edge(clk);
        end procedure;

    begin
        report "========================================";
        report "Swish Unit Testbench Starting";
        report "========================================";
        report "Swish(x) = x * sigmoid(x)";
        report "========================================";
        
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- Test Category 1: Zero Input
        report "--- Test Category 1: Zero Input ---";
        run_test(0.0, "Zero input");

        -- Test Category 2: Positive Inputs
        report "--- Test Category 2: Positive Inputs ---";
        run_test(0.1,  "Positive 0.1");
        run_test(0.25, "Positive 0.25");
        run_test(0.5,  "Positive 0.5");
        run_test(0.75, "Positive 0.75");
        run_test(1.0,  "Positive 1.0");
        run_test(1.5,  "Positive 1.5");
        run_test(2.0,  "Positive 2.0");
        run_test(2.5,  "Positive 2.5");
        run_test(3.0,  "Positive 3.0");
        run_test(3.5,  "Positive 3.5");

        -- Test Category 3: Negative Inputs
        report "--- Test Category 3: Negative Inputs ---";
        run_test(-0.1,  "Negative -0.1");
        run_test(-0.25, "Negative -0.25");
        run_test(-0.5,  "Negative -0.5");
        run_test(-0.75, "Negative -0.75");
        run_test(-1.0,  "Negative -1.0");
        run_test(-1.5,  "Negative -1.5");
        run_test(-2.0,  "Negative -2.0");
        run_test(-2.5,  "Negative -2.5");
        run_test(-3.0,  "Negative -3.0");
        run_test(-3.5,  "Negative -3.5");

        -- Test Category 4: Boundary Cases
        report "--- Test Category 4: Boundary Cases ---";
        run_test(3.9,   "Near max positive");
        run_test(-3.9,  "Near max negative");
        run_test(0.01,  "Very small positive");
        run_test(-0.01, "Very small negative");

        -- Test Category 5: Special Points
        report "--- Test Category 5: Special Points ---";
        run_test(-1.278, "Minimum point (~-1.278)");
        run_test(-1.0, "Before minimum (-1.0)");
        run_test(-1.5, "After minimum (-1.5)");
        run_test(-2.4, "Inflection region (-2.4)");
        run_test(0.693, "ln(2) point");

        -- Test Category 6: Asymptotic Behavior
        report "--- Test Category 6: Asymptotic Behavior ---";
        run_test(3.5, "Large positive (should be near x)");
        run_test(-3.5, "Large negative (should be near 0)");

        -- Test Category 7: Back-to-Back Operations
        report "--- Test Category 7: Back-to-Back Operations ---";
        run_test(1.0,  "B2B Test 1");
        run_test(-1.0, "B2B Test 2");
        run_test(0.5,  "B2B Test 3");
        run_test(-0.5, "B2B Test 4");
        run_test(2.0,  "B2B Test 5");
        run_test(-2.0, "B2B Test 6");

        -- Test Category 8: Reset Behavior
        report "--- Test Category 8: Reset Behavior ---";
        data_in <= real_to_q213(1.5);
        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait for CLK_PERIOD * 5;
        
        rst <= '1';
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);
        
        if busy = '0' then
            report "Reset test: PASS - Unit returned to IDLE";
            pass_count <= pass_count + 1;
        else
            report "Reset test: FAIL - Unit still busy after reset" severity warning;
            fail_count <= fail_count + 1;
        end if;
        
        wait for CLK_PERIOD * 3;

        -- Test Category 9: ReLU Comparison Points
        report "--- Test Category 9: ReLU Comparison Points ---";
        run_test(0.0, "ReLU comparison: x=0");
        run_test(1.0, "ReLU comparison: x=1");
        run_test(2.0, "ReLU comparison: x=2");
        run_test(-1.0, "ReLU comparison: x=-1 (non-zero unlike ReLU)");

        -- Summary
        wait for CLK_PERIOD * 5;
        
        report "========================================";
        report "Swish Unit Testbench Complete";
        report "========================================";
        report "Total Tests: " & integer'image(pass_count + fail_count);
        report "Passed:      " & integer'image(pass_count);
        report "Failed:      " & integer'image(fail_count);
        
        if fail_count = 0 then
            report "STATUS: ALL TESTS PASSED" severity note;
        else
            report "STATUS: SOME TESTS FAILED" severity warning;
        end if;
        
        report "========================================";

        test_done <= true;
        wait;
    end process;

end architecture sim;
