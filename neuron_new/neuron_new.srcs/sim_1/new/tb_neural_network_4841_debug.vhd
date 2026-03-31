--------------------------------------------------------------------------------
-- Testbench: tb_neural_network_4841_debug
-- Description: Debug version with weight and activation monitoring
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;

use work.iris_dataset_small_pkg.all;

entity tb_neural_network_4841_debug is
end entity;

architecture behavioral of tb_neural_network_4841_debug is

    constant CLK_PERIOD : time := 10 ns;
    constant FWD_TIMEOUT : integer := 500;
    constant BWD_TIMEOUT : integer := 800;
    constant UPD_TIMEOUT : integer := 1500;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';
    signal sim_done : boolean := false;

    -- DUT signals
    signal start_forward  : std_logic := '0';
    signal start_backward : std_logic := '0';
    signal start_update   : std_logic := '0';
    signal input_data     : signed(15 downto 0) := (others => '0');
    signal input_index    : unsigned(1 downto 0) := (others => '0');
    signal input_valid    : std_logic := '0';
    signal target         : signed(15 downto 0) := (others => '0');
    signal learning_rate_sig  : signed(15 downto 0) := (others => '0');
    signal output_data    : signed(15 downto 0);
    signal output_class   : signed(15 downto 0);
    signal output_valid   : std_logic;
    signal fwd_done       : std_logic;
    signal bwd_done       : std_logic;
    signal upd_done       : std_logic;

    -- Helper function
    function to_real(s : signed) return real is
    begin
        return real(to_integer(s)) / 8192.0;
    end function;

