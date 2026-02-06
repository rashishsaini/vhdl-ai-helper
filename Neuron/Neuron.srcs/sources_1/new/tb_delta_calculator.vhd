--------------------------------------------------------------------------------
-- Testbench: tb_delta_calculator
-- Description: Comprehensive test for delta_calculator module
--              Tests δ = error × σ'(z) computation
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_delta_calculator is
end entity tb_delta_calculator;

architecture sim of tb_delta_calculator is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : integer := 16;
    constant FRAC_BITS  : integer := 13;
    
    -- Q2.13 constants
    constant ONE        : signed(DATA_WIDTH-1 downto 0) := to_signed(8192, DATA_WIDTH);   -- 1.0
    constant HALF       : signed(DATA_WIDTH-1 downto 0) := to_signed(4096, DATA_WIDTH);   -- 0.5
    constant QUARTER    : signed(DATA_WIDTH-1 downto 0) := to_signed(2048, DATA_WIDTH);   -- 0.25
    constant NEG_ONE    : signed(DATA_WIDTH-1 downto 0) := to_signed(-8192, DATA_WIDTH);  -- -1.0
    constant NEG_HALF   : signed(DATA_WIDTH-1 downto 0) := to_signed(-4096, DATA_WIDTH);  -- -0.5
    constant ZERO_VAL   : signed(DATA_WIDTH-1 downto 0) := to_signed(0, DATA_WIDTH);
    constant SAT_MAX    : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);
    constant SAT_MIN    : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH);

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component delta_calculator is
        generic (
            DATA_WIDTH    : integer := 16;
            FRAC_BITS     : integer := 13;
            REGISTERED    : boolean := true
        );
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            error_in      : in  signed(DATA_WIDTH-1 downto 0);
            z_in          : in  signed(DATA_WIDTH-1 downto 0);
            enable        : in  std_logic;
            delta_out     : out signed(DATA_WIDTH-1 downto 0);
            valid         : out std_logic;
            is_active     : out std_logic;
            zero_delta    : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal error_in   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal z_in       : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal enable     : std_logic := '0';
    signal delta_out  : signed(DATA_WIDTH-1 downto 0);
    signal valid      : std_logic;
    signal is_active  : std_logic;
    signal zero_delta : std_logic;
    
    -- Test tracking
    signal test_count  : integer := 0;
    signal error_count : integer := 0;
    signal sim_done    : boolean := false;
    
    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    function to_real(val : signed) return real is
    begin
        return real(to_integer(val)) / real(2**FRAC_BITS);
    end function;
    
    function to_fixed(val : real) return signed is
        variable temp : integer;
    begin
        temp := integer(val * real(2**FRAC_BITS));
        if temp > 32767 then
            temp := 32767;
        elsif temp < -32768 then
            temp := -32768;
        end if;
        return to_signed(temp, DATA_WIDTH);
    end function;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD/2 when not sim_done else '0';

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : delta_calculator
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            FRAC_BITS  => FRAC_BITS,
            REGISTERED => true
        )
        port map (
            clk        => clk,
            rst        => rst,
            error_in   => error_in,
            z_in       => z_in,
            enable     => enable,
            delta_out  => delta_out,
            valid      => valid,
            is_active  => is_active,
            zero_delta => zero_delta
        );

    ---------------------------------------------------------------------------
    -- Test Process
    ---------------------------------------------------------------------------
    test_proc : process
        
        procedure run_test(
            test_name      : string;
            err_val        : signed(DATA_WIDTH-1 downto 0);
            z_val          : signed(DATA_WIDTH-1 downto 0);
            expected_delta : signed(DATA_WIDTH-1 downto 0);
            exp_active     : std_logic;
            tolerance      : integer := 2  -- Allow small rounding errors
        ) is
            variable delta_diff : integer;
        begin
            test_count <= test_count + 1;
            
            -- Apply inputs
            error_in <= err_val;
            z_in     <= z_val;
            enable   <= '1';
            
            wait until rising_edge(clk);
            enable <= '0';
            
            -- Wait for registered output
            wait until rising_edge(clk);
            wait for 1 ns;
            
            -- Check results
            delta_diff := abs(to_integer(delta_out) - to_integer(expected_delta));
            
            if delta_diff > tolerance then
                report "FAIL " & test_name & 
                       ": error=" & real'image(to_real(err_val)) &
                       ", z=" & real'image(to_real(z_val)) &
                       ", expected delta=" & real'image(to_real(expected_delta)) &
                       ", got=" & real'image(to_real(delta_out))
                    severity warning;
                error_count <= error_count + 1;
            else
                report "PASS " & test_name & 
                       ": delta=" & real'image(to_real(delta_out))
                    severity note;
            end if;
            
            -- Check is_active flag
            if is_active /= exp_active then
                report "FAIL " & test_name & " is_active: expected=" & 
                       std_logic'image(exp_active) & ", got=" & std_logic'image(is_active)
                    severity warning;
                error_count <= error_count + 1;
            end if;
            
            wait until rising_edge(clk);
        end procedure;
        
    begin
        -- Initialize
        rst      <= '1';
        enable   <= '0';
        error_in <= (others => '0');
        z_in     <= (others => '0');
        
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "========================================";
        report "Starting delta_calculator Tests";
        report "========================================";
        
        -----------------------------------------------------------------------
        -- Test Category 1: Active Neuron (z > 0)
        -- For ReLU: σ'(z) = 1, so δ = error × 1 = error
        -----------------------------------------------------------------------
        report "--- Category 1: Active Neuron (z > 0) ---";
        
        -- Test 1.1: Positive error, positive z
        run_test("1.1: err=0.5, z=1.0",
                 HALF, ONE, HALF, '1');
        
        -- Test 1.2: Negative error, positive z
        run_test("1.2: err=-0.5, z=1.0",
                 NEG_HALF, ONE, NEG_HALF, '1');
        
        -- Test 1.3: Error = 1.0, z = 0.25
        run_test("1.3: err=1.0, z=0.25",
                 ONE, QUARTER, ONE, '1');
        
        -- Test 1.4: Small positive error
        run_test("1.4: err=0.25, z=0.5",
                 QUARTER, HALF, QUARTER, '1');
        
        -- Test 1.5: Small z value (just above zero)
        run_test("1.5: err=1.0, z=0.001",
                 ONE, to_signed(8, DATA_WIDTH), ONE, '1');  -- z = 8/8192 ≈ 0.001
        
        -----------------------------------------------------------------------
        -- Test Category 2: Inactive Neuron (z <= 0)
        -- For ReLU: σ'(z) = 0, so δ = error × 0 = 0
        -----------------------------------------------------------------------
        report "--- Category 2: Inactive Neuron (z <= 0) ---";
        
        -- Test 2.1: z = 0 (exactly zero)
        run_test("2.1: err=1.0, z=0",
                 ONE, ZERO_VAL, ZERO_VAL, '0');
        
        -- Test 2.2: z negative
        run_test("2.2: err=1.0, z=-1.0",
                 ONE, NEG_ONE, ZERO_VAL, '0');
        
        -- Test 2.3: Large error, z negative
        run_test("2.3: err=3.0, z=-0.5",
                 to_signed(24576, DATA_WIDTH), NEG_HALF, ZERO_VAL, '0');
        
        -- Test 2.4: Negative error, z negative
        run_test("2.4: err=-2.0, z=-2.0",
                 to_signed(-16384, DATA_WIDTH), to_signed(-16384, DATA_WIDTH), ZERO_VAL, '0');
        
        -- Test 2.5: Small negative z
        run_test("2.5: err=0.5, z=-0.001",
                 HALF, to_signed(-8, DATA_WIDTH), ZERO_VAL, '0');
        
        -----------------------------------------------------------------------
        -- Test Category 3: Boundary Cases
        -----------------------------------------------------------------------
        report "--- Category 3: Boundary Cases ---";
        
        -- Test 3.1: Maximum positive error, active
        run_test("3.1: err=MAX, z=1.0",
                 SAT_MAX, ONE, SAT_MAX, '1');
        
        -- Test 3.2: Maximum negative error, active
        run_test("3.2: err=MIN, z=1.0",
                 SAT_MIN, ONE, SAT_MIN, '1');
        
        -- Test 3.3: Zero error, active
        run_test("3.3: err=0, z=1.0",
                 ZERO_VAL, ONE, ZERO_VAL, '1');
        
        -- Test 3.4: Maximum z value
        run_test("3.4: err=0.5, z=MAX",
                 HALF, SAT_MAX, HALF, '1');
        
        -- Test 3.5: Minimum z value (negative)
        run_test("3.5: err=0.5, z=MIN",
                 HALF, SAT_MIN, ZERO_VAL, '0');
        
        -----------------------------------------------------------------------
        -- Test Category 4: Zero Delta Flag
        -----------------------------------------------------------------------
        report "--- Category 4: Zero Delta Flag ---";
        
        -- Test 4.1: Zero delta due to inactive neuron
        error_in <= ONE;
        z_in     <= NEG_ONE;
        enable   <= '1';
        wait until rising_edge(clk);
        enable <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        test_count <= test_count + 1;
        if zero_delta /= '1' then
            report "FAIL 4.1: zero_delta should be '1' for inactive neuron"
                severity warning;
            error_count <= error_count + 1;
        else
            report "PASS 4.1: zero_delta='1' for inactive neuron" severity note;
        end if;
        wait until rising_edge(clk);
        
        -- Test 4.2: Non-zero delta for active neuron
        error_in <= ONE;
        z_in     <= ONE;
        enable   <= '1';
        wait until rising_edge(clk);
        enable <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        test_count <= test_count + 1;
        if zero_delta /= '0' then
            report "FAIL 4.2: zero_delta should be '0' for active neuron with non-zero error"
                severity warning;
            error_count <= error_count + 1;
        else
            report "PASS 4.2: zero_delta='0' for active neuron" severity note;
        end if;
        wait until rising_edge(clk);
        
        -- Test 4.3: Zero delta due to zero error (active neuron)
        error_in <= ZERO_VAL;
        z_in     <= ONE;
        enable   <= '1';
        wait until rising_edge(clk);
        enable <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        test_count <= test_count + 1;
        if zero_delta /= '1' then
            report "FAIL 4.3: zero_delta should be '1' for zero error"
                severity warning;
            error_count <= error_count + 1;
        else
            report "PASS 4.3: zero_delta='1' for zero error" severity note;
        end if;
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test Category 5: Valid Signal Behavior
        -----------------------------------------------------------------------
        report "--- Category 5: Valid Signal ---";
        
        -- Test 5.1: Valid goes high when enabled
        error_in <= HALF;
        z_in     <= ONE;
        enable   <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        -- Valid should still be low (registered output)
        wait until rising_edge(clk);
        wait for 1 ns;
        
        test_count <= test_count + 1;
        if valid /= '1' then
            report "FAIL 5.1: valid should be '1' after enable pulse"
                severity warning;
            error_count <= error_count + 1;
        else
            report "PASS 5.1: valid='1' after enable" severity note;
        end if;
        
        enable <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        -- Valid should go low
        test_count <= test_count + 1;
        if valid /= '0' then
            report "FAIL 5.2: valid should be '0' when not enabled"
                severity warning;
            error_count <= error_count + 1;
        else
            report "PASS 5.2: valid='0' when disabled" severity note;
        end if;
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test Category 6: Reset Behavior
        -----------------------------------------------------------------------
        report "--- Category 6: Reset Behavior ---";
        
        -- Set up active state
        error_in <= ONE;
        z_in     <= ONE;
        enable   <= '1';
        wait until rising_edge(clk);
        enable <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        -- Apply reset
        rst <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        test_count <= test_count + 1;
        if delta_out /= ZERO_VAL or valid /= '0' then
            report "FAIL 6.1: Reset should clear outputs"
                severity warning;
            error_count <= error_count + 1;
        else
            report "PASS 6.1: Reset clears outputs" severity note;
        end if;
        
        rst <= '0';
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test Category 7: Fractional Values
        -----------------------------------------------------------------------
        report "--- Category 7: Fractional Values ---";
        
        -- Test 7.1: Small fractional error
        run_test("7.1: err=0.125, z=1.0",
                 to_signed(1024, DATA_WIDTH), ONE, to_signed(1024, DATA_WIDTH), '1');
        
        -- Test 7.2: Various fractional combinations
        run_test("7.2: err=0.75, z=0.5",
                 to_signed(6144, DATA_WIDTH), HALF, to_signed(6144, DATA_WIDTH), '1');
        
        -- Test 7.3: Error = -0.125
        run_test("7.3: err=-0.125, z=2.0",
                 to_signed(-1024, DATA_WIDTH), to_signed(16384, DATA_WIDTH), to_signed(-1024, DATA_WIDTH), '1');
        
        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        wait for CLK_PERIOD * 5;
        
        report "========================================";
        report "Test Summary";
        report "========================================";
        report "Total tests: " & integer'image(test_count);
        report "Errors: " & integer'image(error_count);
        
        if error_count = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "SOME TESTS FAILED!" severity error;
        end if;
        
        sim_done <= true;
        wait;
    end process;

end architecture sim;
