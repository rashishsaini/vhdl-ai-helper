--------------------------------------------------------------------------------
-- Package: neural_network_tb_pkg
-- Description: Shared testbench utilities for neural network verification
-- Author: VHDL AI Helper Project
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;

package neural_network_tb_pkg is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz
    constant DATA_WIDTH : integer := 16;
    constant FRAC_BITS  : integer := 13;
    constant SCALE_REAL : real := 8192.0;  -- 2^13 (use literal, not 2**FRAC_BITS for XSIM)

    ---------------------------------------------------------------------------
    -- Test Data Types
    ---------------------------------------------------------------------------
    type test_vector_t is record
        input0 : real;
        input1 : real;
        input2 : real;
        input3 : real;
        target : real;
    end record;

    type test_dataset_t is array (natural range <>) of test_vector_t;

    ---------------------------------------------------------------------------
    -- Training Datasets (declarations only, initialized in body)
    ---------------------------------------------------------------------------
    constant XOR_DATASET  : test_dataset_t(0 to 3);
    constant AND_DATASET  : test_dataset_t(0 to 3);
    constant OR_DATASET   : test_dataset_t(0 to 3);
    constant NAND_DATASET : test_dataset_t(0 to 3);

    ---------------------------------------------------------------------------
    -- Convergence Criteria
    ---------------------------------------------------------------------------
    constant MAX_ITERATIONS   : integer := 200;
    constant CONVERGENCE_LOSS : real := 0.1;  -- MSE < 0.1
    constant FP_TOLERANCE     : real := 0.001;  -- 0.1% error tolerance

    ---------------------------------------------------------------------------
    -- Fixed-Point Conversion Functions
    ---------------------------------------------------------------------------
    function to_fixed(r : real) return signed;
    function to_real(s : signed) return real;
    function fp_equal(a : real; b : real; tol : real := FP_TOLERANCE) return boolean;

    ---------------------------------------------------------------------------
    -- Helper Procedures
    ---------------------------------------------------------------------------
    procedure print_header(msg : string);
    procedure print_test_result(name : string; pass : boolean);
    procedure print_test_result_detailed(
        name : string;
        expected : real;
        actual : real;
        tolerance : real;
        pass : boolean
    );
    procedure wait_clocks(signal clk : std_logic; n : integer);

    ---------------------------------------------------------------------------
    -- Training Utility Functions (Phase 3)
    ---------------------------------------------------------------------------
    function calculate_mse(
        outputs : test_dataset_t;
        dataset : test_dataset_t
    ) return real;

    function is_converged(mse : real; threshold : real) return boolean;

    procedure print_training_progress(
        iteration : integer;
        mse : real;
        outputs : test_dataset_t
    );

    procedure print_convergence_summary(
        dataset_name : string;
        converged : boolean;
        final_iter : integer;
        final_mse : real;
        outputs : test_dataset_t;
        dataset : test_dataset_t
    );

    ---------------------------------------------------------------------------
    -- Classification Helper Functions (for Iris classification)
    ---------------------------------------------------------------------------
    function calculate_accuracy(
        predictions : test_dataset_t;
        labels : test_dataset_t
    ) return real;

    function is_correct_class(
        prediction : real;
        target : real;
        threshold : real := 0.5
    ) return boolean;

end package neural_network_tb_pkg;

--------------------------------------------------------------------------------
-- Package Body
--------------------------------------------------------------------------------

