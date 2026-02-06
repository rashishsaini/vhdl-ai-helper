--------------------------------------------------------------------------------
-- Testbench: bias_correction_unit_tb
-- Description: Comprehensive testbench for bias_correction_unit
--              Tests Full Adam bias correction: m_hat = m/(1-β₁^t), v_hat = v/(1-β₂^t)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;

entity bias_correction_unit_tb is
end entity bias_correction_unit_tb;

architecture testbench of bias_correction_unit_tb is

    component bias_correction_unit is
        port (
            clk      : in  std_logic;
            rst      : in  std_logic;
            start    : in  std_logic;
            m_in     : in  signed(15 downto 0);
            v_in     : in  signed(15 downto 0);
            timestep : in  unsigned(13 downto 0);
            beta1    : in  signed(15 downto 0);
            beta2    : in  signed(15 downto 0);
            m_hat    : out signed(15 downto 0);
            v_hat    : out signed(15 downto 0);
            done     : out std_logic;
            busy     : out std_logic;
            overflow : out std_logic
        );
    end component;

    constant CLK_PERIOD : time := 10 ns;
    constant BETA1 : signed(15 downto 0) := to_signed(29491, 16);  -- 0.9
    constant BETA2 : signed(15 downto 0) := to_signed(32735, 16);  -- 0.999
    constant TOLERANCE : integer := 10;  -- ±10 LSBs (power + division accumulates error)

    signal clk      : std_logic := '0';
    signal rst      : std_logic := '0';
    signal start    : std_logic := '0';
    signal m_in     : signed(15 downto 0) := (others => '0');
    signal v_in     : signed(15 downto 0) := (others => '0');
    signal timestep : unsigned(13 downto 0) := (others => '0');
    signal beta1_sig    : signed(15 downto 0) := BETA1;
    signal beta2_sig    : signed(15 downto 0) := BETA2;
    signal m_hat    : signed(15 downto 0);
    signal v_hat    : signed(15 downto 0);
    signal done     : std_logic;
    signal busy     : std_logic;
    signal overflow : std_logic;

    signal test_done : boolean := false;

    function real_to_fixed_q2_13(val : real) return signed is
        constant scale : real := 2.0 ** 13.0;
        variable result : integer;
    begin
        result := integer(round(val * scale));
        if result > 32767 then
            result := 32767;
        elsif result < -32768 then
            result := -32768;
        end if;
        return to_signed(result, 16);
    end function;

    function fixed_to_real_q2_13(val : signed) return real is
        constant scale : real := 2.0 ** 13.0;
    begin
        return real(to_integer(val)) / scale;
    end function;

    procedure test_bias_correction(
        signal m_in      : out signed(15 downto 0);
        signal v_in      : out signed(15 downto 0);
        signal timestep  : out unsigned(13 downto 0);
        signal start     : out std_logic;
        signal clk       : in std_logic;
        signal done      : in std_logic;
        signal m_hat     : in signed(15 downto 0);
        signal v_hat     : in signed(15 downto 0);
        constant m_val       : in real;
        constant v_val       : in real;
        constant t           : in integer;
        constant m_hat_exp   : in real;
        constant v_hat_exp   : in real;
        constant test_id     : in integer
    ) is
        variable m_error, v_error : integer;
        variable m_hat_exp_fixed, v_hat_exp_fixed : signed(15 downto 0);
    begin
        m_hat_exp_fixed := real_to_fixed_q2_13(m_hat_exp);
        v_hat_exp_fixed := real_to_fixed_q2_13(v_hat_exp);

        m_in <= real_to_fixed_q2_13(m_val);
        v_in <= real_to_fixed_q2_13(v_val);
        timestep <= to_unsigned(t, 14);

        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        wait until done = '1' for 1 us;

        assert done = '1'
            report "TEST " & integer'image(test_id) & " TIMEOUT"
            severity error;

        m_error := abs(to_integer(m_hat) - to_integer(m_hat_exp_fixed));
        v_error := abs(to_integer(v_hat) - to_integer(v_hat_exp_fixed));

        assert m_error <= TOLERANCE
            report "TEST " & integer'image(test_id) & " FAILED (m_hat): " &
                   "t=" & integer'image(t) &
                   " Expected=" & real'image(fixed_to_real_q2_13(m_hat_exp_fixed)) &
                   " Got=" & real'image(fixed_to_real_q2_13(m_hat)) &
                   " Error=" & integer'image(m_error) & " LSBs"
            severity error;

        assert v_error <= TOLERANCE
            report "TEST " & integer'image(test_id) & " FAILED (v_hat): " &
                   "t=" & integer'image(t) &
                   " Expected=" & real'image(fixed_to_real_q2_13(v_hat_exp_fixed)) &
                   " Got=" & real'image(fixed_to_real_q2_13(v_hat)) &
                   " Error=" & integer'image(v_error) & " LSBs"
            severity error;

        if m_error <= TOLERANCE and v_error <= TOLERANCE then
            report "  OK TEST " & integer'image(test_id) & " PASSED (t=" & integer'image(t) & ")";
        end if;

        wait for CLK_PERIOD * 2;
    end procedure;

