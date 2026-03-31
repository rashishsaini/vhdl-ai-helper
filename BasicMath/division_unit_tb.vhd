--------------------------------------------------------------------------------
-- Testbench: division_unit_tb
-- Description: Comprehensive testbench for fixed-point division unit
--              Tests normal operation, edge cases, and error conditions
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity division_unit_tb is
end entity division_unit_tb;

architecture testbench of division_unit_tb is

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component division_unit is
        generic (
            DATA_WIDTH     : integer := 16;
            FRAC_BITS      : integer := 13;
            NUM_ITERATIONS : integer := 3
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            dividend     : in  signed(DATA_WIDTH-1 downto 0);
            divisor      : in  signed(DATA_WIDTH-1 downto 0);
            start        : in  std_logic;
            quotient     : out signed(DATA_WIDTH-1 downto 0);
            done         : out std_logic;
            busy         : out std_logic;
            div_by_zero  : out std_logic;
            overflow     : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : integer := 16;
    constant FRAC_BITS  : integer := 13;
    
    -- Q2.13 conversion factor
    constant SCALE : real := 2.0 ** real(FRAC_BITS);
    
    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal dividend     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal divisor      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal start        : std_logic := '0';
    signal quotient     : signed(DATA_WIDTH-1 downto 0);
    signal done         : std_logic;
    signal busy         : std_logic;
    signal div_by_zero  : std_logic;
    signal overflow     : std_logic;
    
    signal test_running : boolean := true;
    
    -- Test tracking
    signal test_count   : integer := 0;
    signal pass_count   : integer := 0;
    signal fail_count   : integer := 0;
    
    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    
    -- Convert real to Q2.13 fixed-point
    function real_to_fixed(val : real) return signed is
        variable temp : integer;
    begin
        temp := integer(round(val * SCALE));
        -- Clamp to valid range
        if temp > 32767 then
            temp := 32767;
        elsif temp < -32768 then
            temp := -32768;
        end if;
        return to_signed(temp, DATA_WIDTH);
    end function;
    
    -- Convert Q2.13 to real
    function fixed_to_real(val : signed) return real is
    begin
        return real(to_integer(val)) / SCALE;
    end function;
    
    -- Calculate relative error percentage
    function rel_error_pct(expected, actual : real) return real is
    begin
        if abs(expected) < 0.001 then
            return abs(expected - actual) * 100.0;
        else
            return abs((expected - actual) / expected) * 100.0;
        end if;
    end function;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : division_unit
        generic map (
            DATA_WIDTH     => DATA_WIDTH,
            FRAC_BITS      => FRAC_BITS,
            NUM_ITERATIONS => 3
        )
        port map (
            clk          => clk,
            rst          => rst,
            dividend     => dividend,
            divisor      => divisor,
            start        => start,
            quotient     => quotient,
            done         => done,
            busy         => busy,
            div_by_zero  => div_by_zero,
            overflow     => overflow
        );

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk_proc : process
    begin
        while test_running loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    ---------------------------------------------------------------------------
    -- Stimulus Process
    ---------------------------------------------------------------------------
    stim_proc : process
        variable dividend_real : real;
        variable divisor_real  : real;
        variable expected      : real;
        variable result_real   : real;
        variable err_pct       : real;
        variable tolerance     : real := 1.0;  -- 1% error tolerance
        variable cycle_count   : integer;
        
        procedure run_test(
            a_val     : real;
            b_val     : real;
            test_name : string
        ) is
        begin
            test_count <= test_count + 1;
            
            dividend_real := a_val;
            divisor_real  := b_val;
            
            -- Calculate expected result
            if abs(b_val) < 0.001 then
                expected := 0.0;  -- Division by zero
            else
                expected := a_val / b_val;
                -- Clamp expected to Q2.13 range
                if expected > 3.999 then
                    expected := 3.999;
                elsif expected < -4.0 then
                    expected := -4.0;
                end if;
            end if;
            
            -- Apply inputs
            dividend <= real_to_fixed(a_val);
            divisor  <= real_to_fixed(b_val);
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';
            
            -- Count cycles until done
            cycle_count := 0;
            while done /= '1' loop
                wait until rising_edge(clk);
                cycle_count := cycle_count + 1;
                if cycle_count > 50 then
                    report "TIMEOUT: " & test_name severity error;
                    fail_count <= fail_count + 1;
                    return;
                end if;
            end loop;
            wait until rising_edge(clk);
            
            -- Get result
            result_real := fixed_to_real(quotient);
            err_pct := rel_error_pct(expected, result_real);
            
            -- Report results
            report "----------------------------------------";
            report "Test: " & test_name;
            report "  " & real'image(a_val) & " / " & real'image(b_val);
            report "  Expected: " & real'image(expected);
            report "  Got:      " & real'image(result_real);
            report "  Error:    " & real'image(err_pct) & "%";
            report "  Cycles:   " & integer'image(cycle_count);
            
            if div_by_zero = '1' then
                report "  [DIV_BY_ZERO flag]";
            end if;
            if overflow = '1' then
                report "  [OVERFLOW flag]";
            end if;
            
            -- Check pass/fail
            if div_by_zero = '1' and abs(b_val) < 0.001 then
                report "  PASS (div by zero detected)" severity note;
                pass_count <= pass_count + 1;
            elsif overflow = '1' and (abs(expected) >= 3.9 or err_pct > tolerance) then
                report "  PASS (overflow expected)" severity note;
                pass_count <= pass_count + 1;
            elsif err_pct <= tolerance then
                report "  PASS" severity note;
                pass_count <= pass_count + 1;
            else
                report "  FAIL: Error exceeds tolerance!" severity warning;
                fail_count <= fail_count + 1;
            end if;
            
            -- Wait between tests
            for i in 0 to 2 loop
                wait until rising_edge(clk);
            end loop;
        end procedure;
        
    begin
        -- Initial reset
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "===================================================";
        report "       DIVISION UNIT TESTBENCH";
        report "===================================================";
        report " ";
        
        -- =====================================================================
        -- Test Group 1: Simple integer divisions
        -- =====================================================================
        report "=== Test Group 1: Simple Divisions ===";
        
        run_test(1.0, 1.0, "1/1 = 1");
        run_test(2.0, 1.0, "2/1 = 2");
        run_test(1.0, 2.0, "1/2 = 0.5");
        run_test(2.0, 2.0, "2/2 = 1");
        run_test(3.0, 1.0, "3/1 = 3");
        run_test(1.0, 4.0, "1/4 = 0.25");
        
        -- =====================================================================
        -- Test Group 2: Negative numbers
        -- =====================================================================
        report "=== Test Group 2: Negative Numbers ===";
        
        run_test(-1.0, 1.0, "-1/1 = -1");
        run_test(1.0, -1.0, "1/-1 = -1");
        run_test(-1.0, -1.0, "-1/-1 = 1");
        run_test(-2.0, 1.0, "-2/1 = -2");
        run_test(2.0, -1.0, "2/-1 = -2");
        run_test(-2.0, -2.0, "-2/-2 = 1");
        run_test(-3.0, 2.0, "-3/2 = -1.5");
        
        -- =====================================================================
        -- Test Group 3: Fractional values
        -- =====================================================================
        report "=== Test Group 3: Fractional Values ===";
        
        run_test(0.5, 0.5, "0.5/0.5 = 1");
        run_test(0.5, 1.0, "0.5/1.0 = 0.5");
        run_test(1.0, 0.5, "1.0/0.5 = 2");
        run_test(0.25, 0.5, "0.25/0.5 = 0.5");
        run_test(0.75, 0.25, "0.75/0.25 = 3");
        run_test(1.5, 0.5, "1.5/0.5 = 3");
        run_test(0.1, 0.5, "0.1/0.5 = 0.2");
        
        -- =====================================================================
        -- Test Group 4: Results that should be exact fractions
        -- =====================================================================
        report "=== Test Group 4: Repeating Decimals ===";
        
        run_test(1.0, 3.0, "1/3 = 0.333...");
        run_test(2.0, 3.0, "2/3 = 0.666...");
        run_test(1.0, 6.0, "1/6 = 0.166...");
        run_test(1.0, 7.0, "1/7 = 0.142...");
        run_test(3.0, 7.0, "3/7 = 0.428...");
        
        -- =====================================================================
        -- Test Group 5: Edge cases - small divisors (potential overflow)
        -- =====================================================================
        report "=== Test Group 5: Small Divisors (Overflow) ===";
        
        run_test(1.0, 0.5, "1/0.5 = 2");
        run_test(1.0, 0.25, "1/0.25 = 4 (SAT)");
        run_test(2.0, 0.5, "2/0.5 = 4 (SAT)");
        run_test(1.0, 0.125, "1/0.125 = 8 (SAT)");
        run_test(0.5, 0.125, "0.5/0.125 = 4 (SAT)");
        
        -- =====================================================================
        -- Test Group 6: Division by zero
        -- =====================================================================
        report "=== Test Group 6: Division by Zero ===";
        
        run_test(1.0, 0.0, "1/0 (div by zero)");
        run_test(2.5, 0.0, "2.5/0 (div by zero)");
        run_test(-1.0, 0.0, "-1/0 (div by zero)");
        run_test(0.0, 0.0, "0/0 (div by zero)");
        run_test(1.0, 0.0001, "1/0.0001 (near zero)");
        
        -- =====================================================================
        -- Test Group 7: Zero dividend
        -- =====================================================================
        report "=== Test Group 7: Zero Dividend ===";
        
        run_test(0.0, 1.0, "0/1 = 0");
        run_test(0.0, 2.0, "0/2 = 0");
        run_test(0.0, 0.5, "0/0.5 = 0");
        run_test(0.0, -1.0, "0/-1 = 0");
        
        -- =====================================================================
        -- Test Group 8: Values near boundaries
        -- =====================================================================
        report "=== Test Group 8: Boundary Values ===";
        
        run_test(3.9, 1.0, "3.9/1 = 3.9");
        run_test(3.9, 2.0, "3.9/2 = 1.95");
        run_test(-3.9, 1.0, "-3.9/1 = -3.9");
        run_test(-3.9, -1.0, "-3.9/-1 = 3.9");
        run_test(3.9, 3.9, "3.9/3.9 = 1");
        run_test(0.01, 1.0, "0.01/1 = 0.01");
        
        -- =====================================================================
        -- Test Group 9: Typical neural network values
        -- =====================================================================
        report "=== Test Group 9: Neural Network Values ===";
        
        run_test(0.5, 2.0, "weight/2");
        run_test(0.1, 0.01, "gradient/lr (overflow expected)");
        run_test(1.0, 1.414, "normalize by sqrt(2)");
        run_test(0.693, 1.0, "ln(2)/1");
        run_test(2.718, 1.0, "e/1");
        run_test(0.368, 1.0, "1/e normalized");
        
        -- =====================================================================
        -- Final Report
        -- =====================================================================
        wait for CLK_PERIOD * 10;
        
        report "===================================================";
        report "              TEST SUMMARY";
        report "===================================================";
        report "Total Tests: " & integer'image(test_count);
        report "Passed:      " & integer'image(pass_count);
        report "Failed:      " & integer'image(fail_count);
        report "===================================================";
        
        if fail_count = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "SOME TESTS FAILED!" severity warning;
        end if;
        
        test_running <= false;
        wait;
    end process;

end architecture testbench;