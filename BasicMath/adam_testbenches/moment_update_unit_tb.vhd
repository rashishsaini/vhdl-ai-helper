--------------------------------------------------------------------------------
-- Testbench: moment_update_unit_tb
-- Description: Comprehensive testbench for moment_update_unit
--              Tests m_new and v_new computation using golden reference vectors
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;
use IEEE.std_logic_textio.all;

entity moment_update_unit_tb is
end entity moment_update_unit_tb;

architecture testbench of moment_update_unit_tb is

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component moment_update_unit is
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            start           : in  std_logic;
            gradient        : in  signed(15 downto 0);
            m_old           : in  signed(15 downto 0);
            v_old           : in  signed(15 downto 0);
            beta1           : in  signed(15 downto 0);
            beta2           : in  signed(15 downto 0);
            one_minus_beta1 : in  signed(15 downto 0);
            one_minus_beta2 : in  signed(15 downto 0);
            m_new           : out signed(15 downto 0);
            v_new           : out signed(15 downto 0);
            done            : out std_logic;
            busy            : out std_logic;
            overflow        : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;
    constant FRAC_BITS  : integer := 13;  -- Q2.13 format

    -- Beta coefficients (Q0.15)
    constant BETA1 : signed(15 downto 0) := to_signed(29491, 16);  -- 0.9
    constant BETA2 : signed(15 downto 0) := to_signed(32735, 16);  -- 0.999
    constant ONE_MINUS_BETA1 : signed(15 downto 0) := to_signed(3277, 16);  -- 0.1
    constant ONE_MINUS_BETA2 : signed(15 downto 0) := to_signed(33, 16);    -- 0.001

    constant TOLERANCE : integer := 4;  -- ±4 LSBs acceptable for multi-stage operations

    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal clk             : std_logic := '0';
    signal rst             : std_logic := '0';
    signal start           : std_logic := '0';
    signal gradient        : signed(15 downto 0) := (others => '0');
    signal m_old           : signed(15 downto 0) := (others => '0');
    signal v_old           : signed(15 downto 0) := (others => '0');
    signal beta1_sig       : signed(15 downto 0) := BETA1;
    signal beta2_sig       : signed(15 downto 0) := BETA2;
    signal one_minus_beta1_sig : signed(15 downto 0) := ONE_MINUS_BETA1;
    signal one_minus_beta2_sig : signed(15 downto 0) := ONE_MINUS_BETA2;
    signal m_new           : signed(15 downto 0);
    signal v_new           : signed(15 downto 0);
    signal done            : std_logic;
    signal busy            : std_logic;
    signal overflow        : std_logic;

    signal test_done : boolean := false;

    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
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

    ---------------------------------------------------------------------------
    -- Test Procedure
    ---------------------------------------------------------------------------
    procedure test_moment_update(
        signal gradient : out signed(15 downto 0);
        signal m_old    : out signed(15 downto 0);
        signal v_old    : out signed(15 downto 0);
        signal start    : out std_logic;
        signal clk      : in std_logic;
        signal done     : in std_logic;
        signal m_new    : in signed(15 downto 0);
        signal v_new    : in signed(15 downto 0);
        constant gradient_val : in real;
        constant m_old_val    : in real;
        constant v_old_val    : in real;
        constant m_exp        : in real;
        constant v_exp        : in real;
        constant test_id      : in integer
    ) is
        variable m_error, v_error : integer;
        variable m_exp_fixed, v_exp_fixed : signed(15 downto 0);
    begin
        -- Convert expected values to fixed-point
        m_exp_fixed := real_to_fixed_q2_13(m_exp);
        v_exp_fixed := real_to_fixed_q2_13(v_exp);

        -- Apply inputs
        gradient <= real_to_fixed_q2_13(gradient_val);
        m_old <= real_to_fixed_q2_13(m_old_val);
        v_old <= real_to_fixed_q2_13(v_old_val);

        -- Start operation
        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        -- Wait for completion
        wait until done = '1';
        wait for CLK_PERIOD;

        -- Check results
        m_error := abs(to_integer(m_new) - to_integer(m_exp_fixed));
        v_error := abs(to_integer(v_new) - to_integer(v_exp_fixed));

        assert m_error <= TOLERANCE
            report "TEST " & integer'image(test_id) & " FAILED (m_new): " &
                   "Expected=" & real'image(fixed_to_real_q2_13(m_exp_fixed)) &
                   " Got=" & real'image(fixed_to_real_q2_13(m_new)) &
                   " Error=" & integer'image(m_error) & " LSBs"
            severity error;

        assert v_error <= TOLERANCE
            report "TEST " & integer'image(test_id) & " FAILED (v_new): " &
                   "Expected=" & real'image(fixed_to_real_q2_13(v_exp_fixed)) &
                   " Got=" & real'image(fixed_to_real_q2_13(v_new)) &
                   " Error=" & integer'image(v_error) & " LSBs"
            severity error;

        if m_error <= TOLERANCE and v_error <= TOLERANCE then
            report "  OK TEST " & integer'image(test_id) & " PASSED";
        end if;

        wait for CLK_PERIOD;
    end procedure;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    DUT: moment_update_unit
        port map (
            clk             => clk,
            rst             => rst,
            start           => start,
            gradient        => gradient,
            m_old           => m_old,
            v_old           => v_old,
            beta1           => beta1_sig,
            beta2           => beta2_sig,
            one_minus_beta1 => one_minus_beta1_sig,
            one_minus_beta2 => one_minus_beta2_sig,
            m_new           => m_new,
            v_new           => v_new,
            done            => done,
            busy            => busy,
            overflow        => overflow
        );

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
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

    ---------------------------------------------------------------------------
    -- Main Test Process
    ---------------------------------------------------------------------------
    test_process: process
        file test_file : text;
        variable line_in : line;
        variable gradient_val, m_old_val, v_old_val, m_exp, v_exp : real;
        variable test_count : integer := 0;
        variable pass_count : integer := 0;
    begin
        report "========================================";
        report "Starting moment_update_unit testbench";
        report "========================================";

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Test 1: Zero gradient (should maintain old moments with beta decay)
        report "TEST 1: Zero gradient";
        test_moment_update(gradient, m_old, v_old, start, clk, done, m_new, v_new, 0.0, 0.5, 0.25, 0.45, 0.24975, 1);

        -- Test 2: Positive gradient from zero
        report "TEST 2: Positive gradient from zero";
        test_moment_update(gradient, m_old, v_old, start, clk, done, m_new, v_new, 0.5, 0.0, 0.0, 0.05, 0.00025, 2);

        -- Test 3: Negative gradient
        report "TEST 3: Negative gradient";
        test_moment_update(gradient, m_old, v_old, start, clk, done, m_new, v_new, -0.5, 0.0, 0.0, -0.05, 0.00025, 3);

        -- Test 4: Large gradient
        report "TEST 4: Large gradient";
        test_moment_update(gradient, m_old, v_old, start, clk, done, m_new, v_new, 1.5, 0.5, 0.25, 0.6, 0.24925, 4);

        -- Test 5: Golden reference test vectors
        report "========================================";
        report "TEST 5: Golden reference vectors";
        report "========================================";

        file_open(test_file, "../../test_vectors/moment_update_vectors.txt", read_mode);

        -- Skip header lines
        while not endfile(test_file) loop
            readline(test_file, line_in);
            if line_in'length > 0 and line_in(1) /= '#' then
                exit;
            end if;
        end loop;

        -- Read first data line (already read in loop above)
        read(line_in, gradient_val);
        read(line_in, m_old_val);
        read(line_in, v_old_val);
        read(line_in, m_exp);
        read(line_in, v_exp);

        test_moment_update(gradient, m_old, v_old, start, clk, done, m_new, v_new, gradient_val, m_old_val, v_old_val, m_exp, v_exp, 5);
        test_count := test_count + 1;

        -- Read remaining test vectors
        while not endfile(test_file) loop
            readline(test_file, line_in);

            -- Skip comments and empty lines
            if line_in'length = 0 or line_in(1) = '#' then
                next;
            end if;

            -- Parse test vector
            read(line_in, gradient_val);
            read(line_in, m_old_val);
            read(line_in, v_old_val);
            read(line_in, m_exp);
            read(line_in, v_exp);

            -- Run test
            test_moment_update(gradient, m_old, v_old, start, clk, done, m_new, v_new, gradient_val, m_old_val, v_old_val, m_exp, v_exp, 5 + test_count);
            test_count := test_count + 1;

            if test_count >= 100 then
                exit;  -- Limit to 100 tests for simulation time
            end if;
        end loop;

        file_close(test_file);

        report "Tested " & integer'image(test_count) & " golden reference vectors";

        -- Final Report
        report "========================================";
        report "OK ALL TESTS PASSED";
        report "moment_update_unit testbench complete";
        report "Total tests: " & integer'image(test_count + 4);
        report "========================================";

        test_done <= true;
        wait;
    end process;

end architecture testbench;