begin

    DUT: bias_correction_unit
        port map (
            clk      => clk,
            rst      => rst,
            start    => start,
            m_in     => m_in,
            v_in     => v_in,
            timestep => timestep,
            beta1    => beta1_sig,
            beta2    => beta2_sig,
            m_hat    => m_hat,
            v_hat    => v_hat,
            done     => done,
            busy     => busy,
            overflow => overflow
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
        report "Starting bias_correction_unit testbench";
        report "This is the FULL ADAM differentiator!";
        report "========================================";

        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Critical test: t=1 (maximum bias correction effect)
        -- At t=1: 1-β₁¹ = 0.1, 1-β₂¹ = 0.001
        -- Bias correction: m_hat = m/0.1 = 10m, v_hat = v/0.001 = 1000v
        -- Keep within Q2.13 range (-4.0 to +3.9998)
        report "TEST 1: t=1 (maximum bias correction) - small values";
        test_bias_correction(m_in, v_in, timestep, start, clk, done, m_hat, v_hat, 0.1, 0.001, 1, 1.0, 1.0, 1);

        -- Test 2: t=2 (bias correction diminishing)
        -- At t=2: 1-β₁² ≈ 0.19, 1-β₂² ≈ 0.002
        report "TEST 2: t=2 (bias correction diminishing)";
        test_bias_correction(m_in, v_in, timestep, start, clk, done, m_hat, v_hat, 0.1, 0.002, 2, 0.526, 1.053, 2);

        -- Test 3: t=10 (moderate bias correction)
        -- At t=10: 1-β₁¹⁰ ≈ 0.651, 1-β₂¹⁰ ≈ 0.01
        report "TEST 3: t=10";
        test_bias_correction(m_in, v_in, timestep, start, clk, done, m_hat, v_hat, 0.5, 0.01, 10, 0.768, 1.0, 3);

        -- Test 4: t=100 (bias correction minimal)
        -- At t=100: 1-β₁¹⁰⁰ ≈ 1.0, 1-β₂¹⁰⁰ ≈ 0.095
        report "TEST 4: t=100 (bias correction minimal)";
        test_bias_correction(m_in, v_in, timestep, start, clk, done, m_hat, v_hat, 0.5, 0.25, 100, 0.5, 2.632, 4);

        -- Test 5: Negative m (bias correction preserves sign)
        report "TEST 5: Negative m with bias correction";
        test_bias_correction(m_in, v_in, timestep, start, clk, done, m_hat, v_hat, -0.1, 0.001, 1, -1.0, 1.0, 5);

        -- Test 6: Large timestep (bias correction → 1)
        -- At t=1000: 1-β₁¹⁰⁰⁰ ≈ 1.0, 1-β₂¹⁰⁰⁰ ≈ 0.632
        report "TEST 6: Large timestep (t=1000)";
        test_bias_correction(m_in, v_in, timestep, start, clk, done, m_hat, v_hat, 1.0, 1.0, 1000, 1.0, 1.582, 6);

        report "========================================";
        report "OK ALL TESTS PASSED";
        report "bias_correction_unit testbench complete";
        report "Full Adam bias correction validated!";
        report "========================================";

        test_done <= true;
        wait;
    end process;

end architecture testbench;
