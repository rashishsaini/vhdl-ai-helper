--------------------------------------------------------------------------------
-- Testbench: tb_vector_accumulator
-- Description: Comprehensive test for vector_accumulator module
--              Tests y = Σ x[i] computation
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_vector_accumulator is
end entity tb_vector_accumulator;

architecture sim of tb_vector_accumulator is

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
    constant ZERO_VAL  : signed(DATA_WIDTH-1 downto 0) := to_signed(0, DATA_WIDTH);

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component vector_accumulator is
        generic (
            DATA_WIDTH   : integer := 16;
            ACCUM_WIDTH  : integer := 40;
            FRAC_BITS    : integer := 13;
            MAX_ELEMENTS : integer := 16;
            ENABLE_SAT   : boolean := true
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            start        : in  std_logic;
            clear        : in  std_logic;
            num_elements : in  unsigned(7 downto 0);
            data_in      : in  signed(DATA_WIDTH-1 downto 0);
            data_valid   : in  std_logic;
            data_ready   : out std_logic;
            accum_out    : out signed(ACCUM_WIDTH-1 downto 0);
            result_valid : out std_logic;
            out_ready    : in  std_logic;
            busy         : out std_logic;
            done         : out std_logic;
            overflow     : out std_logic;
            elem_count   : out unsigned(7 downto 0)
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
    signal data_in      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal data_valid   : std_logic := '0';
    signal data_ready   : std_logic;
    signal accum_out    : signed(ACCUM_WIDTH-1 downto 0);
    signal result_valid : std_logic;
    signal out_ready    : std_logic := '1';
    signal busy         : std_logic;
    signal done         : std_logic;
    signal overflow     : std_logic;
    signal elem_count   : unsigned(7 downto 0);
    
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
    
    function to_fixed(val : real) return signed is
        variable temp : integer;
    begin
        temp := integer(val * real(2**FRAC_BITS));
        if temp > 32767 then temp := 32767; end if;
        if temp < -32768 then temp := -32768; end if;
        return to_signed(temp, DATA_WIDTH);
    end function;
    
    -- Convert accumulator (Q10.26) to real
    function accum_to_real(val : signed) return real is
    begin
        return real(to_integer(val)) / real(2**FRAC_BITS);
    end function;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD/2 when not sim_done else '0';

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : vector_accumulator
        generic map (
            DATA_WIDTH   => DATA_WIDTH,
            ACCUM_WIDTH  => ACCUM_WIDTH,
            FRAC_BITS    => FRAC_BITS,
            MAX_ELEMENTS => 16,
            ENABLE_SAT   => true
        )
        port map (
            clk          => clk,
            rst          => rst,
            start        => start,
            clear        => clear,
            num_elements => num_elements,
            data_in      => data_in,
            data_valid   => data_valid,
            data_ready   => data_ready,
            accum_out    => accum_out,
            result_valid => result_valid,
            out_ready    => out_ready,
            busy         => busy,
            done         => done,
            overflow     => overflow,
            elem_count   => elem_count
        );

    ---------------------------------------------------------------------------
    -- Test Process
    ---------------------------------------------------------------------------
    test_proc : process
        variable expected_sum : real;
        variable actual_sum   : real;
        variable tolerance    : real := 0.001;
        
        -- Procedure to accumulate a vector
        procedure accumulate_vector(
            vec_name     : string;
            values       : in signed;  -- Dummy, we'll pass one at a time
            num          : integer;
            expected     : real;
            tol          : real := 0.01
        ) is
        begin
            -- Start accumulation
            num_elements <= to_unsigned(num, 8);
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';
            wait until rising_edge(clk);
        end procedure;
        
    begin
        -- Initialize
        rst          <= '1';
        start        <= '0';
        clear        <= '0';
        data_valid   <= '0';
        data_in      <= (others => '0');
        num_elements <= (others => '0');
        out_ready    <= '1';
        
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "========================================";
        report "Starting vector_accumulator Tests";
        report "========================================";
        
        -----------------------------------------------------------------------
        -- Test 1: Single Element
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
        
        -- Provide single value
        data_in    <= ONE;  -- 1.0
        data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        
        -- Wait for done
        wait until done = '1';
        wait for 1 ns;
        
        actual_sum := accum_to_real(accum_out);
        if abs(actual_sum - 1.0) < 0.01 then
            report "PASS Test 1: Single element sum = " & real'image(actual_sum) severity note;
        else
            report "FAIL Test 1: Expected 1.0, got " & real'image(actual_sum) severity warning;
            error_count <= error_count + 1;
        end if;
        
        -- Acknowledge result
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 2: Multiple Elements (Same Value)
        -----------------------------------------------------------------------
        report "--- Test 2: Multiple Same Values ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(4, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        -- Wait for ready
        wait until data_ready = '1';
        
        -- Provide 4 values of 0.5 each
        for i in 0 to 3 loop
            wait until rising_edge(clk);
            data_in    <= HALF;
            data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
        end loop;
        
        -- Wait for done
        wait until done = '1';
        wait for 1 ns;
        
        actual_sum := accum_to_real(accum_out);
        if abs(actual_sum - 2.0) < 0.01 then
            report "PASS Test 2: Sum of 4x0.5 = " & real'image(actual_sum) severity note;
        else
            report "FAIL Test 2: Expected 2.0, got " & real'image(actual_sum) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 3: Mixed Positive and Negative
        -----------------------------------------------------------------------
        report "--- Test 3: Mixed Positive/Negative ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(4, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        
        -- Values: 1.0, -0.5, 0.25, -0.25 = 0.5
        wait until rising_edge(clk);
        data_in <= ONE; data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        wait until rising_edge(clk);
        
        data_in <= to_signed(-4096, DATA_WIDTH); data_valid <= '1';  -- -0.5
        wait until rising_edge(clk);
        data_valid <= '0';
        wait until rising_edge(clk);
        
        data_in <= QUARTER; data_valid <= '1';  -- 0.25
        wait until rising_edge(clk);
        data_valid <= '0';
        wait until rising_edge(clk);
        
        data_in <= to_signed(-2048, DATA_WIDTH); data_valid <= '1';  -- -0.25
        wait until rising_edge(clk);
        data_valid <= '0';
        
        wait until done = '1';
        wait for 1 ns;
        
        actual_sum := accum_to_real(accum_out);
        if abs(actual_sum - 0.5) < 0.01 then
            report "PASS Test 3: Mixed sum = " & real'image(actual_sum) severity note;
        else
            report "FAIL Test 3: Expected 0.5, got " & real'image(actual_sum) severity warning;
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
        
        -- Wait for done signal - should be quick for zero elements
        wait until done = '1' for 200 ns;
        wait for 1 ns;
        
        if done = '1' then
            report "PASS Test 4: Zero elements completes" severity note;
        else
            report "FAIL Test 4: Zero elements timed out" severity warning;
            error_count <= error_count + 1;
        end if;
        
        -- Acknowledge happens automatically since out_ready='1'
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 5: Clear During Accumulation
        -----------------------------------------------------------------------
        report "--- Test 5: Clear During Accumulation ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(4, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        
        -- Provide 2 values
        wait until rising_edge(clk);
        data_in <= ONE; data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        wait until rising_edge(clk);
        
        data_in <= ONE; data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        
        -- Clear before completion
        wait until rising_edge(clk);
        clear <= '1';
        wait until rising_edge(clk);
        clear <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        if busy = '0' and accum_out = (accum_out'range => '0') then
            report "PASS Test 5: Clear resets accumulator" severity note;
        else
            report "FAIL Test 5: Clear should reset" severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 6: Element Count Tracking
        -----------------------------------------------------------------------
        report "--- Test 6: Element Count ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(3, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        
        for i in 0 to 2 loop
            wait until rising_edge(clk);
            data_in <= HALF; data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
        end loop;
        
        wait until done = '1';
        wait for 1 ns;
        
        if elem_count = 3 then
            report "PASS Test 6: Element count = 3" severity note;
        else
            report "FAIL Test 6: Expected count 3, got " & integer'image(to_integer(elem_count)) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 7: Busy Signal
        -----------------------------------------------------------------------
        report "--- Test 7: Busy Signal ---";
        test_count <= test_count + 1;
        
        -- Check busy is low before start
        if busy = '0' then
            report "PASS Test 7a: Busy is low in IDLE" severity note;
        else
            report "FAIL Test 7a: Busy should be low" severity warning;
            error_count <= error_count + 1;
        end if;
        
        num_elements <= to_unsigned(2, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        test_count <= test_count + 1;
        if busy = '1' then
            report "PASS Test 7b: Busy is high during accumulation" severity note;
        else
            report "FAIL Test 7b: Busy should be high" severity warning;
            error_count <= error_count + 1;
        end if;
        
        -- Complete the accumulation - feed data directly
        for i in 0 to 1 loop
            wait until rising_edge(clk);
            data_in <= QUARTER; data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
        end loop;
        
        wait until done = '1' for 500 ns;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 8: Larger Vector
        -----------------------------------------------------------------------
        report "--- Test 8: Larger Vector (8 elements) ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(8, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        
        -- Sum of 8 × 0.125 = 1.0
        for i in 0 to 7 loop
            wait until rising_edge(clk);
            data_in <= to_signed(1024, DATA_WIDTH);  -- 0.125
            data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
        end loop;
        
        wait until done = '1';
        wait for 1 ns;
        
        actual_sum := accum_to_real(accum_out);
        if abs(actual_sum - 1.0) < 0.01 then
            report "PASS Test 8: Sum of 8x0.125 = " & real'image(actual_sum) severity note;
        else
            report "FAIL Test 8: Expected 1.0, got " & real'image(actual_sum) severity warning;
            error_count <= error_count + 1;
        end if;
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        -----------------------------------------------------------------------
        -- Test 9: Out Ready Handshaking
        -----------------------------------------------------------------------
        report "--- Test 9: Out Ready Handshaking ---";
        test_count <= test_count + 1;
        
        out_ready <= '0';  -- Don't accept result yet
        
        num_elements <= to_unsigned(2, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        
        for i in 0 to 1 loop
            wait until rising_edge(clk);
            data_in <= ONE; data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
        end loop;
        
        wait until done = '1';
        wait for CLK_PERIOD * 3;
        
        -- Should still be in DONE state
        if done = '1' and result_valid = '1' then
            report "PASS Test 9a: Holds result until accepted" severity note;
        else
            report "FAIL Test 9a: Should hold result" severity warning;
            error_count <= error_count + 1;
        end if;
        
        -- Accept result
        out_ready <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        
        test_count <= test_count + 1;
        if done = '0' then
            report "PASS Test 9b: Returns to IDLE after accept" severity note;
        else
            report "FAIL Test 9b: Should return to IDLE" severity warning;
            error_count <= error_count + 1;
        end if;
        
        -----------------------------------------------------------------------
        -- Test 10: Reset Behavior
        -----------------------------------------------------------------------
        report "--- Test 10: Reset ---";
        test_count <= test_count + 1;
        
        num_elements <= to_unsigned(3, 8);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        wait until data_ready = '1';
        wait until rising_edge(clk);
        data_in <= ONE; data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';
        
        -- Reset mid-accumulation
        rst <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        
        if busy = '0' and accum_out = (accum_out'range => '0') then
            report "PASS Test 10: Reset clears everything" severity note;
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
