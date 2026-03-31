--------------------------------------------------------------------------------
-- Testbench: gradient_register_bank_tb
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity gradient_register_bank_tb is
end entity gradient_register_bank_tb;

architecture sim of gradient_register_bank_tb is

    constant INPUT_WIDTH  : integer := 32;
    constant ACCUM_WIDTH  : integer := 40;
    constant NUM_ENTRIES  : integer := 13;
    constant ADDR_WIDTH   : integer := 4;
    constant CLK_PERIOD   : time := 10 ns;

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal clear      : std_logic := '0';
    signal accum_en   : std_logic := '0';
    signal accum_addr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal accum_data : signed(INPUT_WIDTH-1 downto 0) := (others => '0');
    signal rd_en      : std_logic := '0';
    signal rd_addr    : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal rd_data    : signed(ACCUM_WIDTH-1 downto 0);
    signal rd_valid   : std_logic;
    signal overflow   : std_logic;

    signal test_count : integer := 0;
    signal pass_count : integer := 0;
    signal fail_count : integer := 0;

begin

    clk <= not clk after CLK_PERIOD/2;

    DUT: entity work.gradient_register_bank
        generic map (
            INPUT_WIDTH  => INPUT_WIDTH,
            ACCUM_WIDTH  => ACCUM_WIDTH,
            NUM_ENTRIES  => NUM_ENTRIES,
            ADDR_WIDTH   => ADDR_WIDTH
        )
        port map (
            clk        => clk,
            rst        => rst,
            clear      => clear,
            accum_en   => accum_en,
            accum_addr => accum_addr,
            accum_data => accum_data,
            rd_en      => rd_en,
            rd_addr    => rd_addr,
            rd_data    => rd_data,
            rd_valid   => rd_valid,
            overflow   => overflow
        );

    test_proc: process
        
        procedure accumulate(addr : integer; value : integer) is
        begin
            accum_en   <= '1';
            accum_addr <= to_unsigned(addr, ADDR_WIDTH);
            accum_data <= to_signed(value, INPUT_WIDTH);
            wait for CLK_PERIOD;
            accum_en <= '0';
            wait for CLK_PERIOD;
        end procedure;
        
        procedure check_value(addr : integer; expected : integer; test_name : string) is
            variable exp_val : signed(ACCUM_WIDTH-1 downto 0);
        begin
            exp_val := to_signed(expected, ACCUM_WIDTH);
            rd_en   <= '1';
            rd_addr <= to_unsigned(addr, ADDR_WIDTH);
            wait for CLK_PERIOD;
            
            if rd_data = exp_val and rd_valid = '1' then
                report "PASS: " & test_name severity note;
                pass_count <= pass_count + 1;
            else
                report "FAIL: " & test_name & " | Expected=" & integer'image(expected) &
                       " Got=" & integer'image(to_integer(rd_data)) severity error;
                fail_count <= fail_count + 1;
            end if;
            
            rd_en <= '0';
            test_count <= test_count + 1;
            wait for CLK_PERIOD;
        end procedure;

    begin
        report "=== gradient_register_bank testbench ===" severity note;
        
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Test 1: Reset
        report "--- Test: Reset behavior ---" severity note;
        check_value(0, 0, "Reset addr 0");
        check_value(5, 0, "Reset addr 5");
        check_value(12, 0, "Reset addr 12");

        -- Test 2: Basic accumulation
        report "--- Test: Basic accumulation ---" severity note;
        accumulate(0, 1000);
        accumulate(1, 2000);
        accumulate(2, -3000);
        
        check_value(0, 1000, "Single accum addr 0");
        check_value(1, 2000, "Single accum addr 1");
        check_value(2, -3000, "Single accum addr 2");

        -- Test 3: Multiple accumulations
        report "--- Test: Multiple accumulations ---" severity note;
        accumulate(5, 100);
        accumulate(5, 200);
        accumulate(5, 300);
        accumulate(5, 400);
        check_value(5, 1000, "Multiple accum (100+200+300+400)");

        -- Test 4: Clear
        report "--- Test: Clear ---" severity note;
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD;
        
        check_value(0, 0, "After clear addr 0");
        check_value(5, 0, "After clear addr 5");

        -- Test 5: Large values
        report "--- Test: Large values ---" severity note;
        accumulate(0, 2147483647);
        check_value(0, 2147483647, "Large positive");
        
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD;
        
        accumulate(1, -2147483648);
        check_value(1, -2147483648, "Large negative");

        -- Test 6: Batch pattern
        report "--- Test: Batch gradient pattern ---" severity note;
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD;
        
        for sample in 0 to 3 loop
            for param in 0 to 12 loop
                accumulate(param, 100 + sample * 10 + param);
            end loop;
        end loop;
        
        check_value(0, 460, "Batch gradient addr 0");
        check_value(5, 480, "Batch gradient addr 5");
        check_value(12, 508, "Batch gradient addr 12");

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
