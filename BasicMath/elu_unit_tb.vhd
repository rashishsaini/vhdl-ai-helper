--------------------------------------------------------------------------------
-- Testbench: elu_unit_tb
-- Description: Comprehensive testbench for ELU activation unit
--              Tests positive path, negative path, boundary cases
--
-- Test Categories:
--   1. Positive inputs (direct passthrough)
--   2. Zero input
--   3. Negative inputs (exp path)
--   4. Boundary cases
--   5. Different alpha values
--   6. Reset behavior
--
-- Expected Results (α = 1.0):
--   ELU(2.0)  = 2.0
--   ELU(1.0)  = 1.0
--   ELU(0.5)  = 0.5
--   ELU(0)    = 0
--   ELU(-0.5) ≈ -0.393  (e^(-0.5) - 1)
--   ELU(-1.0) ≈ -0.632  (e^(-1) - 1)
--   ELU(-2.0) ≈ -0.865  (e^(-2) - 1)
--   ELU(-4.0) ≈ -0.982  (e^(-4) - 1)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity elu_unit_tb is
end entity elu_unit_tb;

architecture sim of elu_unit_tb is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : integer := 16;
    constant FRAC_BITS  : integer := 13;
    constant ONE_Q213   : integer := 8192;
    constant SCALE      : real := 8192.0;

    ---------------------------------------------------------------------------
    -- DUT Signals
    ---------------------------------------------------------------------------
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal data_in      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal alpha        : signed(DATA_WIDTH-1 downto 0) := to_signed(ONE_Q213, DATA_WIDTH);
    signal use_default  : std_logic := '1';
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

    function expected_elu(x : real; a : real) return real is
    begin
        if x > 0.0 then
            return x;
        else
            return a * (exp(x) - 1.0);
        end if;
    end function;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD/2 when not test_done else '0';

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : entity work.elu_unit
        generic map (
            DATA_WIDTH    => DATA_WIDTH,
            FRAC_BITS     => FRAC_BITS,
            DEFAULT_ALPHA => ONE_Q213
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_in      => data_in,
            alpha        => alpha,
            use_default  => use_default,
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
        variable input_real    : real;
        variable output_real   : real;
        variable expected_real : real;
        variable error_pct     : real;
        variable alpha_real    : real;
        variable cycle_count   : integer;
        
        procedure run_test(
            x_val       : real;
            alpha_val   : real;
            use_def     : std_logic;
            test_name   : string
        ) is
        begin
            test_num <= test_num + 1;
            
            data_in     <= real_to_q213(x_val);
            alpha       <= real_to_q213(alpha_val);
            use_default <= use_def;
            
            wait until rising_edge(clk);
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';
            
            cycle_count := 0;
            while done /= '1' and cycle_count < 50 loop
                wait until rising_edge(clk);
                cycle_count := cycle_count + 1;
            end loop;
            
            if cycle_count >= 50 then
                report "TIMEOUT: " & test_name severity error;
                fail_count <= fail_count + 1;
                return;
            end if;
            
            output_real := q213_to_real(data_out);
            if use_def = '1' then
                alpha_real := 1.0;
            else
                alpha_real := alpha_val;
            end if;
            expected_real := expected_elu(x_val, alpha_real);
            
            if abs(expected_real) > 0.001 then
                error_pct := abs((output_real - expected_real) / expected_real) * 100.0;
            else
                error_pct := abs(output_real - expected_real) * 100.0;
            end if;
            
            report test_name & 
                   ": x=" & real'image(x_val) &
                   ", alpha=" & real'image(alpha_real) &
                   ", out=" & real'image(output_real) &
                   ", exp=" & real'image(expected_real) &
                   ", err=" & real'image(error_pct) & "%" &
                   ", cycles=" & integer'image(cycle_count);
            
            if error_pct < 2.0 or abs(output_real - expected_real) < 0.01 then
                pass_count <= pass_count + 1;
                report "  PASS" severity note;
            else
                fail_count <= fail_count + 1;
                report "  FAIL: Error exceeds threshold" severity warning;
            end if;
            
            wait until rising_edge(clk);
        end procedure;

    begin
        report "========================================";
        report "ELU Unit Testbench Starting";
        report "========================================";
        
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- Test Category 1: Positive Inputs
        report "--- Test Category 1: Positive Inputs ---";
        run_test(0.5,  1.0, '1', "Positive 0.5");
        run_test(1.0,  1.0, '1', "Positive 1.0");
        run_test(1.5,  1.0, '1', "Positive 1.5");
        run_test(2.0,  1.0, '1', "Positive 2.0");
        run_test(3.0,  1.0, '1', "Positive 3.0");
        run_test(0.1,  1.0, '1', "Positive 0.1");
        run_test(0.01, 1.0, '1', "Positive 0.01");

        -- Test Category 2: Zero Input
        report "--- Test Category 2: Zero Input ---";
        run_test(0.0, 1.0, '1', "Zero input");

        -- Test Category 3: Negative Inputs
        report "--- Test Category 3: Negative Inputs ---";
        run_test(-0.1,  1.0, '1', "Negative -0.1");
        run_test(-0.25, 1.0, '1', "Negative -0.25");
        run_test(-0.5,  1.0, '1', "Negative -0.5");
        run_test(-0.75, 1.0, '1', "Negative -0.75");
        run_test(-1.0,  1.0, '1', "Negative -1.0");
        run_test(-1.5,  1.0, '1', "Negative -1.5");
        run_test(-2.0,  1.0, '1', "Negative -2.0");
        run_test(-3.0,  1.0, '1', "Negative -3.0");

        -- Test Category 4: Boundary Cases
        report "--- Test Category 4: Boundary Cases ---";
        run_test(3.99,  1.0, '1', "Near max positive");
        run_test(-3.99, 1.0, '1', "Near min negative");
        run_test(0.001, 1.0, '1', "Very small positive");
        run_test(-0.001, 1.0, '1', "Very small negative");

        -- Test Category 5: Different Alpha Values
        report "--- Test Category 5: Different Alpha Values ---";
        run_test(-1.0, 0.5, '0', "Alpha=0.5, x=-1.0");
        run_test(-2.0, 0.5, '0', "Alpha=0.5, x=-2.0");
        run_test(-1.0, 2.0, '0', "Alpha=2.0, x=-1.0");
        run_test(-0.5, 2.0, '0', "Alpha=2.0, x=-0.5");
        run_test(-1.0, 0.1, '0', "Alpha=0.1, x=-1.0");

        -- Test Category 6: Reset Behavior
        report "--- Test Category 6: Reset Behavior ---";
        data_in <= real_to_q213(-1.0);
        use_default <= '1';
        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
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
        
        wait for CLK_PERIOD * 5;

        -- Test Category 7: Back-to-Back Operations
        report "--- Test Category 7: Back-to-Back Operations ---";
        run_test(1.0,  1.0, '1', "B2B Test 1 (positive)");
        run_test(-1.0, 1.0, '1', "B2B Test 2 (negative)");
        run_test(0.5,  1.0, '1', "B2B Test 3 (positive)");
        run_test(-0.5, 1.0, '1', "B2B Test 4 (negative)");

        -- Summary
        wait for CLK_PERIOD * 5;
        
        report "========================================";
        report "ELU Unit Testbench Complete";
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
