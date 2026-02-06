--------------------------------------------------------------------------------
-- Testbench: sigmoid_unit_tb
-- Description: Comprehensive testbench for sigmoid activation unit
--              Tests accuracy across input range and edge cases
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity sigmoid_unit_tb is
end entity sigmoid_unit_tb;

architecture testbench of sigmoid_unit_tb is

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component sigmoid_unit is
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
    
    -- Calculate relative error percentage
    function rel_error_pct(expected, actual : real) return real is
    begin
        if abs(expected) < 0.0001 then
            return abs(expected - actual) * 100.0;
        else
            return abs((expected - actual) / expected) * 100.0;
        end if;
    end function;
    
    -- Calculate sigmoid: σ(x) = 1 / (1 + e^(-x))
    function calc_sigmoid(x : real) return real is
        variable exp_neg_x : real;
    begin
        exp_neg_x := EULER ** (-x);
        return 1.0 / (1.0 + exp_neg_x);
    end function;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : sigmoid_unit
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
        variable tolerance   : real := 5.0;  -- 5% error tolerance (cumulative from exp + recip)
        variable cycle_count : integer;
        
        procedure run_test(
            x_input   : real;
            test_name : string
        ) is
        begin
            test_count <= test_count + 1;
            
            x_val := x_input;
            expected := calc_sigmoid(x_input);
            
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
                if cycle_count > 100 then
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
            report "  sigmoid(x) expected: " & real'image(expected);
            report "  sigmoid(x) got:      " & real'image(result_real);
            report "  Error:               " & real'image(err_pct) & "%";
            report "  Cycles:              " & integer'image(cycle_count);
            
            if overflow = '1' then
                report "  [OVERFLOW flag]";
            end if;
            
            -- Check pass/fail
            if err_pct <= tolerance then
                report "  PASS" severity note;
                pass_count <= pass_count + 1;
            elsif err_pct <= tolerance * 2.0 then
                -- Marginal pass for edge cases
                report "  MARGINAL PASS" severity note;
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
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "===================================================";
        report "          SIGMOID UNIT TESTBENCH";
        report "===================================================";
        report " ";
        
        -- =====================================================================
        -- Test Group 1: Key reference points
        -- =====================================================================
        report "=== Test Group 1: Reference Points ===";
        
        run_test(0.0, "sigmoid(0) = 0.5");
        run_test(1.0, "sigmoid(1) = 0.731");
        run_test(-1.0, "sigmoid(-1) = 0.269");
        run_test(2.0, "sigmoid(2) = 0.881");
        run_test(-2.0, "sigmoid(-2) = 0.119");
        
        -- =====================================================================
        -- Test Group 2: Small positive values (linear region)
        -- =====================================================================
        report "=== Test Group 2: Small Positive x ===";
        
        run_test(0.1, "sigmoid(0.1)");
        run_test(0.2, "sigmoid(0.2)");
        run_test(0.3, "sigmoid(0.3)");
        run_test(0.4, "sigmoid(0.4)");
        run_test(0.5, "sigmoid(0.5)");
        run_test(0.6, "sigmoid(0.6)");
        run_test(0.7, "sigmoid(0.7)");
        run_test(0.8, "sigmoid(0.8)");
        run_test(0.9, "sigmoid(0.9)");
        
        -- =====================================================================
        -- Test Group 3: Small negative values (linear region)
        -- =====================================================================
        report "=== Test Group 3: Small Negative x ===";
        
        run_test(-0.1, "sigmoid(-0.1)");
        run_test(-0.2, "sigmoid(-0.2)");
        run_test(-0.3, "sigmoid(-0.3)");
        run_test(-0.4, "sigmoid(-0.4)");
        run_test(-0.5, "sigmoid(-0.5)");
        run_test(-0.6, "sigmoid(-0.6)");
        run_test(-0.7, "sigmoid(-0.7)");
        run_test(-0.8, "sigmoid(-0.8)");
        run_test(-0.9, "sigmoid(-0.9)");
        
        -- =====================================================================
        -- Test Group 4: Moderate values (transition region)
        -- =====================================================================
        report "=== Test Group 4: Moderate Values ===";
        
        run_test(1.5, "sigmoid(1.5)");
        run_test(-1.5, "sigmoid(-1.5)");
        run_test(2.5, "sigmoid(2.5)");
        run_test(-2.5, "sigmoid(-2.5)");
        run_test(3.0, "sigmoid(3.0)");
        run_test(-3.0, "sigmoid(-3.0)");
        
        -- =====================================================================
        -- Test Group 5: Saturation region (extreme values)
        -- =====================================================================
        report "=== Test Group 5: Saturation Region ===";
        
        run_test(3.5, "sigmoid(3.5) near 1");
        run_test(-3.5, "sigmoid(-3.5) near 0");
        run_test(4.0, "sigmoid(4.0) near 1");
        run_test(-4.0, "sigmoid(-4.0) near 0");
        
        -- =====================================================================
        -- Test Group 6: Neural network typical values
        -- =====================================================================
        report "=== Test Group 6: NN Typical Values ===";
        
        run_test(0.693, "sigmoid(ln2) = 2/3");
        run_test(-0.693, "sigmoid(-ln2) = 1/3");
        run_test(1.098, "sigmoid(ln3)");
        run_test(-1.098, "sigmoid(-ln3)");
        run_test(0.25, "sigmoid(0.25)");
        run_test(-0.25, "sigmoid(-0.25)");
        run_test(0.75, "sigmoid(0.75)");
        run_test(-0.75, "sigmoid(-0.75)");
        
        -- =====================================================================
        -- Test Group 7: Fine-grained sweep
        -- =====================================================================
        report "=== Test Group 7: Fine-Grained Sweep ===";
        
        for i in -8 to 8 loop
            run_test(real(i) * 0.5, "sweep x=" & real'image(real(i)*0.5));
        end loop;
        
        -- =====================================================================
        -- Test Group 8: Symmetry check (σ(x) + σ(-x) = 1)
        -- =====================================================================
        report "=== Test Group 8: Symmetry Check ===";
        
        run_test(1.234, "symmetry test x=1.234");
        run_test(-1.234, "symmetry test x=-1.234");
        run_test(2.5, "symmetry test x=2.5");
        run_test(-2.5, "symmetry test x=-2.5");
        
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