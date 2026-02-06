--------------------------------------------------------------------------------
-- Testbench: adaptive_lr_unit_tb
-- Description: Comprehensive testbench for adaptive_lr_unit
--              Tests adaptive learning rate: update = η × m / (√v + ε)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity adaptive_lr_unit_tb is
end entity adaptive_lr_unit_tb;

architecture testbench of adaptive_lr_unit_tb is

    component adaptive_lr_unit is
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            start         : in  std_logic;
            m_in          : in  signed(15 downto 0);
            v_in          : in  signed(15 downto 0);
            learning_rate : in  signed(15 downto 0);
            epsilon       : in  signed(15 downto 0);
            update_out    : out signed(15 downto 0);
            done          : out std_logic;
            busy          : out std_logic;
            overflow      : out std_logic;
            div_by_zero   : out std_logic
        );
    end component;

    constant CLK_PERIOD : time := 10 ns;
    constant LEARNING_RATE : signed(15 downto 0) := to_signed(33, 16);  -- 0.001 in Q0.15
    constant EPSILON : signed(15 downto 0) := to_signed(82, 16);        -- 0.01 in Q2.13 (matches test expectations)
    constant TOLERANCE : integer := 4;

    signal clk           : std_logic := '0';
    signal rst           : std_logic := '0';
    signal start         : std_logic := '0';
    signal m_in          : signed(15 downto 0) := (others => '0');
    signal v_in          : signed(15 downto 0) := (others => '0');
    signal learning_rate_sig : signed(15 downto 0) := LEARNING_RATE;
    signal epsilon_sig       : signed(15 downto 0) := EPSILON;
    signal update_out    : signed(15 downto 0);
    signal done          : std_logic;
    signal busy          : std_logic;
    signal overflow      : std_logic;
    signal div_by_zero   : std_logic;

    signal test_done : boolean := false;

    function real_to_fixed_q2_13(val : real) return signed is
        constant scale : real := 2.0 ** 13.0;
        variable result : integer;
    begin
        result := integer(round(val * scale));
        if result > 32767 then result := 32767;
        elsif result < -32768 then result := -32768;
        end if;
        return to_signed(result, 16);
    end function;

    function fixed_to_real_q2_13(val : signed) return real is
        constant scale : real := 2.0 ** 13.0;
    begin
        return real(to_integer(val)) / scale;
    end function;

    procedure test_adaptive_lr(
        signal m_in        : out signed(15 downto 0);
        signal v_in        : out signed(15 downto 0);
        signal start       : out std_logic;
        signal clk         : in std_logic;
        signal done        : in std_logic;
        signal update_out  : in signed(15 downto 0);
        constant m_val     : in real;
        constant v_val     : in real;
        constant upd_exp   : in real;
        constant test_id   : in integer
    ) is
        variable err : integer;
        variable upd_exp_fixed : signed(15 downto 0);
    begin
        upd_exp_fixed := real_to_fixed_q2_13(upd_exp);

        m_in <= real_to_fixed_q2_13(m_val);
        v_in <= real_to_fixed_q2_13(v_val);

        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        wait until done = '1' for 1 us;

        assert done = '1'
            report "TEST " & integer'image(test_id) & " TIMEOUT"
            severity failure;

        err := abs(to_integer(update_out) - to_integer(upd_exp_fixed));

        assert err <= TOLERANCE
            report "TEST " & integer'image(test_id) & " FAILED: " &
                   "Expected=" & real'image(fixed_to_real_q2_13(upd_exp_fixed)) &
                   " Got=" & real'image(fixed_to_real_q2_13(update_out)) &
                   " Error=" & integer'image(err) & " LSBs"
            severity failure;

        if err <= TOLERANCE then
            report "  OK TEST " & integer'image(test_id) & " PASSED";
        end if;

        wait for CLK_PERIOD * 2;
    end procedure;

begin

    DUT: adaptive_lr_unit
        port map (
            clk           => clk,
            rst           => rst,
            start         => start,
            m_in          => m_in,
            v_in          => v_in,
            learning_rate => learning_rate_sig,
            epsilon       => epsilon_sig,
            update_out    => update_out,
            done          => done,
            busy          => busy,
            overflow      => overflow,
            div_by_zero   => div_by_zero
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
        report "Starting adaptive_lr_unit testbench";
        report "========================================";

        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Edge case tests
        report "TEST 1: Zero m (update should be zero)";
        test_adaptive_lr(m_in, v_in, start, clk, done, update_out, 0.0, 1.0, 0.0, 1);

        report "TEST 2: Zero v (uses epsilon only)";
        test_adaptive_lr(m_in, v_in, start, clk, done, update_out, 1.0, 0.0, 0.004, 2);

        report "TEST 3: Both zero";
        test_adaptive_lr(m_in, v_in, start, clk, done, update_out, 0.0, 0.0, 0.0, 3);

        report "TEST 4: Typical values";
        test_adaptive_lr(m_in, v_in, start, clk, done, update_out, 0.5, 0.25, 0.001, 4);

        report "TEST 5: Negative m";
        test_adaptive_lr(m_in, v_in, start, clk, done, update_out, -0.5, 0.25, -0.001, 5);

        report "TEST 6: Large v (small update)";
        test_adaptive_lr(m_in, v_in, start, clk, done, update_out, 1.0, 3.0, 0.0006, 6);

        report "========================================";
        report "OK ALL TESTS PASSED";
        report "adaptive_lr_unit testbench complete";
        report "========================================";

        test_done <= true;
        wait;
    end process;

end architecture testbench;
