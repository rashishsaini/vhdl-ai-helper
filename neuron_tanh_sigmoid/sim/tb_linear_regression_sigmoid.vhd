--------------------------------------------------------------------------------
-- Testbench: tb_neural_network_421_linear_regression
-- Description: Linear regression test for 4-2-1 neural network
--              Tests learning of y = x1 + x2 + x3 + x4 (sum of inputs)
-- Author: VHDL AI Helper Project
-- Test: Single regression test with 12 samples
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;

library work;
use work.neural_network_tb_pkg.all;

entity tb_neural_network_421_linear_regression_sigmoid is
end entity tb_neural_network_421_linear_regression_sigmoid;

architecture behavioral of tb_neural_network_421_linear_regression_sigmoid is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant DATA_WIDTH : integer := 16;

    ---------------------------------------------------------------------------
    -- Linear Regression Dataset: y = 0.1*(x1 + x2 + x3 + x4) -- SCALED DOWN
    ---------------------------------------------------------------------------
    constant LINEAR_DATASET : test_dataset_t(0 to 11) := (
        0  => ( 0.0,    0.0,    0.0,    0.0,    0.0),   -- All zeros
        1  => ( 0.1,    0.0,    0.0,    0.0,    0.1),   -- Single input
        2  => ( 0.05,   0.05,   0.0,    0.0,    0.1),   -- Two inputs
        3  => ( 0.05,   0.05,   0.05,   0.05,   0.2),   -- All equal
        4  => ( 0.1,    0.1,    0.1,    0.1,    0.4),   -- All ones
        5  => (-0.05,  -0.05,  -0.05,  -0.05,  -0.2),   -- All negative
        6  => ( 0.025,  0.05,   0.075,  0.1,    0.25),  -- Increasing
        7  => (-0.1,    0.05,   0.05,   0.1,    0.1),   -- Mixed signs
        8  => ( 0.075, -0.025,  0.05,   0.0,    0.1),   -- Mixed with zero
        9  => (-0.05,  -0.05,   0.1,    0.1,    0.1),   -- Balanced
        10 => ( 0.0,    0.0,    0.15,   0.15,   0.3),   -- Sparse
        11 => (-0.1,   -0.05,   0.05,   0.1,    0.0)    -- Sums to zero
    );

    ---------------------------------------------------------------------------
    -- Clock and Reset
    ---------------------------------------------------------------------------
    signal clk : std_logic := '0';
    signal rst : std_logic := '0';
    signal sim_done : boolean := false;

    ---------------------------------------------------------------------------
    -- DUT Signals - Control
    ---------------------------------------------------------------------------
    signal start_forward  : std_logic := '0';
    signal start_backward : std_logic := '0';
    signal start_update   : std_logic := '0';

    ---------------------------------------------------------------------------
    -- DUT Signals - Inputs
    ---------------------------------------------------------------------------
    signal input_data  : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal input_index : unsigned(1 downto 0) := (others => '0');
    signal input_valid : std_logic := '0';

    ---------------------------------------------------------------------------
    -- DUT Signals - Training
    ---------------------------------------------------------------------------
    signal target        : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal learning_rate : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- DUT Signals - Outputs
    ---------------------------------------------------------------------------
    signal output_data  : signed(DATA_WIDTH-1 downto 0);
    signal output_valid : std_logic;

    ---------------------------------------------------------------------------
    -- DUT Signals - Status
    ---------------------------------------------------------------------------
    signal fwd_done : std_logic;
    signal bwd_done : std_logic;
    signal upd_done : std_logic;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    DUT : entity work.neural_network_421_sigmoid
        generic map (
            DATA_WIDTH => DATA_WIDTH
        )
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
            learning_rate  => learning_rate,
            output_data    => output_data,
            output_valid   => output_valid,
            fwd_done       => fwd_done,
            bwd_done       => bwd_done,
            upd_done       => upd_done
        );

    ---------------------------------------------------------------------------
    -- Clock Generation (100 MHz, 10 ns period)
    ---------------------------------------------------------------------------
    clk_proc : process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_proc;

    ---------------------------------------------------------------------------
    -- Test Process
    ---------------------------------------------------------------------------
    test_proc : process
        variable test_pass : boolean;
        variable outputs : test_dataset_t(0 to 11);
        variable mse : real;
        variable converged : boolean;
        variable iter : integer;

        ---------------------------------------------------------------------------
        -- Helper Procedures
        ---------------------------------------------------------------------------

        -- Network-level forward pass
        procedure run_network_forward(
            in0, in1, in2, in3 : real
        ) is
        begin
            start_forward <= '1';
            wait until rising_edge(clk);
            start_forward <= '0';

            input_index <= to_unsigned(0, 2);
            input_data <= to_fixed(in0);
            input_valid <= '1';
            wait until rising_edge(clk);

            input_index <= to_unsigned(1, 2);
            input_data <= to_fixed(in1);
            wait until rising_edge(clk);

            input_index <= to_unsigned(2, 2);
            input_data <= to_fixed(in2);
            wait until rising_edge(clk);

            input_index <= to_unsigned(3, 2);
            input_data <= to_fixed(in3);
            wait until rising_edge(clk);

            input_valid <= '0';
            wait until fwd_done = '1';
            wait until rising_edge(clk);
        end procedure run_network_forward;

        -- Network-level backward pass
        procedure run_network_backward(
            tgt : real
        ) is
        begin
            target <= to_fixed(tgt);
            start_backward <= '1';
            wait until rising_edge(clk);
            start_backward <= '0';
            wait until bwd_done = '1';
            wait until rising_edge(clk);
        end procedure run_network_backward;

        -- Network-level weight update
        procedure run_network_update(
            lr : real
        ) is
        begin
            learning_rate <= to_fixed(lr);
            start_update <= '1';
            wait until rising_edge(clk);
            start_update <= '0';
            wait until upd_done = '1';
            wait until rising_edge(clk);
        end procedure run_network_update;

        -- Complete training step
        procedure run_training_step(
            in0, in1, in2, in3 : real;
            tgt : real;
            lr : real
        ) is
        begin
            run_network_forward(in0, in1, in2, in3);
            run_network_backward(tgt);
            run_network_update(lr);
        end procedure run_training_step;

        -- Train on dataset with convergence checking
        procedure train_on_dataset(
            dataset : test_dataset_t;
            lr : real;
            max_iter : integer;
            threshold : real;
            variable final_outputs : out test_dataset_t;
            variable final_mse : out real;
            variable final_iter : out integer;
            variable final_converged : out boolean
        ) is
            variable temp_outputs : test_dataset_t(dataset'range);
        begin
            iter := 0;
            converged := false;

            while iter < max_iter loop
                iter := iter + 1;

                -- Train on all samples
                for i in dataset'range loop
                    run_training_step(
                        dataset(i).input0,
                        dataset(i).input1,
                        dataset(i).input2,
                        dataset(i).input3,
                        dataset(i).target,
                        lr
                    );
                end loop;

                -- Check convergence every 10 iterations
                if (iter mod 10 = 0) then
                    -- Collect outputs
                    for i in dataset'range loop
                        run_network_forward(
                            dataset(i).input0,
                            dataset(i).input1,
                            dataset(i).input2,
                            dataset(i).input3
                        );
                        temp_outputs(i).target := to_real(output_data);
                    end loop;

                    mse := calculate_mse(temp_outputs, dataset);
                    print_training_progress(iter, mse, temp_outputs);

                    if is_converged(mse, threshold) then
                        converged := true;
                        exit;
                    end if;
                end if;
            end loop;

            -- Final output collection
            for i in dataset'range loop
                run_network_forward(
                    dataset(i).input0,
                    dataset(i).input1,
                    dataset(i).input2,
                    dataset(i).input3
                );
                temp_outputs(i).target := to_real(output_data);
            end loop;

            final_outputs := temp_outputs;
            final_mse := calculate_mse(temp_outputs, dataset);
            final_iter := iter;
            final_converged := converged;
        end procedure train_on_dataset;

    begin
        print_header("4-2-1 Neural Network Linear Regression Test (SIGMOID ACTIVATION)");

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        ---------------------------------------------------------------------------
        -- Linear Regression Test: y = 0.1*(x1 + x2 + x3 + x4) -- NORMALIZED
        ---------------------------------------------------------------------------
        report "Testing: y = 0.1*(x1 + x2 + x3 + x4) [NORMALIZED] with LR=0.5";

        train_on_dataset(LINEAR_DATASET, 0.5, 150, 0.01, outputs, mse, iter, converged);
        print_convergence_summary("LINEAR_SIGMOID_LR_0.5", converged, iter, mse, outputs, LINEAR_DATASET);

        -- Pass criteria
        test_pass := converged and (iter <= 150) and (mse < 0.05);

        if test_pass then
            report "***** LINEAR REGRESSION SUCCESS - NETWORK CAN LEARN CONTINUOUS FUNCTIONS! *****" severity note;
        else
            report "***** LINEAR REGRESSION FAILED - REVIEW CONVERGENCE DETAILS ABOVE *****" severity warning;
        end if;

        print_test_result("Linear Regression (y = x1+x2+x3+x4)", test_pass);

        ---------------------------------------------------------------------------
        -- Test Summary
        ---------------------------------------------------------------------------
        print_header("Linear Regression Test Complete");
        if test_pass then
            report "Network successfully learned 4-variable linear function" severity note;
            report "This validates regression capability beyond binary logic gates" severity note;
        else
            report "Convergence failed - check MSE trend and iteration count above" severity warning;
        end if;

        sim_done <= true;
        wait;
    end process test_proc;

end architecture behavioral;
