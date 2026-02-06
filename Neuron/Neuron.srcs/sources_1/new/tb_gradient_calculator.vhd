--------------------------------------------------------------------------------
-- Testbench: tb_gradient_calculator
-- Description: Comprehensive test for gradient_calculator module
--              Tests ∂L/∂W[i,j] = δ[j] × a[i] computation
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_gradient_calculator is
end entity tb_gradient_calculator;

architecture sim of tb_gradient_calculator is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD    : time := 10 ns;
    constant DATA_WIDTH    : integer := 16;
    constant PRODUCT_WIDTH : integer := 32;
    constant FRAC_BITS     : integer := 13;
    
    -- Q2.13 constants
    constant ONE       : signed(DATA_WIDTH-1 downto 0) := to_signed(8192, DATA_WIDTH);
    constant HALF      : signed(DATA_WIDTH-1 downto 0) := to_signed(4096, DATA_WIDTH);
    constant QUARTER   : signed(DATA_WIDTH-1 downto 0) := to_signed(2048, DATA_WIDTH);
    constant NEG_ONE   : signed(DATA_WIDTH-1 downto 0) := to_signed(-8192, DATA_WIDTH);
    constant NEG_HALF  : signed(DATA_WIDTH-1 downto 0) := to_signed(-4096, DATA_WIDTH);
    constant ZERO_VAL  : signed(DATA_WIDTH-1 downto 0) := to_signed(0, DATA_WIDTH);

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component gradient_calculator is
        generic (
            DATA_WIDTH    : integer := 16;
            PRODUCT_WIDTH : integer := 32;
            FRAC_BITS     : integer := 13;
            MAX_INPUTS    : integer := 8
        );
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            start         : in  std_logic;
            clear         : in  std_logic;
            num_inputs    : in  unsigned(7 downto 0);
            delta_in      : in  signed(DATA_WIDTH-1 downto 0);
            delta_valid   : in  std_logic;
            delta_ready   : out std_logic;
            activation_in : in  signed(DATA_WIDTH-1 downto 0);
            act_valid     : in  std_logic;
            act_ready     : out std_logic;
            gradient_out  : out signed(PRODUCT_WIDTH-1 downto 0);
            grad_valid    : out std_logic;
            grad_ready    : in  std_logic;
            grad_index    : out unsigned(7 downto 0);
            bias_grad_out : out signed(DATA_WIDTH-1 downto 0);
            bias_valid    : out std_logic;
            busy          : out std_logic;
            done          : out std_logic;
            grad_count    : out unsigned(7 downto 0)
        );
    end component;

    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal clk           : std_logic := '0';
    signal rst           : std_logic := '1';
    signal start         : std_logic := '0';
    signal clear         : std_logic := '0';
    signal num_inputs    : unsigned(7 downto 0) := (others => '0');
    signal delta_in      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal delta_valid   : std_logic := '0';
    signal delta_ready   : std_logic;
    signal activation_in : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal act_valid     : std_logic := '0';
    signal act_ready     : std_logic;
    signal gradient_out  : signed(PRODUCT_WIDTH-1 downto 0);
    signal grad_valid    : std_logic;
    signal grad_ready    : std_logic := '1';
    signal grad_index    : unsigned(7 downto 0);
    signal bias_grad_out : signed(DATA_WIDTH-1 downto 0);
    signal bias_valid    : std_logic;
    signal busy          : std_logic;
    signal done          : std_logic;
    signal grad_count    : unsigned(7 downto 0);
    
    -- Test tracking
    signal test_count    : integer := 0;
    signal error_count   : integer := 0;
    signal sim_done      : boolean := false;
    
    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    function to_real(val : signed(DATA_WIDTH-1 downto 0)) return real is
    begin
        return real(to_integer(val)) / real(2**FRAC_BITS);
    end function;
    
    -- Convert product (Q4.26) to real
    function prod_to_real(val : signed(PRODUCT_WIDTH-1 downto 0)) return real is
    begin
        return real(to_integer(val)) / real(2**(2*FRAC_BITS));
    end function;
    
    function to_fixed(val : real) return signed is
        variable temp : integer;
    begin
        temp := integer(val * real(2**FRAC_BITS));
        if temp > 32767 then temp := 32767; end if;
        if temp < -32768 then temp := -32768; end if;
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
    dut : gradient_calculator
        generic map (
            DATA_WIDTH    => DATA_WIDTH,
            PRODUCT_WIDTH => PRODUCT_WIDTH,
            FRAC_BITS     => FRAC_BITS,
            MAX_INPUTS    => 8
        )
        port map (
            clk           => clk,
            rst           => rst,
            start         => start,
            clear         => clear,
            num_inputs    => num_inputs,
            delta_in      => delta_in,
            delta_valid   => delta_valid,
            delta_ready   => delta_ready,
            activation_in => activation_in,
            act_valid     => act_valid,
            act_ready     => act_ready,
            gradient_out  => gradient_out,
            grad_valid    => grad_valid,
            grad_ready    => grad_ready,
            grad_index    => grad_index,
            bias_grad_out => bias_grad_out,
            bias_valid    => bias_valid,
            busy          => busy,
            done          => done,
            grad_count    => grad_count
        );

    ---------------------------------------------------------------------------
    -- Test Process
    ---------------------------------------------------------------------------
    test_proc : process
        variable actual_grad : real;
        variable expected    : real;
        variable tolerance   : real := 0.001;
        
        -- Array to store collected gradients
        type grad_array_t is array (0 to 7) of real;
        variable collected_grads : grad_array_t;
        variable grad_idx : integer;
        
    begin
        -- Initialize
        rst           <= '1';
        start         <= '0';
        clear         <= '0';
        delta_valid   <= '0';
        act_valid     <= '0';
        delta_in      <= (others => '0');
        activation_in <= (others => '0');
        num_inputs    <= (others => '0');
        grad_ready    <= '1';
        
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "========================================";
        report "Starting gradient_calculator Tests";
        report "========================================";
        
        -----------------------------------------------------------------------
        -- Test 1: Single Input (delta=1.0, activation=0.5 → grad=0.5)
        -----------------------------------------------------------------------
        report "--- Test 1: Single Input ---";
        test_count <= test_count + 1;
        
        num_inputs <= to_unsigned(1, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        -- Wait for delta_ready and provide delta
        wait until delta_ready = '1';
        wait until rising_edge(clk);
        delta_in <= ONE;  -- delta = 1.0
        delta_valid <= '1';
        wait until rising_edge(clk);
        delta_valid <= '0';
        
        -- Wait for act_ready and provide activation
        wait until act_ready = '1';
        wait until rising_edge(clk);
        activation_in <= HALF;  -- activation = 0.5
        act_valid <= '1';
        wait until rising_edge(clk);
        act_valid <= '0';
        
        -- Wait for gradient output
        wait until grad_valid = '1' for 500 ns;
        wait for 1 ns;
        
        actual_grad := prod_to_real(gradient_out);
        expected := 0.5;  -- 1.0 × 0.5 = 0.5
        if abs(actual_grad - expected) < tolerance then
            report "PASS Test 1: grad = " & real'image(actual_grad) severity note;
        else
            report "FAIL Test 1: Expected " & real'image(expected) & 
                   ", got " & real'image(actual_grad) severity warning;
            error_count <= error_count + 1;
        end if;
        
        -- Accept gradient
        wait until rising_edge(clk);
        
        -- Wait for done
        wait until done = '1' for 500 ns;
        wait for 1 ns;
        
        -- Check bias gradient
        test_count <= test_count + 1;
        if bias_valid = '1' and bias_grad_out = ONE then
            report "PASS Test 1b: bias_grad = delta" severity note;
        else
            report "FAIL Test 1b: bias_grad should equal delta" severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 2: Multiple Inputs (4 inputs)
        -- delta = 0.5, activations = [1.0, 0.5, 0.25, -0.5]
        -- expected gradients = [0.5, 0.25, 0.125, -0.25]
        -----------------------------------------------------------------------
        report "--- Test 2: Four Inputs ---";
        test_count <= test_count + 1;
        
        num_inputs <= to_unsigned(4, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        -- Provide delta
        wait until delta_ready = '1';
        wait until rising_edge(clk);
        delta_in <= HALF;  -- delta = 0.5
        delta_valid <= '1';
        wait until rising_edge(clk);
        delta_valid <= '0';
        
        -- Provide activations and collect gradients
        for i in 0 to 3 loop
            wait until act_ready = '1';
            wait until rising_edge(clk);
            
            case i is
                when 0 => activation_in <= ONE;      -- 1.0
                when 1 => activation_in <= HALF;     -- 0.5
                when 2 => activation_in <= QUARTER;  -- 0.25
                when 3 => activation_in <= NEG_HALF; -- -0.5
                when others => activation_in <= ZERO_VAL;
            end case;
            act_valid <= '1';
            wait until rising_edge(clk);
            act_valid <= '0';
            
            -- Wait for gradient output
            wait until grad_valid = '1' for 500 ns;
            wait for 1 ns;
            
            collected_grads(i) := prod_to_real(gradient_out);
            grad_idx := to_integer(grad_index);
            
            -- Verify index
            if grad_idx /= i then
                report "FAIL: grad_index mismatch at " & integer'image(i) severity warning;
                error_count <= error_count + 1;
            end if;
            
            wait until rising_edge(clk);
        end loop;
        
        -- Verify collected gradients
        -- Expected: 0.5×[1, 0.5, 0.25, -0.5] = [0.5, 0.25, 0.125, -0.25]
        if abs(collected_grads(0) - 0.5) < tolerance and
           abs(collected_grads(1) - 0.25) < tolerance and
           abs(collected_grads(2) - 0.125) < tolerance and
           abs(collected_grads(3) - (-0.25)) < tolerance then
            report "PASS Test 2: All 4 gradients correct" severity note;
        else
            report "FAIL Test 2: Gradient values incorrect" severity warning;
            report "  grad[0]=" & real'image(collected_grads(0)) & " (exp 0.5)";
            report "  grad[1]=" & real'image(collected_grads(1)) & " (exp 0.25)";
            report "  grad[2]=" & real'image(collected_grads(2)) & " (exp 0.125)";
            report "  grad[3]=" & real'image(collected_grads(3)) & " (exp -0.25)";
            error_count <= error_count + 1;
        end if;
        
        wait until done = '1' for 500 ns;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 3: Zero Delta (all gradients should be zero)
        -----------------------------------------------------------------------
        report "--- Test 3: Zero Delta ---";
        test_count <= test_count + 1;
        
        num_inputs <= to_unsigned(2, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        -- Provide zero delta
        wait until delta_ready = '1';
        wait until rising_edge(clk);
        delta_in <= ZERO_VAL;
        delta_valid <= '1';
        wait until rising_edge(clk);
        delta_valid <= '0';
        
        -- Provide activations
        for i in 0 to 1 loop
            wait until act_ready = '1';
            wait until rising_edge(clk);
            activation_in <= ONE;
            act_valid <= '1';
            wait until rising_edge(clk);
            act_valid <= '0';
            
            wait until grad_valid = '1' for 500 ns;
            wait for 1 ns;
            
            actual_grad := prod_to_real(gradient_out);
            if abs(actual_grad) >= tolerance then
                report "FAIL Test 3: grad should be 0, got " & real'image(actual_grad) severity warning;
                error_count <= error_count + 1;
            end if;
            
            wait until rising_edge(clk);
        end loop;
        
        report "PASS Test 3: Zero delta produces zero gradients" severity note;
        
        wait until done = '1' for 500 ns;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 4: Negative Delta
        -- delta = -1.0, activation = 0.5 → grad = -0.5
        -----------------------------------------------------------------------
        report "--- Test 4: Negative Delta ---";
        test_count <= test_count + 1;
        
        num_inputs <= to_unsigned(1, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until delta_ready = '1';
        wait until rising_edge(clk);
        delta_in <= NEG_ONE;
        delta_valid <= '1';
        wait until rising_edge(clk);
        delta_valid <= '0';
        
        wait until act_ready = '1';
        wait until rising_edge(clk);
        activation_in <= HALF;
        act_valid <= '1';
        wait until rising_edge(clk);
        act_valid <= '0';
        
        wait until grad_valid = '1' for 500 ns;
        wait for 1 ns;
        
        actual_grad := prod_to_real(gradient_out);
        expected := -0.5;
        if abs(actual_grad - expected) < tolerance then
            report "PASS Test 4: Negative delta grad = " & real'image(actual_grad) severity note;
        else
            report "FAIL Test 4: Expected " & real'image(expected) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until done = '1' for 500 ns;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 5: Zero Inputs
        -----------------------------------------------------------------------
        report "--- Test 5: Zero Inputs ---";
        test_count <= test_count + 1;
        
        num_inputs <= to_unsigned(0, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until done = '1' for 500 ns;
        wait for 1 ns;
        
        if done = '1' then
            report "PASS Test 5: Zero inputs completes immediately" severity note;
        else
            report "FAIL Test 5: Should complete immediately" severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 6: Grad Ready Handshaking
        -----------------------------------------------------------------------
        report "--- Test 6: Grad Ready Handshaking ---";
        test_count <= test_count + 1;
        
        grad_ready <= '0';  -- Don't accept gradients initially
        
        num_inputs <= to_unsigned(1, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until delta_ready = '1';
        wait until rising_edge(clk);
        delta_in <= ONE;
        delta_valid <= '1';
        wait until rising_edge(clk);
        delta_valid <= '0';
        
        wait until act_ready = '1';
        wait until rising_edge(clk);
        activation_in <= ONE;
        act_valid <= '1';
        wait until rising_edge(clk);
        act_valid <= '0';
        
        wait until grad_valid = '1' for 500 ns;
        wait for CLK_PERIOD * 3;
        
        -- Should still be in OUTPUT_GRAD state
        if grad_valid = '1' then
            report "PASS Test 6a: Holds gradient until accepted" severity note;
        else
            report "FAIL Test 6a: Should hold gradient" severity warning;
            error_count <= error_count + 1;
        end if;
        
        -- Now accept
        grad_ready <= '1';
        wait until rising_edge(clk);
        wait until done = '1' for 500 ns;
        
        test_count <= test_count + 1;
        if done = '1' then
            report "PASS Test 6b: Proceeds after accept" severity note;
        else
            report "FAIL Test 6b: Should proceed to done" severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 7: Clear During Operation
        -----------------------------------------------------------------------
        report "--- Test 7: Clear During Operation ---";
        test_count <= test_count + 1;
        
        num_inputs <= to_unsigned(4, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until delta_ready = '1';
        wait until rising_edge(clk);
        delta_in <= ONE;
        delta_valid <= '1';
        wait until rising_edge(clk);
        delta_valid <= '0';
        
        -- Provide one activation
        wait until act_ready = '1';
        wait until rising_edge(clk);
        activation_in <= ONE;
        act_valid <= '1';
        wait until rising_edge(clk);
        act_valid <= '0';
        
        wait until grad_valid = '1' for 500 ns;
        wait until rising_edge(clk);
        
        -- Clear mid-operation
        clear <= '1';
        wait until rising_edge(clk);
        clear <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        if busy = '0' then
            report "PASS Test 7: Clear returns to IDLE" severity note;
        else
            report "FAIL Test 7: Should return to IDLE" severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 8: Reset Behavior
        -----------------------------------------------------------------------
        report "--- Test 8: Reset ---";
        test_count <= test_count + 1;
        
        num_inputs <= to_unsigned(2, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until delta_ready = '1';
        wait until rising_edge(clk);
        delta_in <= ONE;
        delta_valid <= '1';
        wait until rising_edge(clk);
        delta_valid <= '0';
        
        -- Reset mid-operation
        rst <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        if busy = '0' then
            report "PASS Test 8: Reset clears state" severity note;
        else
            report "FAIL Test 8: Reset should clear" severity warning;
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
