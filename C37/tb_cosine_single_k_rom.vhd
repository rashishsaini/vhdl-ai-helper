--------------------------------------------------------------------------------
-- Testbench: tb_cosine_single_k_rom
-- DUT: cosine_single_k_rom (ROM-based cosine coefficient generator)
--
-- Test Coverage:
--   1. Reset behavior and initialization
--   2. Enable/disable functionality and data_valid timing
--   3. All 256 memory locations (n_addr = 0 to 255)
--   4. Q1.15 fixed-point accuracy validation with golden model
--   5. Multiple K_VALUE configurations (k=1, k=2, k=3)
--   6. Boundary conditions (min/max addresses, wraparound)
--   7. Random address sequences
--   8. Back-to-back reads (stress testing)
--   9. Enable toggling during operation
--  10. Pipeline behavior and latency verification
--
-- Expected Simulation Time: ~90 us
-- Pass/Fail Criteria: All assertions pass, zero tolerance errors
--
-- Note: Q1.15 format represents signed fixed-point [-1.0, +0.99997]
--       with 1 sign bit and 15 fractional bits (scale factor = 2^15 = 32767)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity tb_cosine_single_k_rom is
    -- Testbench has no ports
end tb_cosine_single_k_rom;

architecture testbench of tb_cosine_single_k_rom is

    -------------------------------------------------------------------------
    -- CONFIGURATION SECTION
    -------------------------------------------------------------------------

    -- Clock parameters
    constant CLK_PERIOD     : time := 10 ns;     -- 100 MHz
    constant CLK_DUTY_CYCLE : real := 0.5;

    -- DUT configuration parameters (multiple test configurations)
    constant WINDOW_SIZE_TB : integer := 256;
    constant COEFF_WIDTH_TB : integer := 16;

    -- Test control parameters
    constant MAX_TOLERANCE  : real := 1.0 / 32767.0;  -- 1 LSB tolerance in Q1.15
    constant PI             : real := MATH_PI;

    -- Test scenario counters
    signal test_count       : integer := 0;
    signal pass_count       : integer := 0;
    signal fail_count       : integer := 0;

    -------------------------------------------------------------------------
    -- COMPONENT DECLARATION
    -------------------------------------------------------------------------

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

    -------------------------------------------------------------------------
    -- SIGNAL DECLARATIONS
    -------------------------------------------------------------------------

    -- Clock and reset
    signal clk_tb           : std_logic := '0';
    signal rst_tb           : std_logic := '0';
    signal sim_done         : boolean := false;

    -- DUT #1: K_VALUE = 1 (fundamental frequency)
    signal enable_1         : std_logic := '1';
    signal n_addr_1         : std_logic_vector(7 downto 0) := (others => '0');
    signal cos_coeff_1      : std_logic_vector(15 downto 0);
    signal data_valid_1     : std_logic;

    -- DUT #2: K_VALUE = 2 (second harmonic)
    signal enable_2         : std_logic := '1';
    signal n_addr_2         : std_logic_vector(7 downto 0) := (others => '0');
    signal cos_coeff_2      : std_logic_vector(15 downto 0);
    signal data_valid_2     : std_logic;

    -- DUT #3: K_VALUE = 3 (third harmonic)
    signal enable_3         : std_logic := '1';
    signal n_addr_3         : std_logic_vector(7 downto 0) := (others => '0');
    signal cos_coeff_3      : std_logic_vector(15 downto 0);
    signal data_valid_3     : std_logic;

    -------------------------------------------------------------------------
    -- HELPER FUNCTIONS
    -------------------------------------------------------------------------

    -- Convert std_logic_vector to hex string (for older VHDL versions)
    function slv_to_hex(slv : std_logic_vector) return string is
        variable result : string(1 to (slv'length + 3) / 4);
        variable nibble : std_logic_vector(3 downto 0);
        variable pos : integer := 1;
        variable temp : std_logic_vector(slv'length-1 downto 0);
        variable padded : std_logic_vector(((slv'length+3)/4)*4-1 downto 0);
    begin
        temp := slv;
        padded := (others => '0');
        padded(slv'length-1 downto 0) := temp;

        for i in result'range loop
            nibble := padded(padded'left - (i-1)*4 downto padded'left - (i-1)*4 - 3);
            case nibble is
                when "0000" => result(i) := '0';
                when "0001" => result(i) := '1';
                when "0010" => result(i) := '2';
                when "0011" => result(i) := '3';
                when "0100" => result(i) := '4';
                when "0101" => result(i) := '5';
                when "0110" => result(i) := '6';
                when "0111" => result(i) := '7';
                when "1000" => result(i) := '8';
                when "1001" => result(i) := '9';
                when "1010" => result(i) := 'A';
                when "1011" => result(i) := 'B';
                when "1100" => result(i) := 'C';
                when "1101" => result(i) := 'D';
                when "1110" => result(i) := 'E';
                when "1111" => result(i) := 'F';
                when others => result(i) := 'X';
            end case;
        end loop;
        return result;
    end function;

    -- Convert Q1.15 signed fixed-point to real
    function q15_to_real(q15_val : std_logic_vector(15 downto 0)) return real is
        variable signed_val : signed(15 downto 0);
        variable int_val : integer;
        variable real_val : real;
    begin
        signed_val := signed(q15_val);
        int_val := to_integer(signed_val);
        real_val := real(int_val) / 32767.0;
        return real_val;
    end function;

    -- Golden model: Calculate expected cosine value
    function golden_cosine(n : integer; k : integer; window_size : integer) return real is
        variable angle : real;
        variable cos_val : real;
    begin
        angle := 2.0 * PI * real(k) * real(n) / real(window_size);
        cos_val := cos(angle);
        return cos_val;
    end function;

    -- Convert real to Q1.15 (matches DUT conversion)
    function real_to_q15(real_val : real) return std_logic_vector is
        variable temp_int : integer;
        variable result : std_logic_vector(15 downto 0);
    begin
        if real_val > 0.99996 then
            temp_int := 32767;
        elsif real_val < -1.0 then
            temp_int := -32768;
        else
            temp_int := integer(real_val * 32767.0);
        end if;
        result := std_logic_vector(to_signed(temp_int, 16));
        return result;
    end function;

    -- Check if two real values are within tolerance
    function within_tolerance(actual, expected, tolerance : real) return boolean is
        variable diff : real;
    begin
        diff := abs(actual - expected);
        return diff <= tolerance;
    end function;

    -------------------------------------------------------------------------
    -- VERIFICATION PROCEDURES
    -------------------------------------------------------------------------

    -- Procedure to check cosine value against golden model
    procedure check_cosine_value(
        constant n_val          : in integer;
        constant k_val          : in integer;
        signal   cos_output     : in std_logic_vector(15 downto 0);
        signal   data_valid_sig : in std_logic;
        constant test_name      : in string;
        signal   test_counter   : inout integer;
        signal   pass_counter   : inout integer;
        signal   fail_counter   : inout integer
    ) is
        variable actual_real    : real;
        variable expected_real  : real;
        variable expected_q15   : std_logic_vector(15 downto 0);
        variable error_val      : real;
    begin
        test_counter <= test_counter + 1;

        -- Calculate expected value from golden model
        expected_real := golden_cosine(n_val, k_val, WINDOW_SIZE_TB);
        expected_q15  := real_to_q15(expected_real);

        -- Convert actual Q1.15 output to real
        actual_real := q15_to_real(cos_output);
        error_val := abs(actual_real - expected_real);

        -- Check data_valid signal
        assert data_valid_sig = '1'
            report "[" & test_name & "] DATA_VALID CHECK FAILED | " &
                   "Expected: '1' | Actual: '" & std_logic'image(data_valid_sig) & "'"
            severity error;

        -- Check cosine value within tolerance
        if within_tolerance(actual_real, expected_real, MAX_TOLERANCE) then
            pass_counter <= pass_counter + 1;
            report "[" & test_name & "] PASS | " &
                   "n=" & integer'image(n_val) & " k=" & integer'image(k_val) & " | " &
                   "Expected: " & real'image(expected_real) & " | " &
                   "Actual: " & real'image(actual_real) & " | " &
                   "Error: " & real'image(error_val)
            severity note;
        else
            fail_counter <= fail_counter + 1;
            report "[" & test_name & "] FAIL | " &
                   "n=" & integer'image(n_val) & " k=" & integer'image(k_val) & " | " &
                   "Expected: " & real'image(expected_real) & " | " &
                   "Actual: " & real'image(actual_real) & " | " &
                   "Error: " & real'image(error_val) & " | " &
                   "Exceeds tolerance: " & real'image(MAX_TOLERANCE)
            severity failure;
        end if;

        -- Also check exact bit pattern match (should be identical to golden)
        assert cos_output = expected_q15
            report "[" & test_name & "] BIT PATTERN MISMATCH | " &
                   "Expected (hex): " & slv_to_hex(expected_q15) & " | " &
                   "Actual (hex): " & slv_to_hex(cos_output)
            severity warning;
    end procedure;

begin

    -------------------------------------------------------------------------
    -- DUT INSTANTIATION
    -------------------------------------------------------------------------

    -- DUT Instance #1: K_VALUE = 1
    DUT_K1: cosine_single_k_rom
        generic map (
            WINDOW_SIZE => WINDOW_SIZE_TB,
            COEFF_WIDTH => COEFF_WIDTH_TB,
            K_VALUE     => 1
        )
        port map (
            clk        => clk_tb,
            rst        => rst_tb,
            enable     => enable_1,
            n_addr     => n_addr_1,
            cos_coeff  => cos_coeff_1,
            data_valid => data_valid_1
        );

    -- DUT Instance #2: K_VALUE = 2
    DUT_K2: cosine_single_k_rom
        generic map (
            WINDOW_SIZE => WINDOW_SIZE_TB,
            COEFF_WIDTH => COEFF_WIDTH_TB,
            K_VALUE     => 2
        )
        port map (
            clk        => clk_tb,
            rst        => rst_tb,
            enable     => enable_2,
            n_addr     => n_addr_2,
            cos_coeff  => cos_coeff_2,
            data_valid => data_valid_2
        );

    -- DUT Instance #3: K_VALUE = 3
    DUT_K3: cosine_single_k_rom
        generic map (
            WINDOW_SIZE => WINDOW_SIZE_TB,
            COEFF_WIDTH => COEFF_WIDTH_TB,
            K_VALUE     => 3
        )
        port map (
            clk        => clk_tb,
            rst        => rst_tb,
            enable     => enable_3,
            n_addr     => n_addr_3,
            cos_coeff  => cos_coeff_3,
            data_valid => data_valid_3
        );

    -------------------------------------------------------------------------
    -- CLOCK GENERATION
    -------------------------------------------------------------------------

    clk_process: process
    begin
        while not sim_done loop
            clk_tb <= '0';
            wait for CLK_PERIOD * (1.0 - CLK_DUTY_CYCLE);
            clk_tb <= '1';
            wait for CLK_PERIOD * CLK_DUTY_CYCLE;
        end loop;
        wait;
    end process;

    -------------------------------------------------------------------------
    -- CONCURRENT ASSERTIONS
    -------------------------------------------------------------------------

    -- Assertion: data_valid should be low during reset
    assert not (rst_tb = '1' and data_valid_1 = '1')
        report "[CONCURRENT] K1 data_valid asserted during reset"
        severity error;

    assert not (rst_tb = '1' and data_valid_2 = '1')
        report "[CONCURRENT] K2 data_valid asserted during reset"
        severity error;

    assert not (rst_tb = '1' and data_valid_3 = '1')
        report "[CONCURRENT] K3 data_valid asserted during reset"
        severity error;

    -- Assertion: data_valid should be low when enable is low (after pipeline delay)
    -- Note: This is a simplified check; full temporal checking is in main process

    -------------------------------------------------------------------------
    -- MAIN TEST SEQUENCER
    -------------------------------------------------------------------------

    test_process: process
        variable seed1, seed2 : integer := 42;
        variable rand_real : real;
        variable rand_addr : integer;
        variable val1, val2 : std_logic_vector(15 downto 0);
    begin

        -----------------------------------------------------------------------
        -- TEST PHASE 1: RESET BEHAVIOR
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "PHASE 1: RESET BEHAVIOR TEST" severity note;
        report "========================================" severity note;

        -- Assert reset
        rst_tb <= '1';
        enable_1 <= '1';
        enable_2 <= '1';
        enable_3 <= '1';
        n_addr_1 <= "00001010";  -- Non-zero address during reset (10)
        n_addr_2 <= "00010101";  -- Address 21
        n_addr_3 <= "00011011";  -- Address 27

        wait for CLK_PERIOD * 3;

        -- Check outputs during reset
        assert data_valid_1 = '0'
            report "[RESET] K1 data_valid should be '0' during reset | " &
                   "Actual: '" & std_logic'image(data_valid_1) & "'"
            severity error;

        assert data_valid_2 = '0'
            report "[RESET] K2 data_valid should be '0' during reset | " &
                   "Actual: '" & std_logic'image(data_valid_2) & "'"
            severity error;

        assert data_valid_3 = '0'
            report "[RESET] K3 data_valid should be '0' during reset | " &
                   "Actual: '" & std_logic'image(data_valid_3) & "'"
            severity error;

        assert cos_coeff_1 = x"0000"
            report "[RESET] K1 cos_coeff should be 0x0000 during reset | " &
                   "Actual: " & slv_to_hex(cos_coeff_1)
            severity error;

        report "[RESET] Reset behavior verified successfully" severity note;

        -- Deassert reset
        rst_tb <= '0';
        wait for CLK_PERIOD;

        -----------------------------------------------------------------------
        -- TEST PHASE 2: ENABLE/DISABLE FUNCTIONALITY
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "PHASE 2: ENABLE/DISABLE CONTROL TEST" severity note;
        report "========================================" severity note;

        -- Test with enable = '0'
        enable_1 <= '0';
        n_addr_1 <= "00000000";
        wait for CLK_PERIOD;
        wait for CLK_PERIOD;

        assert data_valid_1 = '0'
            report "[ENABLE] K1 data_valid should be '0' when enable='0' | " &
                   "Actual: '" & std_logic'image(data_valid_1) & "'"
            severity error;

        report "[ENABLE] data_valid correctly responds to enable='0'" severity note;

        -- Re-enable and check data_valid goes high
        enable_1 <= '1';
        n_addr_1 <= "00000001";
        wait for CLK_PERIOD;
        wait for CLK_PERIOD;

        assert data_valid_1 = '1'
            report "[ENABLE] K1 data_valid should be '1' when enable='1' | " &
                   "Actual: '" & std_logic'image(data_valid_1) & "'"
            severity error;

        report "[ENABLE] data_valid correctly responds to enable='1'" severity note;

        -- Test enable toggling
        enable_1 <= '0';
        wait for CLK_PERIOD;
        wait for CLK_PERIOD;
        assert data_valid_1 = '0'
            report "[ENABLE] Toggle test failed - data_valid should be '0'"
            severity error;

        enable_1 <= '1';
        wait for CLK_PERIOD;
        wait for CLK_PERIOD;
        assert data_valid_1 = '1'
            report "[ENABLE] Toggle test failed - data_valid should be '1'"
            severity error;

        report "[ENABLE] Enable toggle functionality verified" severity note;

        -----------------------------------------------------------------------
        -- TEST PHASE 3: PIPELINE LATENCY VERIFICATION
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "PHASE 3: PIPELINE LATENCY TEST" severity note;
        report "========================================" severity note;

        -- Check that output appears 1 clock cycle after address change
        n_addr_1 <= "00000101";  -- Address n=5
        wait for 1 ns;  -- Delta delay
        assert data_valid_1 = '1'
            report "[LATENCY] data_valid should still be high from previous cycle"
            severity error;

        wait until rising_edge(clk_tb);
        wait for 1 ns;

        -- Now data should reflect new address (n=5, k=1)
        check_cosine_value(5, 1, cos_coeff_1, data_valid_1,
                          "LATENCY", test_count, pass_count, fail_count);

        report "[LATENCY] 1-cycle pipeline latency verified" severity note;

        -----------------------------------------------------------------------
        -- TEST PHASE 4: EXHAUSTIVE ADDRESS SWEEP (K=1)
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "PHASE 4: EXHAUSTIVE SWEEP - ALL 256 LOCATIONS (K=1)" severity note;
        report "========================================" severity note;

        enable_1 <= '1';

        for n in 0 to WINDOW_SIZE_TB - 1 loop
            n_addr_1 <= std_logic_vector(to_unsigned(n, 8));
            wait until rising_edge(clk_tb);
            wait for 1 ns;  -- Allow signals to settle

            check_cosine_value(n, 1, cos_coeff_1, data_valid_1,
                              "SWEEP_K1", test_count, pass_count, fail_count);
        end loop;

        report "[SWEEP_K1] Completed all 256 memory locations" severity note;

        -----------------------------------------------------------------------
        -- TEST PHASE 5: EXHAUSTIVE ADDRESS SWEEP (K=2)
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "PHASE 5: EXHAUSTIVE SWEEP - ALL 256 LOCATIONS (K=2)" severity note;
        report "========================================" severity note;

        enable_2 <= '1';

        for n in 0 to WINDOW_SIZE_TB - 1 loop
            n_addr_2 <= std_logic_vector(to_unsigned(n, 8));
            wait until rising_edge(clk_tb);
            wait for 1 ns;

            check_cosine_value(n, 2, cos_coeff_2, data_valid_2,
                              "SWEEP_K2", test_count, pass_count, fail_count);
        end loop;

        report "[SWEEP_K2] Completed all 256 memory locations" severity note;

        -----------------------------------------------------------------------
        -- TEST PHASE 6: EXHAUSTIVE ADDRESS SWEEP (K=3)
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "PHASE 6: EXHAUSTIVE SWEEP - ALL 256 LOCATIONS (K=3)" severity note;
        report "========================================" severity note;

        enable_3 <= '1';

        for n in 0 to WINDOW_SIZE_TB - 1 loop
            n_addr_3 <= std_logic_vector(to_unsigned(n, 8));
            wait until rising_edge(clk_tb);
            wait for 1 ns;

            check_cosine_value(n, 3, cos_coeff_3, data_valid_3,
                              "SWEEP_K3", test_count, pass_count, fail_count);
        end loop;

        report "[SWEEP_K3] Completed all 256 memory locations" severity note;

        -----------------------------------------------------------------------
        -- TEST PHASE 7: BOUNDARY CONDITIONS
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "PHASE 7: BOUNDARY CONDITIONS" severity note;
        report "========================================" severity note;

        -- Test address 0 (should give cos(0) = 1.0)
        n_addr_1 <= "00000000";
        wait until rising_edge(clk_tb);
        wait for 1 ns;
        check_cosine_value(0, 1, cos_coeff_1, data_valid_1,
                          "BOUNDARY_MIN", test_count, pass_count, fail_count);
        assert q15_to_real(cos_coeff_1) > 0.999
            report "[BOUNDARY] n=0 should give cos(0) approximately 1.0"
            severity error;

        -- Test address 255 (maximum valid address)
        n_addr_1 <= "11111111";  -- 255 in binary
        wait until rising_edge(clk_tb);
        wait for 1 ns;
        check_cosine_value(255, 1, cos_coeff_1, data_valid_1,
                          "BOUNDARY_MAX", test_count, pass_count, fail_count);

        -- Test N/4 point (should be close to 0 for k=1)
        n_addr_1 <= std_logic_vector(to_unsigned(64, 8));  -- 256/4 = 64
        wait until rising_edge(clk_tb);
        wait for 1 ns;
        check_cosine_value(64, 1, cos_coeff_1, data_valid_1,
                          "BOUNDARY_QUARTER", test_count, pass_count, fail_count);

        -- Test N/2 point (should be -1 for k=1)
        n_addr_1 <= std_logic_vector(to_unsigned(128, 8));  -- 256/2 = 128
        wait until rising_edge(clk_tb);
        wait for 1 ns;
        check_cosine_value(128, 1, cos_coeff_1, data_valid_1,
                          "BOUNDARY_HALF", test_count, pass_count, fail_count);
        assert q15_to_real(cos_coeff_1) < -0.999
            report "[BOUNDARY] n=128 (N/2) should give cos(pi) approximately -1.0"
            severity error;

        report "[BOUNDARY] All boundary conditions verified" severity note;

        -----------------------------------------------------------------------
        -- TEST PHASE 8: BACK-TO-BACK READS (STRESS TEST)
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "PHASE 8: BACK-TO-BACK READS STRESS TEST" severity note;
        report "========================================" severity note;

        -- Rapidly change addresses every cycle
        for n in 0 to 31 loop
            n_addr_1 <= std_logic_vector(to_unsigned(n, 8));
            n_addr_2 <= std_logic_vector(to_unsigned(n, 8));
            n_addr_3 <= std_logic_vector(to_unsigned(n, 8));
            wait until rising_edge(clk_tb);
            wait for 1 ns;

            -- Verify all three DUTs simultaneously
            check_cosine_value(n, 1, cos_coeff_1, data_valid_1,
                              "STRESS_K1", test_count, pass_count, fail_count);
            check_cosine_value(n, 2, cos_coeff_2, data_valid_2,
                              "STRESS_K2", test_count, pass_count, fail_count);
            check_cosine_value(n, 3, cos_coeff_3, data_valid_3,
                              "STRESS_K3", test_count, pass_count, fail_count);
        end loop;

        report "[STRESS] Back-to-back reads completed successfully" severity note;

        -----------------------------------------------------------------------
        -- TEST PHASE 9: RANDOM ADDRESS SEQUENCE
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "PHASE 9: RANDOM ADDRESS SEQUENCE" severity note;
        report "========================================" severity note;

        -- Generate 100 random addresses
        for i in 1 to 100 loop
            uniform(seed1, seed2, rand_real);
            rand_addr := integer(rand_real * real(WINDOW_SIZE_TB - 1));

            n_addr_1 <= std_logic_vector(to_unsigned(rand_addr, 8));
            wait until rising_edge(clk_tb);
            wait for 1 ns;

            check_cosine_value(rand_addr, 1, cos_coeff_1, data_valid_1,
                              "RANDOM", test_count, pass_count, fail_count);
        end loop;

        report "[RANDOM] 100 random address tests completed" severity note;

        -----------------------------------------------------------------------
        -- TEST PHASE 10: ENABLE TOGGLING DURING OPERATION
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "PHASE 10: ENABLE TOGGLING DURING READS" severity note;
        report "========================================" severity note;

        for n in 0 to 15 loop
            -- Set address
            n_addr_1 <= std_logic_vector(to_unsigned(n, 8));

            -- Enable for one cycle
            enable_1 <= '1';
            wait until rising_edge(clk_tb);
            wait for 1 ns;

            check_cosine_value(n, 1, cos_coeff_1, data_valid_1,
                              "TOGGLE_EN", test_count, pass_count, fail_count);

            -- Disable for one cycle
            enable_1 <= '0';
            wait until rising_edge(clk_tb);
            wait for 1 ns;

            assert data_valid_1 = '0'
                report "[TOGGLE] data_valid should be '0' when enable toggles low"
                severity error;
        end loop;

        enable_1 <= '1';  -- Re-enable
        report "[TOGGLE] Enable toggling test completed" severity note;

        -----------------------------------------------------------------------
        -- TEST PHASE 11: SYMMETRY VERIFICATION
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "PHASE 11: COSINE SYMMETRY VERIFICATION" severity note;
        report "========================================" severity note;

        -- Verify cos(x) = cos(2*pi - x) symmetry
        -- For k=1: cos(2*pi*1*n/256) should equal cos(2*pi*1*(256-n)/256)
        for n in 1 to 127 loop
            -- Read cos(2*pi*n/256)
            n_addr_1 <= std_logic_vector(to_unsigned(n, 8));
            wait until rising_edge(clk_tb);
            wait for 1 ns;

            val1 := cos_coeff_1;

            -- Read cos(2*pi*(256-n)/256) = cos(2*pi - 2*pi*n/256)
            n_addr_1 <= std_logic_vector(to_unsigned(WINDOW_SIZE_TB - n, 8));
            wait until rising_edge(clk_tb);
            wait for 1 ns;

            val2 := cos_coeff_1;

            assert val1 = val2
                report "[SYMMETRY] Cosine symmetry violated | " &
                       "cos(n=" & integer'image(n) & ") = " & slv_to_hex(val1) & " | " &
                       "cos(n=" & integer'image(WINDOW_SIZE_TB - n) & ") = " & slv_to_hex(val2)
                severity error;
        end loop;

        report "[SYMMETRY] Cosine symmetry verified" severity note;

        -----------------------------------------------------------------------
        -- TEST PHASE 12: SPECIAL VALUE VERIFICATION
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "PHASE 12: SPECIAL COSINE VALUES" severity note;
        report "========================================" severity note;

        -- For K=2, verify cos(0) = 1
        n_addr_2 <= "00000000";  -- n=0
        wait until rising_edge(clk_tb);
        wait for 1 ns;
        assert q15_to_real(cos_coeff_2) > 0.999
            report "[SPECIAL] K=2, n=0 should give cos(0) = 1.0"
            severity error;

        -- For K=2, verify cos(pi) = -1 at n=64 (2*pi*2*64/256 = pi)
        n_addr_2 <= std_logic_vector(to_unsigned(64, 8));
        wait until rising_edge(clk_tb);
        wait for 1 ns;
        assert q15_to_real(cos_coeff_2) < -0.999
            report "[SPECIAL] K=2, n=64 should give cos(pi) = -1.0"
            severity error;

        -- For K=3, verify cos(0) = 1
        n_addr_3 <= "00000000";
        wait until rising_edge(clk_tb);
        wait for 1 ns;
        assert q15_to_real(cos_coeff_3) > 0.999
            report "[SPECIAL] K=3, n=0 should give cos(0) = 1.0"
            severity error;

        report "[SPECIAL] Special value verification completed" severity note;

        -----------------------------------------------------------------------
        -- TEST PHASE 13: RESET DURING OPERATION
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "PHASE 13: RESET DURING OPERATION" severity note;
        report "========================================" severity note;

        -- Set up active read
        n_addr_1 <= "00010101";
        enable_1 <= '1';
        wait until rising_edge(clk_tb);
        wait for 1 ns;

        assert data_valid_1 = '1'
            report "[RESET_OP] data_valid should be high before reset"
            severity error;

        -- Apply reset during operation
        rst_tb <= '1';
        wait for CLK_PERIOD;

        assert data_valid_1 = '0'
            report "[RESET_OP] data_valid should clear immediately on reset"
            severity error;

        assert cos_coeff_1 = x"0000"
            report "[RESET_OP] cos_coeff should clear to 0x0000 on reset"
            severity error;

        -- Release reset and verify recovery
        rst_tb <= '0';
        wait until rising_edge(clk_tb);
        wait for 1 ns;

        check_cosine_value(21, 1, cos_coeff_1, data_valid_1,
                          "RESET_RECOVERY", test_count, pass_count, fail_count);

        report "[RESET_OP] Reset during operation verified" severity note;

        -----------------------------------------------------------------------
        -- FINAL REPORT GENERATION
        -----------------------------------------------------------------------
        report "========================================" severity note;
        report "SIMULATION COMPLETE - FINAL SUMMARY" severity note;
        report "========================================" severity note;
        report "Total Tests:  " & integer'image(test_count) severity note;
        report "Tests Passed: " & integer'image(pass_count) severity note;
        report "Tests Failed: " & integer'image(fail_count) severity note;

        if fail_count = 0 then
            report "*** ALL TESTS PASSED ***" severity note;
        else
            report "*** SOME TESTS FAILED ***" severity error;
        end if;

        report "Coverage Summary:" severity note;
        report "  - Reset behavior: COVERED" severity note;
        report "  - Enable control: COVERED" severity note;
        report "  - Pipeline latency: COVERED" severity note;
        report "  - All 256 addresses (K=1,2,3): COVERED" severity note;
        report "  - Boundary conditions: COVERED" severity note;
        report "  - Back-to-back reads: COVERED" severity note;
        report "  - Random sequences: COVERED" severity note;
        report "  - Enable toggling: COVERED" severity note;
        report "  - Cosine symmetry: COVERED" severity note;
        report "  - Special values: COVERED" severity note;
        report "  - Reset during operation: COVERED" severity note;
        report "========================================" severity note;

        -- End simulation
        sim_done <= true;
        wait;

    end process test_process;

end testbench;
