--------------------------------------------------------------------------------
-- Testbench: tb_weight_updater
-- Description: Comprehensive test for weight_updater module
--              Tests W_new = W_old - learning_rate × gradient
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_weight_updater is
end entity tb_weight_updater;

architecture sim of tb_weight_updater is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD    : time := 10 ns;
    constant DATA_WIDTH    : integer := 16;
    constant GRAD_WIDTH    : integer := 40;
    constant FRAC_BITS     : integer := 13;
    constant GRAD_FRAC_BITS: integer := 26;
    
    -- Q2.13 constants
    constant ONE_Q213      : signed(DATA_WIDTH-1 downto 0) := to_signed(8192, DATA_WIDTH);
    constant HALF_Q213     : signed(DATA_WIDTH-1 downto 0) := to_signed(4096, DATA_WIDTH);
    constant QUARTER_Q213  : signed(DATA_WIDTH-1 downto 0) := to_signed(2048, DATA_WIDTH);
    constant NEG_ONE_Q213  : signed(DATA_WIDTH-1 downto 0) := to_signed(-8192, DATA_WIDTH);
    constant ZERO_Q213     : signed(DATA_WIDTH-1 downto 0) := to_signed(0, DATA_WIDTH);
    constant SAT_MAX_Q213  : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);
    constant SAT_MIN_Q213  : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH);
    
    -- Learning rates in Q2.13
    constant LR_0P01       : signed(DATA_WIDTH-1 downto 0) := to_signed(82, DATA_WIDTH);    -- 0.01
    constant LR_0P1        : signed(DATA_WIDTH-1 downto 0) := to_signed(819, DATA_WIDTH);   -- 0.1
    constant LR_1P0        : signed(DATA_WIDTH-1 downto 0) := to_signed(8192, DATA_WIDTH);  -- 1.0
    
    -- Q10.26 gradient constants (1.0 in Q10.26 = 2^26 = 67108864)
    constant ONE_Q1026     : signed(GRAD_WIDTH-1 downto 0) := to_signed(67108864, GRAD_WIDTH);
    constant HALF_Q1026    : signed(GRAD_WIDTH-1 downto 0) := to_signed(33554432, GRAD_WIDTH);
    constant NEG_ONE_Q1026 : signed(GRAD_WIDTH-1 downto 0) := to_signed(-67108864, GRAD_WIDTH);
    constant ZERO_Q1026    : signed(GRAD_WIDTH-1 downto 0) := to_signed(0, GRAD_WIDTH);

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component weight_updater is
        generic (
            DATA_WIDTH     : integer := 16;
            GRAD_WIDTH     : integer := 40;
            FRAC_BITS      : integer := 13;
            GRAD_FRAC_BITS : integer := 26;
            DEFAULT_LR     : integer := 82
        );
        port (
            clk            : in  std_logic;
            rst            : in  std_logic;
            learning_rate  : in  signed(DATA_WIDTH-1 downto 0);
            weight_in      : in  signed(DATA_WIDTH-1 downto 0);
            gradient_in    : in  signed(GRAD_WIDTH-1 downto 0);
            enable         : in  std_logic;
            weight_out     : out signed(DATA_WIDTH-1 downto 0);
            valid          : out std_logic;
            overflow       : out std_logic;
            done           : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal clk           : std_logic := '0';
    signal rst           : std_logic := '1';
    signal learning_rate : signed(DATA_WIDTH-1 downto 0) := LR_0P1;
    signal weight_in     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal gradient_in   : signed(GRAD_WIDTH-1 downto 0) := (others => '0');
    signal enable        : std_logic := '0';
    signal weight_out    : signed(DATA_WIDTH-1 downto 0);
    signal valid         : std_logic;
    signal overflow      : std_logic;
    signal done          : std_logic;
    
    -- Test tracking
    signal test_count    : integer := 0;
    signal error_count   : integer := 0;
    signal sim_done      : boolean := false;
    
    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    function to_real_q213(val : signed) return real is
    begin
        return real(to_integer(val)) / real(2**FRAC_BITS);
    end function;
    
    function to_real_q1026(val : signed) return real is
    begin
        return real(to_integer(val)) / real(2**GRAD_FRAC_BITS);
    end function;
    
    function to_fixed_q213(val : real) return signed is
        variable temp : integer;
    begin
        temp := integer(val * real(2**FRAC_BITS));
        if temp > 32767 then temp := 32767; end if;
        if temp < -32768 then temp := -32768; end if;
        return to_signed(temp, DATA_WIDTH);
    end function;
    
    function to_fixed_q1026(val : real) return signed is
        variable temp : real;
        variable temp_int : integer;
        constant MAX_VAL : integer := 2147483647;  -- Max positive integer
        constant MIN_VAL : integer := -2147483648; -- Min negative integer
    begin
        temp := val * real(2**GRAD_FRAC_BITS);
        -- Clamp to integer range
        if temp > real(MAX_VAL) then
            temp_int := MAX_VAL;
        elsif temp < real(MIN_VAL) then
            temp_int := MIN_VAL;
        else
            temp_int := integer(temp);
        end if;
        return to_signed(temp_int, GRAD_WIDTH);
    end function;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD/2 when not sim_done else '0';

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : weight_updater
        generic map (
            DATA_WIDTH     => DATA_WIDTH,
            GRAD_WIDTH     => GRAD_WIDTH,
            FRAC_BITS      => FRAC_BITS,
            GRAD_FRAC_BITS => GRAD_FRAC_BITS,
            DEFAULT_LR     => 82
        )
        port map (
            clk           => clk,
            rst           => rst,
            learning_rate => learning_rate,
            weight_in     => weight_in,
            gradient_in   => gradient_in,
            enable        => enable,
            weight_out    => weight_out,
            valid         => valid,
            overflow      => overflow,
            done          => done
        );

    ---------------------------------------------------------------------------
    -- Test Process
    ---------------------------------------------------------------------------
    test_proc : process
        
        procedure run_test(
            test_name       : string;
            lr_val          : signed(DATA_WIDTH-1 downto 0);
            w_val           : signed(DATA_WIDTH-1 downto 0);
            grad_val        : signed(GRAD_WIDTH-1 downto 0);
            expected_w      : signed(DATA_WIDTH-1 downto 0);
            tolerance       : integer := 10  -- Allow rounding errors
        ) is
            variable diff : integer;
        begin
            test_count <= test_count + 1;
            
            -- Apply inputs
            learning_rate <= lr_val;
            weight_in     <= w_val;
            gradient_in   <= grad_val;
            enable        <= '1';
            
            wait until rising_edge(clk);
            enable <= '0';
            
            -- Wait for pipeline (4 stages)
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait for 1 ns;
            
            -- Check result
            diff := abs(to_integer(weight_out) - to_integer(expected_w));
            
            if diff > tolerance then
                report "FAIL " & test_name & 
                       ": lr=" & real'image(to_real_q213(lr_val)) &
                       ", w=" & real'image(to_real_q213(w_val)) &
                       ", grad=" & real'image(to_real_q1026(grad_val)) &
                       ", expected=" & real'image(to_real_q213(expected_w)) &
                       ", got=" & real'image(to_real_q213(weight_out)) &
                       " (diff=" & integer'image(diff) & ")"
                    severity warning;
                error_count <= error_count + 1;
            else
                report "PASS " & test_name & 
                       ": w_new=" & real'image(to_real_q213(weight_out))
                    severity note;
            end if;
            
            wait until rising_edge(clk);
        end procedure;
        
    begin
        -- Initialize
        rst           <= '1';
        enable        <= '0';
        learning_rate <= LR_0P1;
        weight_in     <= (others => '0');
        gradient_in   <= (others => '0');
        
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "========================================";
        report "Starting weight_updater Tests";
        report "========================================";
        
        -----------------------------------------------------------------------
        -- Test Category 1: Basic SGD Updates
        -- W_new = W_old - lr × grad
        -----------------------------------------------------------------------
        report "--- Category 1: Basic SGD Updates ---";
        
        -- Test 1.1: W=1.0, lr=0.1, grad=1.0 → W_new = 1.0 - 0.1×1.0 = 0.9
        run_test("1.1: W=1.0, lr=0.1, grad=1.0",
                 LR_0P1, ONE_Q213, ONE_Q1026,
                 to_fixed_q213(0.9));
        
        -- Test 1.2: W=0.5, lr=0.1, grad=0.5 → W_new = 0.5 - 0.1×0.5 = 0.45
        run_test("1.2: W=0.5, lr=0.1, grad=0.5",
                 LR_0P1, HALF_Q213, HALF_Q1026,
                 to_fixed_q213(0.45));
        
        -- Test 1.3: W=1.0, lr=0.01, grad=1.0 → W_new = 1.0 - 0.01×1.0 = 0.99
        run_test("1.3: W=1.0, lr=0.01, grad=1.0",
                 LR_0P01, ONE_Q213, ONE_Q1026,
                 to_fixed_q213(0.99));
        
        -- Test 1.4: W=0, lr=0.1, grad=1.0 → W_new = 0 - 0.1×1.0 = -0.1
        run_test("1.4: W=0, lr=0.1, grad=1.0",
                 LR_0P1, ZERO_Q213, ONE_Q1026,
                 to_fixed_q213(-0.1));
        
        -----------------------------------------------------------------------
        -- Test Category 2: Negative Gradients (Weight Increase)
        -----------------------------------------------------------------------
        report "--- Category 2: Negative Gradients ---";
        
        -- Test 2.1: W=0.5, lr=0.1, grad=-1.0 → W_new = 0.5 - 0.1×(-1.0) = 0.6
        run_test("2.1: W=0.5, lr=0.1, grad=-1.0",
                 LR_0P1, HALF_Q213, NEG_ONE_Q1026,
                 to_fixed_q213(0.6));
        
        -- Test 2.2: W=-0.5, lr=0.1, grad=-0.5 → W_new = -0.5 - 0.1×(-0.5) = -0.45
        run_test("2.2: W=-0.5, lr=0.1, grad=-0.5",
                 LR_0P1, to_fixed_q213(-0.5), to_fixed_q1026(-0.5),
                 to_fixed_q213(-0.45));
        
        -----------------------------------------------------------------------
        -- Test Category 3: Zero Gradient (No Change)
        -----------------------------------------------------------------------
        report "--- Category 3: Zero Gradient ---";
        
        -- Test 3.1: W=1.0, lr=0.1, grad=0 → W_new = 1.0
        run_test("3.1: W=1.0, lr=0.1, grad=0",
                 LR_0P1, ONE_Q213, ZERO_Q1026,
                 ONE_Q213);
        
        -- Test 3.2: W=-0.5, lr=0.1, grad=0 → W_new = -0.5
        run_test("3.2: W=-0.5, lr=0.1, grad=0",
                 LR_0P1, to_fixed_q213(-0.5), ZERO_Q1026,
                 to_fixed_q213(-0.5));
        
        -----------------------------------------------------------------------
        -- Test Category 4: Large Learning Rate
        -----------------------------------------------------------------------
        report "--- Category 4: Large Learning Rate ---";
        
        -- Test 4.1: W=1.0, lr=1.0, grad=0.5 → W_new = 1.0 - 1.0×0.5 = 0.5
        run_test("4.1: W=1.0, lr=1.0, grad=0.5",
                 LR_1P0, ONE_Q213, HALF_Q1026,
                 to_fixed_q213(0.5));
        
        -- Test 4.2: W=0.5, lr=1.0, grad=1.0 → W_new = 0.5 - 1.0×1.0 = -0.5
        run_test("4.2: W=0.5, lr=1.0, grad=1.0",
                 LR_1P0, HALF_Q213, ONE_Q1026,
                 to_fixed_q213(-0.5));
        
        -----------------------------------------------------------------------
        -- Test Category 5: Saturation Cases
        -----------------------------------------------------------------------
        report "--- Category 5: Saturation Cases ---";
        
        -- Test 5.1: Large positive gradient causing negative saturation
        -- W=0, lr=1.0, grad=5.0 → W_new = 0 - 5.0 = -5.0 → saturate to -4.0
        run_test("5.1: Negative saturation",
                 LR_1P0, ZERO_Q213, to_fixed_q1026(5.0),
                 SAT_MIN_Q213, 100);  -- Larger tolerance for saturation
        
        -- Test 5.2: Large negative gradient causing positive saturation
        -- W=3.0, lr=1.0, grad=-5.0 → W_new = 3.0 + 5.0 = 8.0 → saturate to ~4.0
        run_test("5.2: Positive saturation",
                 LR_1P0, to_fixed_q213(3.0), to_fixed_q1026(-5.0),
                 SAT_MAX_Q213, 100);
        
        -----------------------------------------------------------------------
        -- Test Category 6: Small Updates (Precision Test)
        -----------------------------------------------------------------------
        report "--- Category 6: Small Updates ---";
        
        -- Test 6.1: Very small gradient
        -- W=1.0, lr=0.01, grad=0.01 → W_new = 1.0 - 0.0001 ≈ 0.9999
        run_test("6.1: Very small update",
                 LR_0P01, ONE_Q213, to_fixed_q1026(0.01),
                 to_fixed_q213(0.9999), 5);
        
        -- Test 6.2: Small weight, small gradient
        run_test("6.2: Small weight and gradient",
                 LR_0P1, to_fixed_q213(0.1), to_fixed_q1026(0.1),
                 to_fixed_q213(0.09), 5);
        
        -----------------------------------------------------------------------
        -- Test Category 7: Pipeline Behavior
        -----------------------------------------------------------------------
        report "--- Category 7: Pipeline ---";
        
        -- Test consecutive updates - need proper spacing for 4-stage pipeline
        test_count <= test_count + 1;
        
        -- First update
        learning_rate <= LR_0P1;
        weight_in     <= ONE_Q213;
        gradient_in   <= ONE_Q1026;
        enable        <= '1';
        wait until rising_edge(clk);
        enable <= '0';
        
        -- Wait for first result (4 pipeline stages)
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        
        -- Check first result (W=1.0 - 0.1×1.0 = 0.9)
        if abs(to_integer(weight_out) - to_integer(to_fixed_q213(0.9))) <= 10 then
            report "PASS 7.1: First pipeline result correct" severity note;
        else
            report "FAIL 7.1: First pipeline result incorrect, got=" & 
                   real'image(to_real_q213(weight_out)) severity warning;
            error_count <= error_count + 1;
        end if;
        
        -- Second update
        test_count <= test_count + 1;
        weight_in     <= HALF_Q213;
        gradient_in   <= HALF_Q1026;
        enable        <= '1';
        wait until rising_edge(clk);
        enable <= '0';
        
        -- Wait for second result
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        
        -- Check second result (W=0.5 - 0.1×0.5 = 0.45)
        if abs(to_integer(weight_out) - to_integer(to_fixed_q213(0.45))) <= 10 then
            report "PASS 7.2: Second pipeline result correct" severity note;
        else
            report "FAIL 7.2: Second pipeline result incorrect" severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test Category 8: Reset Behavior
        -----------------------------------------------------------------------
        report "--- Category 8: Reset ---";
        
        -- Start a computation
        weight_in   <= ONE_Q213;
        gradient_in <= ONE_Q1026;
        enable      <= '1';
        wait until rising_edge(clk);
        enable <= '0';
        
        -- Apply reset mid-pipeline
        wait until rising_edge(clk);
        rst <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        test_count <= test_count + 1;
        if valid = '0' then
            report "PASS 8.1: Reset clears valid" severity note;
        else
            report "FAIL 8.1: Reset should clear valid" severity warning;
            error_count <= error_count + 1;
        end if;
        
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
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
