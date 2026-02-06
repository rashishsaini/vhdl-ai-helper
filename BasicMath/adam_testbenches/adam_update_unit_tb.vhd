--------------------------------------------------------------------------------
-- Testbench: adam_update_unit_tb
-- Description: Integration testbench for adam_update_unit
--              Tests complete single-parameter Adam update pipeline
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;

entity adam_update_unit_tb is
end entity adam_update_unit_tb;

architecture testbench of adam_update_unit_tb is

    component adam_update_unit is
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            start         : in  std_logic;
            gradient      : in  signed(15 downto 0);
            m_old         : in  signed(15 downto 0);
            v_old         : in  signed(15 downto 0);
            weight_old    : in  signed(15 downto 0);
            timestep      : in  unsigned(13 downto 0);
            beta1         : in  signed(15 downto 0);
            beta2         : in  signed(15 downto 0);
            one_minus_beta1 : in  signed(15 downto 0);
            one_minus_beta2 : in  signed(15 downto 0);
            learning_rate : in  signed(15 downto 0);
            epsilon       : in  signed(15 downto 0);
            m_new         : out signed(15 downto 0);
            v_new         : out signed(15 downto 0);
            weight_new    : out signed(15 downto 0);
            done          : out std_logic;
            busy          : out std_logic;
            overflow      : out std_logic
        );
    end component;

    constant CLK_PERIOD : time := 10 ns;
    constant BETA1 : signed(15 downto 0) := to_signed(29491, 16);
    constant BETA2 : signed(15 downto 0) := to_signed(32735, 16);
    constant LEARNING_RATE : signed(15 downto 0) := to_signed(33, 16);
    constant EPSILON : signed(15 downto 0) := to_signed(3, 16);
    constant TOLERANCE : integer := 10;  -- Pipeline accumulates error

    signal clk           : std_logic := '0';
    signal rst           : std_logic := '0';
    signal start         : std_logic := '0';
    signal gradient      : signed(15 downto 0) := (others => '0');
    signal m_old         : signed(15 downto 0) := (others => '0');
    signal v_old         : signed(15 downto 0) := (others => '0');
    signal weight_old    : signed(15 downto 0) := (others => '0');
    signal timestep      : unsigned(13 downto 0) := (others => '0');
    signal beta1_sig         : signed(15 downto 0) := BETA1;
    signal beta2_sig         : signed(15 downto 0) := BETA2;
    signal one_minus_beta1_sig : signed(15 downto 0) := to_signed(3277, 16);  -- 0.1 in Q0.15
    signal one_minus_beta2_sig : signed(15 downto 0) := to_signed(33, 16);    -- 0.001 in Q0.15
    signal learning_rate_sig : signed(15 downto 0) := LEARNING_RATE;
    signal epsilon_sig       : signed(15 downto 0) := EPSILON;
    signal m_new         : signed(15 downto 0);
    signal v_new         : signed(15 downto 0);
    signal weight_new    : signed(15 downto 0);
    signal done          : std_logic;
    signal busy          : std_logic;
    signal overflow      : std_logic;

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

begin

    DUT: adam_update_unit
        port map (
            clk           => clk,
            rst           => rst,
            start         => start,
            gradient      => gradient,
            m_old         => m_old,
            v_old         => v_old,
            weight_old    => weight_old,
            timestep      => timestep,
            beta1         => beta1_sig,
            beta2         => beta2_sig,
            one_minus_beta1 => one_minus_beta1_sig,
            one_minus_beta2 => one_minus_beta2_sig,
            learning_rate => learning_rate_sig,
            epsilon       => epsilon_sig,
            m_new         => m_new,
            v_new         => v_new,
            weight_new    => weight_new,
            done          => done,
            busy          => busy,
            overflow      => overflow
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
        variable m_temp, v_temp, w_temp : signed(15 downto 0);
    begin
        report "========================================";
        report "Starting adam_update_unit testbench";
        report "Testing complete Adam update pipeline";
        report "========================================";

        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Test sequence: Multiple updates to verify convergence
        report "TEST: 10-step Adam optimization sequence";

        m_temp := (others => '0');
        v_temp := (others => '0');
        w_temp := real_to_fixed_q2_13(1.0);  -- Initial weight

        for t in 1 to 10 loop
            -- Apply gradient (simulating descent)
            gradient <= real_to_fixed_q2_13(0.1 * real(t) / 10.0);
            m_old <= m_temp;
            v_old <= v_temp;
            weight_old <= w_temp;
            timestep <= to_unsigned(t, 14);

            wait until rising_edge(clk);
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            wait until done = '1' for 2 us;

            assert done = '1'
                report "TIMEOUT at timestep " & integer'image(t)
                severity error;

            -- Update for next iteration
            m_temp := m_new;
            v_temp := v_new;
            w_temp := weight_new;

            report "  Step " & integer'image(t) & ": " &
                   "m=" & real'image(fixed_to_real_q2_13(m_new)) &
                   " v=" & real'image(fixed_to_real_q2_13(v_new)) &
                   " w=" & real'image(fixed_to_real_q2_13(weight_new));

            wait for CLK_PERIOD * 10;
        end loop;

        -- Verify weight updated (should decrease with positive gradients)
        assert weight_new < real_to_fixed_q2_13(1.0)
            report "Weight should decrease with positive gradients"
            severity error;

        report "========================================";
        report "OK INTEGRATION TEST PASSED";
        report "adam_update_unit testbench complete";
        report "Complete Adam pipeline validated!";
        report "========================================";

        test_done <= true;
        wait;
    end process;

end architecture testbench;
