--------------------------------------------------------------------------------
-- Simple testbench to verify division_unit for adaptive_lr_unit debugging
-- Tests: 8192 / 82 (1.0 / 0.01 in Q2.13)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity division_unit_simple_tb is
end entity division_unit_simple_tb;

architecture testbench of division_unit_simple_tb is

    component division_unit is
        generic (
            DATA_WIDTH     : integer := 16;
            FRAC_BITS      : integer := 13;
            NUM_ITERATIONS : integer := 3
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            dividend     : in  signed(15 downto 0);
            divisor      : in  signed(15 downto 0);
            start        : in  std_logic;
            quotient     : out signed(15 downto 0);
            done         : out std_logic;
            busy         : out std_logic;
            div_by_zero  : out std_logic;
            overflow     : out std_logic
        );
    end component;

    constant CLK_PERIOD : time := 10 ns;

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal dividend     : signed(15 downto 0) := (others => '0');
    signal divisor      : signed(15 downto 0) := (others => '0');
    signal start        : std_logic := '0';
    signal quotient     : signed(15 downto 0);
    signal done         : std_logic;
    signal busy         : std_logic;
    signal div_by_zero  : std_logic;
    signal overflow     : std_logic;

    signal test_done : boolean := false;

    function fixed_to_real_q2_13(val : signed) return real is
        constant scale : real := 2.0 ** 13.0;
    begin
        return real(to_integer(val)) / scale;
    end function;

begin

    -- Test with NUM_ITERATIONS = 3 (current adaptive_lr_unit setting)
    DUT: division_unit
        generic map (
            DATA_WIDTH     => 16,
            FRAC_BITS      => 13,
            NUM_ITERATIONS => 3
        )
        port map (
            clk          => clk,
            rst          => rst,
            dividend     => dividend,
            divisor      => divisor,
            start        => start,
            quotient     => quotient,
            done         => done,
            busy         => busy,
            div_by_zero  => div_by_zero,
            overflow     => overflow
        );

    clk_process: process
    begin
        while not test_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    test_process: process
    begin
        report "========================================";
        report "division_unit Simple Test";
        report "Testing: 8192 / 82 (1.0 / 0.01 in Q2.13)";
        report "Expected: ~100 (may overflow)";
        report "NUM_ITERATIONS = 3";
        report "========================================";

        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Test: 1.0 / 0.01 = 100
        dividend <= to_signed(8192, 16);  -- 1.0 in Q2.13
        divisor  <= to_signed(82, 16);    -- 0.01 in Q2.13

        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        wait until done = '1' for 1 us;

        assert done = '1'
            report "TIMEOUT waiting for division"
            severity failure;

        report "Result: quotient=" & integer'image(to_integer(quotient)) &
               " (" & real'image(fixed_to_real_q2_13(quotient)) & ")";
        report "  div_by_zero=" & std_logic'image(div_by_zero);
        report "  overflow=" & std_logic'image(overflow);

        if overflow = '1' then
            report "  OVERFLOW detected (expected for 1.0/0.01)";
        elsif quotient = to_signed(32, 16) then
            report "  BUG CONFIRMED: Got ~0.0039 instead of ~100";
            report "  This matches the adaptive_lr_unit failure!";
        else
            report "  Unexpected result";
        end if;

        wait for CLK_PERIOD * 5;

        -- Test with more iterations
        report "========================================";
        report "NOTE: Try increasing NUM_ITERATIONS to 10+";
        report "      in both division_unit and adaptive_lr_unit";
        report "========================================";

        test_done <= true;
        wait;
    end process;

end architecture testbench;