begin

    -- Clock generation
    clk_proc : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- DUT
    DUT : entity work.neural_network_4841
        generic map (DATA_WIDTH => 16)
        port map (
            clk            => clk,
            rst            => rst,
            start_forward  => start_forward,
            start_backward => start_backward,
            start_update   => start_update,
            input_data     => input_data,
            input_index    => input_index,
            input_valid    => input_valid,
            target         => target,
            learning_rate  => learning_rate_sig,
            output_data    => output_data,
            output_class   => output_class,
            output_valid   => output_valid,
            fwd_done       => fwd_done,
            bwd_done       => bwd_done,
            upd_done       => upd_done
        );

    -- Main test process
    test_proc : process
        variable timeout_count : integer;

        procedure run_forward_debug(sample_idx : integer) is
        begin
            report "----------------------------------------";
            report "FORWARD PASS - Sample " & integer'image(sample_idx);
            report "  Inputs: [" &
                   integer'image(to_integer(IRIS_FEATURES(sample_idx)(0))) & ", " &
                   integer'image(to_integer(IRIS_FEATURES(sample_idx)(1))) & ", " &
                   integer'image(to_integer(IRIS_FEATURES(sample_idx)(2))) & ", " &
                   integer'image(to_integer(IRIS_FEATURES(sample_idx)(3))) & "]";
            report "  Target: " & integer'image(to_integer(IRIS_LABELS(sample_idx)));

            start_forward <= '1';
            wait until rising_edge(clk);
            start_forward <= '0';

            for f in 0 to 3 loop
                input_index <= to_unsigned(f, 2);
                input_data <= IRIS_FEATURES(sample_idx)(f);
                input_valid <= '1';
                wait until rising_edge(clk);
            end loop;

            input_valid <= '0';

            timeout_count := 0;
            while fwd_done /= '1' and timeout_count < FWD_TIMEOUT loop
                wait until rising_edge(clk);
                timeout_count := timeout_count + 1;
            end loop;

            assert timeout_count < FWD_TIMEOUT
                report "Forward pass timeout!" severity error;

            wait until rising_edge(clk);

            -- Report Layer 1 outputs (access via hierarchical path)
            report "  L1 outputs: [" &
                   integer'image(to_integer(<<signal DUT.l1_a(0) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_a(1) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_a(2) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_a(3) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_a(4) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_a(5) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_a(6) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_a(7) : signed>>) & "]";

            -- Report Layer 2 outputs
            report "  L2 outputs: [" &
                   integer'image(to_integer(<<signal DUT.l2_a(0) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l2_a(1) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l2_a(2) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l2_a(3) : signed>>) & "]";

            -- Report Layer 3 output
            report "  L3 output: " & integer'image(to_integer(output_data)) &
                   " (class=" & integer'image(to_integer(output_class)) & ")";
        end procedure;

        procedure run_backward_debug(sample_idx : integer) is
            variable error_val : signed(15 downto 0);
        begin
            target <= IRIS_LABELS(sample_idx);
            error_val := IRIS_LABELS(sample_idx) - output_class;

            report "BACKWARD PASS";
            report "  Error: " & integer'image(to_integer(error_val));

            start_backward <= '1';
            wait until rising_edge(clk);
            start_backward <= '0';

            timeout_count := 0;
            while bwd_done /= '1' and timeout_count < BWD_TIMEOUT loop
                wait until rising_edge(clk);
                timeout_count := timeout_count + 1;
            end loop;

            assert timeout_count < BWD_TIMEOUT
                report "Backward pass timeout!" severity error;

            wait until rising_edge(clk);

            -- Report deltas
            report "  L3 delta: " & integer'image(to_integer(<<signal DUT.l3_delta : signed>>));
            report "  L2 deltas: [" &
                   integer'image(to_integer(<<signal DUT.l2_delta(0) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l2_delta(1) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l2_delta(2) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l2_delta(3) : signed>>) & "]";
            report "  L1 deltas: [" &
                   integer'image(to_integer(<<signal DUT.l1_delta(0) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_delta(1) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_delta(2) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_delta(3) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_delta(4) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_delta(5) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_delta(6) : signed>>) & ", " &
                   integer'image(to_integer(<<signal DUT.l1_delta(7) : signed>>) & "]";
        end procedure;

        procedure run_update_debug is
        begin
            report "UPDATE PASS";

            start_update <= '1';
            wait until rising_edge(clk);
            start_update <= '0';

            timeout_count := 0;
            while upd_done /= '1' and timeout_count < UPD_TIMEOUT loop
                wait until rising_edge(clk);
                timeout_count := timeout_count + 1;
            end loop;

            assert timeout_count < UPD_TIMEOUT
                report "Update pass timeout!" severity error;

            wait until rising_edge(clk);
            report "  Update complete";
        end procedure;

        procedure report_sample_weights is
        begin
            report "========================================";
            report "WEIGHT SAMPLES";
            report "========================================";
            report "L1 Neuron 0, Weight 0: " &
                   integer'image(to_integer(<<signal DUT.l1_neurons(0).neuron_inst.weights(0) : signed>>));
            report "L1 Neuron 0, Bias: " &
                   integer'image(to_integer(<<signal DUT.l1_neurons(0).neuron_inst.bias : signed>>));
            report "L2 Neuron 0, Weight 0: " &
                   integer'image(to_integer(<<signal DUT.l2_neurons(0).neuron_inst.weights(0) : signed>>));
            report "L2 Neuron 0, Bias: " &
                   integer'image(to_integer(<<signal DUT.l2_neurons(0).neuron_inst.bias : signed>>));
            report "L3 Weight 0: " &
                   integer'image(to_integer(<<signal DUT.l3_neuron_inst.weights(0) : signed>>));
            report "L3 Bias: " &
                   integer'image(to_integer(<<signal DUT.l3_neuron_inst.bias : signed>>));
            report "========================================";
        end procedure;

    begin
        report "========================================";
        report "  DEBUG TESTBENCH - 4-8-4-1 Network";
        report "  Testing First 3 Samples Only";
        report "========================================";

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 10;
        rst <= '0';
        wait for CLK_PERIOD * 5;

        -- Learning rate: 0.01 = 82 in Q2.13
        learning_rate_sig <= to_signed(82, 16);

        report "========================================";
        report "INITIAL WEIGHTS (before training)";
        report_sample_weights;

        report "========================================";
        report "EPOCH 1 - Sample 0";
        report "========================================";
        run_forward_debug(0);
        run_backward_debug(0);
        run_update_debug;

        report "========================================";
        report "WEIGHTS AFTER 1 SAMPLE";
        report_sample_weights;

        report "========================================";
        report "EPOCH 1 - Sample 1";
        report "========================================";
        run_forward_debug(1);
        run_backward_debug(1);
        run_update_debug;

        report "========================================";
        report "EPOCH 1 - Sample 2";
        report "========================================";
        run_forward_debug(2);
        run_backward_debug(2);
        run_update_debug;

        report "========================================";
        report "WEIGHTS AFTER 3 SAMPLES";
        report_sample_weights;

        report "========================================";
        report "TESTING SAMPLE 0 AGAIN (after 3 samples training)";
        report "========================================";
        run_forward_debug(0);

        report "========================================";
        report "DEBUG TEST COMPLETE";
        report "========================================";

        sim_done <= true;
        wait;
    end process;

end architecture;
