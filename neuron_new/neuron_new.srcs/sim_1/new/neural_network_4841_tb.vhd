--------------------------------------------------------------------------------
-- Testbench: neural_network_4841_tb
-- Description: Comprehensive training testbench for 4-8-4-1 neural network
--              using Iris dataset (30 samples, binary classification)
--
-- Training Strategy:
--   - 50 epochs of training
--   - 24 training samples (80%), 6 test samples (20%)
--   - Learning rate: 0.1 (819 in Q2.13)
--   - Evaluate accuracy every 10 epochs
--   - Final evaluation on train and test sets
--   - Success criteria: Test accuracy >= 90%
--
-- Test Scenarios Covered:
--   1. Reset initialization and verification
--   2. Complete training loop with forward/backward/update phases
--   3. Boundary conditions: epoch counting, sample indexing
--   4. Timeout detection for all three phases (FWD, BWD, UPD)
--   5. Accuracy measurement and convergence tracking
--   6. Train/test split validation
--   7. Classification decision logic verification (>0 → class 1, else → class 0)
--
-- Expected Simulation Time: ~5-10 minutes (50 epochs × 30 samples × ~1500 cycles)
-- Pass/Fail Criteria: Test accuracy >= 90% after 50 epochs
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;

library work;
use work.iris_dataset_small_pkg.all;

entity neural_network_4841_tb is
end entity neural_network_4841_tb;

