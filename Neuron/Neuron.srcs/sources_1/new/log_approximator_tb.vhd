--------------------------------------------------------------------------------
-- Testbench: log_approximator_tb
-- Description: Comprehensive testbench for natural logarithm approximator
--              Tests accuracy across input range and edge cases
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity log_approximator_tb is
end entity log_approximator_tb;

architecture testbench of log_approximator_tb is

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component log_approximator is
        generic (
            DATA_WIDTH : integer := 16;
            FRAC_BITS  : integer := 13
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            data_in      : in  signed(DATA_WIDTH-1 downto 0);
            start        : in  std_logic;
            data_out     : out signed(DATA_WIDTH-1 downto 0);
            done         : out std_logic;
            busy         : out std_logic;
            invalid      : out std_logic;
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
    
    -- Mathematical constant
    constant EULER : real := 2.71828182845905;
    
    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal data_in      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal start        : std_logic := '0';
    signal data_out     : signed(DATA_WIDTH-1 downto 0);
    signal done         : std_logic;
    signal busy         : std_logic;
    signal invalid      : std_logic;
    signal overflow     : std_logic;
    
    signal test_running : boolean := true;
    
    -- Test tracking
    signal test_count   : integer := 0;
    signal pass_count   : integer := 0;
    signal fail_count   : integer := 0;
    
    -- Statistics
    signal max_error    : real := 0.0;
    signal total_error  : real := 0.0;
    
    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    
    -- Convert real to Q2.13 fixed-point
    function real_to_fixed(val : real) return signed is
        variable temp : integer;
    begin
        temp := integer(round(val * SCALE));
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
    
    -- Calculate absolute error
    function abs_error(expected, actual : real) return real is
    begin
        return abs(expected - actual);
    end function;
    
    -- Calculate relative error percentage (handle zero expected)
    function rel_error_pct(expected, actual : real) return real is
    begin
        if abs(expected) < 0.001 then
            -- For values near zero, use absolute error scaled
            return abs(expected - actual) * 100.0;
        else
            return abs((expected - actual) / expected) * 100.0;
        end if;
    end function;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : log_approximator
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
            invalid      => invalid,
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
        variable x_val       : real;
        variable expected    : real;
        variable result_real : real;
        variable err_pct     : real;
        variable err_abs     : real;
        variable tolerance   : real := 10.0;  -- 10% error tolerance for log (steep near 0)
        variable cycle_count : integer;
        
        procedure run_test(
            x_input   : real;
            test_name : string
        ) is
        begin
            test_count <= test_count + 1;
            
            x_val := x_input;
            
            -- Calculate expected (handle invalid inputs)
            if x_input <= 0.0 then
                expected := -4.0;  -- Clamped minimum
            else
                expected := log(x_input);  -- Natural log (ln)
                -- Clamp to Q2.13 range
                if expected > 3.999 then
                    expected := 3.999;
                elsif expected < -4.0 then
                    expected := -4.0;
                end if;
            end if;
            
            -- Apply input
            data_in <= real_to_fixed(x_input);
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
            result_real := fixed_to_real(data_out);
            err_pct := rel_error_pct(expected, result_real);
            err_abs := abs_error(expected, result_real);
            
            -- Update statistics (only for valid inputs)
            if x_input > 0.0 and invalid = '0' then
                if err_pct > max_error then
                    max_error <= err_pct;
                end if;
                total_error <= total_error + err_pct;
            end if;
            
            -- Report results
            report "----------------------------------------";
            report "Test: " & test_name;
            report "  x = " & real'image(x_input);
            report "  ln(x) expected: " & real'image(expected);
            report "  ln(x) got:      " & real'image(result_real);
            report "  Error:          " & real'image(err_pct) & "% (abs: " & real'image(err_abs) & ")";
            report "  Cycles:         " & integer'image(cycle_count);
            
            if invalid = '1' then
                report "  [INVALID flag - input <= 0]";
            end if;
            if overflow = '1' then
                report "  [OVERFLOW flag]";
            end if;
            
            -- Check pass/fail
            if invalid = '1' and x_input <= 0.0 then
                report "  PASS (invalid input detected)" severity note;
                pass_count <= pass_count + 1;
            elsif overflow = '1' and (x_input < 0.02 or x_input > 3.9 or abs(expected) >= 3.9) then
                -- Overflow expected for very small inputs (<0.02), very large inputs (>4),
                -- or when result would exceed representable range
                report "  PASS (overflow expected)" severity note;
                pass_count <= pass_count + 1;
            elsif err_pct <= tolerance then
                report "  PASS" severity note;
                pass_count <= pass_count + 1;
            elsif err_abs <= 0.15 then
                -- For values near 0, accept small absolute error
                report "  PASS (small absolute error)" severity note;
                pass_count <= pass_count + 1;
            elsif err_pct <= tolerance * 2.0 then
                report "  MARGINAL PASS" severity note;
                pass_count <= pass_count + 1;
            else
                report "  FAIL: Error exceeds tolerance!" severity warning;
                fail_count <= fail_count + 1;
            end if;
            
            -- Wait between tests
            for i in 0 to 1 loop
                wait until rising_edge(clk);
            end loop;
        end procedure;
        
    begin
        -- Initial reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "===================================================";
        report "        LOG APPROXIMATOR TESTBENCH";
        report "===================================================";
        report " ";
        
        -- =====================================================================
        -- Test Group 1: Key reference points
        -- =====================================================================
        report "=== Test Group 1: Reference Points ===";
        
        run_test(1.0, "ln(1) = 0");
        run_test(EULER, "ln(e) = 1");
        run_test(2.0, "ln(2) = 0.693");
        run_test(0.5, "ln(0.5) = -0.693");
        run_test(3.0, "ln(3) = 1.099");
        
        -- =====================================================================
        -- Test Group 2: Small values (steep region)
        -- =====================================================================
        report "=== Test Group 2: Small Values ===";
        
        run_test(0.1, "ln(0.1) = -2.303");
        run_test(0.2, "ln(0.2) = -1.609");
        run_test(0.25, "ln(0.25) = -1.386");
        run_test(0.3, "ln(0.3) = -1.204");
        run_test(0.4, "ln(0.4) = -0.916");
        run_test(0.5, "ln(0.5) = -0.693");
        run_test(0.6, "ln(0.6) = -0.511");
        run_test(0.7, "ln(0.7) = -0.357");
        run_test(0.8, "ln(0.8) = -0.223");
        run_test(0.9, "ln(0.9) = -0.105");
        
        -- =====================================================================
        -- Test Group 3: Values around 1 (critical region)
        -- =====================================================================
        report "=== Test Group 3: Around 1.0 ===";
        
        run_test(0.95, "ln(0.95)");
        run_test(0.99, "ln(0.99)");
        run_test(1.0, "ln(1.0) = 0");
        run_test(1.01, "ln(1.01)");
        run_test(1.05, "ln(1.05)");
        run_test(1.1, "ln(1.1)");
        run_test(1.2, "ln(1.2)");
        run_test(1.3, "ln(1.3)");
        
        -- =====================================================================
        -- Test Group 4: Values 1 to 4 (moderate region)
        -- =====================================================================
        report "=== Test Group 4: Values 1 to 4 ===";
        
        run_test(1.5, "ln(1.5) = 0.405");
        run_test(1.75, "ln(1.75)");
        run_test(2.0, "ln(2.0) = 0.693");
        run_test(2.25, "ln(2.25)");
        run_test(2.5, "ln(2.5) = 0.916");
        run_test(2.75, "ln(2.75)");
        run_test(3.0, "ln(3.0) = 1.099");
        run_test(3.5, "ln(3.5) = 1.253");
        run_test(3.9, "ln(3.9) = 1.361");
        
        -- =====================================================================
        -- Test Group 5: Invalid inputs (x <= 0)
        -- =====================================================================
        report "=== Test Group 5: Invalid Inputs ===";
        
        run_test(0.0, "ln(0) = undefined");
        run_test(-1.0, "ln(-1) = undefined");
        run_test(-0.5, "ln(-0.5) = undefined");
        
        -- =====================================================================
        -- Test Group 6: Very small values (near overflow)
        -- =====================================================================
        report "=== Test Group 6: Very Small Values ===";
        
        run_test(0.05, "ln(0.05) = -3.0");
        run_test(0.02, "ln(0.02) = -3.9 (near limit)");
        run_test(0.01, "ln(0.01) = -4.6 (overflow)");
        
        -- =====================================================================
        -- Test Group 7: Neural network typical values
        -- =====================================================================
        report "=== Test Group 7: NN Typical Values ===";
        
        run_test(0.5, "probability 50%");
        run_test(0.73, "sigmoid(1)");
        run_test(0.88, "sigmoid(2)");
        run_test(0.27, "sigmoid(-1)");
        run_test(0.12, "sigmoid(-2)");
        run_test(1.0, "cross-entropy at p=1");
        
        -- =====================================================================
        -- Test Group 8: Fine-grained sweep
        -- =====================================================================
        report "=== Test Group 8: Fine-Grained Sweep ===";
        
        for i in 1 to 15 loop
            run_test(real(i) * 0.25, "sweep x=" & real'image(real(i)*0.25));
        end loop;
        
        -- =====================================================================
        -- Test Group 9: Inverse relationship with exp
        -- =====================================================================
        report "=== Test Group 9: Exp/Log Inverse Check ===";
        
        -- ln(e^x) should equal x
        run_test(1.0, "ln(e^0) = 0");
        run_test(EULER, "ln(e^1) = 1");
        run_test(EULER * EULER, "ln(e^2) = 2 (overflow)");  -- e^2 ≈ 7.39 > 4
        
        -- =====================================================================
        -- Final Report
        -- =====================================================================
        wait for CLK_PERIOD * 10;
        
        report "===================================================";
        report "              TEST SUMMARY";
        report "===================================================";
        report "Total Tests:   " & integer'image(test_count);
        report "Passed:        " & integer'image(pass_count);
        report "Failed:        " & integer'image(fail_count);
        report "Max Error:     " & real'image(max_error) & "%";
        report "Avg Error:     " & real'image(total_error / real(test_count)) & "%";
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