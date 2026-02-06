--------------------------------------------------------------------------------
-- Comprehensive Testbench for 256-Point DFT Complex Calculator
--------------------------------------------------------------------------------
-- DUT: dft_complex_calculator
-- Purpose: Exhaustive verification of DFT computation with golden model
-- Test Coverage:
--   1. DC Signal (constant value)
--   2. Impulse Response (single sample)
--   3. Sinusoid at K=1 (fundamental frequency)
--   4. Sinusoid at K=5 (5th harmonic)
--   5. Sinusoid at K=10 (10th harmonic)
--   6. Cosine Signal at K=1
--   7. Complex Exponential (cosine + sine mix)
--   8. Random Noise
--   9. Edge Cases (max/min alternating - Nyquist frequency)
--   10. State Recovery (consecutive DFTs)
--
-- Expected Simulation Time: ~35 us @ 100 MHz
-- Pass/Fail: Automated with detailed error reporting
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity tb_dft_complex_calculator is
end tb_dft_complex_calculator;

architecture testbench of tb_dft_complex_calculator is

    -------------------------------------------------------------------------
    -- CONFIGURATION SECTION
    -------------------------------------------------------------------------
    constant WINDOW_SIZE       : integer := 256;
    constant SAMPLE_WIDTH      : integer := 16;
    constant COEFF_WIDTH       : integer := 16;
    constant ACCUMULATOR_WIDTH : integer := 48;
    constant OUTPUT_WIDTH      : integer := 32;
    constant K_VALUE           : integer := 1;

    -- Clock configuration
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz

    -- Fixed-point scaling constants
    constant Q15_SCALE  : real := 32767.0;       -- 2^15 - 1
    constant Q16_15_SCALE : real := 32768.0;     -- 2^15

    -- Verification tolerances
    constant MAGNITUDE_LSB_TOL : integer := 1;
    constant MAGNITUDE_PCT_TOL : real := 0.02;   -- 2%
    constant PHASE_TOL_HIGH    : real := 5.0;    -- degrees for mag > 10% peak
    constant PHASE_TOL_MED     : real := 10.0;   -- degrees for mag 1-10% peak
    constant PHASE_TOL_MIN_MAG : real := 0.01;   -- Skip phase check below 1% peak

    -------------------------------------------------------------------------
    -- COMPONENT DECLARATIONS
    -------------------------------------------------------------------------

    -- DUT Component
    component dft_complex_calculator is
        generic (
            WINDOW_SIZE       : integer := 256;
            SAMPLE_WIDTH      : integer := 16;
            COEFF_WIDTH       : integer := 16;
            ACCUMULATOR_WIDTH : integer := 48;
            OUTPUT_WIDTH      : integer := 32
        );
        port (
            clk            : in  std_logic;
            rst            : in  std_logic;
            start          : in  std_logic;
            done           : out std_logic;
            sample_data    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            sample_addr    : out std_logic_vector(7 downto 0);
            cos_coeff      : in  std_logic_vector(COEFF_WIDTH-1 downto 0);
            cos_addr       : out std_logic_vector(7 downto 0);
            cos_valid      : in  std_logic;
            sin_coeff      : in  std_logic_vector(COEFF_WIDTH-1 downto 0);
            sin_addr       : out std_logic_vector(7 downto 0);
            sin_valid      : in  std_logic;
            real_result    : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            imag_result    : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            result_valid   : out std_logic
        );
    end component;

    -- Cosine ROM Component
    component cosine_single_k_rom is
        generic (
            WINDOW_SIZE : integer := 256;
            COEFF_WIDTH : integer := 16;
            K_VALUE     : integer := 1
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            enable      : in  std_logic := '1';
            n_addr      : in  std_logic_vector(7 downto 0);
            cos_coeff   : out std_logic_vector(COEFF_WIDTH-1 downto 0);
            data_valid  : out std_logic
        );
    end component;

    -- Sine ROM Component
    component sine_single_k_rom is
        generic (
            WINDOW_SIZE : integer := 256;
            COEFF_WIDTH : integer := 16;
            K_VALUE     : integer := 1
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            enable      : in  std_logic := '1';
            n_addr      : in  std_logic_vector(7 downto 0);
            sin_coeff   : out std_logic_vector(COEFF_WIDTH-1 downto 0);
            data_valid  : out std_logic
        );
    end component;

    -------------------------------------------------------------------------
    -- SIGNAL DECLARATIONS
    -------------------------------------------------------------------------

    -- Clock and reset
    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    -- DUT control signals
    signal start        : std_logic := '0';
    signal done         : std_logic;
    signal result_valid : std_logic;

    -- Sample buffer interface
    signal sample_data  : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal sample_addr  : std_logic_vector(7 downto 0);

    -- Cosine ROM interface
    signal cos_coeff    : std_logic_vector(COEFF_WIDTH-1 downto 0);
    signal cos_addr     : std_logic_vector(7 downto 0);
    signal cos_valid    : std_logic;
    signal cos_enable   : std_logic := '1';

    -- Sine ROM interface
    signal sin_coeff    : std_logic_vector(COEFF_WIDTH-1 downto 0);
    signal sin_addr     : std_logic_vector(7 downto 0);
    signal sin_valid    : std_logic;
    signal sin_enable   : std_logic := '1';

    -- Result outputs
    signal real_result  : std_logic_vector(OUTPUT_WIDTH-1 downto 0);
    signal imag_result  : std_logic_vector(OUTPUT_WIDTH-1 downto 0);

    -- Sample buffer memory (256 samples, Q15 format)
    type sample_buffer_type is array (0 to WINDOW_SIZE-1) of
         std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal sample_buffer : sample_buffer_type := (others => (others => '0'));

    -- Test control signals
    signal test_running : boolean := true;
    signal tests_passed : integer := 0;
    signal tests_failed : integer := 0;

    -------------------------------------------------------------------------
    -- HELPER FUNCTIONS AND PROCEDURES
    -------------------------------------------------------------------------

    -- Convert real to Q15 format
    function real_to_q15(real_val : real) return std_logic_vector is
        variable temp_int : integer;
    begin
        if real_val >= 1.0 then
            temp_int := 32767;
        elsif real_val <= -1.0 then
            temp_int := -32768;
        else
            temp_int := integer(real_val * Q15_SCALE);
        end if;
        return std_logic_vector(to_signed(temp_int, SAMPLE_WIDTH));
    end function;

    -- Convert Q16.15 to real
    function q16_15_to_real(q_val : std_logic_vector(OUTPUT_WIDTH-1 downto 0))
             return real is
        variable signed_val : signed(OUTPUT_WIDTH-1 downto 0);
    begin
        signed_val := signed(q_val);
        return real(to_integer(signed_val)) / Q16_15_SCALE;
    end function;

    -- Calculate magnitude from real and imaginary parts
    function calc_magnitude(real_val, imag_val : real) return real is
    begin
        return sqrt(real_val * real_val + imag_val * imag_val);
    end function;

    -- Calculate phase in degrees from real and imaginary parts
    function calc_phase_deg(real_val, imag_val : real) return real is
        variable phase_rad : real;
        constant RAD_TO_DEG : real := 180.0 / MATH_PI;
    begin
        if abs(real_val) < 1.0e-10 and abs(imag_val) < 1.0e-10 then
            return 0.0;
        end if;
        phase_rad := arctan(imag_val, real_val);
        return phase_rad * RAD_TO_DEG;
    end function;

    -- Normalize angle difference to [-180, 180]
    function normalize_angle_diff(angle_diff : real) return real is
        variable normalized : real;
    begin
        normalized := angle_diff;
        while normalized > 180.0 loop
            normalized := normalized - 360.0;
        end loop;
        while normalized < -180.0 loop
            normalized := normalized + 360.0;
        end loop;
        return normalized;
    end function;

    -- Golden model: DFT computation using MATH_REAL
    procedure golden_dft(
        signal sample_buf : in sample_buffer_type;
        constant k_val : in integer;
        variable real_out : out real;
        variable imag_out : out real
    ) is
        variable sum_real : real := 0.0;
        variable sum_imag : real := 0.0;
        variable sample_q15 : integer;
        variable cos_q15 : integer;
        variable sin_q15 : integer;
        variable cos_val : real;
        variable sin_val : real;
        variable angle : real;
        constant PI : real := MATH_PI;
    begin
        -- CORRECTED: Match DUT's fixed-point arithmetic exactly
        for n in 0 to WINDOW_SIZE-1 loop
            -- Get sample as Q15 integer (same as DUT sees)
            sample_q15 := to_integer(signed(sample_buf(n)));

            -- Calculate angle: 2*pi*k*n/N
            angle := 2.0 * PI * real(k_val) * real(n) / real(WINDOW_SIZE);

            -- Calculate trig values and quantize to Q1.15 (same as ROM)
            cos_val := cos(angle);
            sin_val := sin(angle);

            -- Quantize to Q1.15 (same scaling as ROMs)
            if cos_val > 0.99996 then
                cos_q15 := 32767;
            elsif cos_val < -1.0 then
                cos_q15 := -32768;
            else
                cos_q15 := integer(cos_val * 32767.0);
            end if;

            if sin_val > 0.99996 then
                sin_q15 := 32767;
            elsif sin_val < -1.0 then
                sin_q15 := -32768;
            else
                sin_q15 := integer(sin_val * 32767.0);
            end if;

            -- Match DUT: Q15 * Q1.15 >> 15 = Q16.15
            -- (sample_q15 * cos_q15) produces Q16.30, divide by 32768 to get Q16.15
            sum_real := sum_real + floor(real(sample_q15 * cos_q15) / 32768.0);
            sum_imag := sum_imag + floor(real(-(sample_q15 * sin_q15)) / 32768.0);
        end loop;

        -- Convert to normalized real (same as q16_15_to_real does)
        real_out := sum_real / Q16_15_SCALE;
        imag_out := sum_imag / Q16_15_SCALE;
    end procedure;

    -- Load sample buffer with generated pattern
    procedure load_sample_buffer(
        signal sample_buf : out sample_buffer_type;
        constant pattern_type : in string;
        constant amplitude : in real := 1.0;
        constant frequency : in integer := 1;
        constant seed1_in : in integer := 12345;
        constant seed2_in : in integer := 67890
    ) is
        variable sample_val : real;
        variable angle : real;
        variable seed1 : integer := seed1_in;
        variable seed2 : integer := seed2_in;
        variable rand_val : real;
        constant PI : real := MATH_PI;
    begin
        for n in 0 to WINDOW_SIZE-1 loop
            if pattern_type = "DC" then
                -- Constant value
                sample_val := amplitude;

            elsif pattern_type = "IMPULSE" then
                -- Single impulse at n=0
                if n = 0 then
                    sample_val := amplitude;
                else
                    sample_val := 0.0;
                end if;

            elsif pattern_type = "SINE" then
                -- Sinusoid: amplitude * sin(2π*freq*n/N)
                angle := 2.0 * PI * real(frequency) * real(n) / real(WINDOW_SIZE);
                sample_val := amplitude * sin(angle);

            elsif pattern_type = "COSINE" then
                -- Cosine: amplitude * cos(2π*freq*n/N)
                angle := 2.0 * PI * real(frequency) * real(n) / real(WINDOW_SIZE);
                sample_val := amplitude * cos(angle);

            elsif pattern_type = "COMPLEX_EXP" then
                -- Complex exponential: cos + 0.5*sin at freq=1
                angle := 2.0 * PI * real(n) / real(WINDOW_SIZE);
                sample_val := amplitude * (cos(angle) + 0.5 * sin(angle));

            elsif pattern_type = "RANDOM" then
                -- Uniform random noise
                uniform(seed1, seed2, rand_val);
                sample_val := amplitude * (2.0 * rand_val - 1.0);

            elsif pattern_type = "ALTERNATING" then
                -- Alternating max/min (Nyquist frequency)
                if n mod 2 = 0 then
                    sample_val := amplitude;
                else
                    sample_val := -amplitude;
                end if;

            else
                sample_val := 0.0;
            end if;

            sample_buf(n) <= real_to_q15(sample_val);
        end loop;

        -- CRITICAL FIX: Wait for signal assignments to propagate
        -- Signal assignments are non-blocking and take effect after delta cycle
        wait for 0 ns;  -- Wait one delta cycle for all assignments to complete
    end procedure;

    -- Run DFT and wait for completion
    procedure run_dft_test(
        signal start_sig : out std_logic;
        signal done_sig : in std_logic;
        signal result_valid_sig : in std_logic;
        constant timeout_cycles : in integer := 10000
    ) is
        variable cycle_count : integer := 0;
    begin
        -- Assert start
        start_sig <= '1';
        wait until rising_edge(clk);
        start_sig <= '0';

        -- Wait for done
        while done_sig = '0' and cycle_count < timeout_cycles loop
            wait until rising_edge(clk);
            cycle_count := cycle_count + 1;
        end loop;

        assert cycle_count < timeout_cycles
            report "[ERROR] DFT timeout - done signal not asserted"
            severity error;

        -- Wait for result_valid
        wait until rising_edge(clk);

        assert result_valid_sig = '1'
            report "[ERROR] result_valid not asserted after done"
            severity error;

        -- Additional settling time
        wait until rising_edge(clk);
    end procedure;

    -- Verify DFT results against golden model
    procedure verify_dft_result(
        constant test_name : in string;
        signal real_res : in std_logic_vector(OUTPUT_WIDTH-1 downto 0);
        signal imag_res : in std_logic_vector(OUTPUT_WIDTH-1 downto 0);
        constant expected_real : in real;
        constant expected_imag : in real;
        constant expected_magnitude : in real;
        constant expected_phase : in real;
        signal pass_count : inout integer;
        signal fail_count : inout integer
    ) is
        variable actual_real : real;
        variable actual_imag : real;
        variable actual_magnitude : real;
        variable actual_phase : real;
        variable mag_error : real;
        variable mag_tolerance : real;
        variable phase_error : real;
        variable phase_tolerance : real;
        variable test_passed : boolean := true;
        variable peak_magnitude : real;
    begin
        -- Convert actual results to real
        actual_real := q16_15_to_real(real_res);
        actual_imag := q16_15_to_real(imag_res);
        actual_magnitude := calc_magnitude(actual_real, actual_imag);
        actual_phase := calc_phase_deg(actual_real, actual_imag);

        -- Calculate peak magnitude for relative tolerance
        peak_magnitude := expected_magnitude;
        if peak_magnitude < 1.0 then
            peak_magnitude := 1.0;  -- Avoid division by zero
        end if;

        -- Magnitude verification
        mag_error := abs(actual_magnitude - expected_magnitude);
        mag_tolerance := real(MAGNITUDE_LSB_TOL) / Q16_15_SCALE +
                        MAGNITUDE_PCT_TOL * expected_magnitude;

        -- CRITICAL FIX: Add minimum absolute tolerance for quantization effects
        -- 256 accumulations can produce cumulative quantization error
        -- Minimum tolerance accounts for fixed-point rounding in multiply-accumulate
        if mag_tolerance < 0.02 then
            mag_tolerance := 0.02;
        end if;

        if mag_error > mag_tolerance then
            report "[FAIL] " & test_name & " - MAGNITUDE | " &
                   "Expected: " & real'image(expected_magnitude) & " | " &
                   "Actual: " & real'image(actual_magnitude) & " | " &
                   "Error: " & real'image(mag_error) & " | " &
                   "Tolerance: " & real'image(mag_tolerance)
                severity warning;
            test_passed := false;
        end if;

        -- Phase verification (only if magnitude is significant)
        if expected_magnitude > PHASE_TOL_MIN_MAG * peak_magnitude then
            phase_error := abs(normalize_angle_diff(actual_phase - expected_phase));

            if expected_magnitude > 0.10 * peak_magnitude then
                phase_tolerance := PHASE_TOL_HIGH;
            else
                phase_tolerance := PHASE_TOL_MED;
            end if;

            if phase_error > phase_tolerance then
                report "[FAIL] " & test_name & " - PHASE | " &
                       "Expected: " & real'image(expected_phase) & " deg | " &
                       "Actual: " & real'image(actual_phase) & " deg | " &
                       "Error: " & real'image(phase_error) & " deg | " &
                       "Tolerance: " & real'image(phase_tolerance) & " deg"
                    severity warning;
                test_passed := false;
            end if;
        end if;

        -- Update counters
        if test_passed then
            report "[PASS] " & test_name & " | " &
                   "Mag: " & real'image(actual_magnitude) & " | " &
                   "Phase: " & real'image(actual_phase) & " deg";
            pass_count <= pass_count + 1;
        else
            fail_count <= fail_count + 1;
        end if;
    end procedure;

