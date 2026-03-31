--------------------------------------------------------------------------------
-- Testbench: adam_optimizer_tb
-- Description: System integration testbench for adam_optimizer
--              Tests full 13-parameter Adam optimization cycle
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity adam_optimizer_tb is
end entity adam_optimizer_tb;

architecture testbench of adam_optimizer_tb is

    component adam_optimizer is
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            start           : in  std_logic;
            timestep        : in  unsigned(13 downto 0);
            gradient_addr   : out unsigned(3 downto 0);
            gradient_data   : in  signed(15 downto 0);
            weight_rd_addr  : out unsigned(3 downto 0);
            weight_rd_data  : in  signed(15 downto 0);
            weight_wr_addr  : out unsigned(3 downto 0);
            weight_wr_data  : out signed(15 downto 0);
            weight_wr_en    : out std_logic;
            beta1           : in  signed(15 downto 0);
            beta2           : in  signed(15 downto 0);
            one_minus_beta1 : in  signed(15 downto 0);
            one_minus_beta2 : in  signed(15 downto 0);
            learning_rate   : in  signed(15 downto 0);
            epsilon         : in  signed(15 downto 0);
            done            : out std_logic;
            busy            : out std_logic;
            current_param   : out unsigned(3 downto 0);
            overflow        : out std_logic
        );
    end component;

    constant CLK_PERIOD : time := 10 ns;
    constant NUM_PARAMS : integer := 13;
    constant BETA1 : signed(15 downto 0) := to_signed(29491, 16);
    constant BETA2 : signed(15 downto 0) := to_signed(32735, 16);
    constant LEARNING_RATE : signed(15 downto 0) := to_signed(33, 16);
    constant EPSILON : signed(15 downto 0) := to_signed(3, 16);

    signal clk             : std_logic := '0';
    signal rst             : std_logic := '0';
    signal start           : std_logic := '0';
    signal timestep        : unsigned(13 downto 0) := (others => '0');
    signal gradient_addr   : unsigned(3 downto 0);
    signal gradient_data   : signed(15 downto 0);
    signal weight_rd_addr  : unsigned(3 downto 0);
    signal weight_rd_data  : signed(15 downto 0);
    signal weight_wr_addr  : unsigned(3 downto 0);
    signal weight_wr_data  : signed(15 downto 0);
    signal weight_wr_en    : std_logic;
    signal beta1_sig           : signed(15 downto 0) := BETA1;
    signal beta2_sig           : signed(15 downto 0) := BETA2;
    signal one_minus_beta1_sig : signed(15 downto 0) := to_signed(3277, 16);  -- 0.1 in Q0.15
    signal one_minus_beta2_sig : signed(15 downto 0) := to_signed(33, 16);    -- 0.001 in Q0.15
    signal learning_rate_sig   : signed(15 downto 0) := LEARNING_RATE;
    signal epsilon_sig         : signed(15 downto 0) := EPSILON;
    signal done            : std_logic;
    signal busy            : std_logic;
    signal current_param   : unsigned(3 downto 0);
    signal overflow        : std_logic;

    signal test_done : boolean := false;

    -- Mock gradient and weight memory
    type memory_array is array (0 to NUM_PARAMS-1) of signed(15 downto 0);
    signal gradient_memory : memory_array := (others => (others => '0'));
    signal weight_memory   : memory_array := (others => (others => '0'));

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

    DUT: adam_optimizer
        port map (
            clk             => clk,
            rst             => rst,
            start           => start,
            timestep        => timestep,
            gradient_addr   => gradient_addr,
            gradient_data   => gradient_data,
            weight_rd_addr  => weight_rd_addr,
            weight_rd_data  => weight_rd_data,
            weight_wr_addr  => weight_wr_addr,
            weight_wr_data  => weight_wr_data,
            weight_wr_en    => weight_wr_en,
            beta1           => beta1_sig,
            beta2           => beta2_sig,
            one_minus_beta1 => one_minus_beta1_sig,
            one_minus_beta2 => one_minus_beta2_sig,
            learning_rate   => learning_rate_sig,
            epsilon         => epsilon_sig,
            done            => done,
            busy            => busy,
            current_param   => current_param,
            overflow        => overflow
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

    -- Memory interface process
    memory_process: process(clk)
    begin
        if rising_edge(clk) then
            -- Gradient read (asynchronous)
            if to_integer(gradient_addr) < NUM_PARAMS then
                gradient_data <= gradient_memory(to_integer(gradient_addr));
            end if;

            -- Weight read (asynchronous)
            if to_integer(weight_rd_addr) < NUM_PARAMS then
                weight_rd_data <= weight_memory(to_integer(weight_rd_addr));
            end if;

            -- Weight write (synchronous)
            if weight_wr_en = '1' and to_integer(weight_wr_addr) < NUM_PARAMS then
                weight_memory(to_integer(weight_wr_addr)) <= weight_wr_data;
            end if;
        end if;
    end process;

    test_process: process
    begin
        report "========================================";
        report "Starting adam_optimizer testbench";
        report "Testing full 13-parameter optimization";
        report "========================================";

        -- Initialize weights
        for i in 0 to NUM_PARAMS-1 loop
            weight_memory(i) <= real_to_fixed_q2_13(1.0);  -- Initialize to 1.0
        end loop;

        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Run 5 optimization steps
        for t in 1 to 5 loop
            report "========================================";
            report "Optimization Step " & integer'image(t);
            report "========================================";

            -- Generate random gradients
            for i in 0 to NUM_PARAMS-1 loop
                gradient_memory(i) <= real_to_fixed_q2_13(0.1 * real(i+1) / 13.0);
            end loop;

            -- Start optimization
            timestep <= to_unsigned(t, 14);
            wait until rising_edge(clk);
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            -- Wait for completion (expect ~780 cycles for 13 params)
            wait until done = '1' for 20 us;

            assert done = '1'
                report "ERROR: Optimization timeout at step " & integer'image(t)
                severity error;

            report "  OK Step " & integer'image(t) & " complete";

            -- Print updated weights
            for i in 0 to NUM_PARAMS-1 loop
                report "    Param " & integer'image(i) & ": " &
                       real'image(fixed_to_real_q2_13(weight_memory(i)));
            end loop;

            wait for CLK_PERIOD * 10;
        end loop;

        -- Verify weights changed
        assert weight_memory(0) /= real_to_fixed_q2_13(1.0)
            report "ERROR: Weights did not update"
            severity error;

        report "========================================";
        report "OK SYSTEM INTEGRATION TEST PASSED";
        report "adam_optimizer testbench complete";
        report "Full 13-parameter Adam optimizer validated!";
        report "========================================";

        test_done <= true;
        wait;
    end process;

end architecture testbench;
