--------------------------------------------------------------------------------
-- Testbench: forward_cache_tb
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity forward_cache_tb is
end entity forward_cache_tb;

architecture sim of forward_cache_tb is

    constant DATA_WIDTH    : integer := 16;
    constant NUM_Z_VALUES  : integer := 3;
    constant NUM_A_VALUES  : integer := 7;
    constant Z_ADDR_WIDTH  : integer := 2;
    constant A_ADDR_WIDTH  : integer := 3;
    constant CLK_PERIOD    : time := 10 ns;

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal clear       : std_logic := '0';
    
    signal z_wr_en     : std_logic := '0';
    signal z_wr_addr   : unsigned(Z_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal z_wr_data   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal z_rd_en     : std_logic := '0';
    signal z_rd_addr   : unsigned(Z_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal z_rd_data   : signed(DATA_WIDTH-1 downto 0);
    signal z_rd_valid  : std_logic;
    
    signal a_wr_en     : std_logic := '0';
    signal a_wr_addr   : unsigned(A_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal a_wr_data   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal a_rd_en     : std_logic := '0';
    signal a_rd_addr   : unsigned(A_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal a_rd_data   : signed(DATA_WIDTH-1 downto 0);
    signal a_rd_valid  : std_logic;

    signal test_count  : integer := 0;
    signal pass_count  : integer := 0;
    signal fail_count  : integer := 0;

begin

    clk <= not clk after CLK_PERIOD/2;

    DUT: entity work.forward_cache
        generic map (
            DATA_WIDTH    => DATA_WIDTH,
            NUM_Z_VALUES  => NUM_Z_VALUES,
            NUM_A_VALUES  => NUM_A_VALUES,
            Z_ADDR_WIDTH  => Z_ADDR_WIDTH,
            A_ADDR_WIDTH  => A_ADDR_WIDTH
        )
        port map (
            clk         => clk,
            rst         => rst,
            clear       => clear,
            z_wr_en     => z_wr_en,
            z_wr_addr   => z_wr_addr,
            z_wr_data   => z_wr_data,
            z_rd_en     => z_rd_en,
            z_rd_addr   => z_rd_addr,
            z_rd_data   => z_rd_data,
            z_rd_valid  => z_rd_valid,
            a_wr_en     => a_wr_en,
            a_wr_addr   => a_wr_addr,
            a_wr_data   => a_wr_data,
            a_rd_en     => a_rd_en,
            a_rd_addr   => a_rd_addr,
            a_rd_data   => a_rd_data,
            a_rd_valid  => a_rd_valid
        );

    test_proc: process
        
        procedure write_z(addr : integer; value : integer) is
        begin
            z_wr_en   <= '1';
            z_wr_addr <= to_unsigned(addr, Z_ADDR_WIDTH);
            z_wr_data <= to_signed(value, DATA_WIDTH);
            wait for CLK_PERIOD;
            z_wr_en <= '0';
            wait for CLK_PERIOD;
        end procedure;
        
        procedure write_a(addr : integer; value : integer) is
        begin
            a_wr_en   <= '1';
            a_wr_addr <= to_unsigned(addr, A_ADDR_WIDTH);
            a_wr_data <= to_signed(value, DATA_WIDTH);
            wait for CLK_PERIOD;
            a_wr_en <= '0';
            wait for CLK_PERIOD;
        end procedure;
        
        procedure check_z(addr : integer; expected : integer; test_name : string) is
        begin
            z_rd_en   <= '1';
            z_rd_addr <= to_unsigned(addr, Z_ADDR_WIDTH);
            wait for CLK_PERIOD;
            
            if to_integer(z_rd_data) = expected and z_rd_valid = '1' then
                report "PASS: Z " & test_name severity note;
                pass_count <= pass_count + 1;
            else
                report "FAIL: Z " & test_name & " | Exp=" & integer'image(expected) &
                       " Got=" & integer'image(to_integer(z_rd_data)) severity error;
                fail_count <= fail_count + 1;
            end if;
            
            z_rd_en <= '0';
            test_count <= test_count + 1;
            wait for CLK_PERIOD;
        end procedure;
        
        procedure check_a(addr : integer; expected : integer; test_name : string) is
        begin
            a_rd_en   <= '1';
            a_rd_addr <= to_unsigned(addr, A_ADDR_WIDTH);
            wait for CLK_PERIOD;
            
            if to_integer(a_rd_data) = expected and a_rd_valid = '1' then
                report "PASS: A " & test_name severity note;
                pass_count <= pass_count + 1;
            else
                report "FAIL: A " & test_name & " | Exp=" & integer'image(expected) &
                       " Got=" & integer'image(to_integer(a_rd_data)) severity error;
                fail_count <= fail_count + 1;
            end if;
            
            a_rd_en <= '0';
            test_count <= test_count + 1;
            wait for CLK_PERIOD;
        end procedure;

    begin
        report "=== forward_cache testbench ===" severity note;
        
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Test 1: Reset
        report "--- Test: Reset behavior ---" severity note;
        check_z(0, 0, "Reset z[0]");
        check_z(1, 0, "Reset z[1]");
        check_z(2, 0, "Reset z[2]");
        check_a(0, 0, "Reset a[0]");
        check_a(3, 0, "Reset a[3]");
        check_a(6, 0, "Reset a[6]");

        -- Test 2: Z cache operations
        report "--- Test: Z cache ops ---" severity note;
        write_z(0, 1000);
        write_z(1, 2000);
        write_z(2, -3000);
        
        check_z(0, 1000, "Write z[0]");
        check_z(1, 2000, "Write z[1]");
        check_z(2, -3000, "Write z[2]");

        -- Test 3: A cache operations
        report "--- Test: A cache ops ---" severity note;
        write_a(0, 4096);
        write_a(1, -4096);
        write_a(4, 6000);
        write_a(6, 5000);
        
        check_a(0, 4096, "Write a[0]");
        check_a(1, -4096, "Write a[1]");
        check_a(4, 6000, "Write a[4]");
        check_a(6, 5000, "Write a[6]");

        -- Test 4: Clear
        report "--- Test: Clear ---" severity note;
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD;
        
        check_z(0, 0, "Clear z[0]");
        check_z(2, 0, "Clear z[2]");
        check_a(0, 0, "Clear a[0]");
        check_a(6, 0, "Clear a[6]");

        -- Test 5: Independence
        report "--- Test: Z/A independence ---" severity note;
        write_z(0, 111);
        write_z(1, 222);
        check_a(0, 0, "A unchanged after Z write");
        
        write_a(0, 333);
        write_a(1, 444);
        check_z(0, 111, "Z unchanged after A write");
        check_z(1, 222, "Z unchanged after A write");

        -- Test 6: Forward pass pattern
        report "--- Test: Forward pass ---" severity note;
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD;
        
        -- Input layer activations
        write_a(0, 4096);
        write_a(1, 8192);
        write_a(2, -4096);
        write_a(3, 0);
        
        -- Hidden layer
        write_z(0, 12000);
        write_a(4, 12000);
        write_z(1, -5000);
        write_a(5, 0);
        
        -- Output layer
        write_z(2, 8000);
        write_a(6, 8000);
        
        check_a(0, 4096, "FP input a[0]");
        check_a(1, 8192, "FP input a[1]");
        check_z(0, 12000, "FP hidden z[0]");
        check_a(4, 12000, "FP hidden a[4]");
        check_z(2, 8000, "FP output z[2]");
        check_a(6, 8000, "FP output a[6]");

        -- Test 7: Boundary values
        report "--- Test: Boundary values ---" severity note;
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD;
        
        write_z(0, 32767);
        write_z(1, -32768);
        write_a(0, 32767);
        write_a(1, -32768);
        
        check_z(0, 32767, "Max Z");
        check_z(1, -32768, "Min Z");
        check_a(0, 32767, "Max A");
        check_a(1, -32768, "Min A");

        -- Summary
        wait for CLK_PERIOD * 2;
        report "===================================" severity note;
        report "Total: " & integer'image(test_count) & " | Pass: " & 
               integer'image(pass_count) & " | Fail: " & integer'image(fail_count) severity note;
        
        if fail_count = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "SOME TESTS FAILED!" severity warning;
        end if;

        wait;
    end process;

end architecture sim;