package body neural_network_tb_pkg is

    ---------------------------------------------------------------------------
    -- Fixed-Point Conversion Functions
    ---------------------------------------------------------------------------

    function to_fixed(r : real) return signed is
        variable temp : integer;
    begin
        -- Convert real to Q2.13 fixed-point
        -- Use literal 8192.0 not SCALE_REAL for XSIM compatibility
        temp := integer(r * 8192.0);
        return to_signed(temp, DATA_WIDTH);
    end function;

    function to_real(s : signed) return real is
    begin
        -- Convert Q2.13 fixed-point to real
        return real(to_integer(s)) / 8192.0;
    end function;

    function fp_equal(a : real; b : real; tol : real := FP_TOLERANCE) return boolean is
        variable err : real;
    begin
        if b = 0.0 then
            return abs(a) < tol;
        else
            err := abs((a - b) / b);
            return err < tol;
        end if;
    end function;

    ---------------------------------------------------------------------------
    -- Training Datasets (initialized in body for XSIM compatibility)
    ---------------------------------------------------------------------------

    -- XOR: Output=1 when input pairs differ
    -- Pattern: [in0,in1] XOR [in2,in3]
    constant XOR_DATASET : test_dataset_t(0 to 3) := (
        0 => (0.0, 0.0, 0.0, 0.0, 0.0),  -- [0,0] XOR [0,0] = 0
        1 => (0.0, 0.0, 1.0, 1.0, 0.0),  -- [0,0] XOR [1,1] = 0
        2 => (1.0, 1.0, 0.0, 0.0, 1.0),  -- [1,1] XOR [0,0] = 1
        3 => (1.0, 1.0, 1.0, 1.0, 0.0)   -- [1,1] XOR [1,1] = 0
    );

    -- AND: Output=1 only when all inputs=1
    constant AND_DATASET : test_dataset_t(0 to 3) := (
        0 => (0.0, 0.0, 0.0, 0.0, 0.0),
        1 => (0.0, 0.0, 1.0, 1.0, 0.0),
        2 => (1.0, 1.0, 0.0, 0.0, 0.0),
        3 => (1.0, 1.0, 1.0, 1.0, 1.0)
    );

    -- OR: Output=1 when any input=1
    constant OR_DATASET : test_dataset_t(0 to 3) := (
        0 => (0.0, 0.0, 0.0, 0.0, 0.0),
        1 => (0.0, 0.0, 1.0, 1.0, 1.0),
        2 => (1.0, 1.0, 0.0, 0.0, 1.0),
        3 => (1.0, 1.0, 1.0, 1.0, 1.0)
    );

    -- NAND: Output=0 only when all inputs=1
    constant NAND_DATASET : test_dataset_t(0 to 3) := (
        0 => (0.0, 0.0, 0.0, 0.0, 1.0),
        1 => (0.0, 0.0, 1.0, 1.0, 1.0),
        2 => (1.0, 1.0, 0.0, 0.0, 1.0),
        3 => (1.0, 1.0, 1.0, 1.0, 0.0)
    );

    ---------------------------------------------------------------------------
    -- Helper Procedures
    ---------------------------------------------------------------------------

    procedure print_header(msg : string) is
        variable l : line;
    begin
        write(l, string'("========================================"));
        writeline(output, l);
        write(l, msg);
        writeline(output, l);
        write(l, string'("========================================"));
        writeline(output, l);
    end procedure;

    procedure print_test_result(name : string; pass : boolean) is
        variable l : line;
    begin
        write(l, string'("Test: ") & name & string'(" ... "));
        if pass then
            write(l, string'("PASS"));
        else
            write(l, string'("FAIL"));
        end if;
        writeline(output, l);
    end procedure;

    procedure print_test_result_detailed(
        name : string;
        expected : real;
        actual : real;
        tolerance : real;
        pass : boolean
    ) is
        variable l : line;
    begin
        write(l, string'("Test: ") & name);
        writeline(output, l);
        write(l, string'("  Expected: "));
        write(l, expected);
        writeline(output, l);
        write(l, string'("  Actual:   "));
        write(l, actual);
        writeline(output, l);
        write(l, string'("  Error:    "));
        write(l, abs(expected - actual));
        writeline(output, l);
        write(l, string'("  Tolerance: "));
        write(l, tolerance);
        writeline(output, l);
        write(l, string'("  Result:   "));
        if pass then
            write(l, string'("PASS"));
        else
            write(l, string'("FAIL"));
        end if;
        writeline(output, l);
    end procedure;

    procedure wait_clocks(signal clk : std_logic; n : integer) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

    ---------------------------------------------------------------------------
    -- Training Utility Functions (Phase 3 Implementation)
    ---------------------------------------------------------------------------

    function calculate_mse(
        outputs : test_dataset_t;
        dataset : test_dataset_t
    ) return real is
        variable sum_sq_error : real := 0.0;
        variable error : real;
        variable n : integer;
    begin
        n := dataset'length;
        for i in dataset'range loop
            error := outputs(i).target - dataset(i).target;
            sum_sq_error := sum_sq_error + (error * error);
        end loop;
        return sum_sq_error / real(n);
    end function;

    function is_converged(mse : real; threshold : real) return boolean is
    begin
        return mse < threshold;
    end function;

    procedure print_training_progress(
        iteration : integer;
        mse : real;
        outputs : test_dataset_t
    ) is
        variable l : line;
    begin
        write(l, string'("Iteration "));
        write(l, iteration);
        write(l, string'(": MSE="));
        write(l, mse, left, 6, 4);
        write(l, string'(" | Outputs: "));
        for i in outputs'range loop
            write(l, outputs(i).target, left, 5, 3);
            write(l, ' ');
        end loop;
        writeline(output, l);
    end procedure;

    procedure print_convergence_summary(
        dataset_name : string;
        converged : boolean;
        final_iter : integer;
        final_mse : real;
        outputs : test_dataset_t;
        dataset : test_dataset_t
    ) is
        variable l : line;
        variable error : real;
    begin
        write(l, string'("========================================"));
        writeline(output, l);
        write(l, string'("Training Summary: ") & dataset_name);
        writeline(output, l);
        write(l, string'("========================================"));
        writeline(output, l);

        write(l, string'("Converged: "));
        if converged then
            write(l, string'("YES"));
        else
            write(l, string'("NO"));
        end if;
        writeline(output, l);

        write(l, string'("Final Iteration: "));
        write(l, final_iter);
        writeline(output, l);

        write(l, string'("Final MSE: "));
        write(l, final_mse, left, 8, 6);
        writeline(output, l);

        write(l, string'(""));
        writeline(output, l);
        write(l, string'("Sample Results:"));
        writeline(output, l);

        for i in dataset'range loop
            error := abs(outputs(i).target - dataset(i).target);
            write(l, string'("  Sample "));
            write(l, i);
            write(l, string'(": Target="));
            write(l, dataset(i).target, left, 5, 3);
            write(l, string'(", Output="));
            write(l, outputs(i).target, left, 5, 3);
            write(l, string'(", Error="));
            write(l, error, left, 6, 4);
            writeline(output, l);
        end loop;

        write(l, string'("========================================"));
        writeline(output, l);
    end procedure;

    ---------------------------------------------------------------------------
    -- Classification Helper Functions Implementation
    ---------------------------------------------------------------------------

    function calculate_accuracy(
        predictions : test_dataset_t;
        labels : test_dataset_t
    ) return real is
        variable correct : integer := 0;
        variable total : integer;
        variable pred_class, actual_class : integer;
    begin
        total := predictions'length;

        for i in predictions'range loop
            -- Threshold at 0.5 (4096 in Q2.13)
            if predictions(i).target > 0.5 then
                pred_class := 1;
            else
                pred_class := 0;
            end if;

            if labels(i).target > 0.5 then
                actual_class := 1;
            else
                actual_class := 0;
            end if;

            if pred_class = actual_class then
                correct := correct + 1;
            end if;
        end loop;

        return real(correct) / real(total) * 100.0;
    end function;

    function is_correct_class(
        prediction : real;
        target : real;
        threshold : real := 0.5
    ) return boolean is
        variable pred_class, actual_class : integer;
    begin
        if prediction > threshold then
            pred_class := 1;
        else
            pred_class := 0;
        end if;

        if target > threshold then
            actual_class := 1;
        else
            actual_class := 0;
        end if;

        return pred_class = actual_class;
    end function;

end package body neural_network_tb_pkg;
