--------------------------------------------------------------------------------
-- Testbench: power_unit_tb
-- Description: Comprehensive testbench for power_unit (binary exponentiation)
--              Tests beta^t computation for Adam bias correction
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity power_unit_tb is
end entity power_unit_tb;

architecture testbench of power_unit_tb is

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component power_unit is
        generic (
            DATA_WIDTH : integer := 16;
            EXP_WIDTH  : integer := 14;
            MAX_POWER  : integer := 10000
        );
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            base      : in  signed(15 downto 0);
            exponent  : in  unsigned(13 downto 0);
            start     : in  std_logic;
            result    : out signed(15 downto 0);
            done      : out std_logic;
            busy      : out std_logic;
            underflow : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : integer := 16;
    constant FRAC_BITS  : integer := 15;  -- Q0.15 format

    constant SCALE : real := 2.0 ** real(FRAC_BITS);

    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '0';
    signal base       : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal exponent   : unsigned(13 downto 0) := (others => '0');
    signal start      : std_logic := '0';
    signal result     : signed(DATA_WIDTH-1 downto 0);
    signal done       : std_logic;
    signal busy       : std_logic;
    signal underflow  : std_logic;

    signal test_running : boolean := true;

    -- Test statistics
    signal pass_count : integer := 0;
    signal fail_count : integer := 0;

    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------

    function real_to_fixed_q0_15(val : real) return signed is
        variable temp : integer;
    begin
        temp := integer(round(val * SCALE));
        -- Saturate to Q0.15 range [0, 0.999969]
        if temp > 32767 then
            return to_signed(32767, DATA_WIDTH);
        elsif temp < 0 then
            return to_signed(0, DATA_WIDTH);
        else
            return to_signed(temp, DATA_WIDTH);
        end if;
    end function;

    function fixed_to_real_q0_15(val : signed) return real is
    begin
        return real(to_integer(val)) / SCALE;
    end function;

    ---------------------------------------------------------------------------
    -- Test Procedure
    ---------------------------------------------------------------------------
    procedure test_power(
        constant base_val  : in real;
        constant exp_val   : in integer;
        constant test_name : in string;
        signal clk_sig     : in std_logic;
        signal base_sig    : out signed;
        signal exp_sig     : out unsigned;
        signal start_sig   : out std_logic;
        signal done_sig    : in std_logic;
        signal result_sig  : in signed;
        signal underflow_sig : in std_logic;
        signal pass_cnt    : inout integer;
        signal fail_cnt    : inout integer
    ) is
        variable result_real : real;
        variable expected    : real;
        variable error       : real;
        variable tolerance   : real := 0.001;  -- 0.1% error tolerance
    begin
        -- Apply inputs
        base_sig <= real_to_fixed_q0_15(base_val);
        exp_sig  <= to_unsigned(exp_val, 14);
        start_sig <= '1';
        wait until rising_edge(clk_sig);
        start_sig <= '0';

        -- Wait for completion
        wait until done_sig = '1';
        wait for 1 ns;

        -- Calculate expected value
        expected := base_val ** exp_val;

        -- Get result
        result_real := fixed_to_real_q0_15(result_sig);
        error := abs(expected - result_real);

        report "Test: " & test_name;
        report "  Base:     " & real'image(base_val);
        report "  Exponent: " & integer'image(exp_val);
        report "  Expected: " & real'image(expected);
        report "  Got:      " & real'image(result_real);
        report "  Error:    " & real'image(error);

        if underflow_sig = '1' then
            report "  [UNDERFLOW flag set]";
        end if;

        -- Check result (relative error for small values, absolute for larger)
        if expected > 0.01 then
            -- Use relative error for values > 0.01
            if error / expected > tolerance then
                report "  FAIL: Result exceeds tolerance!" severity warning;
                fail_cnt <= fail_cnt + 1;
            else
                report "  PASS" severity note;
                pass_cnt <= pass_cnt + 1;
            end if;
        else
            -- Use absolute error for very small values (near underflow)
            if error > 0.001 and underflow_sig = '0' then
                report "  FAIL: Result exceeds tolerance!" severity warning;
                fail_cnt <= fail_cnt + 1;
            else
                report "  PASS (small value/underflow)" severity note;
                pass_cnt <= pass_cnt + 1;
            end if;
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
    dut : power_unit
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            EXP_WIDTH  => 14,
            MAX_POWER  => 10000
        )
        port map (
            clk       => clk,
            rst       => rst,
            base      => base,
            exponent  => exponent,
            start     => start,
            result    => result,
            done      => done,
            busy      => busy,
            underflow => underflow
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
        report "Starting Power Unit Tests (Binary Exponentiation)";
        report "===================================================";
        report " ";

        -- Test 1: Special cases
        report "--- Test Set 1: Special Cases ---";
        test_power(0.9, 0, "beta1^0 = 1.0", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.9, 1, "beta1^1 = 0.9", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.999, 1, "beta2^1 = 0.999", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);

        -- Test 2: Small exponents (Adam early training steps)
        report "--- Test Set 2: Early Training Steps (t=1-10) ---";
        test_power(0.9, 2, "beta1^2 = 0.81", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.9, 3, "beta1^3 = 0.729", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.9, 5, "beta1^5 = 0.59049", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.9, 10, "beta1^10 = 0.3487", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);

        test_power(0.999, 2, "beta2^2 = 0.998", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.999, 5, "beta2^5 = 0.995", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.999, 10, "beta2^10 = 0.990", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);

        -- Test 3: Medium exponents (typical training)
        report "--- Test Set 3: Typical Training Steps (t=50-100) ---";
        test_power(0.9, 50, "beta1^50 = 0.00515", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.9, 100, "beta1^100 = 0.0000266", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);

        test_power(0.999, 50, "beta2^50 = 0.9512", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.999, 100, "beta2^100 = 0.9048", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);

        -- Test 4: Large exponents (extended training - may underflow)
        report "--- Test Set 4: Extended Training (t=500-1000) ---";
        test_power(0.9, 500, "beta1^500 (underflow expected)", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.9, 1000, "beta1^1000 (underflow expected)", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);

        test_power(0.999, 500, "beta2^500 = 0.6065", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.999, 1000, "beta2^1000 = 0.3677", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);

        -- Test 5: Other common beta values
        report "--- Test Set 5: Alternative Beta Values ---";
        test_power(0.95, 10, "beta1=0.95, t=10", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.99, 10, "beta1=0.99, t=10", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.9999, 100, "beta2=0.9999, t=100", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);

        -- Test 6: Edge cases
        report "--- Test Set 6: Edge Cases ---";
        test_power(1.0, 1000, "1.0^1000 = 1.0", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);
        test_power(0.5, 10, "0.5^10 = 0.00098", clk, base, exponent, start, done, result, underflow, pass_count, fail_count);

        wait for CLK_PERIOD * 10;

        report "===================================================";
        report "All Tests Completed";
        report "PASS: " & integer'image(pass_count);
        report "FAIL: " & integer'image(fail_count);
        report "===================================================";

        test_running <= false;
        wait;
    end process;

end architecture testbench;