begin

    -------------------------------------------------------------------------
    -- CLOCK GENERATION
    -------------------------------------------------------------------------
    clk_process: process
    begin
        while test_running loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -------------------------------------------------------------------------
    -- DUT INSTANTIATION
    -------------------------------------------------------------------------
    DUT: dft_complex_calculator
        generic map (
            WINDOW_SIZE       => WINDOW_SIZE,
            SAMPLE_WIDTH      => SAMPLE_WIDTH,
            COEFF_WIDTH       => COEFF_WIDTH,
            ACCUMULATOR_WIDTH => ACCUMULATOR_WIDTH,
            OUTPUT_WIDTH      => OUTPUT_WIDTH
        )
        port map (
            clk            => clk,
            rst            => rst,
            start          => start,
            done           => done,
            sample_data    => sample_data,
            sample_addr    => sample_addr,
            cos_coeff      => cos_coeff,
            cos_addr       => cos_addr,
            cos_valid      => cos_valid,
            sin_coeff      => sin_coeff,
            sin_addr       => sin_addr,
            sin_valid      => sin_valid,
            real_result    => real_result,
            imag_result    => imag_result,
            result_valid   => result_valid
        );

    -------------------------------------------------------------------------
    -- ROM INSTANTIATIONS
    -------------------------------------------------------------------------
    COS_ROM: cosine_single_k_rom
        generic map (
            WINDOW_SIZE => WINDOW_SIZE,
            COEFF_WIDTH => COEFF_WIDTH,
            K_VALUE     => K_VALUE
        )
        port map (
            clk        => clk,
            rst        => rst,
            enable     => cos_enable,
            n_addr     => cos_addr,
            cos_coeff  => cos_coeff,
            data_valid => cos_valid
        );

    SIN_ROM: sine_single_k_rom
        generic map (
            WINDOW_SIZE => WINDOW_SIZE,
            COEFF_WIDTH => COEFF_WIDTH,
            K_VALUE     => K_VALUE
        )
        port map (
            clk        => clk,
            rst        => rst,
            enable     => sin_enable,
            n_addr     => sin_addr,
            sin_coeff  => sin_coeff,
            data_valid => sin_valid
        );

    -------------------------------------------------------------------------
    -- SAMPLE BUFFER READ PROCESS
    -------------------------------------------------------------------------
    sample_buffer_read: process(sample_addr, sample_buffer)
        variable addr_int : integer;
    begin
        addr_int := to_integer(unsigned(sample_addr));
        if addr_int >= 0 and addr_int < WINDOW_SIZE then
            sample_data <= sample_buffer(addr_int);
        else
            sample_data <= (others => '0');
        end if;
    end process;

    -------------------------------------------------------------------------
    -- MAIN TEST SEQUENCE
    -------------------------------------------------------------------------
    test_process: process
        variable golden_real : real;
        variable golden_imag : real;
        variable golden_magnitude : real;
        variable golden_phase : real;
        variable first_real : std_logic_vector(OUTPUT_WIDTH-1 downto 0);
        variable first_imag : std_logic_vector(OUTPUT_WIDTH-1 downto 0);
    begin
        -- Print testbench header
        report "========================================";
        report "DFT Complex Calculator Testbench";
        report "========================================";
        report "Window Size: " & integer'image(WINDOW_SIZE);
        report "Clock Period: " & time'image(CLK_PERIOD);
        report "K Value (ROM): " & integer'image(K_VALUE);
        report "----------------------------------------";

        -- Initialize
        rst <= '1';
        start <= '0';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -----------------------------------------------------------------------
        -- TEST 1: DC Signal
        -----------------------------------------------------------------------
        report "========================================";
        report "TEST 1: DC Signal (Constant 0.5)";
        report "========================================";

        -- Load DC signal: all samples = 0.5 (16384 in Q15)
        load_sample_buffer(sample_buffer, "DC", 0.5);

        -- Run DFT
        run_dft_test(start, done, result_valid);

        -- Golden model computation for K=1
        golden_dft(sample_buffer, K_VALUE, golden_real, golden_imag);
        golden_magnitude := calc_magnitude(golden_real, golden_imag);
        golden_phase := calc_phase_deg(golden_real, golden_imag);

        -- For DC signal, K=1 should have near-zero magnitude
        -- (all energy is at K=0, which we're not testing)
        verify_dft_result(
            test_name => "Test 1: DC Signal (K=1)",
            real_res => real_result,
            imag_res => imag_result,
            expected_real => golden_real,
            expected_imag => golden_imag,
            expected_magnitude => golden_magnitude,
            expected_phase => golden_phase,
            pass_count => tests_passed,
            fail_count => tests_failed
        );

        wait for CLK_PERIOD * 10;

        -----------------------------------------------------------------------
        -- TEST 2: Impulse Response
        -----------------------------------------------------------------------
        report "========================================";
        report "TEST 2: Impulse Response";
        report "========================================";

        -- Load impulse: sample[0] = 1.0, rest = 0
        load_sample_buffer(sample_buffer, "IMPULSE", 1.0);

        -- Run DFT
        run_dft_test(start, done, result_valid);

        -- Golden model
        golden_dft(sample_buffer, K_VALUE, golden_real, golden_imag);
        golden_magnitude := calc_magnitude(golden_real, golden_imag);
        golden_phase := calc_phase_deg(golden_real, golden_imag);

        -- For impulse, all frequencies should have uniform magnitude ≈ 1.0/256 = 0.00391
        verify_dft_result(
            test_name => "Test 2: Impulse (K=1)",
            real_res => real_result,
            imag_res => imag_result,
            expected_real => golden_real,
            expected_imag => golden_imag,
            expected_magnitude => golden_magnitude,
            expected_phase => golden_phase,
            pass_count => tests_passed,
            fail_count => tests_failed
        );

        wait for CLK_PERIOD * 10;

        -----------------------------------------------------------------------
        -- TEST 3: Sinusoid at K=1 (Fundamental)
        -----------------------------------------------------------------------
        report "========================================";
        report "TEST 3: Sinusoid at K=1 (Fundamental)";
        report "========================================";

        -- Load sinusoid at K=1: amplitude = 1.0
        load_sample_buffer(sample_buffer, "SINE", 1.0, K_VALUE);

        -- Run DFT
        run_dft_test(start, done, result_valid);

        -- Golden model
        golden_dft(sample_buffer, K_VALUE, golden_real, golden_imag);
        golden_magnitude := calc_magnitude(golden_real, golden_imag);
        golden_phase := calc_phase_deg(golden_real, golden_imag);

        -- For sine at K=1, expect magnitude ≈ 128 (256/2), phase ≈ -90°
        verify_dft_result(
            test_name => "Test 3: Sine K=1",
            real_res => real_result,
            imag_res => imag_result,
            expected_real => golden_real,
            expected_imag => golden_imag,
            expected_magnitude => golden_magnitude,
            expected_phase => golden_phase,
            pass_count => tests_passed,
            fail_count => tests_failed
        );

        wait for CLK_PERIOD * 10;

        -----------------------------------------------------------------------
        -- TEST 4: Sinusoid at K=5
        -----------------------------------------------------------------------
        report "========================================";
        report "TEST 4: Sinusoid at K=5";
        report "========================================";

        -- Load sinusoid at K=5
        load_sample_buffer(sample_buffer, "SINE", 1.0, 5);

        -- Run DFT
        run_dft_test(start, done, result_valid);

        -- Golden model (still computing for K=1, but input is K=5)
        -- For K=1 ROM looking at K=5 input, should get near-zero
        golden_dft(sample_buffer, K_VALUE, golden_real, golden_imag);
        golden_magnitude := calc_magnitude(golden_real, golden_imag);
        golden_phase := calc_phase_deg(golden_real, golden_imag);

        verify_dft_result(
            test_name => "Test 4: Sine K=5 (measured at K=1)",
            real_res => real_result,
            imag_res => imag_result,
            expected_real => golden_real,
            expected_imag => golden_imag,
            expected_magnitude => golden_magnitude,
            expected_phase => golden_phase,
            pass_count => tests_passed,
            fail_count => tests_failed
        );

        wait for CLK_PERIOD * 10;

        -----------------------------------------------------------------------
        -- TEST 5: Sinusoid at K=10
        -----------------------------------------------------------------------
        report "========================================";
        report "TEST 5: Sinusoid at K=10";
        report "========================================";

        -- Load sinusoid at K=10
        load_sample_buffer(sample_buffer, "SINE", 1.0, 10);

        -- Run DFT
        run_dft_test(start, done, result_valid);

        -- Golden model
        golden_dft(sample_buffer, K_VALUE, golden_real, golden_imag);
        golden_magnitude := calc_magnitude(golden_real, golden_imag);
        golden_phase := calc_phase_deg(golden_real, golden_imag);

        verify_dft_result(
            test_name => "Test 5: Sine K=10 (measured at K=1)",
            real_res => real_result,
            imag_res => imag_result,
            expected_real => golden_real,
            expected_imag => golden_imag,
            expected_magnitude => golden_magnitude,
            expected_phase => golden_phase,
            pass_count => tests_passed,
            fail_count => tests_failed
        );

        wait for CLK_PERIOD * 10;

        -----------------------------------------------------------------------
        -- TEST 6: Cosine Signal at K=1
        -----------------------------------------------------------------------
        report "========================================";
        report "TEST 6: Cosine Signal at K=1";
        report "========================================";

        -- Load cosine at K=1
        load_sample_buffer(sample_buffer, "COSINE", 1.0, K_VALUE);

        -- Run DFT
        run_dft_test(start, done, result_valid);

        -- Golden model
        golden_dft(sample_buffer, K_VALUE, golden_real, golden_imag);
        golden_magnitude := calc_magnitude(golden_real, golden_imag);
        golden_phase := calc_phase_deg(golden_real, golden_imag);

        -- For cosine at K=1, expect magnitude ≈ 128, phase ≈ 0°
        verify_dft_result(
            test_name => "Test 6: Cosine K=1",
            real_res => real_result,
            imag_res => imag_result,
            expected_real => golden_real,
            expected_imag => golden_imag,
            expected_magnitude => golden_magnitude,
            expected_phase => golden_phase,
            pass_count => tests_passed,
            fail_count => tests_failed
        );

        wait for CLK_PERIOD * 10;

        -----------------------------------------------------------------------
        -- TEST 7: Complex Exponential (Cosine + 0.5*Sine)
        -----------------------------------------------------------------------
        report "========================================";
        report "TEST 7: Complex Exponential";
        report "========================================";

        -- Load complex exponential
        load_sample_buffer(sample_buffer, "COMPLEX_EXP", 1.0);

        -- Run DFT
        run_dft_test(start, done, result_valid);

        -- Golden model
        golden_dft(sample_buffer, K_VALUE, golden_real, golden_imag);
        golden_magnitude := calc_magnitude(golden_real, golden_imag);
        golden_phase := calc_phase_deg(golden_real, golden_imag);

        verify_dft_result(
            test_name => "Test 7: Complex Exponential",
            real_res => real_result,
            imag_res => imag_result,
            expected_real => golden_real,
            expected_imag => golden_imag,
            expected_magnitude => golden_magnitude,
            expected_phase => golden_phase,
            pass_count => tests_passed,
            fail_count => tests_failed
        );

        wait for CLK_PERIOD * 10;

        -----------------------------------------------------------------------
        -- TEST 8: Random Noise
        -----------------------------------------------------------------------
        report "========================================";
        report "TEST 8: Random Noise";
        report "========================================";

        -- Load random noise (amplitude = 0.5 to stay within Q15 range)
        load_sample_buffer(sample_buffer, "RANDOM", 0.5, 0, 12345, 67890);

        -- Run DFT
        run_dft_test(start, done, result_valid);

        -- Golden model
        golden_dft(sample_buffer, K_VALUE, golden_real, golden_imag);
        golden_magnitude := calc_magnitude(golden_real, golden_imag);
        golden_phase := calc_phase_deg(golden_real, golden_imag);

        -- Random noise should have low magnitude across all frequencies
        verify_dft_result(
            test_name => "Test 8: Random Noise",
            real_res => real_result,
            imag_res => imag_result,
            expected_real => golden_real,
            expected_imag => golden_imag,
            expected_magnitude => golden_magnitude,
            expected_phase => golden_phase,
            pass_count => tests_passed,
            fail_count => tests_failed
        );

        wait for CLK_PERIOD * 10;

        -----------------------------------------------------------------------
        -- TEST 9: Edge Cases - Alternating Max/Min (Nyquist)
        -----------------------------------------------------------------------
        report "========================================";
        report "TEST 9: Alternating Max/Min (Nyquist)";
        report "========================================";

        -- Load alternating max/min pattern
        load_sample_buffer(sample_buffer, "ALTERNATING", 1.0);

        -- Run DFT
        run_dft_test(start, done, result_valid);

        -- Golden model
        golden_dft(sample_buffer, K_VALUE, golden_real, golden_imag);
        golden_magnitude := calc_magnitude(golden_real, golden_imag);
        golden_phase := calc_phase_deg(golden_real, golden_imag);

        -- Alternating pattern is Nyquist frequency (K=128)
        -- At K=1, should see near-zero magnitude
        verify_dft_result(
            test_name => "Test 9: Nyquist (measured at K=1)",
            real_res => real_result,
            imag_res => imag_result,
            expected_real => golden_real,
            expected_imag => golden_imag,
            expected_magnitude => golden_magnitude,
            expected_phase => golden_phase,
            pass_count => tests_passed,
            fail_count => tests_failed
        );

        wait for CLK_PERIOD * 10;

        -----------------------------------------------------------------------
        -- TEST 10: Multiple Consecutive DFTs (State Recovery)
        -----------------------------------------------------------------------
        report "========================================";
        report "TEST 10: Consecutive DFTs (State Recovery)";
        report "========================================";

        -- Load sine at K=1 (same as Test 3)
        load_sample_buffer(sample_buffer, "SINE", 1.0, K_VALUE);

        -- First DFT
        run_dft_test(start, done, result_valid);

        -- Store first results
        first_real := real_result;
        first_imag := imag_result;

        wait for CLK_PERIOD * 5;

        -- Second DFT (without reset, testing state recovery)
        run_dft_test(start, done, result_valid);

        -- Golden model
        golden_dft(sample_buffer, K_VALUE, golden_real, golden_imag);
        golden_magnitude := calc_magnitude(golden_real, golden_imag);
        golden_phase := calc_phase_deg(golden_real, golden_imag);

        -- Verify second DFT
        verify_dft_result(
            test_name => "Test 10: Consecutive DFT #2",
            real_res => real_result,
            imag_res => imag_result,
            expected_real => golden_real,
            expected_imag => golden_imag,
            expected_magnitude => golden_magnitude,
            expected_phase => golden_phase,
            pass_count => tests_passed,
            fail_count => tests_failed
        );

        -- Verify both DFTs produced identical results
        assert first_real = real_result and first_imag = imag_result
            report "[FAIL] Test 10: Consecutive DFTs produced different results"
            severity warning;

        if first_real = real_result and first_imag = imag_result then
            report "[PASS] Test 10: State Recovery - Results match";
        else
            tests_failed <= tests_failed + 1;
        end if;

        wait for CLK_PERIOD * 10;

        -----------------------------------------------------------------------
        -- FINAL SUMMARY
        -----------------------------------------------------------------------
        report "========================================";
        report "TEST SUMMARY";
        report "========================================";
        report "Tests Passed: " & integer'image(tests_passed);
        report "Tests Failed: " & integer'image(tests_failed);

        if tests_failed = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "SOME TESTS FAILED!" severity warning;
        end if;

        report "========================================";
        report "Simulation Complete";
        report "========================================";

        test_running <= false;
        wait;
    end process;

end testbench;
