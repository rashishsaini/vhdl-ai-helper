--------------------------------------------------------------------------------
-- Simple testbench to verify single neuron learns a simple pattern
-- Test: Can a single neuron learn to output 1.0 for input [1,1] and 0.0 for [0,0]?
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity tb_single_neuron_simple is
end entity;

architecture behavioral of tb_single_neuron_simple is

    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : integer := 16;
    constant NUM_INPUTS : integer := 2;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';
    signal sim_done : boolean := false;

    -- DUT signals
    signal fwd_start : std_logic := '0';
    signal input_data : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal input_index : unsigned(7 downto 0) := (others => '0');
    signal input_valid : std_logic := '0';
    signal fwd_done : std_logic;
    signal a_out : signed(DATA_WIDTH-1 downto 0);

    signal bwd_start : std_logic := '0';
    signal error_in : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal error_valid : std_logic := '0';
    signal bwd_done : std_logic;
    signal delta_out : signed(DATA_WIDTH-1 downto 0);

    signal upd_start : std_logic := '0';
    signal learning_rate : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal upd_done : std_logic;

    -- Weight read interface (unused)
    signal weight_prop_idx : unsigned(7 downto 0) := (others => '0');
    signal weight_for_prop : signed(DATA_WIDTH-1 downto 0);

    function to_real(s : signed) return real is
    begin
        return real(to_integer(s)) / 8192.0;
    end function;

    function to_fixed(r : real) return signed is
    begin
        return to_signed(integer(r * 8192.0), DATA_WIDTH);
    end function;

begin

    clk_proc : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    DUT : entity work.single_neuron
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            NUM_INPUTS => NUM_INPUTS,
            NEURON_ID => 99,
            USE_LINEAR_ACT => true  -- Use linear activation for simplicity
        )
        port map (
            clk => clk,
            rst => rst,
            fwd_start => fwd_start,
            input_data => input_data,
            input_index => input_index,
            input_valid => input_valid,
            fwd_done => fwd_done,
            a_out => a_out,
            bwd_start => bwd_start,
            error_in => error_in,
            error_valid => error_valid,
            bwd_done => bwd_done,
            delta_out => delta_out,
            upd_start => upd_start,
            learning_rate => learning_rate,
            upd_done => upd_done,
            weight_prop_idx => weight_prop_idx,
            weight_for_prop => weight_for_prop
        );

    test_proc : process
        variable output_val : real;
        variable error_val : real;

        procedure run_forward(inp0, inp1 : real) is
        begin
            fwd_start <= '1';
            wait until rising_edge(clk);
            fwd_start <= '0';

            -- Feed input 0
            input_index <= to_unsigned(0, 8);
            input_data <= to_fixed(inp0);
            input_valid <= '1';
            wait until rising_edge(clk);

            -- Feed input 1
            input_index <= to_unsigned(1, 8);
            input_data <= to_fixed(inp1);
            input_valid <= '1';
            wait until rising_edge(clk);

            input_valid <= '0';

            -- Wait for forward to complete
            wait until fwd_done = '1' for 100 ns;
            wait until rising_edge(clk);
        end procedure;

        procedure run_backward(target : real) is
        begin
            error_val := target - to_real(a_out);
            error_in <= to_fixed(error_val);
            error_valid <= '1';
            bwd_start <= '1';
            wait until rising_edge(clk);
            bwd_start <= '0';
            error_valid <= '0';

            wait until bwd_done = '1' for 100 ns;
            wait until rising_edge(clk);
        end procedure;

        procedure run_update is
        begin
            upd_start <= '1';
            wait until rising_edge(clk);
            upd_start <= '0';

            wait until upd_done = '1' for 100 ns;
            wait until rising_edge(clk);
        end procedure;

    begin
        report "========================================";
        report "  Single Neuron Learning Test";
        report "  Goal: Learn y = x0 (identity for first input)";
        report "========================================";

        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- Learning rate: 0.1 = 819 in Q2.13
        learning_rate <= to_signed(819, DATA_WIDTH);

        -- Training: Learn to output the first input value
        for epoch in 1 to 10 loop
            -- Sample 1: [1, 0] -> target 1.0
            run_forward(1.0, 0.0);
            output_val := to_real(a_out);
            run_backward(1.0);
            run_update;

            -- Sample 2: [0, 1] -> target 0.0
            run_forward(0.0, 1.0);
            output_val := to_real(a_out);
            run_backward(0.0);
            run_update;

            if epoch mod 2 = 0 then
                -- Test sample 1
                run_forward(1.0, 0.0);
                report "Epoch " & integer'image(epoch) &
                       " Sample[1,0]: output=" & real'image(to_real(a_out)) &
                       " (target=1.0)";

                -- Test sample 2
                run_forward(0.0, 1.0);
                report "Epoch " & integer'image(epoch) &
                       " Sample[0,1]: output=" & real'image(to_real(a_out)) &
                       " (target=0.0)";
            end if;
        end loop;

        report "========================================";
        report "  Final Test";
        report "========================================";

        run_forward(1.0, 0.0);
        report "Input [1,0]: output=" & real'image(to_real(a_out)) & " (target=1.0)";

        run_forward(0.0, 1.0);
        report "Input [0,1]: output=" & real'image(to_real(a_out)) & " (target=0.0)";

        sim_done <= true;
        wait;
    end process;

end architecture;
