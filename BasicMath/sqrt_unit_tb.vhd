--------------------------------------------------------------------------------
-- Testbench: sqrt_unit_tb
-- Description: Comprehensive testbench for Newton-Raphson square root unit
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity sqrt_unit_tb is
end entity sqrt_unit_tb;

architecture testbench of sqrt_unit_tb is

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component sqrt_unit is
        generic (
            DATA_WIDTH     : integer := 16;
            FRAC_BITS      : integer := 13;
            NUM_ITERATIONS : integer := 4
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
    signal invalid      : std_logic;
    signal overflow     : std_logic;
    
    signal test_running : boolean := true;
    
    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    
    function real_to_fixed(val : real) return signed is
        variable temp : integer;
    begin
        temp := integer(round(val * SCALE));
        return to_signed(temp, DATA_WIDTH);
    end function;
    
    function fixed_to_real(val : signed) return real is
    begin
        return real(to_integer(val)) / SCALE;
    end function;
    
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
    procedure test_sqrt(
        constant input_val : in real;
        constant expected  : in real;
        constant test_name : in string;
        signal clk_sig     : in std_logic;
        signal data_in_sig : out signed;
        signal start_sig   : out std_logic;
        signal done_sig    : in std_logic;
        signal data_out_sig: in signed;
        signal invalid_sig : in std_logic;
        signal ovf_sig     : in std_logic
    ) is
        variable result_real : real;
        variable rel_err     : real;
        variable tolerance   : real := 0.02;  -- 2% error tolerance
    begin
        -- Apply input
        data_in_sig <= real_to_fixed(input_val);
        start_sig <= '1';
        wait until rising_edge(clk_sig);
        start_sig <= '0';
        
        -- Wait for completion
        wait until done_sig = '1';
        wait for 1 ns;  -- Small delay to ensure output is stable
        
        -- Check result
        result_real := fixed_to_real(data_out_sig);
        rel_err := rel_error(expected, result_real);
        
        report "Test: " & test_name;
        report "  Input:    " & real'image(input_val);
        report "  Expected: " & real'image(expected);
        report "  Got:      " & real'image(result_real);
        report "  Error:    " & real'image(rel_err * 100.0) & "%";
        
        if invalid_sig = '1' then
            report "  [INVALID flag set - negative input]";
        end if;
        
        if ovf_sig = '1' then
            report "  [OVERFLOW flag set]";
        end if;
        
        -- Check error tolerance
        if rel_err > tolerance and invalid_sig = '0' and ovf_sig = '0' then
            report "  FAIL: Result exceeds tolerance!" severity warning;
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
    dut : sqrt_unit
        generic map (
            DATA_WIDTH     => DATA_WIDTH,
            FRAC_BITS      => FRAC_BITS,
            NUM_ITERATIONS => 4
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
    begin
        -- Initial reset
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "===================================================";
        report "Starting Square Root Unit Tests";
        report "===================================================";
        report " ";
        
        -- Test 1: Perfect squares
        test_sqrt(1.0, 1.0, "sqrt(1.0) = 1.0", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(4.0, 2.0, "sqrt(4.0) = 2.0 (SAT)", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(0.25, 0.5, "sqrt(0.25) = 0.5", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(0.0625, 0.25, "sqrt(0.0625) = 0.25", clk, data_in, start, done, data_out, invalid, overflow);
        
        -- Test 2: Simple values
        test_sqrt(2.0, 1.414, "sqrt(2.0) = 1.414", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(3.0, 1.732, "sqrt(3.0) = 1.732", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(0.5, 0.707, "sqrt(0.5) = 0.707", clk, data_in, start, done, data_out, invalid, overflow);
        
        -- Test 3: Values near 1.0
        test_sqrt(0.9, 0.949, "sqrt(0.9) = 0.949", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(1.1, 1.049, "sqrt(1.1) = 1.049", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(1.5, 1.225, "sqrt(1.5) = 1.225", clk, data_in, start, done, data_out, invalid, overflow);
        
        -- Test 4: Small values
        test_sqrt(0.1, 0.316, "sqrt(0.1) = 0.316", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(0.01, 0.1, "sqrt(0.01) = 0.1", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(0.04, 0.2, "sqrt(0.04) = 0.2", clk, data_in, start, done, data_out, invalid, overflow);
        
        -- Test 5: Larger values (near Q2.13 max ~4.0)
        test_sqrt(3.5, 1.871, "sqrt(3.5) = 1.871", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(3.9, 1.975, "sqrt(3.9) = 1.975", clk, data_in, start, done, data_out, invalid, overflow);
        
        -- Test 6: Edge cases
        test_sqrt(0.0, 0.0, "sqrt(0.0) = 0.0", clk, data_in, start, done, data_out, invalid, overflow);
        
        -- Test 7: Negative input (should set invalid flag)
        test_sqrt(-1.0, 0.0, "sqrt(-1.0) = invalid", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(-0.5, 0.0, "sqrt(-0.5) = invalid", clk, data_in, start, done, data_out, invalid, overflow);
        
        -- Test 8: Fractional values
        test_sqrt(0.36, 0.6, "sqrt(0.36) = 0.6", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(0.49, 0.7, "sqrt(0.49) = 0.7", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(0.64, 0.8, "sqrt(0.64) = 0.8", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(0.81, 0.9, "sqrt(0.81) = 0.9", clk, data_in, start, done, data_out, invalid, overflow);
        
        -- Test 9: More varied values
        test_sqrt(2.25, 1.5, "sqrt(2.25) = 1.5", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(2.56, 1.6, "sqrt(2.56) = 1.6", clk, data_in, start, done, data_out, invalid, overflow);
        test_sqrt(1.44, 1.2, "sqrt(1.44) = 1.2", clk, data_in, start, done, data_out, invalid, overflow);
        
        wait for CLK_PERIOD * 10;
        
        report "===================================================";
        report "All Tests Completed";
        report "===================================================";
        
        test_running <= false;
        wait;
    end process;

end architecture testbench;