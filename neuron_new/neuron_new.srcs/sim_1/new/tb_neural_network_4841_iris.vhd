--------------------------------------------------------------------------------
-- Testbench: tb_neural_network_4841_iris
-- Description: Train and test 4-8-4-1 network on Iris binary classification
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;

-- Use small dataset for faster simulation
use work.iris_dataset_small_pkg.all;

entity tb_neural_network_4841_iris is
end entity;

architecture behavioral of tb_neural_network_4841_iris is

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
        variable correct : integer;
        variable total : integer;
        variable accuracy : real;
        variable train_acc, test_acc : real;
        variable timeout_count : integer;

        procedure run_forward(sample_idx : integer) is
        begin
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
        end procedure;

        procedure run_backward(sample_idx : integer) is
            variable error_val : signed(15 downto 0);
        begin
            target <= IRIS_LABELS(sample_idx);
            error_val := IRIS_LABELS(sample_idx) - output_class;

            -- Debug: print error value
            report "  Backward: target=" & integer'image(to_integer(IRIS_LABELS(sample_idx))) &
                   " output=" & integer'image(to_integer(output_class)) &
                   " error=" & integer'image(to_integer(error_val));

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
        end procedure;

        procedure run_update is
        begin
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
        end procedure;

        procedure train_sample(sample_idx : integer) is
        begin
            run_forward(sample_idx);
            run_backward(sample_idx);
            run_update;
        end procedure;

        procedure evaluate(start_idx, end_idx : integer; variable acc : out real) is
            variable pred_class, actual_class : integer;
        begin
            correct := 0;
            total := 0;

            for i in start_idx to end_idx loop
                run_forward(i);

                if output_class > 0 then
                    pred_class := 1;
                else
                    pred_class := 0;
                end if;

                if IRIS_LABELS(i) > 0 then
                    actual_class := 1;
                else
                    actual_class := 0;
                end if;

                if pred_class = actual_class then
                    correct := correct + 1;
                end if;
                total := total + 1;
            end loop;

            acc := real(correct) / real(total) * 100.0;
        end procedure;

        procedure detailed_evaluate(start_idx, end_idx : integer; set_name : string) is
            variable pred_class, actual_class : integer;
            variable match : string(1 to 5);
        begin
            report "========================================";
            report "  " & set_name & " Set Detailed Results";
            report "========================================";

            correct := 0;
            total := 0;

            for i in start_idx to end_idx loop
                run_forward(i);

                if output_class > 0 then
                    pred_class := 1;
                else
                    pred_class := 0;
                end if;

                if IRIS_LABELS(i) > 0 then
                    actual_class := 1;
                else
                    actual_class := 0;
                end if;

                if pred_class = actual_class then
                    correct := correct + 1;
                    match := "MATCH";
                else
                    match := "WRONG";
                end if;

                total := total + 1;

                report "Sample " & integer'image(i) &
                       ": output=" & integer'image(to_integer(output_class)) &
                       " pred=" & integer'image(pred_class) &
                       " actual=" & integer'image(actual_class) &
                       " [" & match & "]";
            end loop;

            report "----------------------------------------";
            report set_name & " Accuracy: " & integer'image(correct) & "/" &
                   integer'image(total) & " = " &
                   real'image(real(correct)/real(total)*100.0) & "%";
            report "========================================";
        end procedure;

    begin
        report "========================================";
        report "  4-8-4-1 Iris Binary Classification";
        report "  Task: Setosa vs Non-Setosa";
        report "  Samples: " & integer'image(NUM_SAMPLES);
        report "========================================";

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 10;
        rst <= '0';
        wait for CLK_PERIOD * 5;

        -- Learning rate: 0.05 = 410 in Q2.13 (increased to overcome small gradients)
        learning_rate_sig <= to_signed(410, 16);

        report "========================================";
        report " TRAINING - 100 epochs on all training samples";
        report "========================================";

        -- Full training loop
        for epoch in 1 to 100 loop
            -- Train on training set (samples 0-23)
            for s in 0 to 23 loop
                train_sample(s);
            end loop;

            -- Evaluate every 10 epochs
            if epoch mod 10 = 0 then
                evaluate(0, 23, train_acc);
                report "Epoch " & integer'image(epoch) &
                       ": Train Accuracy = " & real'image(train_acc) & "%";
            end if;
        end loop;

        -- Final evaluation
        report "========================================";
        report "  Final Results";
        report "========================================";

        evaluate(0, 23, train_acc);
        report "Training Accuracy: " & real'image(train_acc) & "%";

        evaluate(24, 29, test_acc);
        report "Test Accuracy: " & real'image(test_acc) & "%";

        if test_acc >= 90.0 then
            report "*** SUCCESS: Iris classification achieved! ***" severity note;
        else
            report "*** NEEDS IMPROVEMENT: Accuracy below 90% ***" severity warning;
        end if;

        report "========================================";

        -- Detailed per-sample analysis
        detailed_evaluate(0, 23, "Training");
        detailed_evaluate(24, 29, "Test");

        -- Test on ALL 30 samples for comprehensive analysis
        detailed_evaluate(0, 29, "Complete Dataset");

        sim_done <= true;
        wait;
    end process;

end architecture;
