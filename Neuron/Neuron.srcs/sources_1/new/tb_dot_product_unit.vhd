--------------------------------------------------------------------------------
-- Testbench: tb_dot_product_unit
-- Description: Comprehensive test for dot_product_unit module
--              Tests y = Σ(w[i] × x[i]) computation
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_dot_product_unit is
end entity tb_dot_product_unit;

architecture sim of tb_dot_product_unit is

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
    component dot_product_unit is
        generic (
            DATA_WIDTH   : integer := 16;
            ACCUM_WIDTH  : integer := 40;
            FRAC_BITS    : integer := 13;
            MAX_ELEMENTS : integer := 16
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            start        : in  std_logic;
            clear        : in  std_logic;
            num_elements : in  unsigned(7 downto 0);
            weight_in    : in  signed(DATA_WIDTH-1 downto 0);
            data_in      : in  signed(DATA_WIDTH-1 downto 0);
            data_valid   : in  std_logic;
            data_ready   : out std_logic;
            result_out   : out signed(ACCUM_WIDTH-1 downto 0);
            result_valid : out std_logic;
            out_ready    : in  std_logic;
            busy         : out std_logic;
            done         : out std_logic;
            overflow     : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal start        : std_logic := '0';
    signal clear        : std_logic := '0';
    signal num_elements : unsigned(7 downto 0) := (others => '0');
    signal weight_in    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal data_in      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal data_valid   : std_logic := '0';
    signal data_ready   : std_logic;
    signal result_out   : signed(ACCUM_WIDTH-1 downto 0);
    signal result_valid : std_logic;
    signal out_ready    : std_logic := '1';
    signal busy         : std_logic;
    signal done         : std_logic;
    signal overflow     : std_logic;
    
    -- Test tracking
    signal test_count   : integer := 0;
    signal error_count  : integer := 0;
    signal sim_done     : boolean := false;
    
    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    function to_real(val : signed) return real is
    begin
        return real(to_integer(val)) / real(2**FRAC_BITS);
    end function;
    
    -- Convert accumulator (Q4.26) to real
    -- Note: Accumulator holds Q4.26 after multiplication of two Q2.13 values
    function accum_to_real(val : signed) return real is
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
    dut : dot_product_unit
        generic map (
            DATA_WIDTH   => DATA_WIDTH,
            ACCUM_WIDTH  => ACCUM_WIDTH,
            FRAC_BITS    => FRAC_BITS,
            MAX_ELEMENTS => 16
        )
        port map (
            clk          => clk,
            rst          => rst,
            start        => start,
            clear        => clear,
            num_elements => num_elements,
            weight_in    => weight_in,
            data_in      => data_in,
            data_valid   => data_valid,
            data_ready   => data_ready,
            result_out   => result_out,
            result_valid => result_valid,
            out_ready    => out_ready,
            busy         => busy,
            done         => done,
            overflow     => overflow
        );

    ---------------------------------------------------------------------------
    -- Test Process
    ---------------------------------------------------------------------------
    test_proc : process
        variable actual_result : real;
        variable expected      : real;
        variable tolerance     : real := 0.001;
        
    begin
        -- Initialize
        rst          <= '1';
        start        <= '0';
        clear        <= '0';
        data_valid   <= '0';
        weight_in    <= (others => '0');
        data_in      <= (others => '0');
        num_elements <= (others => '0');
        out_ready    <= '1';
        
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "========================================";
        report "Starting dot_product_unit Tests";
        report "========================================";
        
        -----------------------------------------------------------------------
        -- Test 1: Single Element (1.0 × 1.0 = 1.0)
        -----------------------------------------------------------------------
        report "--- Test 1: Single Element ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(1, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        -- Wait for ready
        wait until data_ready = '1';
        wait until rising_edge(clk);
        
        -- Provide single pair
        weight_in  <= ONE;
        data_in    <= ONE;
        data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        
        -- Wait for done
        wait until done = '1' for 500 ns;
        wait for 1 ns;
        
        actual_result := accum_to_real(result_out);
        expected := 1.0;
        if abs(actual_result - expected) < tolerance then
            report "PASS Test 1: 1.0 x 1.0 = " & real'image(actual_result) severity note;
        else
            report "FAIL Test 1: Expected " & real'image(expected) & 
                   ", got " & real'image(actual_result) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 2: Two Elements ([1.0, 0.5] · [0.5, 1.0] = 0.5 + 0.5 = 1.0)
        -----------------------------------------------------------------------
        report "--- Test 2: Two Elements ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(2, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        
        -- First pair: 1.0 × 0.5
        wait until rising_edge(clk);
        weight_in <= ONE; data_in <= HALF; data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        wait until rising_edge(clk);
        
        -- Second pair: 0.5 × 1.0
        weight_in <= HALF; data_in <= ONE; data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        
        wait until done = '1' for 500 ns;
        wait for 1 ns;
        
        actual_result := accum_to_real(result_out);
        expected := 1.0;
        if abs(actual_result - expected) < tolerance then
            report "PASS Test 2: [1,0.5]·[0.5,1] = " & real'image(actual_result) severity note;
        else
            report "FAIL Test 2: Expected " & real'image(expected) & 
                   ", got " & real'image(actual_result) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 3: Four Elements with mixed signs
        -- [1, -0.5, 0.25, -0.25] · [1, 1, 1, 1] = 1 - 0.5 + 0.25 - 0.25 = 0.5
        -----------------------------------------------------------------------
        report "--- Test 3: Four Elements Mixed Signs ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(4, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        
        -- Pair 1: 1.0 × 1.0
        wait until rising_edge(clk);
        weight_in <= ONE; data_in <= ONE; data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        wait until rising_edge(clk);
        
        -- Pair 2: -0.5 × 1.0
        weight_in <= NEG_HALF; data_in <= ONE; data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        wait until rising_edge(clk);
        
        -- Pair 3: 0.25 × 1.0
        weight_in <= QUARTER; data_in <= ONE; data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        wait until rising_edge(clk);
        
        -- Pair 4: -0.25 × 1.0
        weight_in <= to_signed(-2048, DATA_WIDTH); data_in <= ONE; data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        
        wait until done = '1' for 500 ns;
        wait for 1 ns;
        
        actual_result := accum_to_real(result_out);
        expected := 0.5;
        if abs(actual_result - expected) < tolerance then
            report "PASS Test 3: Mixed signs = " & real'image(actual_result) severity note;
        else
            report "FAIL Test 3: Expected " & real'image(expected) & 
                   ", got " & real'image(actual_result) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 4: Zero Elements
        -----------------------------------------------------------------------
        report "--- Test 4: Zero Elements ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(0, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until done = '1' for 500 ns;
        wait for 1 ns;
        
        actual_result := accum_to_real(result_out);
        if abs(actual_result) < tolerance then
            report "PASS Test 4: Zero elements = " & real'image(actual_result) severity note;
        else
            report "FAIL Test 4: Expected 0, got " & real'image(actual_result) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 5: All Zeros (0 × anything = 0)
        -----------------------------------------------------------------------
        report "--- Test 5: All Zeros ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(3, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        
        for i in 0 to 2 loop
            wait until rising_edge(clk);
            weight_in <= ZERO_VAL; data_in <= ONE; data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
        end loop;
        
        wait until done = '1' for 500 ns;
        wait for 1 ns;
        
        actual_result := accum_to_real(result_out);
        if abs(actual_result) < tolerance then
            report "PASS Test 5: All zeros = " & real'image(actual_result) severity note;
        else
            report "FAIL Test 5: Expected 0, got " & real'image(actual_result) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 6: Negative Result
        -- [-1, -1] · [1, 1] = -2
        -----------------------------------------------------------------------
        report "--- Test 6: Negative Result ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(2, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        
        for i in 0 to 1 loop
            wait until rising_edge(clk);
            weight_in <= NEG_ONE; data_in <= ONE; data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
        end loop;
        
        wait until done = '1' for 500 ns;
        wait for 1 ns;
        
        actual_result := accum_to_real(result_out);
        expected := -2.0;
        if abs(actual_result - expected) < tolerance then
            report "PASS Test 6: Negative result = " & real'image(actual_result) severity note;
        else
            report "FAIL Test 6: Expected " & real'image(expected) & 
                   ", got " & real'image(actual_result) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 7: Larger Vector (8 elements)
        -- [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5] · [0.25, ...] = 8 × 0.125 = 1.0
        -----------------------------------------------------------------------
        report "--- Test 7: Larger Vector (8 elements) ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(8, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        
        for i in 0 to 7 loop
            wait until rising_edge(clk);
            weight_in <= HALF; data_in <= QUARTER; data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
        end loop;
        
        wait until done = '1' for 1 us;
        wait for 1 ns;
        
        actual_result := accum_to_real(result_out);
        expected := 1.0;  -- 8 × (0.5 × 0.25) = 8 × 0.125 = 1.0
        if abs(actual_result - expected) < tolerance then
            report "PASS Test 7: 8 elements = " & real'image(actual_result) severity note;
        else
            report "FAIL Test 7: Expected " & real'image(expected) & 
                   ", got " & real'image(actual_result) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 8: Clear During Operation
        -----------------------------------------------------------------------
        report "--- Test 8: Clear During Operation ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(4, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        
        -- Provide 2 pairs
        for i in 0 to 1 loop
            wait until rising_edge(clk);
            weight_in <= ONE; data_in <= ONE; data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
        end loop;
        
        -- Clear before completion
        wait until rising_edge(clk);
        clear <= '1';
        wait until rising_edge(clk);
        clear <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        if busy = '0' then
            report "PASS Test 8: Clear returns to IDLE" severity note;
        else
            report "FAIL Test 8: Should return to IDLE" severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 9: Out Ready Handshaking
        -----------------------------------------------------------------------
        report "--- Test 9: Out Ready Handshaking ---";
        test_count <= test_count + 1;
        
        out_ready <= '0';  -- Don't accept result
        
        num_elements <= to_unsigned(1, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        wait until rising_edge(clk);
        weight_in <= ONE; data_in <= ONE; data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        
        wait until done = '1' for 500 ns;
        wait for CLK_PERIOD * 3;
        
        if done = '1' and result_valid = '1' then
            report "PASS Test 9a: Holds result" severity note;
        else
            report "FAIL Test 9a: Should hold result" severity warning;
            error_count <= error_count + 1;
        end if;
        
        out_ready <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        
        test_count <= test_count + 1;
        if done = '0' then
            report "PASS Test 9b: Returns to IDLE" severity note;
        else
            report "FAIL Test 9b: Should return to IDLE" severity warning;
            error_count <= error_count + 1;
        end if;
        
        -----------------------------------------------------------------------
        -- Test 10: Reset Behavior
        -----------------------------------------------------------------------
        report "--- Test 10: Reset ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(2, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        wait until rising_edge(clk);
        weight_in <= ONE; data_in <= ONE; data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        
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
