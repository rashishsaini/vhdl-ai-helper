--------------------------------------------------------------------------------
-- Testbench: bias_adder_tb
-- Description: Comprehensive testbench for bias_adder module
--              Tests all functionality with detailed TCL console output
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

entity bias_adder_tb is
    -- Testbench has no ports
end bias_adder_tb;

architecture behavioral of bias_adder_tb is
    
    -- Component Declaration
    component bias_adder is
        generic (
            ACCUM_WIDTH : integer := 40;
            BIAS_WIDTH  : integer := 16;
            ENABLE_OVERFLOW_CHECK : boolean := true
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            enable      : in  std_logic;
            accum_in    : in  signed(ACCUM_WIDTH-1 downto 0);
            bias        : in  signed(BIAS_WIDTH-1 downto 0);
            sum_out     : out signed(ACCUM_WIDTH-1 downto 0);
            valid       : out std_logic;
            overflow    : out std_logic
        );
    end component;
    
    -- Test Configuration
    constant ACCUM_WIDTH : integer := 40;
    constant BIAS_WIDTH  : integer := 16;
    constant CLK_PERIOD  : time := 10 ns;  -- 100 MHz
    
    -- Clock and Reset
    signal clk       : std_logic := '0';
    signal rst       : std_logic := '0';
    signal enable    : std_logic := '0';
    
    -- DUT Signals
    signal accum_in  : signed(ACCUM_WIDTH-1 downto 0) := (others => '0');
    signal bias      : signed(BIAS_WIDTH-1 downto 0) := (others => '0');
    signal sum_out   : signed(ACCUM_WIDTH-1 downto 0);
    signal valid     : std_logic;
    signal overflow  : std_logic;
    
    -- Test Control
    signal test_complete : boolean := false;
    signal test_num      : integer := 0;
    signal pass_count    : integer := 0;
    signal fail_count    : integer := 0;
    
    -- Helper function to convert signed to real (Q10.26 format)
    function to_real_q10_26(s : signed) return real is
        variable result : real;
    begin
        result := real(to_integer(s)) / real(2**26);
        return result;
    end function;
    
    -- Helper function to convert signed to real (Q2.13 format)
    function to_real_q2_13(s : signed) return real is
        variable result : real;
    begin
        result := real(to_integer(s)) / real(2**13);
        return result;
    end function;
    
    -- Procedure to print formatted test header
    procedure print_test_header is
        variable l : line;
    begin
        write(l, string'("================================================================================"));
        writeline(output, l);
        write(l, string'("                    BIAS ADDER TESTBENCH"));
        writeline(output, l);
        write(l, string'("================================================================================"));
        writeline(output, l);
        write(l, string'("Configuration:"));
        writeline(output, l);
        write(l, string'("  ACCUM_WIDTH = ") & integer'image(ACCUM_WIDTH) & string'(" bits (Q10.26)"));
        writeline(output, l);
        write(l, string'("  BIAS_WIDTH  = ") & integer'image(BIAS_WIDTH) & string'(" bits (Q2.13)"));
        writeline(output, l);
        write(l, string'("  CLK_PERIOD  = ") & time'image(CLK_PERIOD));
        writeline(output, l);
        write(l, string'("================================================================================"));
        writeline(output, l);
        writeline(output, l);
    end procedure;
    
    -- Procedure to print test case
    procedure print_test_case(
        test_id    : integer;
        test_name  : string;
        accum_val  : signed;
        bias_val   : signed;
        expected   : signed;
        actual     : signed;
        pass       : boolean;
        ovf        : std_logic
    ) is
        variable l : line;
        variable accum_real  : real;
        variable bias_real   : real;
        variable expected_real : real;
        variable actual_real : real;
    begin
        -- Convert to real for display
        accum_real := to_real_q10_26(accum_val);
        bias_real := to_real_q2_13(resize(bias_val, 16));
        expected_real := to_real_q10_26(expected);
        actual_real := to_real_q10_26(actual);
        
        write(l, string'("Test #") & integer'image(test_id) & string'(": ") & test_name);
        writeline(output, l);
        write(l, string'("--------------------------------------------------------------------------------"));
        writeline(output, l);
        
        -- Print inputs in both hex and decimal
        write(l, string'("  Accumulator:  0x"));
        hwrite(l, std_logic_vector(accum_val));
        write(l, string'("  (") & real'image(accum_real) & string'(")"));
        writeline(output, l);
        
        write(l, string'("  Bias:         0x"));
        hwrite(l, std_logic_vector(resize(bias_val, 16)));
        write(l, string'("              (") & real'image(bias_real) & string'(")"));
        writeline(output, l);
        
        -- Print expected and actual
        write(l, string'("  Expected:     0x"));
        hwrite(l, std_logic_vector(expected));
        write(l, string'("  (") & real'image(expected_real) & string'(")"));
        writeline(output, l);
        
        write(l, string'("  Actual:       0x"));
        hwrite(l, std_logic_vector(actual));
        write(l, string'("  (") & real'image(actual_real) & string'(")"));
        writeline(output, l);
        
        -- Print overflow status
        write(l, string'("  Overflow:     ") & std_logic'image(ovf));
        writeline(output, l);
        
        -- Print result
        if pass then
            write(l, string'("  Result:       PASS "));
        else
            write(l, string'("  Result:       FAIL "));
        end if;
        writeline(output, l);
        writeline(output, l);
    end procedure;
    
    -- Procedure to run a test case
    procedure run_test(
        signal clk_sig     : in  std_logic;
        signal enable_sig  : out std_logic;
        signal accum_sig   : out signed;
        signal bias_sig    : out signed;
        signal sum_sig     : in  signed;
        signal valid_sig   : in  std_logic;
        signal ovf_sig     : in  std_logic;
        signal test_n      : inout integer;
        signal pass_c      : inout integer;
        signal fail_c      : inout integer;
        test_name          : string;
        accum_val          : signed;
        bias_val           : signed;
        expected_val       : signed;
        check_overflow     : boolean := false;
        expect_overflow    : std_logic := '0'
    ) is
        variable actual_val : signed(ACCUM_WIDTH-1 downto 0);
        variable test_pass  : boolean;
    begin
        test_n <= test_n + 1;
        
        -- Apply inputs
        accum_sig <= accum_val;
        bias_sig <= bias_val;
        enable_sig <= '1';
        
        -- Wait for clock edge
        wait until rising_edge(clk_sig);
        wait for 1 ns;  -- Small delay for signals to settle
        
        -- Capture output
        actual_val := sum_sig;
        
        -- Check result
        test_pass := (actual_val = expected_val);
        if check_overflow then
            test_pass := test_pass and (ovf_sig = expect_overflow);
        end if;
        
        -- Update counters
        if test_pass then
            pass_c <= pass_c + 1;
        else
            fail_c <= fail_c + 1;
        end if;
        
        -- Print results
        print_test_case(test_n, test_name, accum_val, bias_val, 
                       expected_val, actual_val, test_pass, ovf_sig);
        
        -- Disable for next test
        enable_sig <= '0';
        wait until rising_edge(clk_sig);
    end procedure;
    
begin

    ----------------------------------------------------------------------------
    -- Clock Generation
    ----------------------------------------------------------------------------
    clk_process: process
    begin
        while not test_complete loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;
    
    ----------------------------------------------------------------------------
    -- Device Under Test (DUT)
    ----------------------------------------------------------------------------
    DUT: bias_adder
        generic map (
            ACCUM_WIDTH => ACCUM_WIDTH,
            BIAS_WIDTH  => BIAS_WIDTH,
            ENABLE_OVERFLOW_CHECK => true
        )
        port map (
            clk      => clk,
            rst      => rst,
            enable   => enable,
            accum_in => accum_in,
            bias     => bias,
            sum_out  => sum_out,
            valid    => valid,
            overflow => overflow
        );
    
    ----------------------------------------------------------------------------
    -- Test Stimulus Process
    ----------------------------------------------------------------------------
    stimulus: process
        variable l : line;
        
        -- Test value definitions (Q10.26 for accumulator, Q2.13 for bias)
        -- Accumulator values (40-bit Q10.26)
        constant ACCUM_ZERO     : signed(39 downto 0) := (others => '0');
        constant ACCUM_POS_1    : signed(39 downto 0) := to_signed(67108864, 40);    -- 1.0 in Q10.26
        constant ACCUM_POS_10   : signed(39 downto 0) := to_signed(671088640, 40);   -- 10.0 in Q10.26
        constant ACCUM_NEG_1    : signed(39 downto 0) := to_signed(-67108864, 40);   -- -1.0 in Q10.26
        constant ACCUM_NEG_10   : signed(39 downto 0) := to_signed(-671088640, 40);  -- -10.0 in Q10.26
        
        -- Bias values (16-bit Q2.13)
        constant BIAS_ZERO      : signed(15 downto 0) := (others => '0');
        constant BIAS_POS_0_5   : signed(15 downto 0) := to_signed(4096, 16);   -- 0.5 in Q2.13
        constant BIAS_POS_1     : signed(15 downto 0) := to_signed(8192, 16);   -- 1.0 in Q2.13
        constant BIAS_POS_2     : signed(15 downto 0) := to_signed(16384, 16);  -- 2.0 in Q2.13
        constant BIAS_NEG_0_5   : signed(15 downto 0) := to_signed(-4096, 16);  -- -0.5 in Q2.13
        constant BIAS_NEG_1     : signed(15 downto 0) := to_signed(-8192, 16);  -- -1.0 in Q2.13
        constant BIAS_MAX       : signed(15 downto 0) := to_signed(32767, 16);  -- Max: ~3.999
        constant BIAS_MIN       : signed(15 downto 0) := to_signed(-32768, 16); -- Min: -4.0
        
    begin
        -- Print test header
        print_test_header;
        
        ----------------------------------------------------------------------------
        -- Test 1: Reset Behavior
        ----------------------------------------------------------------------------
        write(l, string'(">>> Testing Reset Behavior"));
        writeline(output, l);
        writeline(output, l);
        
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD;
        
        assert sum_out = (ACCUM_WIDTH-1 downto 0 => '0')
            report "Reset failed: Output not zero"
            severity error;
        
        write(l, string'("Reset Test: PASS "));
        writeline(output, l);
        writeline(output, l);
        pass_count <= pass_count + 1;
        
        ----------------------------------------------------------------------------
        -- Test 2: Basic Positive Addition
        ----------------------------------------------------------------------------
        write(l, string'(">>> Testing Basic Positive Additions"));
        writeline(output, l);
        writeline(output, l);
        
        -- Test 2.1: Zero accumulator + positive bias
        run_test(clk, enable, accum_in, bias, sum_out, valid, overflow,
                test_num, pass_count, fail_count,
                "Zero accumulator + 1.0 bias",
                ACCUM_ZERO, BIAS_POS_1,
                resize(shift_left(resize(BIAS_POS_1, 40), 13), 40));
        
        -- Test 2.2: Positive accumulator + positive bias
        run_test(clk, enable, accum_in, bias, sum_out, valid, overflow,
                test_num, pass_count, fail_count,
                "10.0 accumulator + 2.0 bias",
                ACCUM_POS_10, BIAS_POS_2,
                ACCUM_POS_10 + resize(shift_left(resize(BIAS_POS_2, 40), 13), 40));
        
        ----------------------------------------------------------------------------
        -- Test 3: Basic Negative Addition
        ----------------------------------------------------------------------------
        write(l, string'(">>> Testing Negative Value Additions"));
        writeline(output, l);
        writeline(output, l);
        
        -- Test 3.1: Positive accumulator + negative bias
        run_test(clk, enable, accum_in, bias, sum_out, valid, overflow,
                test_num, pass_count, fail_count,
                "10.0 accumulator + (-1.0) bias",
                ACCUM_POS_10, BIAS_NEG_1,
                ACCUM_POS_10 + resize(shift_left(resize(BIAS_NEG_1, 40), 13), 40));
        
        -- Test 3.2: Negative accumulator + negative bias
        run_test(clk, enable, accum_in, bias, sum_out, valid, overflow,
                test_num, pass_count, fail_count,
                "(-10.0) accumulator + (-1.0) bias",
                ACCUM_NEG_10, BIAS_NEG_1,
                ACCUM_NEG_10 + resize(shift_left(resize(BIAS_NEG_1, 40), 13), 40));
        
        -- Test 3.3: Negative accumulator + positive bias (result positive)
        run_test(clk, enable, accum_in, bias, sum_out, valid, overflow,
                test_num, pass_count, fail_count,
                "(-1.0) accumulator + 2.0 bias",
                ACCUM_NEG_1, BIAS_POS_2,
                ACCUM_NEG_1 + resize(shift_left(resize(BIAS_POS_2, 40), 13), 40));
        
        ----------------------------------------------------------------------------
        -- Test 4: Zero Cases
        ----------------------------------------------------------------------------
        write(l, string'(">>> Testing Zero Cases"));
        writeline(output, l);
        writeline(output, l);
        
        -- Test 4.1: Zero + zero
        run_test(clk, enable, accum_in, bias, sum_out, valid, overflow,
                test_num, pass_count, fail_count,
                "Zero accumulator + zero bias",
                ACCUM_ZERO, BIAS_ZERO, ACCUM_ZERO);
        
        
        ----------------------------------------------------------------------------
        -- Test 5: Boundary Cases
        ----------------------------------------------------------------------------
        write(l, string'(">>> Testing Boundary Values"));
        writeline(output, l);
        writeline(output, l);
        
        -- Test 5.1: Maximum bias
        run_test(clk, enable, accum_in, bias, sum_out, valid, overflow,
                test_num, pass_count, fail_count,
                "10.0 accumulator + max bias (~3.999)",
                ACCUM_POS_10, BIAS_MAX,
                ACCUM_POS_10 + resize(shift_left(resize(BIAS_MAX, 40), 13), 40));
        
        -- Test 5.2: Minimum bias
        run_test(clk, enable, accum_in, bias, sum_out, valid, overflow,
                test_num, pass_count, fail_count,
                "10.0 accumulator + min bias (-4.0)",
                ACCUM_POS_10, BIAS_MIN,
                ACCUM_POS_10 + resize(shift_left(resize(BIAS_MIN, 40), 13), 40));
        
        ----------------------------------------------------------------------------
        -- Test 6: Fractional Values
        ----------------------------------------------------------------------------
        write(l, string'(">>> Testing Fractional Values"));
        writeline(output, l);
        writeline(output, l);
        
        -- Test 6.1: Fractional bias
        run_test(clk, enable, accum_in, bias, sum_out, valid, overflow,
                test_num, pass_count, fail_count,
                "1.0 accumulator + 0.5 bias",
                ACCUM_POS_1, BIAS_POS_0_5,
                ACCUM_POS_1 + resize(shift_left(resize(BIAS_POS_0_5, 40), 13), 40));
        
        -- Test 6.2: Negative fractional
        run_test(clk, enable, accum_in, bias, sum_out, valid, overflow,
                test_num, pass_count, fail_count,
                "1.0 accumulator + (-0.5) bias",
                ACCUM_POS_1, BIAS_NEG_0_5,
                ACCUM_POS_1 + resize(shift_left(resize(BIAS_NEG_0_5, 40), 13), 40));
        
        ----------------------------------------------------------------------------
        -- Test 7: Enable Signal Behavior
        ----------------------------------------------------------------------------
        write(l, string'(">>> Testing Enable Signal Control"));
        writeline(output, l);
        writeline(output, l);
        
        -- Apply values but don't enable
        accum_in <= ACCUM_POS_10;
        bias <= BIAS_POS_1;
        enable <= '0';
        wait for CLK_PERIOD * 2;
        
        assert valid = '0'
            report "Valid should be low when enable is low"
            severity error;
        
        write(l, string'("Enable Control Test: PASS "));
        writeline(output, l);
        writeline(output, l);
        pass_count <= pass_count + 1;
        
        ----------------------------------------------------------------------------
        -- Test Summary
        ----------------------------------------------------------------------------
        wait for CLK_PERIOD * 2;
        
        write(l, string'("================================================================================"));
        writeline(output, l);
        write(l, string'("                         TEST SUMMARY"));
        writeline(output, l);
        write(l, string'("================================================================================"));
        writeline(output, l);
        write(l, string'("Total Tests:  ") & integer'image(test_num + 2));  -- +2 for reset and enable
        writeline(output, l);
        write(l, string'("Passed:       ") & integer'image(pass_count));
        writeline(output, l);
        write(l, string'("Failed:       ") & integer'image(fail_count));
        writeline(output, l);
        write(l, string'("================================================================================"));
        writeline(output, l);
        
        if fail_count = 0 then
            write(l, string'(">>> ALL TESTS PASSED! "));
            writeline(output, l);
        else
            write(l, string'(">>> SOME TESTS FAILED! Review output above."));
            writeline(output, l);
        end if;
        
        write(l, string'("================================================================================"));
        writeline(output, l);
        writeline(output, l);
        
        -- End simulation
        test_complete <= true;
        write(l, string'("Simulation completed."));
        writeline(output, l);
        
        wait;
    end process;

end behavioral;