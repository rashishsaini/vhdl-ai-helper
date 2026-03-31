--------------------------------------------------------------------------------
-- Testbench: tb_error_propagator
-- Description: Comprehensive test for error_propagator module
--              Tests δ[l-1] = (W^T × δ[l]) ⊙ σ'(z[l-1]) computation
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_error_propagator is
end entity tb_error_propagator;

architecture sim of tb_error_propagator is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD   : time := 10 ns;
    constant DATA_WIDTH   : integer := 16;
    constant ACCUM_WIDTH  : integer := 40;
    constant FRAC_BITS    : integer := 13;
    
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
    component error_propagator is
        generic (
            DATA_WIDTH   : integer := 16;
            ACCUM_WIDTH  : integer := 40;
            FRAC_BITS    : integer := 13;
            MAX_NEURONS  : integer := 8;
            MAX_DELTAS   : integer := 8
        );
        port (
            clk            : in  std_logic;
            rst            : in  std_logic;
            start          : in  std_logic;
            clear          : in  std_logic;
            num_neurons    : in  unsigned(7 downto 0);
            num_deltas     : in  unsigned(7 downto 0);
            weight_in      : in  signed(DATA_WIDTH-1 downto 0);
            weight_valid   : in  std_logic;
            weight_ready   : out std_logic;
            delta_in       : in  signed(DATA_WIDTH-1 downto 0);
            delta_valid    : in  std_logic;
            delta_ready    : out std_logic;
            z_in           : in  signed(DATA_WIDTH-1 downto 0);
            z_valid        : in  std_logic;
            z_ready        : out std_logic;
            delta_out      : out signed(DATA_WIDTH-1 downto 0);
            delta_out_valid: out std_logic;
            delta_out_ready: in  std_logic;
            neuron_index   : out unsigned(7 downto 0);
            busy           : out std_logic;
            done           : out std_logic;
            overflow       : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal clk             : std_logic := '0';
    signal rst             : std_logic := '1';
    signal start           : std_logic := '0';
    signal clear           : std_logic := '0';
    signal num_neurons     : unsigned(7 downto 0) := (others => '0');
    signal num_deltas      : unsigned(7 downto 0) := (others => '0');
    signal weight_in       : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal weight_valid    : std_logic := '0';
    signal weight_ready    : std_logic;
    signal delta_in        : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal delta_valid     : std_logic := '0';
    signal delta_ready     : std_logic;
    signal z_in            : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal z_valid         : std_logic := '0';
    signal z_ready         : std_logic;
    signal delta_out       : signed(DATA_WIDTH-1 downto 0);
    signal delta_out_valid : std_logic;
    signal delta_out_ready : std_logic := '1';
    signal neuron_index    : unsigned(7 downto 0);
    signal busy            : std_logic;
    signal done            : std_logic;
    signal overflow        : std_logic;
    
    -- Test tracking
    signal test_count      : integer := 0;
    signal error_count     : integer := 0;
    signal sim_done        : boolean := false;
    
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
    dut : error_propagator
        generic map (
            DATA_WIDTH   => DATA_WIDTH,
            ACCUM_WIDTH  => ACCUM_WIDTH,
            FRAC_BITS    => FRAC_BITS,
            MAX_NEURONS  => 8,
            MAX_DELTAS   => 8
        )
        port map (
            clk             => clk,
            rst             => rst,
            start           => start,
            clear           => clear,
            num_neurons     => num_neurons,
            num_deltas      => num_deltas,
            weight_in       => weight_in,
            weight_valid    => weight_valid,
            weight_ready    => weight_ready,
            delta_in        => delta_in,
            delta_valid     => delta_valid,
            delta_ready     => delta_ready,
            z_in            => z_in,
            z_valid         => z_valid,
            z_ready         => z_ready,
            delta_out       => delta_out,
            delta_out_valid => delta_out_valid,
            delta_out_ready => delta_out_ready,
            neuron_index    => neuron_index,
            busy            => busy,
            done            => done,
            overflow        => overflow
        );

    ---------------------------------------------------------------------------
    -- Test Process
    ---------------------------------------------------------------------------
    test_proc : process
        variable actual_delta : real;
        variable expected     : real;
        variable tolerance    : real := 0.01;
        
        -- Array for collected deltas
        type delta_array_t is array (0 to 7) of real;
        variable collected_deltas : delta_array_t;
        
    begin
        -- Initialize
        rst             <= '1';
        start           <= '0';
        clear           <= '0';
        weight_valid    <= '0';
        delta_valid     <= '0';
        z_valid         <= '0';
        weight_in       <= (others => '0');
        delta_in        <= (others => '0');
        z_in            <= (others => '0');
        num_neurons     <= (others => '0');
        num_deltas      <= (others => '0');
        delta_out_ready <= '1';
        
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "========================================";
        report "Starting error_propagator Tests";
        report "========================================";
        
        -----------------------------------------------------------------------
        -- Test 1: Single Neuron, Single Delta, Active (z > 0)
        -- δ_out = W × δ_in × σ'(z) = 0.5 × 1.0 × 1 = 0.5
        -----------------------------------------------------------------------
        report "--- Test 1: Single Neuron, Active ---";
        test_count <= test_count + 1;
        
        num_neurons <= to_unsigned(1, 8);
        num_deltas  <= to_unsigned(1, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        -- Provide z value (positive, so neuron is active)
        wait until z_ready = '1';
        wait until rising_edge(clk);
        z_in <= ONE;  -- z = 1.0 > 0, so active
        z_valid <= '1';
        wait until rising_edge(clk);
        z_valid <= '0';
        
        -- Provide weight and delta
        wait until weight_ready = '1' and delta_ready = '1';
        wait until rising_edge(clk);
        weight_in <= HALF;   -- W = 0.5
        delta_in  <= ONE;    -- δ = 1.0
        weight_valid <= '1';
        delta_valid  <= '1';
        wait until rising_edge(clk);
        weight_valid <= '0';
        delta_valid  <= '0';
        
        -- Wait for output
        wait until delta_out_valid = '1' for 1 us;
        wait for 1 ns;
        
        actual_delta := to_real(delta_out);
        expected := 0.5;  -- 0.5 × 1.0 × 1 = 0.5
        if abs(actual_delta - expected) < tolerance then
            report "PASS Test 1: Active neuron δ = " & real'image(actual_delta) severity note;
        else
            report "FAIL Test 1: Expected " & real'image(expected) & 
                   ", got " & real'image(actual_delta) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until done = '1' for 500 ns;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 2: Single Neuron, Single Delta, Inactive (z <= 0)
        -- δ_out = W × δ_in × σ'(z) = 0.5 × 1.0 × 0 = 0
        -----------------------------------------------------------------------
        report "--- Test 2: Single Neuron, Inactive ---";
        test_count <= test_count + 1;
        
        num_neurons <= to_unsigned(1, 8);
        num_deltas  <= to_unsigned(1, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        -- Provide z value (negative, so neuron is inactive)
        wait until z_ready = '1';
        wait until rising_edge(clk);
        z_in <= NEG_ONE;  -- z = -1.0 <= 0, so inactive
        z_valid <= '1';
        wait until rising_edge(clk);
        z_valid <= '0';
        
        -- Provide weight and delta
        wait until weight_ready = '1' and delta_ready = '1';
        wait until rising_edge(clk);
        weight_in <= HALF;
        delta_in  <= ONE;
        weight_valid <= '1';
        delta_valid  <= '1';
        wait until rising_edge(clk);
        weight_valid <= '0';
        delta_valid  <= '0';
        
        -- Wait for output
        wait until delta_out_valid = '1' for 1 us;
        wait for 1 ns;
        
        actual_delta := to_real(delta_out);
        expected := 0.0;  -- Inactive: σ'(z) = 0
        if abs(actual_delta - expected) < tolerance then
            report "PASS Test 2: Inactive neuron δ = " & real'image(actual_delta) severity note;
        else
            report "FAIL Test 2: Expected " & real'image(expected) & 
                   ", got " & real'image(actual_delta) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until done = '1' for 500 ns;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 3: Two Neurons, One Delta (like output→hidden in 4-2-1)
        -- Neuron 0: z=1.0 (active), W=0.5, δ=1.0 → δ_out = 0.5
        -- Neuron 1: z=0.5 (active), W=0.25, δ=1.0 → δ_out = 0.25
        -----------------------------------------------------------------------
        report "--- Test 3: Two Neurons, One Delta ---";
        test_count <= test_count + 1;
        
        num_neurons <= to_unsigned(2, 8);
        num_deltas  <= to_unsigned(1, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        -- Process neuron 0
        wait until z_ready = '1';
        wait until rising_edge(clk);
        z_in <= ONE;  -- Active
        z_valid <= '1';
        wait until rising_edge(clk);
        z_valid <= '0';
        
        wait until weight_ready = '1';
        wait until rising_edge(clk);
        weight_in <= HALF;
        delta_in  <= ONE;
        weight_valid <= '1';
        delta_valid  <= '1';
        wait until rising_edge(clk);
        weight_valid <= '0';
        delta_valid  <= '0';
        
        wait until delta_out_valid = '1' for 1 us;
        wait for 1 ns;
        collected_deltas(0) := to_real(delta_out);
        wait until rising_edge(clk);
        
        -- Process neuron 1
        wait until z_ready = '1';
        wait until rising_edge(clk);
        z_in <= HALF;  -- Active
        z_valid <= '1';
        wait until rising_edge(clk);
        z_valid <= '0';
        
        wait until weight_ready = '1';
        wait until rising_edge(clk);
        weight_in <= QUARTER;
        delta_in  <= ONE;
        weight_valid <= '1';
        delta_valid  <= '1';
        wait until rising_edge(clk);
        weight_valid <= '0';
        delta_valid  <= '0';
        
        wait until delta_out_valid = '1' for 1 us;
        wait for 1 ns;
        collected_deltas(1) := to_real(delta_out);
        
        -- Verify results
        if abs(collected_deltas(0) - 0.5) < tolerance and
           abs(collected_deltas(1) - 0.25) < tolerance then
            report "PASS Test 3: Two neurons δ = [" & 
                   real'image(collected_deltas(0)) & ", " & 
                   real'image(collected_deltas(1)) & "]" severity note;
        else
            report "FAIL Test 3: Expected [0.5, 0.25], got [" &
                   real'image(collected_deltas(0)) & ", " & 
                   real'image(collected_deltas(1)) & "]" severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until done = '1' for 1 us;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 4: One Neuron, Two Deltas (multiple sources)
        -- δ_out = (W0×δ0 + W1×δ1) × σ'(z)
        --       = (0.5×1.0 + 0.25×0.5) × 1 = 0.625
        -----------------------------------------------------------------------
        report "--- Test 4: One Neuron, Two Deltas ---";
        test_count <= test_count + 1;
        
        num_neurons <= to_unsigned(1, 8);
        num_deltas  <= to_unsigned(2, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        -- Provide z (active)
        wait until z_ready = '1';
        wait until rising_edge(clk);
        z_in <= ONE;
        z_valid <= '1';
        wait until rising_edge(clk);
        z_valid <= '0';
        
        -- First weight/delta pair
        wait until weight_ready = '1';
        wait until rising_edge(clk);
        weight_in <= HALF;   -- W0 = 0.5
        delta_in  <= ONE;    -- δ0 = 1.0
        weight_valid <= '1';
        delta_valid  <= '1';
        wait until rising_edge(clk);
        weight_valid <= '0';
        delta_valid  <= '0';
        
        -- Second weight/delta pair - need to wait for FSM to be ready
        -- The FSM stays in ACCUMULATE after first pair if more deltas expected
        for wait_loop in 0 to 50 loop
            wait until rising_edge(clk);
            exit when weight_ready = '1';
        end loop;
        
        weight_in <= QUARTER; -- W1 = 0.25
        delta_in  <= HALF;    -- δ1 = 0.5
        weight_valid <= '1';
        delta_valid  <= '1';
        wait until rising_edge(clk);
        weight_valid <= '0';
        delta_valid  <= '0';
        
        -- Wait for output
        wait until delta_out_valid = '1' for 1 us;
        wait for 1 ns;
        
        actual_delta := to_real(delta_out);
        expected := 0.625;  -- (0.5×1.0 + 0.25×0.5) × 1 = 0.625
        if abs(actual_delta - expected) < tolerance then
            report "PASS Test 4: Multi-delta sum δ = " & real'image(actual_delta) severity note;
        else
            report "FAIL Test 4: Expected " & real'image(expected) & 
                   ", got " & real'image(actual_delta) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until done = '1' for 1 us;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 5: Negative Weights and Deltas
        -- δ_out = (-0.5 × -1.0) × 1 = 0.5
        -----------------------------------------------------------------------
        report "--- Test 5: Negative Values ---";
        test_count <= test_count + 1;
        
        num_neurons <= to_unsigned(1, 8);
        num_deltas  <= to_unsigned(1, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until z_ready = '1';
        wait until rising_edge(clk);
        z_in <= ONE;  -- Active
        z_valid <= '1';
        wait until rising_edge(clk);
        z_valid <= '0';
        
        wait until weight_ready = '1';
        wait until rising_edge(clk);
        weight_in <= NEG_HALF;  -- W = -0.5
        delta_in  <= NEG_ONE;   -- δ = -1.0
        weight_valid <= '1';
        delta_valid  <= '1';
        wait until rising_edge(clk);
        weight_valid <= '0';
        delta_valid  <= '0';
        
        wait until delta_out_valid = '1' for 1 us;
        wait for 1 ns;
        
        actual_delta := to_real(delta_out);
        expected := 0.5;  -- (-0.5) × (-1.0) = 0.5
        if abs(actual_delta - expected) < tolerance then
            report "PASS Test 5: Negative values δ = " & real'image(actual_delta) severity note;
        else
            report "FAIL Test 5: Expected " & real'image(expected) & 
                   ", got " & real'image(actual_delta) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until done = '1' for 1 us;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 6: Zero Neurons
        -----------------------------------------------------------------------
        report "--- Test 6: Zero Neurons ---";
        test_count <= test_count + 1;
        
        num_neurons <= to_unsigned(0, 8);
        num_deltas  <= to_unsigned(1, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until done = '1' for 500 ns;
        wait for 1 ns;
        
        if done = '1' then
            report "PASS Test 6: Zero neurons completes immediately" severity note;
        else
            report "FAIL Test 6: Should complete immediately" severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 7: Zero Deltas (result should be 0 for active neuron)
        -----------------------------------------------------------------------
        report "--- Test 7: Zero Deltas ---";
        test_count <= test_count + 1;
        
        num_neurons <= to_unsigned(1, 8);
        num_deltas  <= to_unsigned(0, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until z_ready = '1';
        wait until rising_edge(clk);
        z_in <= ONE;  -- Active
        z_valid <= '1';
        wait until rising_edge(clk);
        z_valid <= '0';
        
        -- Should skip accumulation and output zero
        wait until delta_out_valid = '1' for 1 us;
        wait for 1 ns;
        
        actual_delta := to_real(delta_out);
        if abs(actual_delta) < tolerance then
            report "PASS Test 7: Zero deltas -> delta = 0" severity note;
        else
            report "FAIL Test 7: Expected 0, got " & real'image(actual_delta) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until done = '1' for 1 us;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 8: Output Ready Handshaking
        -----------------------------------------------------------------------
        report "--- Test 8: Output Ready Handshaking ---";
        test_count <= test_count + 1;
        
        delta_out_ready <= '0';  -- Don't accept output
        
        num_neurons <= to_unsigned(1, 8);
        num_deltas  <= to_unsigned(1, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until z_ready = '1';
        wait until rising_edge(clk);
        z_in <= ONE;
        z_valid <= '1';
        wait until rising_edge(clk);
        z_valid <= '0';
        
        wait until weight_ready = '1';
        wait until rising_edge(clk);
        weight_in <= ONE;
        delta_in  <= ONE;
        weight_valid <= '1';
        delta_valid  <= '1';
        wait until rising_edge(clk);
        weight_valid <= '0';
        delta_valid  <= '0';
        
        wait until delta_out_valid = '1' for 1 us;
        wait for CLK_PERIOD * 3;
        
        if delta_out_valid = '1' then
            report "PASS Test 8a: Holds output until accepted" severity note;
        else
            report "FAIL Test 8a: Should hold output" severity warning;
            error_count <= error_count + 1;
        end if;
        
        delta_out_ready <= '1';
        wait until rising_edge(clk);
        wait until done = '1' for 1 us;
        
        test_count <= test_count + 1;
        if done = '1' then
            report "PASS Test 8b: Proceeds after accept" severity note;
        else
            report "FAIL Test 8b: Should proceed" severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 9: Clear During Operation
        -----------------------------------------------------------------------
        report "--- Test 9: Clear During Operation ---";
        test_count <= test_count + 1;
        
        num_neurons <= to_unsigned(2, 8);
        num_deltas  <= to_unsigned(1, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until z_ready = '1';
        wait until rising_edge(clk);
        z_in <= ONE;
        z_valid <= '1';
        wait until rising_edge(clk);
        z_valid <= '0';
        
        -- Clear before completion
        wait for CLK_PERIOD * 2;
        clear <= '1';
        wait until rising_edge(clk);
        clear <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        if busy = '0' then
            report "PASS Test 9: Clear returns to IDLE" severity note;
        else
            report "FAIL Test 9: Should return to IDLE" severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 10: Reset Behavior
        -----------------------------------------------------------------------
        report "--- Test 10: Reset ---";
        test_count <= test_count + 1;
        
        num_neurons <= to_unsigned(1, 8);
        num_deltas  <= to_unsigned(1, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until z_ready = '1';
        wait until rising_edge(clk);
        z_in <= ONE;
        z_valid <= '1';
        wait until rising_edge(clk);
        z_valid <= '0';
        
        -- Reset mid-operation
        rst <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        if busy = '0' then
            report "PASS Test 10: Reset clears state" severity note;
        else
            report "FAIL Test 10: Reset should clear" severity warning;
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