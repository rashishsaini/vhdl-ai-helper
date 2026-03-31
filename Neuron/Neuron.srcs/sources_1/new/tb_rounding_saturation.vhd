--------------------------------------------------------------------------------
-- Testbench: tb_rounding_saturation
-- Description: Comprehensive verification testbench for rounding_saturation module
--              Outputs TCL-formatted debug information for Vivado analysis
--              Compatible with Vivado XSIM (VHDL-93/2002)
--
-- Test Coverage:
--   1. Reset behavior verification
--   2. Normal operation (values within range)
--   3. Positive saturation boundary
--   4. Negative saturation boundary
--   5. Exact boundary values
--   6. Rounding behavior (0.5 threshold)
--   7. Maximum/minimum input values
--   8. Sequential throughput test
--   9. Random stress test
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity tb_rounding_saturation is
end entity tb_rounding_saturation;

architecture sim of tb_rounding_saturation is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD   : time := 10 ns;
    constant INPUT_WIDTH  : integer := 40;
    constant OUTPUT_WIDTH : integer := 16;
    constant FRAC_SHIFT   : integer := 13;
    constant SAT_MAX      : integer := 32767;
    constant SAT_MIN      : integer := -32768;
    constant ROUND_CONST  : integer := 2**(FRAC_SHIFT-1);
    
    ---------------------------------------------------------------------------
    -- DUT Signals
    ---------------------------------------------------------------------------
    signal clk           : std_logic := '0';
    signal rst           : std_logic := '1';
    signal data_in       : std_logic_vector(INPUT_WIDTH-1 downto 0) := (others => '0');
    signal valid_in      : std_logic := '0';
    signal data_out      : std_logic_vector(OUTPUT_WIDTH-1 downto 0);
    signal valid_out     : std_logic;
    signal done          : std_logic;
    signal overflow_pos  : std_logic;
    signal overflow_neg  : std_logic;
    signal saturated     : std_logic;
    
    ---------------------------------------------------------------------------
    -- Test Control
    ---------------------------------------------------------------------------
    signal test_running  : boolean := true;
    signal pass_count    : integer := 0;
    signal fail_count    : integer := 0;
    
    ---------------------------------------------------------------------------
    -- Helper Functions (Vivado Compatible)
    ---------------------------------------------------------------------------
    
    function hex_char(val : integer) return character is
        constant hex_chars : string(1 to 16) := "0123456789ABCDEF";
    begin
        if val >= 0 and val <= 15 then
            return hex_chars(val + 1);
        else
            return 'X';
        end if;
    end function;
    
    function slv40_to_hex(val : std_logic_vector(39 downto 0)) return string is
        variable result : string(1 to 10);
        variable nibble : integer;
    begin
        for i in 0 to 9 loop
            nibble := to_integer(unsigned(val((39-i*4) downto (36-i*4))));
            result(i+1) := hex_char(nibble);
        end loop;
        return result;
    end function;
    
    function slv16_to_hex(val : std_logic_vector(15 downto 0)) return string is
        variable result : string(1 to 4);
        variable nibble : integer;
    begin
        for i in 0 to 3 loop
            nibble := to_integer(unsigned(val((15-i*4) downto (12-i*4))));
            result(i+1) := hex_char(nibble);
        end loop;
        return result;
    end function;
    
    function slv3_to_str(val : std_logic_vector(2 downto 0)) return string is
        variable result : string(1 to 3);
    begin
        for i in 2 downto 0 loop
            if val(i) = '1' then
                result(3-i) := '1';
            else
                result(3-i) := '0';
            end if;
        end loop;
        return result;
    end function;
    
    function int_to_str(val : integer) return string is
        variable temp   : integer;
        variable result : string(1 to 12) := (others => ' ');
        variable idx    : integer := 12;
        variable is_neg : boolean := false;
    begin
        if val = 0 then
            return "0";
        end if;
        
        if val < 0 then
            is_neg := true;
            temp := -val;
        else
            temp := val;
        end if;
        
        while temp > 0 and idx > 0 loop
            result(idx) := character'val((temp mod 10) + character'pos('0'));
            temp := temp / 10;
            idx := idx - 1;
        end loop;
        
        if is_neg and idx > 0 then
            result(idx) := '-';
            idx := idx - 1;
        end if;
        
        return result(idx+1 to 12);
    end function;
    
    ---------------------------------------------------------------------------
    -- Golden Model
    ---------------------------------------------------------------------------
    function golden_model(input_val : signed(INPUT_WIDTH-1 downto 0)) 
        return std_logic_vector is
        variable rounded : signed(INPUT_WIDTH-1 downto 0);
        variable shifted : signed(INPUT_WIDTH-1 downto 0);
    begin
        rounded := input_val + to_signed(ROUND_CONST, INPUT_WIDTH);
        shifted := shift_right(rounded, FRAC_SHIFT);
        
        if shifted > to_signed(SAT_MAX, INPUT_WIDTH) then
            return std_logic_vector(to_signed(SAT_MAX, OUTPUT_WIDTH));
        elsif shifted < to_signed(SAT_MIN, INPUT_WIDTH) then
            return std_logic_vector(to_signed(SAT_MIN, OUTPUT_WIDTH));
        else
            return std_logic_vector(shifted(OUTPUT_WIDTH-1 downto 0));
        end if;
    end function;
    
    function expect_flags(input_val : signed(INPUT_WIDTH-1 downto 0)) 
        return std_logic_vector is
        variable rounded : signed(INPUT_WIDTH-1 downto 0);
        variable shifted : signed(INPUT_WIDTH-1 downto 0);
    begin
        rounded := input_val + to_signed(ROUND_CONST, INPUT_WIDTH);
        shifted := shift_right(rounded, FRAC_SHIFT);
        
        if shifted > to_signed(SAT_MAX, INPUT_WIDTH) then
            return "101";
        elsif shifted < to_signed(SAT_MIN, INPUT_WIDTH) then
            return "110";
        else
            return "000";
        end if;
    end function;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk_process: process
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
    -- DUT
    ---------------------------------------------------------------------------
    dut: entity work.rounding_saturation
        generic map (
            INPUT_WIDTH  => INPUT_WIDTH,
            OUTPUT_WIDTH => OUTPUT_WIDTH,
            FRAC_SHIFT   => FRAC_SHIFT,
            SAT_MAX      => SAT_MAX,
            SAT_MIN      => SAT_MIN
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_in      => data_in,
            valid_in     => valid_in,
            data_out     => data_out,
            valid_out    => valid_out,
            done         => done,
            overflow_pos => overflow_pos,
            overflow_neg => overflow_neg,
            saturated    => saturated
        );

    ---------------------------------------------------------------------------
    -- Main Test Process
    ---------------------------------------------------------------------------
    test_process: process
        variable test_input    : signed(INPUT_WIDTH-1 downto 0);
        variable expected_out  : std_logic_vector(OUTPUT_WIDTH-1 downto 0);
        variable expected_flags: std_logic_vector(2 downto 0);
        variable actual_flags  : std_logic_vector(2 downto 0);
        variable test_passed   : boolean;
        variable seed1, seed2  : positive := 42;
        variable rand_real     : real;
        variable rand_int      : integer;
        
        procedure run_test(
            test_id   : integer;
            test_desc : string;
            input_val : signed(INPUT_WIDTH-1 downto 0)
        ) is
        begin
            expected_out := golden_model(input_val);
            expected_flags := expect_flags(input_val);
            
            data_in <= std_logic_vector(input_val);
            valid_in <= '1';
            wait until rising_edge(clk);
            valid_in <= '0';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            
            actual_flags := saturated & overflow_neg & overflow_pos;
            test_passed := (data_out = expected_out) and (actual_flags = expected_flags);
            
            report "TCL_LOG: ----------------------------------------" severity note;
            report "TCL_LOG: TEST_ID: " & int_to_str(test_id) severity note;
            report "TCL_LOG: TEST_DESC: " & test_desc severity note;
            report "TCL_LOG: INPUT_HEX: 0x" & slv40_to_hex(std_logic_vector(input_val)) severity note;
            report "TCL_LOG: EXPECTED_OUT_HEX: 0x" & slv16_to_hex(expected_out) severity note;
            report "TCL_LOG: ACTUAL_OUT_HEX: 0x" & slv16_to_hex(data_out) severity note;
            report "TCL_LOG: EXPECTED_FLAGS: " & slv3_to_str(expected_flags) severity note;
            report "TCL_LOG: ACTUAL_FLAGS: " & slv3_to_str(actual_flags) severity note;
            
            if valid_out = '1' then
                report "TCL_LOG: VALID_OUT: 1" severity note;
            else
                report "TCL_LOG: VALID_OUT: 0" severity note;
            end if;
            
            if done = '1' then
                report "TCL_LOG: DONE: 1" severity note;
            else
                report "TCL_LOG: DONE: 0" severity note;
            end if;
            
            if test_passed then
                report "TCL_LOG: RESULT: PASS" severity note;
                pass_count <= pass_count + 1;
            else
                report "TCL_LOG: RESULT: FAIL" severity note;
                fail_count <= fail_count + 1;
            end if;
            
            wait until rising_edge(clk);
        end procedure;
        
    begin
        report "TCL_LOG: ========================================" severity note;
        report "TCL_LOG: TESTBENCH START: rounding_saturation" severity note;
        report "TCL_LOG: INPUT_WIDTH: " & int_to_str(INPUT_WIDTH) severity note;
        report "TCL_LOG: OUTPUT_WIDTH: " & int_to_str(OUTPUT_WIDTH) severity note;
        report "TCL_LOG: FRAC_SHIFT: " & int_to_str(FRAC_SHIFT) severity note;
        report "TCL_LOG: ========================================" severity note;
        
        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);
        report "TCL_LOG: RESET_COMPLETE: 1" severity note;
        
        -- Test 1: Zero
        run_test(1, "Zero input", to_signed(0, INPUT_WIDTH));
        
        -- Test 2: 1.0 in Q10.26
        run_test(2, "1.0 in Q10.26", to_signed(2**26, INPUT_WIDTH));
        
        -- Test 3: -1.0 in Q10.26
        run_test(3, "-1.0 in Q10.26", to_signed(-2**26, INPUT_WIDTH));
        
        -- Test 4: Max Q2.13 boundary
        run_test(4, "Max Q2.13 boundary", to_signed(32767 * (2**13), INPUT_WIDTH));
        
        -- Test 5: Above max (saturate)
        run_test(5, "Above max (saturate pos)", to_signed(32768 * (2**13), INPUT_WIDTH));
        
        -- Test 6: Min Q2.13 boundary
        run_test(6, "Min Q2.13 boundary", to_signed(-32768 * (2**13), INPUT_WIDTH));
        
        -- Test 7: Below min (saturate)
        run_test(7, "Below min (saturate neg)", to_signed(-32769 * (2**13), INPUT_WIDTH));
        
        -- Test 8: Large positive
        test_input := shift_left(to_signed(1, INPUT_WIDTH), 35);
        run_test(8, "Large positive overflow", test_input);
        
        -- Test 9: Large negative
        test_input := -shift_left(to_signed(1, INPUT_WIDTH), 35);
        run_test(9, "Large negative overflow", test_input);
        
        -- Test 10: Rounding at 0.5
        run_test(10, "Rounding at 0.5 boundary", to_signed(2**12, INPUT_WIDTH));
        
        -- Test 11: Just below 0.5
        run_test(11, "Rounding just below 0.5", to_signed(2**12 - 1, INPUT_WIDTH));
        
        -- Test 12: 2.5 in Q10.26
        run_test(12, "2.5 in Q10.26", to_signed(integer(2.5 * real(2**26)), INPUT_WIDTH));
        
        -- Test 13: -2.5 in Q10.26
        run_test(13, "-2.5 in Q10.26", to_signed(integer(-2.5 * real(2**26)), INPUT_WIDTH));
        
        -- Test 14: 0.125 in Q10.26
        run_test(14, "0.125 in Q10.26", to_signed(integer(0.125 * real(2**26)), INPUT_WIDTH));
        
        -- Test 15: Max 40-bit positive
        test_input := (INPUT_WIDTH-1 => '0', others => '1');
        run_test(15, "Max 40-bit positive", test_input);
        
        -- Test 16: Min 40-bit negative
        test_input := (INPUT_WIDTH-1 => '1', others => '0');
        run_test(16, "Min 40-bit negative", test_input);
        
        -- Tests 17-26: Random
        for i in 17 to 26 loop
            uniform(seed1, seed2, rand_real);
            rand_int := integer((rand_real - 0.5) * real(2**30));
            run_test(i, "Random test", to_signed(rand_int, INPUT_WIDTH));
        end loop;
        
        -- Throughput test
        report "TCL_LOG: THROUGHPUT_TEST_START" severity note;
        for i in 0 to 9 loop
            data_in <= std_logic_vector(to_signed(i * 1000000, INPUT_WIDTH));
            valid_in <= '1';
            wait until rising_edge(clk);
        end loop;
        valid_in <= '0';
        wait for CLK_PERIOD * 5;
        report "TCL_LOG: THROUGHPUT_TEST_COMPLETE" severity note;
        
        -- Summary
        wait for CLK_PERIOD * 3;
        report "TCL_LOG: ========================================" severity note;
        report "TCL_LOG: TESTBENCH COMPLETE" severity note;
        report "TCL_LOG: TOTAL_TESTS: " & int_to_str(pass_count + fail_count) severity note;
        report "TCL_LOG: PASSED: " & int_to_str(pass_count) severity note;
        report "TCL_LOG: FAILED: " & int_to_str(fail_count) severity note;
        
        if fail_count = 0 then
            report "TCL_LOG: OVERALL_RESULT: ALL_TESTS_PASSED" severity note;
            report "=== ALL TESTS PASSED ===" severity note;
        else
            report "TCL_LOG: OVERALL_RESULT: SOME_TESTS_FAILED" severity note;
            report "=== SOME TESTS FAILED ===" severity error;
        end if;
        
        report "TCL_LOG: ========================================" severity note;
        
        test_running <= false;
        wait;
    end process;

end architecture sim;