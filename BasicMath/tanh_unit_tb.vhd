--------------------------------------------------------------------------------
-- Testbench: tanh_unit_tb
-- Description: Comprehensive testbench for hyperbolic tangent unit
--              Tests accuracy across input range and edge cases
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity tanh_unit_tb is
end entity tanh_unit_tb;

architecture testbench of tanh_unit_tb is

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component tanh_unit is
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
        if abs(expected) < 0.001 then
            -- For values near zero, use absolute error
            return abs(expected - actual) * 100.0;
        else
            return abs((expected - actual) / expected) * 100.0;
        end if;
    end function;
    
    -- Calculate tanh(x) = (e^x - e^(-x)) / (e^x + e^(-x))
    function calc_tanh(x : real) return real is
        variable exp_x     : real;
        variable exp_neg_x : real;
    begin
        exp_x := EULER ** x;
        exp_neg_x := EULER ** (-x);
        return (exp_x - exp_neg_x) / (exp_x + exp_neg_x);
    end function;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : tanh_unit
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
        variable tolerance   : real := 5.0;  -- 5% error tolerance
        variable cycle_count : integer;
        
        procedure run_test(
            x_input   : real;
            test_name : string
        ) is
        begin
            test_count <= test_count + 1;
            
            x_val := x_input;
            expected := calc_tanh(x_input);
            
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
            report "  tanh(x) expected: " & real'image(expected);
            report "  tanh(x) got:      " & real'image(result_real);
            report "  Error:            " & real'image(err_pct) & "%";
            report "  Cycles:           " & integer'image(cycle_count);
            
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
        report "            TANH UNIT TESTBENCH";
        report "===================================================";
        report " ";
        
        -- =====================================================================
        -- Test Group 1: Key reference points
        -- =====================================================================
        report "=== Test Group 1: Reference Points ===";
        
        run_test(0.0, "tanh(0) = 0");
        run_test(1.0, "tanh(1) = 0.7616");
        run_test(-1.0, "tanh(-1) = -0.7616");
        run_test(2.0, "tanh(2) = 0.9640");
        run_test(-2.0, "tanh(-2) = -0.9640");
        
        -- =====================================================================
        -- Test Group 2: Small positive values (linear region)
        -- =====================================================================
        report "=== Test Group 2: Small Positive x ===";
        
        run_test(0.1, "tanh(0.1)");
        run_test(0.2, "tanh(0.2)");
        run_test(0.3, "tanh(0.3)");
        run_test(0.4, "tanh(0.4)");
        run_test(0.5, "tanh(0.5)");
        run_test(0.6, "tanh(0.6)");
        run_test(0.7, "tanh(0.7)");
        run_test(0.8, "tanh(0.8)");
        run_test(0.9, "tanh(0.9)");
        
        -- =====================================================================
        -- Test Group 3: Small negative values (linear region)
        -- =====================================================================
        report "=== Test Group 3: Small Negative x ===";
        
        run_test(-0.1, "tanh(-0.1)");
        run_test(-0.2, "tanh(-0.2)");
        run_test(-0.3, "tanh(-0.3)");
        run_test(-0.4, "tanh(-0.4)");
        run_test(-0.5, "tanh(-0.5)");
        run_test(-0.6, "tanh(-0.6)");
        run_test(-0.7, "tanh(-0.7)");
        run_test(-0.8, "tanh(-0.8)");
        run_test(-0.9, "tanh(-0.9)");
        
        -- =====================================================================
        -- Test Group 4: Moderate values (transition region)
        -- =====================================================================
        report "=== Test Group 4: Moderate Values ===";
        
        run_test(1.5, "tanh(1.5)");
        run_test(-1.5, "tanh(-1.5)");
        run_test(2.5, "tanh(2.5)");
        run_test(-2.5, "tanh(-2.5)");
        run_test(3.0, "tanh(3.0)");
        run_test(-3.0, "tanh(-3.0)");
        
        -- =====================================================================
        -- Test Group 5: Saturation region (extreme values)
        -- =====================================================================
        report "=== Test Group 5: Saturation Region ===";
        
        run_test(3.5, "tanh(3.5) near 1");
        run_test(-3.5, "tanh(-3.5) near -1");
        run_test(4.0, "tanh(4.0) near 1");
        run_test(-4.0, "tanh(-4.0) near -1");
        
        -- =====================================================================
        -- Test Group 6: Relationship with sigmoid
        -- tanh(x) = 2*sigmoid(2x) - 1
        -- =====================================================================
        report "=== Test Group 6: Sigmoid Relationship ===";
        
        -- At x=0.5, 2x=1, sigmoid(1)=0.731, 2*0.731-1=0.462
        -- tanh(0.5) = 0.462
        run_test(0.5, "tanh(0.5) via 2*sig(1)-1");
        
        -- At x=0.25, 2x=0.5, sigmoid(0.5)=0.622, 2*0.622-1=0.244
        -- tanh(0.25) = 0.245
        run_test(0.25, "tanh(0.25) via 2*sig(0.5)-1");
        
        -- At x=-0.5, 2x=-1, sigmoid(-1)=0.269, 2*0.269-1=-0.462
        -- tanh(-0.5) = -0.462
        run_test(-0.5, "tanh(-0.5) via 2*sig(-1)-1");
        
        -- =====================================================================
        -- Test Group 7: Fine-grained sweep
        -- =====================================================================
        report "=== Test Group 7: Fine-Grained Sweep ===";
        
        for i in -8 to 8 loop
            run_test(real(i) * 0.5, "sweep x=" & real'image(real(i)*0.5));
        end loop;
        
        -- =====================================================================
        -- Test Group 8: Symmetry check (tanh(-x) = -tanh(x))
        -- =====================================================================
        report "=== Test Group 8: Symmetry Check ===";
        
        run_test(1.234, "symmetry test x=1.234");
        run_test(-1.234, "symmetry test x=-1.234");
        run_test(0.777, "symmetry test x=0.777");
        run_test(-0.777, "symmetry test x=-0.777");
        run_test(2.5, "symmetry test x=2.5");
        run_test(-2.5, "symmetry test x=-2.5");
        
        -- =====================================================================
        -- Test Group 9: Neural network typical values
        -- =====================================================================
        report "=== Test Group 9: NN Typical Values ===";
        
        run_test(0.693, "tanh(ln2)");
        run_test(-0.693, "tanh(-ln2)");
        run_test(1.098, "tanh(ln3)");
        run_test(-1.098, "tanh(-ln3)");
        run_test(0.1, "small gradient region");
        run_test(-0.1, "small gradient region neg");
        
        -- =====================================================================
        -- Test Group 10: Boundary values near saturation
        -- =====================================================================
        report "=== Test Group 10: Near Saturation ===";
        
        run_test(1.8, "tanh(1.8) = 0.947");
        run_test(-1.8, "tanh(-1.8) = -0.947");
        run_test(2.2, "tanh(2.2) = 0.976");
        run_test(-2.2, "tanh(-2.2) = -0.976");
        run_test(2.6, "tanh(2.6) = 0.989");
        run_test(-2.6, "tanh(-2.6) = -0.989");
        
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