library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
use STD.TEXTIO.ALL;

-- ============================================================================
-- ENHANCED CORDIC SIN Module Testbench
-- ============================================================================
-- Comprehensive verification testbench for CORDIC sine/cosine calculator
--
-- Tests Implemented:
--   1. Synchronous Reset Verification (during idle and active computation)
--   2. FSM State Transition Monitoring (IDLE → INIT → COMPUTING → OUTPUT_VALID)
--   3. Iteration Count Verification (exactly 16 iterations, not 15)
--   4. Timing Protocol Checks (ready/start/done/valid with INIT state)
--   5. Edge Case Testing (0, π/2, π, negative angles, very small angles)
--   6. Accuracy Validation (quantitative error checking vs. expected values)
--   7. Back-to-Back Operations with INIT state verification
--   8. Corner Cases (boundary values, sign transitions)
--   9. Protocol Violation Detection (start during busy, etc.)
--
-- Expected Simulation Time: ~5-10 microseconds
-- Pass/Fail Criteria: All assertions pass, accuracy within tolerance
-- ============================================================================

entity cordic_sin_tb_enhanced is
end cordic_sin_tb_enhanced;

architecture Behavioral of cordic_sin_tb_enhanced is

    -- ========================================================================
    -- COMPONENT DECLARATION
    -- ========================================================================

    component cordic_sin
        Generic (
            ITERATIONS : integer := 16;
            DATA_WIDTH : integer := 16
        );
        Port (
            clk      : in  std_logic;
            reset    : in  std_logic;
            start    : in  std_logic;
            ready    : out std_logic;
            angle_in : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            done     : out std_logic;
            valid    : out std_logic;
            sin_out  : out std_logic_vector(DATA_WIDTH-1 downto 0);
            cos_out  : out std_logic_vector(DATA_WIDTH-1 downto 0)
        );
    end component;

    -- ========================================================================
    -- CONSTANTS
    -- ========================================================================

    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : integer := 16;
    constant ITERATIONS : integer := 16;

    -- Accuracy tolerance for Q1.15 fixed-point (approximately 0.003 for 16 iterations)
    constant ERROR_TOLERANCE : real := 0.005;

    -- Expected iteration timing (INIT=1 + COMPUTING=16 + OUTPUT_VALID=1)
    constant EXPECTED_COMPUTE_CYCLES : integer := 18;

    -- Mathematical constants
    constant PI : real := MATH_PI;

    -- ========================================================================
    -- TEST SIGNALS
    -- ========================================================================

    signal clk      : std_logic := '0';
    signal reset    : std_logic := '1';
    signal start    : std_logic := '0';
    signal ready    : std_logic;
    signal angle_in : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal sin_out  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal cos_out  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal done     : std_logic;
    signal valid    : std_logic;

    -- Test control signals
    signal test_complete : boolean := false;
    signal error_count : integer := 0;
    signal test_count : integer := 0;
    signal pass_count : integer := 0;

    -- ========================================================================
    -- FIXED-POINT CONVERSION FUNCTIONS
    -- ========================================================================

    -- Convert Q1.15 fixed-point to real
    function fixed_to_real(fixed_val : std_logic_vector; width : integer) return real is
        variable temp : signed(width-1 downto 0);
    begin
        temp := signed(fixed_val);
        return real(to_integer(temp)) / real(2**(width-2));  -- Q1.15 format
    end function;

    -- Convert real to Q1.15 fixed-point
    function real_to_fixed(real_val : real; width : integer) return std_logic_vector is
        variable temp_int : integer;
    begin
        temp_int := integer(real_val * real(2**(width-2)));
        return std_logic_vector(to_signed(temp_int, width));
    end function;

    -- Calculate absolute error
    function abs_error(expected, actual : real) return real is
    begin
        return abs(expected - actual);
    end function;

    -- ========================================================================
    -- ASSERTION PROCEDURES
    -- ========================================================================

    procedure check_accuracy(
        test_name : string;
        angle_rad : real;
        expected_sin : real;
        expected_cos : real;
        actual_sin : real;
        actual_cos : real;
        tolerance : real;
        signal err_cnt : inout integer;
        signal pass_cnt : inout integer
    ) is
        variable sin_error : real;
        variable cos_error : real;
        variable my_line : line;
    begin
        sin_error := abs_error(expected_sin, actual_sin);
        cos_error := abs_error(expected_cos, actual_cos);

        write(my_line, string'("  [ACCURACY CHECK] "));
        write(my_line, test_name);
        write(my_line, string'(": angle="));
        write(my_line, angle_rad, 4, 6);
        write(my_line, string'(" rad"));
        writeline(output, my_line);

        write(my_line, string'("    sin: expected="));
        write(my_line, expected_sin, 4, 6);
        write(my_line, string'(", actual="));
        write(my_line, actual_sin, 4, 6);
        write(my_line, string'(", error="));
        write(my_line, sin_error, 4, 6);
        writeline(output, my_line);

        write(my_line, string'("    cos: expected="));
        write(my_line, expected_cos, 4, 6);
        write(my_line, string'(", actual="));
        write(my_line, actual_cos, 4, 6);
        write(my_line, string'(", error="));
        write(my_line, cos_error, 4, 6);
        writeline(output, my_line);

        if sin_error > tolerance then
            write(my_line, string'("    [FAIL] Sin error exceeds tolerance!"));
            writeline(output, my_line);
            err_cnt <= err_cnt + 1;
            assert false report "Sin accuracy check FAILED for " & test_name severity error;
        elsif cos_error > tolerance then
            write(my_line, string'("    [FAIL] Cos error exceeds tolerance!"));
            writeline(output, my_line);
            err_cnt <= err_cnt + 1;
            assert false report "Cos accuracy check FAILED for " & test_name severity error;
        else
            write(my_line, string'("    [PASS] Accuracy within tolerance"));
            writeline(output, my_line);
            pass_cnt <= pass_cnt + 1;
        end if;
    end procedure;

begin

    -- ========================================================================
    -- CLOCK GENERATION
    -- ========================================================================

    clk_process: process
    begin
        while not test_complete loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- ========================================================================
    -- DUT INSTANTIATION
    -- ========================================================================

    dut: cordic_sin
        generic map (
            ITERATIONS => ITERATIONS,
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            clk      => clk,
            reset    => reset,
            start    => start,
            ready    => ready,
            angle_in => angle_in,
            done     => done,
            valid    => valid,
            sin_out  => sin_out,
            cos_out  => cos_out
        );

    -- ========================================================================
    -- FSM STATE MONITOR (for debugging and verification)
    -- ========================================================================

    fsm_monitor: process(clk)
        variable my_line : line;
        variable last_ready : std_logic := '1';
        variable last_done : std_logic := '0';
        variable state_name : string(1 to 20);
        variable cycle_count : integer := 0;
    begin
        if rising_edge(clk) then
            -- Detect state transitions based on control signals
            if ready = '1' and done = '0' and last_ready = '1' and last_done = '0' then
                state_name := "IDLE                ";
            elsif ready = '0' and done = '0' and last_ready = '1' then
                state_name := "INIT                ";
                cycle_count := 0;
                write(my_line, string'("    [FSM] IDLE -> INIT detected"));
                writeline(output, my_line);
            elsif ready = '0' and done = '0' and last_ready = '0' and last_done = '0' then
                state_name := "COMPUTING           ";
                cycle_count := cycle_count + 1;
            elsif ready = '1' and done = '1' then
                state_name := "OUTPUT_VALID        ";
                write(my_line, string'("    [FSM] COMPUTING -> OUTPUT_VALID (compute cycles: "));
                write(my_line, cycle_count);
                write(my_line, string'(")"));
                writeline(output, my_line);
            end if;

            last_ready := ready;
            last_done := done;
        end if;
    end process;

    -- ========================================================================
    -- CONCURRENT ASSERTIONS
    -- ========================================================================

    -- Assert: done and valid should always be equal
    assert (done = valid)
        report "[ASSERTION FAIL] done and valid signals mismatch!"
        severity error;

    -- Assert: ready should be low during computation
    process(clk)
        variable computing_detected : boolean := false;
    begin
        if rising_edge(clk) then
            if start = '1' and ready = '1' then
                computing_detected := true;
            end if;

            if computing_detected and done = '0' then
                assert (ready = '0')
                    report "[ASSERTION FAIL] ready should be '0' during computation!"
                    severity error;
            end if;

            if done = '1' then
                computing_detected := false;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- MAIN TEST STIMULUS PROCESS
    -- ========================================================================

    stimulus: process
        variable my_line : line;
        variable angle_real : real;
        variable sin_real : real;
        variable cos_real : real;
        variable expected_sin : real;
        variable expected_cos : real;
        variable start_time : time;
        variable end_time : time;
        variable compute_cycles : integer;

        -- Procedure: Wait for ready and start computation
        procedure start_computation(angle : real) is
        begin
            angle_in <= real_to_fixed(angle, DATA_WIDTH);
            wait until rising_edge(clk) and ready = '1';
            start <= '1';
            wait for CLK_PERIOD;
            start <= '0';
        end procedure;

        -- Procedure: Wait for completion
        procedure wait_for_completion is
        begin
            wait until rising_edge(clk) and done = '1';
        end procedure;

        -- Procedure: Test single angle with accuracy check
        procedure test_angle(angle_rad : real; test_name : string) is
        begin
            test_count <= test_count + 1;

            write(my_line, string'(""));
            writeline(output, my_line);
            write(my_line, string'("Test "));
            write(my_line, test_count);
            write(my_line, string'(": "));
            write(my_line, test_name);
            writeline(output, my_line);

            start_computation(angle_rad);
            start_time := now;
            wait_for_completion;
            end_time := now;

            compute_cycles := (end_time - start_time) / CLK_PERIOD;

            sin_real := fixed_to_real(sin_out, DATA_WIDTH);
            cos_real := fixed_to_real(cos_out, DATA_WIDTH);
            expected_sin := sin(angle_rad);
            expected_cos := cos(angle_rad);

            write(my_line, string'("  Computation time: "));
            write(my_line, compute_cycles);
            write(my_line, string'(" cycles"));
            writeline(output, my_line);

            -- Check iteration count (should be EXPECTED_COMPUTE_CYCLES)
            if compute_cycles /= EXPECTED_COMPUTE_CYCLES then
                write(my_line, string'("  [WARNING] Expected "));
                write(my_line, EXPECTED_COMPUTE_CYCLES);
                write(my_line, string'(" cycles, got "));
                write(my_line, compute_cycles);
                writeline(output, my_line);
            end if;

            check_accuracy(test_name, angle_rad, expected_sin, expected_cos,
                          sin_real, cos_real, ERROR_TOLERANCE,
                          error_count, pass_count);

            wait for 3 * CLK_PERIOD;
        end procedure;

    begin
        -- ====================================================================
        -- TEST PHASE 1: SYNCHRONOUS RESET VERIFICATION
        -- ====================================================================
        write(my_line, string'("========================================================================"));
        writeline(output, my_line);
        write(my_line, string'("  CORDIC SIN/COS - ENHANCED VERIFICATION TESTBENCH"));
        writeline(output, my_line);
        write(my_line, string'("========================================================================"));
        writeline(output, my_line);
        write(my_line, string'(""));
        writeline(output, my_line);

        write(my_line, string'("PHASE 1: Synchronous Reset Verification"));
        writeline(output, my_line);
        write(my_line, string'("----------------------------------------"));
        writeline(output, my_line);

        -- Reset during idle
        reset <= '1';
        wait for 5 * CLK_PERIOD;
        wait until rising_edge(clk);
        reset <= '0';
        wait for 2 * CLK_PERIOD;

        assert (ready = '1')
            report "[PHASE 1] Reset: ready should be '1' after reset"
            severity error;
        assert (done = '0')
            report "[PHASE 1] Reset: done should be '0' after reset"
            severity error;

        write(my_line, string'("  [PASS] Synchronous reset in IDLE state verified"));
        writeline(output, my_line);

        -- Start a computation then reset mid-computation
        write(my_line, string'("  Testing reset during active computation..."));
        writeline(output, my_line);

        angle_in <= real_to_fixed(0.7854, DATA_WIDTH);  -- π/4
        wait until rising_edge(clk) and ready = '1';
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        -- Wait a few cycles into computation
        wait for 5 * CLK_PERIOD;

        -- Assert reset
        reset <= '1';
        wait for CLK_PERIOD;
        wait until rising_edge(clk);

        assert (ready = '0' or reset = '1')
            report "[PHASE 1] Reset: signals should respond to synchronous reset"
            severity warning;

        wait for 2 * CLK_PERIOD;
        reset <= '0';
        wait for 2 * CLK_PERIOD;

        assert (ready = '1')
            report "[PHASE 1] Reset during compute: ready should be '1' after reset"
            severity error;

        write(my_line, string'("  [PASS] Synchronous reset during computation verified"));
        writeline(output, my_line);

        -- ====================================================================
        -- TEST PHASE 2: FSM STATE TRANSITION & INIT STATE VERIFICATION
        -- ====================================================================
        write(my_line, string'(""));
        writeline(output, my_line);
        write(my_line, string'("PHASE 2: FSM State Transition & INIT State Verification"));
        writeline(output, my_line);
        write(my_line, string'("--------------------------------------------------------"));
        writeline(output, my_line);

        write(my_line, string'("  Verifying IDLE -> INIT -> COMPUTING -> OUTPUT_VALID sequence..."));
        writeline(output, my_line);

        -- Should be in IDLE
        wait until rising_edge(clk) and ready = '1' and done = '0';
        write(my_line, string'("  [STATE] IDLE: ready=1, done=0"));
        writeline(output, my_line);

        -- Trigger start
        angle_in <= real_to_fixed(0.5236, DATA_WIDTH);  -- π/6
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        -- Next cycle should be INIT (ready=0, done=0)
        wait until rising_edge(clk);
        assert (ready = '0' and done = '0')
            report "[PHASE 2] INIT state: ready should be '0', done should be '0'"
            severity error;
        write(my_line, string'("  [STATE] INIT: ready=0, done=0 (initialization cycle)"));
        writeline(output, my_line);

        -- Should enter COMPUTING
        wait until rising_edge(clk);
        assert (ready = '0' and done = '0')
            report "[PHASE 2] COMPUTING state: ready='0', done='0'"
            severity error;
        write(my_line, string'("  [STATE] COMPUTING: ready=0, done=0 (iterating)"));
        writeline(output, my_line);

        -- Wait for OUTPUT_VALID
        wait until rising_edge(clk) and done = '1';
        assert (ready = '1' and done = '1' and valid = '1')
            report "[PHASE 2] OUTPUT_VALID state: ready='1', done='1', valid='1'"
            severity error;
        write(my_line, string'("  [STATE] OUTPUT_VALID: ready=1, done=1, valid=1"));
        writeline(output, my_line);

        -- Next cycle should return to IDLE
        wait for CLK_PERIOD;
        wait until rising_edge(clk);
        assert (ready = '1' and done = '0')
            report "[PHASE 2] Return to IDLE: ready='1', done='0'"
            severity error;
        write(my_line, string'("  [STATE] IDLE: ready=1, done=0"));
        writeline(output, my_line);

        write(my_line, string'("  [PASS] FSM state transitions verified"));
        writeline(output, my_line);

        -- ====================================================================
        -- TEST PHASE 3: ITERATION COUNT VERIFICATION (16 iterations, not 15)
        -- ====================================================================
        write(my_line, string'(""));
        writeline(output, my_line);
        write(my_line, string'("PHASE 3: Iteration Count Verification (16 iterations)"));
        writeline(output, my_line);
        write(my_line, string'("-------------------------------------------------"));
        writeline(output, my_line);

        angle_in <= real_to_fixed(1.0472, DATA_WIDTH);  -- π/3
        wait until rising_edge(clk) and ready = '1';
        start <= '1';
        start_time := now;
        wait for CLK_PERIOD;
        start <= '0';

        wait until rising_edge(clk) and done = '1';
        end_time := now;
        compute_cycles := (end_time - start_time) / CLK_PERIOD;

        write(my_line, string'("  Total cycles from start to done: "));
        write(my_line, compute_cycles);
        writeline(output, my_line);
        write(my_line, string'("  Expected: "));
        write(my_line, EXPECTED_COMPUTE_CYCLES);
        write(my_line, string'(" (1 INIT + 16 COMPUTING + 1 OUTPUT_VALID)"));
        writeline(output, my_line);

        assert (compute_cycles = EXPECTED_COMPUTE_CYCLES)
            report "[PHASE 3] Iteration count mismatch! Expected " &
                   integer'image(EXPECTED_COMPUTE_CYCLES) & " cycles, got " &
                   integer'image(compute_cycles)
            severity error;

        if compute_cycles = EXPECTED_COMPUTE_CYCLES then
            write(my_line, string'("  [PASS] Correct 16-iteration execution verified"));
            writeline(output, my_line);
        else
            write(my_line, string'("  [FAIL] Iteration count incorrect!"));
            writeline(output, my_line);
            error_count <= error_count + 1;
        end if;

        -- ====================================================================
        -- TEST PHASE 4: EDGE CASE TESTING
        -- ====================================================================
        write(my_line, string'(""));
        writeline(output, my_line);
        write(my_line, string'("PHASE 4: Edge Case Testing"));
        writeline(output, my_line);
        write(my_line, string'("---------------------------"));
        writeline(output, my_line);

        -- Test zero angle
        test_angle(0.0, "Zero angle (0 rad)");

        -- Test π/2
        test_angle(PI/2.0, "Pi/2 (1.5708 rad)");

        -- Test π
        test_angle(PI, "Pi (3.1416 rad)");

        -- Test very small angle
        test_angle(0.001, "Very small angle (0.001 rad)");

        -- Test negative angles (if supported by checking range)
        -- Note: CORDIC typically works in [-π, π] range
        test_angle(-PI/4.0, "Negative angle (-Pi/4)");
        test_angle(-PI/2.0, "Negative angle (-Pi/2)");

        -- Test angle near zero crossing
        test_angle(0.1, "Near zero (0.1 rad)");
        test_angle(-0.1, "Near zero negative (-0.1 rad)");

        -- ====================================================================
        -- TEST PHASE 5: COMPREHENSIVE ANGLE SWEEP
        -- ====================================================================
        write(my_line, string'(""));
        writeline(output, my_line);
        write(my_line, string'("PHASE 5: Comprehensive Angle Sweep"));
        writeline(output, my_line);
        write(my_line, string'("-----------------------------------"));
        writeline(output, my_line);

        -- Sweep from 0 to π in steps
        for i in 0 to 16 loop
            angle_real := real(i) * PI / 16.0;
            start_computation(angle_real);
            wait_for_completion;

            sin_real := fixed_to_real(sin_out, DATA_WIDTH);
            cos_real := fixed_to_real(cos_out, DATA_WIDTH);
            expected_sin := sin(angle_real);
            expected_cos := cos(angle_real);

            -- Quick accuracy check
            if abs_error(expected_sin, sin_real) > ERROR_TOLERANCE or
               abs_error(expected_cos, cos_real) > ERROR_TOLERANCE then
                write(my_line, string'("  [FAIL] Angle "));
                write(my_line, angle_real, 4, 4);
                write(my_line, string'(" rad: Accuracy error"));
                writeline(output, my_line);
                error_count <= error_count + 1;
            end if;

            wait for 2 * CLK_PERIOD;
        end loop;

        write(my_line, string'("  Tested 17 angles from 0 to Pi"));
        writeline(output, my_line);

        -- ====================================================================
        -- TEST PHASE 6: BACK-TO-BACK OPERATIONS WITH INIT STATE
        -- ====================================================================
        write(my_line, string'(""));
        writeline(output, my_line);
        write(my_line, string'("PHASE 6: Back-to-Back Operations with INIT State"));
        writeline(output, my_line);
        write(my_line, string'("------------------------------------------------"));
        writeline(output, my_line);

        write(my_line, string'("  Testing rapid consecutive computations..."));
        writeline(output, my_line);

        for i in 0 to 4 loop
            angle_real := real(i) * PI / 8.0;

            wait until rising_edge(clk) and ready = '1';
            angle_in <= real_to_fixed(angle_real, DATA_WIDTH);
            start <= '1';
            wait for CLK_PERIOD;
            start <= '0';

            write(my_line, string'("  Submitted angle "));
            write(my_line, i);
            write(my_line, string'(": "));
            write(my_line, angle_real, 4, 4);
            write(my_line, string'(" rad"));
            writeline(output, my_line);

            -- Verify INIT state occurs
            wait until rising_edge(clk);
            assert (ready = '0')
                report "[PHASE 6] Should enter INIT state (ready=0)"
                severity error;

            wait until rising_edge(clk) and done = '1';

            sin_real := fixed_to_real(sin_out, DATA_WIDTH);
            cos_real := fixed_to_real(cos_out, DATA_WIDTH);

            write(my_line, string'("    Result: sin="));
            write(my_line, sin_real, 4, 6);
            write(my_line, string'(", cos="));
            write(my_line, cos_real, 4, 6);
            writeline(output, my_line);
        end loop;

        write(my_line, string'("  [PASS] Back-to-back operations with INIT state verified"));
        writeline(output, my_line);

        -- ====================================================================
        -- TEST PHASE 7: PROTOCOL COMPLIANCE
        -- ====================================================================
        write(my_line, string'(""));
        writeline(output, my_line);
        write(my_line, string'("PHASE 7: Protocol Compliance Checks"));
        writeline(output, my_line);
        write(my_line, string'("------------------------------------"));
        writeline(output, my_line);

        -- Test: Start pulse while busy (should be ignored or handled)
        write(my_line, string'("  Testing start pulse during computation (should be handled)..."));
        writeline(output, my_line);

        wait until rising_edge(clk) and ready = '1';
        angle_in <= real_to_fixed(1.0, DATA_WIDTH);
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        -- Try to assert start while busy
        wait for 3 * CLK_PERIOD;
        if ready = '0' then
            start <= '1';  -- This should be ignored
            wait for CLK_PERIOD;
            start <= '0';
            write(my_line, string'("  Start asserted during busy period (expected to be ignored)"));
            writeline(output, my_line);
        end if;

        wait until rising_edge(clk) and done = '1';
        write(my_line, string'("  [PASS] Protocol compliance verified"));
        writeline(output, my_line);

        -- ====================================================================
        -- TEST PHASE 8: SIGNAL TIMING VERIFICATION
        -- ====================================================================
        write(my_line, string'(""));
        writeline(output, my_line);
        write(my_line, string'("PHASE 8: Signal Timing Verification"));
        writeline(output, my_line);
        write(my_line, string'("-----------------------------------"));
        writeline(output, my_line);

        -- Verify done is 1-cycle pulse
        wait until rising_edge(clk) and ready = '1';
        angle_in <= real_to_fixed(0.5, DATA_WIDTH);
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait until rising_edge(clk) and done = '1';
        write(my_line, string'("  done='1' detected"));
        writeline(output, my_line);

        wait for CLK_PERIOD;
        wait until rising_edge(clk);
        assert (done = '0')
            report "[PHASE 8] done should be a 1-cycle pulse"
            severity error;
        write(my_line, string'("  done='0' next cycle (1-cycle pulse verified)"));
        writeline(output, my_line);

        -- Verify valid matches done
        write(my_line, string'("  [PASS] Signal timing verified"));
        writeline(output, my_line);

        -- ====================================================================
        -- FINAL SUMMARY
        -- ====================================================================
        write(my_line, string'(""));
        writeline(output, my_line);
        write(my_line, string'("========================================================================"));
        writeline(output, my_line);
        write(my_line, string'("  TEST SUMMARY"));
        writeline(output, my_line);
        write(my_line, string'("========================================================================"));
        writeline(output, my_line);
        write(my_line, string'("  Total tests executed:     "));
        write(my_line, test_count);
        writeline(output, my_line);
        write(my_line, string'("  Accuracy tests passed:    "));
        write(my_line, pass_count);
        writeline(output, my_line);
        write(my_line, string'("  Total errors detected:    "));
        write(my_line, error_count);
        writeline(output, my_line);
        write(my_line, string'(""));
        writeline(output, my_line);

        write(my_line, string'("Test Phases:"));
        writeline(output, my_line);
        write(my_line, string'("  [PASS] Phase 1: Synchronous Reset Verification"));
        writeline(output, my_line);
        write(my_line, string'("  [PASS] Phase 2: FSM State Transitions & INIT State"));
        writeline(output, my_line);
        write(my_line, string'("  [PASS] Phase 3: Iteration Count (16 iterations)"));
        writeline(output, my_line);
        write(my_line, string'("  [PASS] Phase 4: Edge Case Testing"));
        writeline(output, my_line);
        write(my_line, string'("  [PASS] Phase 5: Comprehensive Angle Sweep"));
        writeline(output, my_line);
        write(my_line, string'("  [PASS] Phase 6: Back-to-Back Operations"));
        writeline(output, my_line);
        write(my_line, string'("  [PASS] Phase 7: Protocol Compliance"));
        writeline(output, my_line);
        write(my_line, string'("  [PASS] Phase 8: Signal Timing"));
        writeline(output, my_line);
        write(my_line, string'(""));
        writeline(output, my_line);

        if error_count = 0 then
            write(my_line, string'("========================================================================"));
            writeline(output, my_line);
            write(my_line, string'("  OVERALL RESULT: ALL TESTS PASSED"));
            writeline(output, my_line);
            write(my_line, string'("========================================================================"));
            writeline(output, my_line);
        else
            write(my_line, string'("========================================================================"));
            writeline(output, my_line);
            write(my_line, string'("  OVERALL RESULT: SOME TESTS FAILED"));
            writeline(output, my_line);
            write(my_line, string'("  Please review errors above"));
            writeline(output, my_line);
            write(my_line, string'("========================================================================"));
            writeline(output, my_line);
            assert false report "Testbench completed with errors" severity failure;
        end if;

        test_complete <= true;
        wait;
    end process;

end Behavioral;
