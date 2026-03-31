--------------------------------------------------------------------------------
-- Testbench: cross_entropy_unit_tb
-- Description: Comprehensive verification of cross-entropy loss computation
--              Tests numerical accuracy, edge cases, and timing behavior
--
-- Test Coverage:
--   1. Nominal cases (p in typical range, y=0 or y=1)
--   2. Edge cases (p near 0 or 1)
--   3. Boundary conditions
--   4. Invalid inputs
--   5. Timing verification
--
-- Compilation Order:
--   1. log_approximator.vhd
--   2. cross_entropy_unit.vhd
--   3. cross_entropy_unit_tb.vhd
--
-- Run: ghdl -a log_approximator.vhd cross_entropy_unit.vhd cross_entropy_unit_tb.vhd
--      ghdl -e cross_entropy_unit_tb
--      ghdl -r cross_entropy_unit_tb --wave=ce_tb.ghw
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity cross_entropy_unit_tb is
end entity cross_entropy_unit_tb;

architecture sim of cross_entropy_unit_tb is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant DATA_WIDTH : integer := 16;
    constant FRAC_BITS  : integer := 13;
    constant CLK_PERIOD : time := 10 ns;
    constant ONE_Q213   : integer := 2**FRAC_BITS;  -- 8192
    
    -- Tolerance for floating-point comparison
    constant LOSS_TOLERANCE : real := 0.15;  -- Allow 15% error due to LUT approximation
    constant GRAD_TOLERANCE : real := 0.01;  -- Gradient should be very accurate

    ---------------------------------------------------------------------------
    -- DUT Signals
    ---------------------------------------------------------------------------
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal predicted    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal target       : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal start        : std_logic := '0';
    signal loss_out     : signed(DATA_WIDTH-1 downto 0);
    signal gradient_out : signed(DATA_WIDTH-1 downto 0);
    signal done         : std_logic;
    signal busy         : std_logic;
    signal overflow     : std_logic;
    signal invalid      : std_logic;

    ---------------------------------------------------------------------------
    -- Test Control
    ---------------------------------------------------------------------------
    signal sim_done     : boolean := false;
    signal test_count   : integer := 0;
    signal pass_count   : integer := 0;
    signal fail_count   : integer := 0;

    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    
    -- Convert real to Q2.13 fixed-point
    function to_fixed(x : real) return signed is
        variable temp : integer;
    begin
        temp := integer(round(x * real(ONE_Q213)));
        if temp > 32767 then 
            temp := 32767; 
        end if;
        if temp < -32768 then 
            temp := -32768; 
        end if;
        return to_signed(temp, DATA_WIDTH);
    end function;

    -- Convert Q2.13 fixed-point to real
    function to_real(x : signed) return real is
    begin
        return real(to_integer(x)) / real(ONE_Q213);
    end function;

    -- Compute expected cross-entropy loss
    -- L = -[y * ln(p) + (1-y) * ln(1-p)]
    function expected_ce(p, y : real) return real is
        variable p_clip : real;
        variable term1, term2 : real;
    begin
        -- Clip p to avoid log(0)
        p_clip := p;
        if p_clip < 0.001 then 
            p_clip := 0.001; 
        end if;
        if p_clip > 0.999 then 
            p_clip := 0.999; 
        end if;
        
        -- Compute terms
        if y > 0.5 then
            -- y ≈ 1: term1 dominates
            term1 := y * log(p_clip);
            term2 := (1.0 - y) * log(1.0 - p_clip);
        else
            -- y ≈ 0: term2 dominates
            term1 := y * log(p_clip);
            term2 := (1.0 - y) * log(1.0 - p_clip);
        end if;
        
        return -(term1 + term2);
    end function;

    -- Compute expected gradient: p - y
    function expected_grad(p, y : real) return real is
    begin
        return p - y;
    end function;

    -- Check if two reals are approximately equal
    function approx_equal(a, b, tolerance : real) return boolean is
        variable diff : real;
        variable max_val : real;
    begin
        diff := abs(a - b);
        max_val := abs(a);
        if abs(b) > max_val then
            max_val := abs(b);
        end if;
        
        -- Use absolute tolerance for small values, relative for large
        if max_val < 0.1 then
            return diff < tolerance;
        else
            return diff < tolerance * max_val;
        end if;
    end function;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD/2 when not sim_done else '0';

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    DUT: entity work.cross_entropy_unit
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            FRAC_BITS  => FRAC_BITS
        )
        port map (
            clk          => clk,
            rst          => rst,
            predicted    => predicted,
            target       => target,
            start        => start,
            loss_out     => loss_out,
            gradient_out => gradient_out,
            done         => done,
            busy         => busy,
            overflow     => overflow,
            invalid      => invalid
        );

    ---------------------------------------------------------------------------
    -- Stimulus Process
    ---------------------------------------------------------------------------
    stim_proc: process
        variable p_val, y_val : real;
        variable exp_loss, exp_grad : real;
        variable act_loss, act_grad : real;
        variable loss_ok, grad_ok : boolean;
        variable cycle_count : integer;
        
        -- Procedure to run a single test
        procedure run_test(
            test_name : string;
            p_in      : real;
            y_in      : real;
            expect_invalid : boolean := false
        ) is
        begin
            test_count <= test_count + 1;
            
            report "----------------------------------------" severity note;
            report "Test " & integer'image(test_count) & ": " & test_name severity note;
            report "  p = " & real'image(p_in) & ", y = " & real'image(y_in) severity note;
            
            -- Apply inputs
            predicted <= to_fixed(p_in);
            target    <= to_fixed(y_in);
            
            -- Pulse start
            wait for CLK_PERIOD;
            start <= '1';
            wait for CLK_PERIOD;
            start <= '0';
            
            -- Wait for completion with timeout
            cycle_count := 0;
            while done /= '1' and cycle_count < 50 loop
                wait for CLK_PERIOD;
                cycle_count := cycle_count + 1;
            end loop;
            
            -- Check timeout
            if cycle_count >= 50 then
                report "  FAIL: Timeout waiting for done signal!" severity error;
                fail_count <= fail_count + 1;
                return;
            end if;
            
            report "  Completed in " & integer'image(cycle_count) & " cycles" severity note;
            
            -- Sample outputs
            wait for CLK_PERIOD/4;  -- Sample after clock edge settles
            act_loss := to_real(loss_out);
            act_grad := to_real(gradient_out);
            
            -- Check invalid flag
            if expect_invalid then
                if invalid = '1' then
                    report "  PASS: Invalid flag correctly asserted" severity note;
                    pass_count <= pass_count + 1;
                else
                    report "  FAIL: Expected invalid flag" severity error;
                    fail_count <= fail_count + 1;
                end if;
                wait for CLK_PERIOD * 2;
                return;
            end if;
            
            -- Compute expected values
            exp_loss := expected_ce(p_in, y_in);
            exp_grad := expected_grad(p_in, y_in);
            
            -- Report results
            report "  Expected loss: " & real'image(exp_loss) severity note;
            report "  Actual loss:   " & real'image(act_loss) severity note;
            report "  Expected grad: " & real'image(exp_grad) severity note;
            report "  Actual grad:   " & real'image(act_grad) severity note;
            
            -- Verify results
            loss_ok := approx_equal(act_loss, exp_loss, LOSS_TOLERANCE);
            grad_ok := approx_equal(act_grad, exp_grad, GRAD_TOLERANCE);
            
            if loss_ok and grad_ok then
                report "  PASS" severity note;
                pass_count <= pass_count + 1;
            else
                if not loss_ok then
                    report "  FAIL: Loss error = " & 
                           real'image(abs(act_loss - exp_loss)) severity error;
                end if;
                if not grad_ok then
                    report "  FAIL: Gradient error = " & 
                           real'image(abs(act_grad - exp_grad)) severity error;
                end if;
                fail_count <= fail_count + 1;
            end if;
            
            -- Check overflow flag
            if overflow = '1' then
                report "  Note: Overflow flag set" severity note;
            end if;
            
            wait for CLK_PERIOD * 2;
        end procedure;
        
    begin
        -- Initialize
        report "========================================" severity note;
        report "Cross-Entropy Unit Comprehensive Testbench" severity note;
        report "========================================" severity note;
        
        -- Reset sequence
        rst <= '1';
        predicted <= (others => '0');
        target <= (others => '0');
        start <= '0';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 3;
        
        -----------------------------------------------------------------------
        -- Test Category 1: Nominal Cases (Confident Correct Predictions)
        -----------------------------------------------------------------------
        report "" severity note;
        report "=== Category 1: Confident Correct Predictions ===" severity note;
        
        -- Test 1.1: p=0.9, y=1 (high confidence, correct class 1)
        run_test("High confidence correct (y=1)", 0.9, 1.0);
        
        -- Test 1.2: p=0.1, y=0 (high confidence, correct class 0)
        run_test("High confidence correct (y=0)", 0.1, 0.0);
        
        -- Test 1.3: p=0.8, y=1 (moderate confidence, correct)
        run_test("Moderate confidence correct (y=1)", 0.8, 1.0);
        
        -- Test 1.4: p=0.2, y=0 (moderate confidence, correct)
        run_test("Moderate confidence correct (y=0)", 0.2, 0.0);
        
        -----------------------------------------------------------------------
        -- Test Category 2: Confident Wrong Predictions (High Loss)
        -----------------------------------------------------------------------
        report "" severity note;
        report "=== Category 2: Confident Wrong Predictions ===" severity note;
        
        -- Test 2.1: p=0.9, y=0 (confident wrong)
        run_test("High confidence wrong (y=0)", 0.9, 0.0);
        
        -- Test 2.2: p=0.1, y=1 (confident wrong)
        run_test("High confidence wrong (y=1)", 0.1, 1.0);
        
        -----------------------------------------------------------------------
        -- Test Category 3: Uncertain Predictions (p ≈ 0.5)
        -----------------------------------------------------------------------
        report "" severity note;
        report "=== Category 3: Uncertain Predictions ===" severity note;
        
        -- Test 3.1: p=0.5, y=1 (maximum uncertainty)
        run_test("Maximum uncertainty (y=1)", 0.5, 1.0);
        
        -- Test 3.2: p=0.5, y=0 (maximum uncertainty)
        run_test("Maximum uncertainty (y=0)", 0.5, 0.0);
        
        -- Test 3.3: p=0.6, y=1 (slight lean correct)
        run_test("Slight lean correct (y=1)", 0.6, 1.0);
        
        -- Test 3.4: p=0.4, y=0 (slight lean correct)
        run_test("Slight lean correct (y=0)", 0.4, 0.0);
        
        -----------------------------------------------------------------------
        -- Test Category 4: Edge Cases (p near boundaries)
        -----------------------------------------------------------------------
        report "" severity note;
        report "=== Category 4: Edge Cases ===" severity note;
        
        -- Test 4.1: p very small
        run_test("Very small p (y=1)", 0.01, 1.0);
        
        -- Test 4.2: p very large
        run_test("Very large p (y=0)", 0.99, 0.0);
        
        -- Test 4.3: p=0.05, y=1
        run_test("Small p (y=1)", 0.05, 1.0);
        
        -- Test 4.4: p=0.95, y=0
        run_test("Large p (y=0)", 0.95, 0.0);
        
        -----------------------------------------------------------------------
        -- Test Category 5: Invalid Inputs
        -----------------------------------------------------------------------
        report "" severity note;
        report "=== Category 5: Invalid Inputs ===" severity note;
        
        -- Test 5.1: p=0 (invalid - log(0) undefined)
        run_test("Invalid: p=0", 0.0, 1.0, true);
        
        -- Test 5.2: p=1 (invalid - log(1-p)=log(0) undefined)
        run_test("Invalid: p=1", 1.0, 0.0, true);
        
        -- Test 5.3: p negative (invalid)
        run_test("Invalid: p<0", -0.1, 1.0, true);
        
        -----------------------------------------------------------------------
        -- Test Category 6: Gradient Accuracy (Critical for Training)
        -----------------------------------------------------------------------
        report "" severity note;
        report "=== Category 6: Gradient Accuracy Sweep ===" severity note;
        
        -- Sweep p from 0.1 to 0.9
        for i in 1 to 9 loop
            p_val := real(i) / 10.0;
            run_test("Gradient sweep p=" & real'image(p_val), p_val, 1.0);
        end loop;
        
        -----------------------------------------------------------------------
        -- Test Category 7: Back-to-Back Operations
        -----------------------------------------------------------------------
        report "" severity note;
        report "=== Category 7: Back-to-Back Operations ===" severity note;
        
        -- Quick successive operations
        for i in 1 to 3 loop
            p_val := 0.3 + real(i) * 0.2;
            run_test("Back-to-back " & integer'image(i), p_val, 1.0);
        end loop;
        
        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        wait for CLK_PERIOD * 5;
        
        report "" severity note;
        report "========================================" severity note;
        report "TEST SUMMARY" severity note;
        report "========================================" severity note;
        report "Total tests:  " & integer'image(test_count) severity note;
        report "Passed:       " & integer'image(pass_count) severity note;
        report "Failed:       " & integer'image(fail_count) severity note;
        
        if fail_count = 0 then
            report "*** ALL TESTS PASSED ***" severity note;
        else
            report "*** SOME TESTS FAILED ***" severity error;
        end if;
        
        report "========================================" severity note;
        
        sim_done <= true;
        wait;
    end process;

end architecture sim;
