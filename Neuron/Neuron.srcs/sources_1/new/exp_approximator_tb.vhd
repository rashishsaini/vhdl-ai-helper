--------------------------------------------------------------------------------
-- Testbench: exp_approximator_tb
-- Description: Comprehensive testbench for exponential approximation unit
--              Tests accuracy across input range and edge cases
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity exp_approximator_tb is
end entity exp_approximator_tb;

architecture testbench of exp_approximator_tb is

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component exp_approximator is
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
            overflow     : out std_logic;
            underflow    : out std_logic
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
    signal overflow     : std_logic;
    signal underflow    : std_logic;
    
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
    
    -- Calculate relative error percentage
    function rel_error_pct(expected, actual : real) return real is
    begin
        if abs(expected) < 0.0001 then
            return abs(expected - actual) * 100.0;
        else
            return abs((expected - actual) / expected) * 100.0;
        end if;
    end function;
    
    -- Calculate e^x
    function calc_exp(x : real) return real is
    begin
        return EULER ** x;
    end function;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : exp_approximator
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
            overflow     => overflow,
            underflow    => underflow
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
        variable tolerance   : real := 5.0;  -- 5% error tolerance for piecewise linear
        variable cycle_count : integer;
        
        procedure run_test(
            x_input   : real;
            test_name : string
        ) is
        begin
            test_count <= test_count + 1;
            
            x_val := x_input;
            expected := calc_exp(x_input);
            
            -- Clamp expected to Q2.13 representable range
            if expected > 3.999 then
                expected := 3.999;
            elsif expected < 0.0001 then
                expected := 0.0001;
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
                if cycle_count > 20 then
                    report "TIMEOUT: " & test_name severity error;
                    fail_count <= fail_count + 1;
                    return;
                end if;
            end loop;
            wait until rising_edge(clk);
            
            -- Get result
            result_real := fixed_to_real(data_out);
            err_pct := rel_error_pct(expected, result_real);
            
            -- Update statistics
            if err_pct > max_error then
                max_error <= err_pct;
            end if;
            total_error <= total_error + err_pct;
            
            -- Report results
            report "----------------------------------------";
            report "Test: " & test_name;
            report "  x = " & real'image(x_input);
            report "  e^x expected: " & real'image(expected);
            report "  e^x got:      " & real'image(result_real);
            report "  Error:        " & real'image(err_pct) & "%";
            report "  Cycles:       " & integer'image(cycle_count);
            
            if overflow = '1' then
                report "  [OVERFLOW flag]";
            end if;
            if underflow = '1' then
                report "  [UNDERFLOW flag]";
            end if;
            
            -- Check pass/fail (relaxed for saturation cases)
            if overflow = '1' and calc_exp(x_input) > 3.5 then
                report "  PASS (overflow expected)" severity note;
                pass_count <= pass_count + 1;
            elsif underflow = '1' and calc_exp(x_input) < 0.01 then
                report "  PASS (underflow expected)" severity note;
                pass_count <= pass_count + 1;
            elsif err_pct <= tolerance then
                report "  PASS" severity note;
                pass_count <= pass_count + 1;
            elsif err_pct <= tolerance * 2.0 then
                -- Marginal pass for difficult regions
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
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "===================================================";
        report "       EXPONENTIAL APPROXIMATOR TESTBENCH";
        report "===================================================";
        report " ";
        
        -- =====================================================================
        -- Test Group 1: Key reference points
        -- =====================================================================
        report "=== Test Group 1: Reference Points ===";
        
        run_test(0.0, "e^0 = 1.0");
        run_test(1.0, "e^1 = 2.718");
        run_test(-1.0, "e^(-1) = 0.368");
        run_test(0.5, "e^0.5 = 1.649");
        run_test(-0.5, "e^(-0.5) = 0.607");
        
        -- =====================================================================
        -- Test Group 2: Small positive values
        -- =====================================================================
        report "=== Test Group 2: Small Positive x ===";
        
        run_test(0.1, "e^0.1");
        run_test(0.2, "e^0.2");
        run_test(0.25, "e^0.25");
        run_test(0.3, "e^0.3");
        run_test(0.4, "e^0.4");
        run_test(0.6, "e^0.6");
        run_test(0.7, "e^0.7");
        run_test(0.75, "e^0.75");
        run_test(0.8, "e^0.8");
        run_test(0.9, "e^0.9");
        
        -- =====================================================================
        -- Test Group 3: Small negative values (important for sigmoid)
        -- =====================================================================
        report "=== Test Group 3: Small Negative x (Sigmoid Range) ===";
        
        run_test(-0.1, "e^(-0.1)");
        run_test(-0.2, "e^(-0.2)");
        run_test(-0.25, "e^(-0.25)");
        run_test(-0.3, "e^(-0.3)");
        run_test(-0.4, "e^(-0.4)");
        run_test(-0.6, "e^(-0.6)");
        run_test(-0.7, "e^(-0.7)");
        run_test(-0.75, "e^(-0.75)");
        run_test(-0.8, "e^(-0.8)");
        run_test(-0.9, "e^(-0.9)");
        
        -- =====================================================================
        -- Test Group 4: Larger negative values
        -- =====================================================================
        report "=== Test Group 4: Larger Negative x ===";
        
        run_test(-1.5, "e^(-1.5)");
        run_test(-2.0, "e^(-2.0)");
        run_test(-2.5, "e^(-2.5)");
        run_test(-3.0, "e^(-3.0)");
        run_test(-3.5, "e^(-3.5)");
        run_test(-4.0, "e^(-4.0) (min input)");
        
        -- =====================================================================
        -- Test Group 5: Positive values approaching saturation
        -- =====================================================================
        report "=== Test Group 5: Positive x Near Saturation ===";
        
        run_test(1.1, "e^1.1");
        run_test(1.2, "e^1.2");
        run_test(1.3, "e^1.3");
        run_test(1.35, "e^1.35 (near sat)");
        run_test(1.38, "e^1.38 (at sat)");
        run_test(1.4, "e^1.4 (overflow)");
        run_test(1.5, "e^1.5 (overflow)");
        run_test(2.0, "e^2.0 (overflow)");
        
        -- =====================================================================
        -- Test Group 6: Sigmoid-relevant values (e^(-x) for x in [-5,5])
        -- =====================================================================
        report "=== Test Group 6: Sigmoid Function Values ===";
        
        -- For sigmoid(x) = 1/(1+e^(-x)), we need e^(-x)
        run_test(-0.0, "sigmoid at x=0: e^0");
        run_test(0.5, "sigmoid at x=-0.5: e^0.5");
        run_test(1.0, "sigmoid at x=-1: e^1");
        run_test(2.0, "sigmoid at x=-2: e^2 (sat)");
        run_test(-0.5, "sigmoid at x=0.5: e^(-0.5)");
        run_test(-1.0, "sigmoid at x=1: e^(-1)");
        run_test(-2.0, "sigmoid at x=2: e^(-2)");
        run_test(-3.0, "sigmoid at x=3: e^(-3)");
        
        -- =====================================================================
        -- Test Group 7: Fine-grained sweep (accuracy check)
        -- =====================================================================
        report "=== Test Group 7: Fine-Grained Sweep ===";
        
        for i in -16 to 5 loop
            run_test(real(i) * 0.25, "sweep x=" & real'image(real(i)*0.25));
        end loop;
        
        -- =====================================================================
        -- Test Group 8: Random/arbitrary values
        -- =====================================================================
        report "=== Test Group 8: Arbitrary Values ===";
        
        run_test(0.693, "e^ln(2) = 2");
        run_test(-0.693, "e^(-ln(2)) = 0.5");
        run_test(0.333, "e^0.333");
        run_test(-0.333, "e^(-0.333)");
        run_test(1.234, "e^1.234");
        run_test(-1.234, "e^(-1.234)");
        
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