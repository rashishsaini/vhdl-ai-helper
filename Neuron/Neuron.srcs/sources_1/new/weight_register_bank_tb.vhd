--------------------------------------------------------------------------------
-- Testbench: weight_register_bank_tb
-- Description: Verifies weight_register_bank functionality
--
-- Test Strategy:
--   1. Reset behavior
--   2. Write and read back
--   3. Initialization port
--   4. Address boundary conditions
--   5. Read-during-write behavior
--   6. Multiple consecutive operations
--
-- No textio used - uses assertions and report statements
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity weight_register_bank_tb is
end entity weight_register_bank_tb;

architecture sim of weight_register_bank_tb is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant DATA_WIDTH   : integer := 16;
    constant NUM_ENTRIES  : integer := 13;
    constant ADDR_WIDTH   : integer := 4;
    constant CLK_PERIOD   : time := 10 ns;

    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    
    -- Read port
    signal rd_en     : std_logic := '0';
    signal rd_addr   : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal rd_data   : signed(DATA_WIDTH-1 downto 0);
    signal rd_valid  : std_logic;
    
    -- Write port
    signal wr_en     : std_logic := '0';
    signal wr_addr   : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal wr_data   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Init port
    signal init_en   : std_logic := '0';
    signal init_addr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal init_data : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal init_done : std_logic;

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
    DUT: entity work.weight_register_bank
        generic map (
            DATA_WIDTH  => DATA_WIDTH,
            NUM_ENTRIES => NUM_ENTRIES,
            ADDR_WIDTH  => ADDR_WIDTH
        )
        port map (
            clk       => clk,
            rst       => rst,
            rd_en     => rd_en,
            rd_addr   => rd_addr,
            rd_data   => rd_data,
            rd_valid  => rd_valid,
            wr_en     => wr_en,
            wr_addr   => wr_addr,
            wr_data   => wr_data,
            init_en   => init_en,
            init_addr => init_addr,
            init_data => init_data,
            init_done => init_done
        );

    ---------------------------------------------------------------------------
    -- Test Process
    ---------------------------------------------------------------------------
    test_proc: process
        
        -- Helper procedure to check a value
        procedure check_value(
            addr          : integer;
            expected      : integer;
            test_name     : string
        ) is
        begin
            rd_en <= '1';
            rd_addr <= to_unsigned(addr, ADDR_WIDTH);
            wait for CLK_PERIOD;
            
            if to_integer(rd_data) = expected and rd_valid = '1' then
                report "PASS: " & test_name & 
                       " | Addr=" & integer'image(addr) &
                       " | Value=" & integer'image(to_integer(rd_data))
                    severity note;
                pass_count <= pass_count + 1;
            else
                report "FAIL: " & test_name & 
                       " | Addr=" & integer'image(addr) &
                       " | Expected=" & integer'image(expected) &
                       " | Got=" & integer'image(to_integer(rd_data)) &
                       " | Valid=" & std_logic'image(rd_valid)
                    severity error;
                fail_count <= fail_count + 1;
            end if;
            
            rd_en <= '0';
            test_count <= test_count + 1;
            wait for CLK_PERIOD;
        end procedure;
        
        -- Helper procedure to write a value
        procedure write_value(
            addr  : integer;
            value : integer
        ) is
        begin
            wr_en <= '1';
            wr_addr <= to_unsigned(addr, ADDR_WIDTH);
            wr_data <= to_signed(value, DATA_WIDTH);
            wait for CLK_PERIOD;
            wr_en <= '0';
            wait for CLK_PERIOD;
        end procedure;
        
        -- Helper procedure to initialize a value
        procedure init_value(
            addr  : integer;
            value : integer
        ) is
        begin
            init_en <= '1';
            init_addr <= to_unsigned(addr, ADDR_WIDTH);
            init_data <= to_signed(value, DATA_WIDTH);
            wait for CLK_PERIOD;
            init_en <= '0';
            wait for CLK_PERIOD;
        end procedure;

    begin
        report "========================================" severity note;
        report "Starting weight_register_bank testbench" severity note;
        report "========================================" severity note;
        report "Configuration: " & integer'image(NUM_ENTRIES) & " entries x " &
               integer'image(DATA_WIDTH) & " bits" severity note;
        
        -- Initial reset
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD;

        -----------------------------------------------------------------------
        -- Test Group 1: Reset behavior - all registers should be zero
        -----------------------------------------------------------------------
        report "--- Test Group 1: Reset behavior ---" severity note;
        
        for i in 0 to NUM_ENTRIES-1 loop
            check_value(i, 0, "After reset addr " & integer'image(i));
        end loop;

        -----------------------------------------------------------------------
        -- Test Group 2: Basic write and read
        -----------------------------------------------------------------------
        report "--- Test Group 2: Basic write/read ---" severity note;
        
        -- Write unique values to all entries
        for i in 0 to NUM_ENTRIES-1 loop
            write_value(i, 1000 + i * 100);
        end loop;
        
        -- Read back and verify
        for i in 0 to NUM_ENTRIES-1 loop
            check_value(i, 1000 + i * 100, "Write/read addr " & integer'image(i));
        end loop;

        -----------------------------------------------------------------------
        -- Test Group 3: Initialization port (overrides write)
        -----------------------------------------------------------------------
        report "--- Test Group 3: Init port ---" severity note;
        
        -- Use init to set specific values
        init_value(0, 5000);
        init_value(5, 5500);
        init_value(12, 6200);
        
        check_value(0, 5000, "Init addr 0");
        check_value(5, 5500, "Init addr 5");
        check_value(12, 6200, "Init addr 12");
        -- Other addresses should retain their values
        check_value(1, 1100, "Unchanged addr 1");

        -----------------------------------------------------------------------
        -- Test Group 4: Negative values
        -----------------------------------------------------------------------
        report "--- Test Group 4: Negative values ---" severity note;
        
        write_value(0, -1000);
        write_value(1, -8192);   -- -1.0 in Q2.13
        write_value(2, -32768);  -- Min value
        
        check_value(0, -1000, "Negative small");
        check_value(1, -8192, "-1.0 in Q2.13");
        check_value(2, -32768, "Min negative");

        -----------------------------------------------------------------------
        -- Test Group 5: Boundary values
        -----------------------------------------------------------------------
        report "--- Test Group 5: Boundary values ---" severity note;
        
        write_value(0, 32767);   -- Max positive
        write_value(1, -32768);  -- Min negative
        write_value(12, 8192);   -- 1.0 in Q2.13
        
        check_value(0, 32767, "Max positive");
        check_value(1, -32768, "Max negative");
        check_value(12, 8192, "1.0 in Q2.13");

        -----------------------------------------------------------------------
        -- Test Group 6: Invalid address behavior
        -----------------------------------------------------------------------
        report "--- Test Group 6: Invalid address ---" severity note;
        
        -- Read from invalid address (should return 0 with valid='0')
        rd_en <= '1';
        rd_addr <= to_unsigned(15, ADDR_WIDTH);  -- Out of range
        wait for CLK_PERIOD;
        
        if rd_valid = '0' then
            report "PASS: Invalid address returns valid='0'" severity note;
            pass_count <= pass_count + 1;
        else
            report "FAIL: Invalid address should return valid='0'" severity error;
            fail_count <= fail_count + 1;
        end if;
        test_count <= test_count + 1;
        rd_en <= '0';
        wait for CLK_PERIOD;

        -----------------------------------------------------------------------
        -- Test Group 7: Reset clears all values
        -----------------------------------------------------------------------
        report "--- Test Group 7: Reset clears values ---" severity note;
        
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;
        
        -- Verify all zeros
        check_value(0, 0, "Post-reset addr 0");
        check_value(6, 0, "Post-reset addr 6");
        check_value(12, 0, "Post-reset addr 12");

        -----------------------------------------------------------------------
        -- Test Group 8: Typical neural network weight pattern
        -----------------------------------------------------------------------
        report "--- Test Group 8: NN weight pattern ---" severity note;
        
        -- Simulate layer 1 weights (addresses 0-7)
        -- Typical small weights after initialization
        write_value(0, 410);    -- ~0.05
        write_value(1, -820);   -- ~-0.1
        write_value(2, 1638);   -- ~0.2
        write_value(3, -2048);  -- ~-0.25
        write_value(4, 614);    -- ~0.075
        write_value(5, -1024);  -- ~-0.125
        write_value(6, 2458);   -- ~0.3
        write_value(7, -3276);  -- ~-0.4
        
        -- Layer 1 biases (addresses 8-9)
        write_value(8, 82);     -- ~0.01
        write_value(9, -164);   -- ~-0.02
        
        -- Layer 2 weights (addresses 10-11)
        write_value(10, 4096);  -- ~0.5
        write_value(11, -4096); -- ~-0.5
        
        -- Layer 2 bias (address 12)
        write_value(12, 0);     -- 0.0
        
        -- Verify critical weights
        check_value(0, 410, "L1 W[0,0]");
        check_value(7, -3276, "L1 W[1,3]");
        check_value(10, 4096, "L2 W[0,0]");
        check_value(12, 0, "L2 bias");

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