architecture behavioral of neural_network_4841_tb is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD      : time := 10 ns;
    constant DATA_WIDTH      : integer := 16;
    constant FRAC_BITS       : integer := 13;

    -- Training parameters
    constant NUM_EPOCHS      : integer := 50;
    constant LEARNING_RATE   : signed(15 downto 0) := to_signed(819, 16);  -- 0.1 in Q2.13
    constant TRAIN_SIZE      : integer := 24;  -- 80% of 30
    constant TEST_SIZE       : integer := 6;   -- 20% of 30
    constant TRAIN_START     : integer := 0;
    constant TRAIN_END       : integer := 23;
    constant TEST_START      : integer := 24;
    constant TEST_END        : integer := 29;
    constant EVAL_INTERVAL   : integer := 10;  -- Evaluate every 10 epochs

    -- Timeout values (in clock cycles)
    constant FWD_TIMEOUT     : integer := 500;
    constant BWD_TIMEOUT     : integer := 800;
    constant UPD_TIMEOUT     : integer := 1500;

    -- Classification thresholds
    constant CLASS_THRESHOLD : signed(15 downto 0) := to_signed(0, 16);  -- Decision: >0 → class 1
    constant TARGET_ACCURACY : real := 90.0;  -- 90% success threshold

    ---------------------------------------------------------------------------
    -- DUT Signals
    ---------------------------------------------------------------------------
    signal clk             : std_logic := '0';
    signal rst             : std_logic := '0';
    signal start_forward   : std_logic := '0';
    signal start_backward  : std_logic := '0';
    signal start_update    : std_logic := '0';
    signal input_data      : signed(15 downto 0) := (others => '0');
    signal input_index     : unsigned(1 downto 0) := (others => '0');
    signal input_valid     : std_logic := '0';
    signal target          : signed(15 downto 0) := (others => '0');
    signal learning_rate   : signed(15 downto 0) := LEARNING_RATE;
    signal output_data     : signed(15 downto 0);
    signal output_class    : signed(15 downto 0);
    signal output_valid    : std_logic;
    signal fwd_done        : std_logic;
    signal bwd_done        : std_logic;
    signal upd_done        : std_logic;

    ---------------------------------------------------------------------------
    -- Testbench Control
    ---------------------------------------------------------------------------
    signal sim_done        : boolean := false;
    signal test_passed     : boolean := false;
    signal total_errors    : integer := 0;

    ---------------------------------------------------------------------------
    -- Helper Function: Fixed-Point to Real Conversion
    ---------------------------------------------------------------------------
    function to_real(s : signed) return real is
    begin
        return real(to_integer(s)) / 8192.0;
    end function;

    ---------------------------------------------------------------------------
    -- Helper Function: Real to Fixed-Point Conversion
    ---------------------------------------------------------------------------
    function to_fixed(r : real) return signed is
    begin
        return to_signed(integer(r * 8192.0), 16);
    end function;

    ---------------------------------------------------------------------------
    -- Procedures
    ---------------------------------------------------------------------------

    -- Procedure: run_forward
    -- Executes forward pass for given sample index
    procedure run_forward(
        constant sample_idx : in integer;
        signal clk          : in std_logic;
        signal start_fwd    : out std_logic;
        signal inp_data     : out signed(15 downto 0);
        signal inp_idx      : out unsigned(1 downto 0);
        signal inp_valid    : out std_logic;
        signal fwd_done_sig : in std_logic
    ) is
        variable timeout_counter : integer;
        variable l : line;
    begin
        -- Wait for stable clock
        wait until rising_edge(clk);

        -- Assert start_forward
        start_fwd <= '1';
        wait until rising_edge(clk);
        start_fwd <= '0';

        -- Feed 4 input features
        for i in 0 to 3 loop
            inp_data <= IRIS_FEATURES(sample_idx)(i);
            inp_idx <= to_unsigned(i, 2);
            inp_valid <= '1';
            wait until rising_edge(clk);
        end loop;
        inp_valid <= '0';

        -- Wait for forward pass completion with timeout
        timeout_counter := 0;
        while fwd_done_sig = '0' and timeout_counter < FWD_TIMEOUT loop
            wait until rising_edge(clk);
            timeout_counter := timeout_counter + 1;
        end loop;

        -- Check for timeout
        assert timeout_counter < FWD_TIMEOUT
            report "[FWD_TIMEOUT] Forward pass timeout for sample " & integer'image(sample_idx) &
                   " | Cycles: " & integer'image(timeout_counter)
            severity error;

        if timeout_counter >= FWD_TIMEOUT then
            total_errors <= total_errors + 1;
        end if;

        wait until rising_edge(clk);
    end procedure;

    -- Procedure: run_backward
    -- Executes backward pass for given sample index
    procedure run_backward(
        constant sample_idx : in integer;
        signal clk          : in std_logic;
        signal start_bwd    : out std_logic;
        signal tgt          : out signed(15 downto 0);
        signal bwd_done_sig : in std_logic
    ) is
        variable timeout_counter : integer;
        variable l : line;
    begin
        wait until rising_edge(clk);

        -- Set target value
        tgt <= IRIS_LABELS(sample_idx);

        -- Assert start_backward
        start_bwd <= '1';
        wait until rising_edge(clk);
        start_bwd <= '0';

        -- Wait for backward pass completion with timeout
        timeout_counter := 0;
        while bwd_done_sig = '0' and timeout_counter < BWD_TIMEOUT loop
            wait until rising_edge(clk);
            timeout_counter := timeout_counter + 1;
        end loop;

        -- Check for timeout
        assert timeout_counter < BWD_TIMEOUT
            report "[BWD_TIMEOUT] Backward pass timeout for sample " & integer'image(sample_idx) &
                   " | Cycles: " & integer'image(timeout_counter)
            severity error;

        if timeout_counter >= BWD_TIMEOUT then
            total_errors <= total_errors + 1;
        end if;

        wait until rising_edge(clk);
    end procedure;

    -- Procedure: run_update
    -- Executes weight update pass
    procedure run_update(
        signal clk          : in std_logic;
        signal start_upd    : out std_logic;
        signal upd_done_sig : in std_logic
    ) is
        variable timeout_counter : integer;
        variable l : line;
    begin
        wait until rising_edge(clk);

        -- Assert start_update
        start_upd <= '1';
        wait until rising_edge(clk);
        start_upd <= '0';

        -- Wait for update completion with timeout
        timeout_counter := 0;
        while upd_done_sig = '0' and timeout_counter < UPD_TIMEOUT loop
            wait until rising_edge(clk);
            timeout_counter := timeout_counter + 1;
        end loop;

        -- Check for timeout
        assert timeout_counter < UPD_TIMEOUT
            report "[UPD_TIMEOUT] Update pass timeout | Cycles: " & integer'image(timeout_counter)
            severity error;

        if timeout_counter >= UPD_TIMEOUT then
            total_errors <= total_errors + 1;
        end if;

        wait until rising_edge(clk);
    end procedure;

    -- Procedure: train_sample
    -- Complete training cycle: forward -> backward -> update
    procedure train_sample(
        constant sample_idx : in integer;
        signal clk          : in std_logic;
        signal start_fwd    : out std_logic;
        signal start_bwd    : out std_logic;
        signal start_upd    : out std_logic;
        signal inp_data     : out signed(15 downto 0);
        signal inp_idx      : out unsigned(1 downto 0);
        signal inp_valid    : out std_logic;
        signal tgt          : out signed(15 downto 0);
        signal fwd_done_sig : in std_logic;
        signal bwd_done_sig : in std_logic;
        signal upd_done_sig : in std_logic
    ) is
    begin
        -- Forward pass
        run_forward(sample_idx, clk, start_fwd, inp_data, inp_idx, inp_valid, fwd_done_sig);

        -- Backward pass
        run_backward(sample_idx, clk, start_bwd, tgt, bwd_done_sig);

        -- Update weights
        run_update(clk, start_upd, upd_done_sig);
    end procedure;

    -- Procedure: evaluate
    -- Evaluate accuracy on a range of samples
    procedure evaluate(
        constant start_idx     : in integer;
        constant end_idx       : in integer;
        constant phase_name    : in string;
        signal clk             : in std_logic;
        signal start_fwd       : out std_logic;
        signal inp_data        : out signed(15 downto 0);
        signal inp_idx         : out unsigned(1 downto 0);
        signal inp_valid       : out std_logic;
        signal fwd_done_sig    : in std_logic;
        signal out_class       : in signed(15 downto 0);
        variable correct_count : out integer;
        variable accuracy      : out real
    ) is
        variable predicted_class : integer;
        variable actual_class    : integer;
        variable l : line;
    begin
        correct_count := 0;

        for i in start_idx to end_idx loop
            -- Run forward pass only (no training)
            run_forward(i, clk, start_fwd, inp_data, inp_idx, inp_valid, fwd_done_sig);

            -- Determine predicted class: output_class > 0 → class 1, else → class 0
            if out_class > CLASS_THRESHOLD then
                predicted_class := 1;
            else
                predicted_class := 0;
            end if;

            -- Determine actual class
            if IRIS_LABELS(i) > CLASS_THRESHOLD then
                actual_class := 1;
            else
                actual_class := 0;
            end if;

            -- Check if prediction is correct
            if predicted_class = actual_class then
                correct_count := correct_count + 1;
            end if;
        end loop;

        -- Calculate accuracy percentage
        accuracy := (real(correct_count) / real(end_idx - start_idx + 1)) * 100.0;

        -- Report results
        write(l, string'("[") & phase_name & string'("] Accuracy: "));
        write(l, correct_count);
        write(l, string'("/"));
        write(l, end_idx - start_idx + 1);
        write(l, string'(" = "));
        write(l, accuracy, left, 5, 1);
        write(l, string'("%"));
        writeline(output, l);
    end procedure;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : entity work.neural_network_4841
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
            output_class   => output_class,
            output_valid   => output_valid,
            fwd_done       => fwd_done,
            bwd_done       => bwd_done,
            upd_done       => upd_done
        );

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk_gen : process
    begin
        while not sim_done loop
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
    main_test : process
        variable l : line;
        variable train_correct : integer;
        variable test_correct : integer;
        variable train_accuracy : real;
        variable test_accuracy : real;
        variable epoch_start_time : time;
        variable epoch_duration : time;
    begin
        -- Print test header
        write(l, string'("========================================"));
        writeline(output, l);
        write(l, string'("Neural Network 4-8-4-1 Training Testbench"));
        writeline(output, l);
        write(l, string'("Iris Dataset Binary Classification"));
        writeline(output, l);
        write(l, string'("========================================"));
        writeline(output, l);
        write(l, string'("Configuration:"));
        writeline(output, l);
        write(l, string'("  Epochs: "));
        write(l, NUM_EPOCHS);
        writeline(output, l);
        write(l, string'("  Learning Rate: 0.1 (Q2.13 = "));
        write(l, to_integer(LEARNING_RATE));
        write(l, string'(")"));
        writeline(output, l);
        write(l, string'("  Train Samples: 0-23 (24 samples)"));
        writeline(output, l);
        write(l, string'("  Test Samples: 24-29 (6 samples)"));
        writeline(output, l);
        write(l, string'("  Target Accuracy: >= 90%"));
        writeline(output, l);
        write(l, string'("========================================"));
        writeline(output, l);

        -- Phase 1: Reset
        write(l, string'("[RESET] Asserting reset signal"));
        writeline(output, l);
        rst <= '1';
        wait for CLK_PERIOD * 10;
        wait until rising_edge(clk);
        rst <= '0';
        wait for CLK_PERIOD * 5;

        assert fwd_done = '0' and bwd_done = '0' and upd_done = '0'
            report "[RESET_CHECK] Done signals should be low after reset"
            severity error;

        write(l, string'("[RESET] Reset complete"));
        writeline(output, l);
        write(l, string'(""));
        writeline(output, l);

        -- Phase 2: Training Loop
        write(l, string'("========================================"));
        writeline(output, l);
        write(l, string'("[TRAINING] Starting training loop"));
        writeline(output, l);
        write(l, string'("========================================"));
        writeline(output, l);

        for epoch in 1 to NUM_EPOCHS loop
            epoch_start_time := now;

            -- Train on all training samples
            for sample in TRAIN_START to TRAIN_END loop
                train_sample(
                    sample, clk,
                    start_forward, start_backward, start_update,
                    input_data, input_index, input_valid, target,
                    fwd_done, bwd_done, upd_done
                );
            end loop;

            epoch_duration := now - epoch_start_time;

            -- Evaluate accuracy every EVAL_INTERVAL epochs
            if (epoch mod EVAL_INTERVAL = 0) or (epoch = NUM_EPOCHS) then
                write(l, string'(""));
                writeline(output, l);
                write(l, string'("--- Epoch "));
                write(l, epoch);
                write(l, string'(" Evaluation ("));
                write(l, epoch_duration / 1 us);
                write(l, string'(" us) ---"));
                writeline(output, l);

                -- Evaluate on training set
                evaluate(
                    TRAIN_START, TRAIN_END, "TRAIN",
                    clk, start_forward, input_data, input_index, input_valid,
                    fwd_done, output_class,
                    train_correct, train_accuracy
                );

                -- Evaluate on test set
                evaluate(
                    TEST_START, TEST_END, "TEST",
                    clk, start_forward, input_data, input_index, input_valid,
                    fwd_done, output_class,
                    test_correct, test_accuracy
                );

                write(l, string'(""));
                writeline(output, l);
            end if;
        end loop;

        -- Phase 3: Final Evaluation
        write(l, string'("========================================"));
        writeline(output, l);
        write(l, string'("[FINAL EVALUATION] All epochs complete"));
        writeline(output, l);
        write(l, string'("========================================"));
        writeline(output, l);

        -- Final train accuracy
        evaluate(
            TRAIN_START, TRAIN_END, "FINAL_TRAIN",
            clk, start_forward, input_data, input_index, input_valid,
            fwd_done, output_class,
            train_correct, train_accuracy
        );

        -- Final test accuracy
        evaluate(
            TEST_START, TEST_END, "FINAL_TEST",
            clk, start_forward, input_data, input_index, input_valid,
            fwd_done, output_class,
            test_correct, test_accuracy
        );

        -- Phase 4: Test Result Summary
        write(l, string'(""));
        writeline(output, l);
        write(l, string'("========================================"));
        writeline(output, l);
        write(l, string'("TEST SUMMARY"));
        writeline(output, l);
        write(l, string'("========================================"));
        writeline(output, l);
        write(l, string'("Total Training Errors: "));
        write(l, total_errors);
        writeline(output, l);
        write(l, string'("Final Train Accuracy: "));
        write(l, train_accuracy, left, 5, 1);
        write(l, string'("%"));
        writeline(output, l);
        write(l, string'("Final Test Accuracy:  "));
        write(l, test_accuracy, left, 5, 1);
        write(l, string'("%"));
        writeline(output, l);
        write(l, string'("Target Accuracy:      >= "));
        write(l, TARGET_ACCURACY, left, 5, 1);
        write(l, string'("%"));
        writeline(output, l);

        -- Determine pass/fail
        if test_accuracy >= TARGET_ACCURACY and total_errors = 0 then
            test_passed <= true;
            write(l, string'(""));
            writeline(output, l);
            write(l, string'("*** TEST PASSED ***"));
            writeline(output, l);
            write(l, string'("Test accuracy meets target threshold and no errors detected."));
            writeline(output, l);
        else
            test_passed <= false;
            write(l, string'(""));
            writeline(output, l);
            write(l, string'("*** TEST FAILED ***"));
            writeline(output, l);
            if test_accuracy < TARGET_ACCURACY then
                write(l, string'("Reason: Test accuracy below threshold ("));
                write(l, test_accuracy, left, 5, 1);
                write(l, string'("% < "));
                write(l, TARGET_ACCURACY, left, 5, 1);
                write(l, string'("%)"));
                writeline(output, l);
            end if;
            if total_errors > 0 then
                write(l, string'("Reason: "));
                write(l, total_errors);
                write(l, string'(" timeout/assertion errors detected"));
                writeline(output, l);
            end if;
        end if;

        write(l, string'("========================================"));
        writeline(output, l);

        -- Final assertion for automated test runners
        assert test_accuracy >= TARGET_ACCURACY
            report "[FINAL_CHECK] Test accuracy below target: " &
                   real'image(test_accuracy) & "% < " & real'image(TARGET_ACCURACY) & "%"
            severity error;

        assert total_errors = 0
            report "[FINAL_CHECK] Total errors detected: " & integer'image(total_errors)
            severity error;

        -- End simulation
        write(l, string'(""));
        writeline(output, l);
        write(l, string'("[SIMULATION] Ending simulation"));
        writeline(output, l);
        sim_done <= true;
        wait;
    end process;

    ---------------------------------------------------------------------------
    -- Safety Timeout Watchdog (prevents infinite simulation)
    ---------------------------------------------------------------------------
    watchdog : process
        variable l : line;
    begin
        wait for 100 ms;  -- Absolute maximum simulation time
        if not sim_done then
            write(l, string'(""));
            writeline(output, l);
            write(l, string'("========================================"));
            writeline(output, l);
            write(l, string'("[WATCHDOG] SIMULATION TIMEOUT"));
            writeline(output, l);
            write(l, string'("Simulation exceeded maximum time limit"));
            writeline(output, l);
            write(l, string'("========================================"));
            writeline(output, l);
            assert false
                report "Watchdog timeout: Simulation exceeded 100ms"
                severity failure;
        end if;
        wait;
    end process;

end architecture behavioral;
