--------------------------------------------------------------------------------
-- Testbench: reciprocal_unit_tb
-- Description: Comprehensive testbench for Newton-Raphson reciprocal unit
--              Tests normal operation, edge cases, and error handling
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity reciprocal_unit_tb is
end entity reciprocal_unit_tb;

architecture testbench of reciprocal_unit_tb is

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component reciprocal_unit is
        generic (
            DATA_WIDTH     : integer := 16;
            FRAC_BITS      : integer := 13;
            INTERNAL_WIDTH : integer := 32;
            NUM_ITERATIONS : integer := 3;
            LUT_ADDR_BITS  : integer := 6
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            data_in      : in  signed(DATA_WIDTH-1 downto 0);
            start        : in  std_logic;
            data_out     : out signed(DATA_WIDTH-1 downto 0);
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
    signal data_in      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal start        : std_logic := '0';
    signal data_out     : signed(DATA_WIDTH-1 downto 0);
    signal done         : std_logic;
    signal busy         : std_logic;
    signal div_by_zero  : std_logic;
    signal overflow     : std_logic;
    
    signal test_running : boolean := true;
    
    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    
    -- Convert real to Q2.13 fixed-point
    function real_to_fixed(val : real) return signed is
        variable temp : integer;
    begin
        temp := integer(round(val * SCALE));
        return to_signed(temp, DATA_WIDTH);
    end function;
    
    -- Convert Q2.13 to real
    function fixed_to_real(val : signed) return real is
    begin
        return real(to_integer(val)) / SCALE;
    end function;
    
    -- Calculate relative error
    function rel_error(expected, actual : real) return real is
    begin
        if abs(expected) < 1.0e-6 then
            return abs(expected - actual);
        else
            return abs((expected - actual) / expected);
        end if;
    end function;
    
    ---------------------------------------------------------------------------
    -- Test Procedure
    ---------------------------------------------------------------------------
    procedure test_reciprocal(
        constant input_val : in real;
        constant expected  : in real;
        constant test_name : in string;
        signal clk_sig     : in std_logic;
        signal data_in_sig : out signed;
        signal start_sig   : out std_logic;
        signal done_sig    : in std_logic;
        signal data_out_sig: in signed;
        signal dbz_sig     : in std_logic;
        signal ovf_sig     : in std_logic
    ) is
        variable result_real : real;
        variable rel_err     : real;
        variable tolerance   : real := 0.01;  -- 1% error tolerance
    begin
        -- Apply input
        data_in_sig <= real_to_fixed(input_val);
        start_sig <= '1';
        wait until rising_edge(clk_sig);
        start_sig <= '0';
        
        -- Wait for completion
        wait until done_sig = '1';
        wait until rising_edge(clk_sig);
        
        -- Check result
        result_real := fixed_to_real(data_out_sig);
        rel_err := rel_error(expected, result_real);
        
        report "Test: " & test_name;
        report "  Input:    " & real'image(input_val);
        report "  Expected: " & real'image(expected);
        report "  Got:      " & real'image(result_real);
        report "  Error:    " & real'image(rel_err * 100.0) & "%";
        
        if dbz_sig = '1' then
            report "  [DIV_BY_ZERO flag set]";
        end if;
        
        if ovf_sig = '1' then
            report "  [OVERFLOW flag set]";
        end if;
        
        -- Check error tolerance (unless overflow/dbz expected)
        if rel_err > tolerance and dbz_sig = '0' and ovf_sig = '0' then
            report "  ERROR: Result exceeds tolerance!" severity failure;
        else
            report "  PASS" severity note;
        end if;
        
        report " ";
        
        -- Small delay between tests
        for i in 0 to 2 loop
            wait until rising_edge(clk_sig);
        end loop;
    end procedure;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : reciprocal_unit
        generic map (
            DATA_WIDTH     => DATA_WIDTH,
            FRAC_BITS      => FRAC_BITS,
            INTERNAL_WIDTH => 32,
            NUM_ITERATIONS => 3,
            LUT_ADDR_BITS  => 6
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_in      => data_in,
            start        => start,
            data_out     => data_out,
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
    begin
        -- Initial reset
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "===================================================";
        report "Starting Reciprocal Unit Tests";
        report "===================================================";
        report " ";
        
        -- Test 1: Simple cases with known results
        test_reciprocal(1.0, 1.0, "1.0 -> 1.0", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(2.0, 0.5, "2.0 -> 0.5", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(0.5, 2.0, "0.5 -> 2.0", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(4.0, 0.25, "4.0 -> 0.25 (SAT)", clk, data_in, start, done, data_out, div_by_zero, overflow);
        
        -- Test 2: Negative numbers
        test_reciprocal(-1.0, -1.0, "-1.0 -> -1.0", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(-2.0, -0.5, "-2.0 -> -0.5", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(-0.5, -2.0, "-0.5 -> -2.0", clk, data_in, start, done, data_out, div_by_zero, overflow);
        
        -- Test 3: Fractional values
        test_reciprocal(0.25, 4.0, "0.25 -> 4.0 (SAT)", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(0.75, 1.333, "0.75 -> 1.333", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(1.5, 0.667, "1.5 -> 0.667", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(3.0, 0.333, "3.0 -> 0.333", clk, data_in, start, done, data_out, div_by_zero, overflow);
        
        -- Test 4: Edge cases - small numbers (near divide-by-zero)
        test_reciprocal(0.01, 100.0, "0.01 -> 100 (overflow)", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(0.001, 1000.0, "0.001 -> 1000 (overflow)", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(0.0001, 10000.0, "0.0001 -> 10000 (div_by_zero)", clk, data_in, start, done, data_out, div_by_zero, overflow);
        
        -- Test 5: Powers of 2 (exact in fixed-point)
        test_reciprocal(0.125, 8.0, "0.125 -> 8.0 (SAT)", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(0.0625, 16.0, "0.0625 -> 16 (SAT)", clk, data_in, start, done, data_out, div_by_zero, overflow);
        
        -- Test 6: Values close to 1
        test_reciprocal(0.9, 1.111, "0.9 -> 1.111", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(1.1, 0.909, "1.1 -> 0.909", clk, data_in, start, done, data_out, div_by_zero, overflow);
        
        -- Test 7: Random values in valid range
        test_reciprocal(0.3333, 3.0, "0.3333 -> 3.0", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(2.5, 0.4, "2.5 -> 0.4", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(1.25, 0.8, "1.25 -> 0.8", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(0.8, 1.25, "0.8 -> 1.25", clk, data_in, start, done, data_out, div_by_zero, overflow);
        
        -- Test 8: Near saturation boundaries
        test_reciprocal(3.9, 0.256, "3.9 -> 0.256", clk, data_in, start, done, data_out, div_by_zero, overflow);
        test_reciprocal(-3.9, -0.256, "-3.9 -> -0.256", clk, data_in, start, done, data_out, div_by_zero, overflow);
        
        wait for CLK_PERIOD * 10;
        
        report "===================================================";
        report "All Tests Completed";
        report "===================================================";
        
        test_running <= false;
        wait;
    end process;

end architecture testbench;