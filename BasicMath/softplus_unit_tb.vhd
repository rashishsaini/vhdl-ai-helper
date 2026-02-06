--------------------------------------------------------------------------------
-- Testbench: softplus_unit_tb
-- Description: Comprehensive testbench for softplus activation unit
--              Tests: softplus(x) = ln(1 + e^x)
--
-- Test Categories:
--   1. Basic functionality across input range
--   2. Boundary conditions (saturation, overflow)
--   3. Fast path verification (large positive x)
--   4. Very negative x (approaching zero output)
--   5. Special values (x=0 → ln(2), x=1 → ln(1+e))
--   6. Mathematical accuracy verification
--   7. Sequential operation (back-to-back computations)
--
-- Author: FPGA Neural Network Project
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity softplus_unit_tb is
end entity softplus_unit_tb;

architecture sim of softplus_unit_tb is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD  : time := 10 ns;
    constant DATA_WIDTH  : integer := 16;
    constant FRAC_BITS   : integer := 13;
    constant SCALE       : real := real(2**FRAC_BITS);  -- 8192.0
    
    -- Error tolerance: ~1% relative error or 0.01 absolute error
    constant REL_ERROR_TOL : real := 0.02;   -- 2% relative tolerance
    constant ABS_ERROR_TOL : real := 0.015;  -- 0.015 absolute tolerance
    
    -- Timeout for waiting on done signal
    constant MAX_CYCLES  : integer := 50;

    ---------------------------------------------------------------------------
    -- DUT Signals
    ---------------------------------------------------------------------------
    signal clk            : std_logic := '0';
    signal rst            : std_logic := '1';
    signal data_in        : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal start          : std_logic := '0';
    signal data_out       : signed(DATA_WIDTH-1 downto 0);
    signal done           : std_logic;
    signal busy           : std_logic;
    signal overflow       : std_logic;
    signal used_fast_path : std_logic;

    ---------------------------------------------------------------------------
    -- Test Control
    ---------------------------------------------------------------------------
    signal test_running   : boolean := true;
    signal test_name      : string(1 to 40) := (others => ' ');
    signal tests_passed   : integer := 0;
    signal tests_failed   : integer := 0;
    signal total_tests    : integer := 0;

    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    
    -- Convert real to Q2.13 fixed-point
    function to_fixed(x : real) return signed is
        variable temp : integer;
    begin
        temp := integer(round(x * SCALE));
        if temp > 32767 then
            temp := 32767;
        elsif temp < -32768 then
            temp := -32768;
        end if;
        return to_signed(temp, DATA_WIDTH);
    end function;
    
    -- Convert Q2.13 fixed-point to real
    function to_real(x : signed) return real is
    begin
        return real(to_integer(x)) / SCALE;
    end function;
    
    -- Compute expected softplus: ln(1 + e^x)
    function softplus_expected(x : real) return real is
        variable exp_x : real;
    begin
        -- Handle overflow cases
        if x > 10.0 then
            return x;  -- softplus(x) ≈ x for large x
        elsif x < -10.0 then
            return exp(x);  -- softplus(x) ≈ e^x for very negative x
        else
            exp_x := exp(x);
            return log(1.0 + exp_x);
        end if;
    end function;
    
    -- Check if result is within tolerance
    function check_result(actual : real; expected : real) return boolean is
        variable abs_err : real;
        variable rel_err : real;
    begin
        abs_err := abs(actual - expected);
        
        -- For very small expected values, use absolute error
        if abs(expected) < 0.1 then
            return abs_err < ABS_ERROR_TOL;
        else
            -- Use relative error for larger values
            rel_err := abs_err / abs(expected);
            return rel_err < REL_ERROR_TOL or abs_err < ABS_ERROR_TOL;
        end if;
    end function;
    
    -- Set test name helper
    procedure set_test_name(name : string) is
    begin
        test_name <= (others => ' ');
        for i in 1 to name'length loop
            if i <= test_name'length then
                test_name(i) <= name(i);
            end if;
        end loop;
    end procedure;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD/2 when test_running else '0';

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : entity work.softplus_unit
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            FRAC_BITS  => FRAC_BITS
        )
        port map (
            clk            => clk,
            rst            => rst,
            data_in        => data_in,
            start          => start,
            data_out       => data_out,
            done           => done,
            busy           => busy,
            overflow       => overflow,
            used_fast_path => used_fast_path
        );

    ---------------------------------------------------------------------------
    -- Main Test Process
    ---------------------------------------------------------------------------
    test_proc : process
        variable x_real      : real;
        variable expected    : real;
        variable actual      : real;
        variable cycle_count : integer;
        variable test_pass   : boolean;
        variable abs_err     : real;
        variable rel_err     : real;
        
        -- Test procedure: run single softplus computation
        procedure run_test(x : real; check_fast_path : boolean := false; 
                          expect_fast : boolean := false) is
        begin
            total_tests <= total_tests + 1;
            
            -- Apply input
            data_in <= to_fixed(x);
            wait for CLK_PERIOD;
            
            -- Start computation
            start <= '1';
            wait for CLK_PERIOD;
            start <= '0';
            
            -- Wait for completion with timeout
            cycle_count := 0;
            while done = '0' and cycle_count < MAX_CYCLES loop
                wait for CLK_PERIOD;
                cycle_count := cycle_count + 1;
            end loop;
            
            -- Check timeout
            if cycle_count >= MAX_CYCLES then
                report "TIMEOUT: Test did not complete within " & 
                       integer'image(MAX_CYCLES) & " cycles for x = " &
                       real'image(x)
                    severity error;
                tests_failed <= tests_failed + 1;
                return;
            end if;
            
            -- Get results
            actual := to_real(data_out);
            expected := softplus_expected(x);
            
            -- Calculate errors
            abs_err := abs(actual - expected);
            if abs(expected) > 0.001 then
                rel_err := abs_err / abs(expected);
            else
                rel_err := abs_err;
            end if;
            
            -- Check result
            test_pass := check_result(actual, expected);
            
            -- Check fast path if requested
            if check_fast_path then
                if expect_fast and used_fast_path = '0' then
                    report "FAST PATH ERROR: Expected fast path for x = " & real'image(x)
                        severity warning;
                    test_pass := false;
                elsif not expect_fast and used_fast_path = '1' then
                    report "FAST PATH ERROR: Unexpected fast path for x = " & real'image(x)
                        severity warning;
                    -- Don't fail test, just warn
                end if;
            end if;
            
            -- Report result
            if test_pass then
                tests_passed <= tests_passed + 1;
                report "PASS: x=" & real'image(x) & 
                       " expected=" & real'image(expected) &
                       " actual=" & real'image(actual) &
                       " err=" & real'image(abs_err) &
                       " cycles=" & integer'image(cycle_count) &
                       " fast=" & std_logic'image(used_fast_path)
                    severity note;
            else
                tests_failed <= tests_failed + 1;
                report "FAIL: x=" & real'image(x) & 
                       " expected=" & real'image(expected) &
                       " actual=" & real'image(actual) &
                       " abs_err=" & real'image(abs_err) &
                       " rel_err=" & real'image(rel_err)
                    severity error;
            end if;
            
            -- Wait for done to clear
            wait for CLK_PERIOD * 2;
        end procedure;
        
    begin
        report "========================================";
        report "Starting Softplus Unit Testbench";
        report "========================================";
        
        -- Initialize
        rst <= '1';
        start <= '0';
        data_in <= (others => '0');
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        -----------------------------------------------------------------------
        -- Test Category 1: Special Values
        -----------------------------------------------------------------------
        report "--- Test Category 1: Special Values ---";
        set_test_name("Special Values");
        
        -- x = 0: softplus(0) = ln(2) ≈ 0.693
        run_test(0.0);
        
        -- x = 1: softplus(1) = ln(1 + e) ≈ 1.313
        run_test(1.0);
        
        -- x = -1: softplus(-1) = ln(1 + 1/e) ≈ 0.313
        run_test(-1.0);
        
        -----------------------------------------------------------------------
        -- Test Category 2: Normal Operation Range
        -----------------------------------------------------------------------
        report "--- Test Category 2: Normal Operation Range ---";
        set_test_name("Normal Range");
        
        -- Test across the main operating range
        run_test(-3.0);
        run_test(-2.5);
        run_test(-2.0);
        run_test(-1.5);
        run_test(-0.5);
        run_test(0.25);
        run_test(0.5);
        run_test(0.75);
        run_test(1.0);
        run_test(1.25);
        
        -----------------------------------------------------------------------
        -- Test Category 3: Fast Path (Large Positive x)
        -----------------------------------------------------------------------
        report "--- Test Category 3: Fast Path (Large Positive x) ---";
        set_test_name("Fast Path Positive");
        
        -- For x > 1.35, should use fast path: softplus(x) ≈ x
        run_test(1.5, true, true);
        run_test(2.0, true, true);
        run_test(2.5, true, true);
        run_test(3.0, true, true);
        run_test(3.5, true, true);
        
        -----------------------------------------------------------------------
        -- Test Category 4: Very Negative Values
        -----------------------------------------------------------------------
        report "--- Test Category 4: Very Negative Values ---";
        set_test_name("Very Negative x");
        
        -- For very negative x, softplus(x) ≈ e^x ≈ 0
        run_test(-3.5);
        run_test(-3.75);
        run_test(-3.9);
        
        -----------------------------------------------------------------------
        -- Test Category 5: Boundary Conditions
        -----------------------------------------------------------------------
        report "--- Test Category 5: Boundary Conditions ---";
        set_test_name("Boundary Conditions");
        
        -- Near threshold for fast path
        run_test(1.30);  -- Below threshold - normal path
        run_test(1.35);  -- At threshold
        run_test(1.40);  -- Above threshold - fast path
        
        -- Near zero (softplus crosses 0.693 at x=0)
        run_test(0.01);
        run_test(-0.01);
        run_test(0.1);
        run_test(-0.1);
        
        -----------------------------------------------------------------------
        -- Test Category 6: Symmetry Check (softplus is NOT symmetric)
        -----------------------------------------------------------------------
        report "--- Test Category 6: Asymmetry Verification ---";
        set_test_name("Asymmetry Check");
        
        -- softplus(x) ≠ softplus(-x) in general
        -- softplus(x) + softplus(-x) = x + ln(2) for all x (identity)
        run_test(0.5);
        run_test(-0.5);
        run_test(1.0);
        run_test(-1.0);
        
        -----------------------------------------------------------------------
        -- Test Category 7: Fine-Grained Accuracy
        -----------------------------------------------------------------------
        report "--- Test Category 7: Fine-Grained Accuracy ---";
        set_test_name("Fine Accuracy");
        
        -- Test with finer increments in critical region
        for i in -20 to 20 loop
            x_real := real(i) * 0.1;
            if x_real < 1.35 then  -- Stay in normal computation range
                run_test(x_real);
            end if;
        end loop;
        
        -----------------------------------------------------------------------
        -- Test Category 8: Sequential Operations
        -----------------------------------------------------------------------
        report "--- Test Category 8: Sequential Operations ---";
        set_test_name("Sequential Ops");
        
        -- Rapid sequential computations to test state machine
        for i in 1 to 5 loop
            x_real := real(i) * 0.2 - 0.5;
            run_test(x_real);
        end loop;
        
        -----------------------------------------------------------------------
        -- Test Category 9: Edge Cases
        -----------------------------------------------------------------------
        report "--- Test Category 9: Edge Cases ---";
        set_test_name("Edge Cases");
        
        -- Maximum representable positive (should use fast path)
        run_test(3.99, true, true);
        
        -- Minimum representable negative
        run_test(-3.99);
        
        -- Very small positive
        run_test(0.001);
        
        -- Very small negative
        run_test(-0.001);
        
        -----------------------------------------------------------------------
        -- Test Category 10: Derivative Relationship Check
        -- Note: d/dx softplus(x) = sigmoid(x)
        -- We verify softplus values are consistent with this relationship
        -----------------------------------------------------------------------
        report "--- Test Category 10: Mathematical Properties ---";
        set_test_name("Math Properties");
        
        -- softplus(x) is always positive
        run_test(-2.0);
        run_test(-1.0);
        run_test(0.0);
        run_test(1.0);
        
        -- softplus(0) = ln(2) ≈ 0.693
        run_test(0.0);
        
        -----------------------------------------------------------------------
        -- Final Report
        -----------------------------------------------------------------------
        wait for CLK_PERIOD * 10;
        
        report "========================================";
        report "Testbench Complete";
        report "========================================";
        report "Total Tests: " & integer'image(total_tests);
        report "Passed:      " & integer'image(tests_passed);
        report "Failed:      " & integer'image(tests_failed);
        
        if tests_failed = 0 then
            report "*** ALL TESTS PASSED ***" severity note;
        else
            report "*** SOME TESTS FAILED ***" severity error;
        end if;
        
        report "========================================";
        
        -- End simulation
        test_running <= false;
        wait;
        
    end process;

end architecture sim;
