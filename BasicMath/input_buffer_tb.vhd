--------------------------------------------------------------------------------
-- Testbench: input_buffer_tb
-- Description: Verifies input_buffer functionality
--
-- Test Strategy:
--   1. Reset behavior
--   2. Sequential loading and ready flag
--   3. Random order loading
--   4. Clear functionality
--   5. Read operations
--   6. Typical input patterns
--
-- No textio used - uses assertions and report statements
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity input_buffer_tb is
end entity input_buffer_tb;

architecture sim of input_buffer_tb is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant DATA_WIDTH  : integer := 16;
    constant NUM_INPUTS  : integer := 4;
    constant ADDR_WIDTH  : integer := 2;
    constant CLK_PERIOD  : time := 10 ns;

    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal clear     : std_logic := '0';
    
    -- Load interface
    signal load_en   : std_logic := '0';
    signal load_addr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal load_data : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Read interface
    signal rd_en     : std_logic := '0';
    signal rd_addr   : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal rd_data   : signed(DATA_WIDTH-1 downto 0);
    
    -- Status
    signal ready     : std_logic;
    signal count     : unsigned(ADDR_WIDTH downto 0);

    ---------------------------------------------------------------------------
    -- Test tracking
    ---------------------------------------------------------------------------
    signal test_count : integer := 0;
    signal pass_count : integer := 0;
    signal fail_count : integer := 0;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD/2;

    ---------------------------------------------------------------------------
    -- Device Under Test
    ---------------------------------------------------------------------------
    DUT: entity work.input_buffer
        generic map (
            DATA_WIDTH  => DATA_WIDTH,
            NUM_INPUTS  => NUM_INPUTS,
            ADDR_WIDTH  => ADDR_WIDTH
        )
        port map (
            clk       => clk,
            rst       => rst,
            clear     => clear,
            load_en   => load_en,
            load_addr => load_addr,
            load_data => load_data,
            rd_en     => rd_en,
            rd_addr   => rd_addr,
            rd_data   => rd_data,
            ready     => ready,
            count     => count
        );

    ---------------------------------------------------------------------------
    -- Test Process
    ---------------------------------------------------------------------------
    test_proc: process
        
        -- Helper procedure to load a value
        procedure load_value(
            addr  : integer;
            value : integer
        ) is
        begin
            load_en <= '1';
            load_addr <= to_unsigned(addr, ADDR_WIDTH);
            load_data <= to_signed(value, DATA_WIDTH);
            wait for CLK_PERIOD;
            load_en <= '0';
            wait for CLK_PERIOD;
        end procedure;
        
        -- Helper procedure to check a value
        procedure check_value(
            addr     : integer;
            expected : integer;
            test_name: string
        ) is
        begin
            rd_en <= '1';
            rd_addr <= to_unsigned(addr, ADDR_WIDTH);
            wait for CLK_PERIOD;
            
            if to_integer(rd_data) = expected then
                report "PASS: " & test_name & 
                       " | Addr=" & integer'image(addr) &
                       " | Value=" & integer'image(to_integer(rd_data))
                    severity note;
                pass_count <= pass_count + 1;
            else
                report "FAIL: " & test_name & 
                       " | Addr=" & integer'image(addr) &
                       " | Expected=" & integer'image(expected) &
                       " | Got=" & integer'image(to_integer(rd_data))
                    severity error;
                fail_count <= fail_count + 1;
            end if;
            
            rd_en <= '0';
            test_count <= test_count + 1;
            wait for CLK_PERIOD;
        end procedure;
        
        -- Helper to check status
        procedure check_status(
            expected_ready : std_logic;
            expected_count : integer;
            test_name      : string
        ) is
        begin
            wait for CLK_PERIOD/2;  -- Sample mid-cycle
            
            if ready = expected_ready and to_integer(count) = expected_count then
                report "PASS: " & test_name & 
                       " | Ready=" & std_logic'image(ready) &
                       " | Count=" & integer'image(to_integer(count))
                    severity note;
                pass_count <= pass_count + 1;
            else
                report "FAIL: " & test_name & 
                       " | Expected ready=" & std_logic'image(expected_ready) &
                       " count=" & integer'image(expected_count) &
                       " | Got ready=" & std_logic'image(ready) &
                       " count=" & integer'image(to_integer(count))
                    severity error;
                fail_count <= fail_count + 1;
            end if;
            
            test_count <= test_count + 1;
            wait for CLK_PERIOD/2;
        end procedure;

    begin
        report "========================================" severity note;
        report "Starting input_buffer testbench" severity note;
        report "========================================" severity note;
        report "Configuration: " & integer'image(NUM_INPUTS) & " inputs x " &
               integer'image(DATA_WIDTH) & " bits" severity note;
        
        -- Initial reset
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD;

        -----------------------------------------------------------------------
        -- Test Group 1: Reset behavior
        -----------------------------------------------------------------------
        report "--- Test Group 1: Reset behavior ---" severity note;
        
        check_status('0', 0, "After reset - not ready");
        check_value(0, 0, "Reset addr 0");
        check_value(1, 0, "Reset addr 1");
        check_value(2, 0, "Reset addr 2");
        check_value(3, 0, "Reset addr 3");

        -----------------------------------------------------------------------
        -- Test Group 2: Sequential loading
        -----------------------------------------------------------------------
        report "--- Test Group 2: Sequential loading ---" severity note;
        
        -- Load first value
        load_value(0, 1000);
        check_status('0', 1, "After 1st load");
        
        -- Load second value
        load_value(1, 2000);
        check_status('0', 2, "After 2nd load");
        
        -- Load third value
        load_value(2, 3000);
        check_status('0', 3, "After 3rd load");
        
        -- Load fourth value - should become ready
        load_value(3, 4000);
        check_status('1', 4, "After 4th load - ready");
        
        -- Verify all values
        check_value(0, 1000, "Seq load addr 0");
        check_value(1, 2000, "Seq load addr 1");
        check_value(2, 3000, "Seq load addr 2");
        check_value(3, 4000, "Seq load addr 3");

        -----------------------------------------------------------------------
        -- Test Group 3: Clear functionality
        -----------------------------------------------------------------------
        report "--- Test Group 3: Clear ---" severity note;
        
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD;
        
        check_status('0', 0, "After clear - not ready");
        check_value(0, 0, "Clear addr 0");
        check_value(3, 0, "Clear addr 3");

        -----------------------------------------------------------------------
        -- Test Group 4: Random order loading
        -----------------------------------------------------------------------
        report "--- Test Group 4: Random order loading ---" severity note;
        
        -- Load in non-sequential order
        load_value(2, 300);
        check_status('0', 1, "After addr 2");
        
        load_value(0, 100);
        check_status('0', 2, "After addr 0");
        
        load_value(3, 400);
        check_status('0', 3, "After addr 3");
        
        load_value(1, 200);
        check_status('1', 4, "After addr 1 - ready");
        
        -- Verify values
        check_value(0, 100, "Random addr 0");
        check_value(1, 200, "Random addr 1");
        check_value(2, 300, "Random addr 2");
        check_value(3, 400, "Random addr 3");

        -----------------------------------------------------------------------
        -- Test Group 5: Overwrite existing values
        -----------------------------------------------------------------------
        report "--- Test Group 5: Overwrite values ---" severity note;
        
        -- Overwrite without clear
        load_value(1, 999);
        check_value(1, 999, "Overwrite addr 1");
        check_status('1', 4, "Still ready after overwrite");

        -----------------------------------------------------------------------
        -- Test Group 6: Typical neural network input pattern
        -----------------------------------------------------------------------
        report "--- Test Group 6: NN input pattern ---" severity note;
        
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD;
        
        -- Load typical normalized inputs (range -1 to 1)
        load_value(0, 4096);    -- 0.5
        load_value(1, -4096);   -- -0.5
        load_value(2, 8192);    -- 1.0
        load_value(3, -8192);   -- -1.0
        
        check_status('1', 4, "NN inputs loaded");
        check_value(0, 4096, "Input 0.5");
        check_value(1, -4096, "Input -0.5");
        check_value(2, 8192, "Input 1.0");
        check_value(3, -8192, "Input -1.0");

        -----------------------------------------------------------------------
        -- Test Group 7: Boundary values
        -----------------------------------------------------------------------
        report "--- Test Group 7: Boundary values ---" severity note;
        
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD;
        
        load_value(0, 32767);   -- Max
        load_value(1, -32768);  -- Min
        load_value(2, 0);       -- Zero
        load_value(3, 1);       -- Smallest positive
        
        check_value(0, 32767, "Max value");
        check_value(1, -32768, "Min value");
        check_value(2, 0, "Zero value");
        check_value(3, 1, "Smallest positive");

        -----------------------------------------------------------------------
        -- Test Group 8: Reset vs Clear
        -----------------------------------------------------------------------
        report "--- Test Group 8: Reset vs Clear ---" severity note;
        
        -- Verify reset also clears
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;
        
        check_status('0', 0, "After reset");
        check_value(0, 0, "Post-reset addr 0");

        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        wait for CLK_PERIOD * 2;
        report "========================================" severity note;
        report "Test Summary:" severity note;
        report "  Total tests: " & integer'image(test_count) severity note;
        report "  Passed:      " & integer'image(pass_count) severity note;
        report "  Failed:      " & integer'image(fail_count) severity note;
        report "========================================" severity note;
        
        if fail_count = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "SOME TESTS FAILED!" severity error;
        end if;

        wait;
    end process;

end architecture sim;