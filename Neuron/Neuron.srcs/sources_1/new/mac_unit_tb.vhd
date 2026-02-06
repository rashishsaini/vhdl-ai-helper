--------------------------------------------------------------------------------
-- Testbench: mac_unit_tb
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity mac_unit_tb is
end entity mac_unit_tb;

architecture sim of mac_unit_tb is

    constant DATA_WIDTH    : integer := 16;
    constant PRODUCT_WIDTH : integer := 32;
    constant ACCUM_WIDTH   : integer := 40;
    constant CLK_PERIOD    : time := 10 ns;
    constant ONE_Q213      : integer := 8192;

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal clear      : std_logic := '0';
    signal enable     : std_logic := '0';
    signal data_in    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal weight     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal accum_out  : signed(ACCUM_WIDTH-1 downto 0);
    signal valid      : std_logic;
    signal overflow   : std_logic;
    signal busy       : std_logic;

    signal test_count : integer := 0;
    signal pass_count : integer := 0;
    signal fail_count : integer := 0;

begin

    clk <= not clk after CLK_PERIOD/2;

    DUT: entity work.mac_unit
        generic map (
            DATA_WIDTH    => DATA_WIDTH,
            PRODUCT_WIDTH => PRODUCT_WIDTH,
            ACCUM_WIDTH   => ACCUM_WIDTH,
            ENABLE_SAT    => true
        )
        port map (
            clk       => clk,
            rst       => rst,
            clear     => clear,
            enable    => enable,
            data_in   => data_in,
            weight    => weight,
            accum_out => accum_out,
            valid     => valid,
            overflow  => overflow,
            busy      => busy
        );

    test_proc: process
        
        procedure do_mac(d : integer; w : integer) is
        begin
            data_in <= to_signed(d, DATA_WIDTH);
            weight  <= to_signed(w, DATA_WIDTH);
            enable  <= '1';
            wait for CLK_PERIOD;
            enable <= '0';
            wait for CLK_PERIOD;
        end procedure;
        
        procedure do_clear is
        begin
            clear <= '1';
            wait for CLK_PERIOD;
            clear <= '0';
            wait for CLK_PERIOD * 2;
        end procedure;
        
        procedure check_accum(expected : signed(ACCUM_WIDTH-1 downto 0); test_name : string) is
        begin
            if accum_out = expected then
                report "PASS: " & test_name severity note;
                pass_count <= pass_count + 1;
            else
                report "FAIL: " & test_name severity warning;
                fail_count <= fail_count + 1;
            end if;
            test_count <= test_count + 1;
        end procedure;
        
        variable expected : signed(ACCUM_WIDTH-1 downto 0);
        variable prod1, prod2, prod3, prod4 : signed(PRODUCT_WIDTH-1 downto 0);

    begin
        report "=== mac_unit testbench ===" severity note;
        
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Test 1: Reset
        report "--- Test: Reset ---" severity note;
        expected := (others => '0');
        check_accum(expected, "After reset");

        -- Test 2: Single MAC (1.0 * 1.0)
        report "--- Test: Single MAC ---" severity note;
        do_clear;
        do_mac(ONE_Q213, ONE_Q213);
        prod1 := to_signed(ONE_Q213, DATA_WIDTH) * to_signed(ONE_Q213, DATA_WIDTH);
        expected := resize(prod1, ACCUM_WIDTH);
        check_accum(expected, "1.0 * 1.0 = " & integer'image(to_integer(expected)));

        -- Test 3: Single MAC (0.5 * 0.5)
        do_clear;
        do_mac(4096, 4096);
        prod1 := to_signed(4096, DATA_WIDTH) * to_signed(4096, DATA_WIDTH);
        expected := resize(prod1, ACCUM_WIDTH);
        check_accum(expected, "0.5 * 0.5");

        -- Test 4: Two MACs (dot product)
        report "--- Test: Dot product ---" severity note;
        do_clear;
        do_mac(100, 200);  -- 20000
        do_mac(300, 400);  -- 120000
        prod1 := to_signed(100, DATA_WIDTH) * to_signed(200, DATA_WIDTH);
        prod2 := to_signed(300, DATA_WIDTH) * to_signed(400, DATA_WIDTH);
        expected := resize(prod1, ACCUM_WIDTH) + resize(prod2, ACCUM_WIDTH);
        check_accum(expected, "100*200 + 300*400 = 140000");

        -- Test 5: Clear
        report "--- Test: Clear ---" severity note;
        do_clear;
        expected := (others => '0');
        check_accum(expected, "After clear");
        
        do_mac(1000, 2000);
        prod1 := to_signed(1000, DATA_WIDTH) * to_signed(2000, DATA_WIDTH);
        expected := resize(prod1, ACCUM_WIDTH);
        check_accum(expected, "After restart: 1000*2000");

        -- Test 6: Negative values
        report "--- Test: Negative values ---" severity note;
        do_clear;
        do_mac(1000, -500);
        prod1 := to_signed(1000, DATA_WIDTH) * to_signed(-500, DATA_WIDTH);
        expected := resize(prod1, ACCUM_WIDTH);
        check_accum(expected, "1000 * -500 = -500000");
        
        do_clear;
        do_mac(-1000, -500);
        prod1 := to_signed(-1000, DATA_WIDTH) * to_signed(-500, DATA_WIDTH);
        expected := resize(prod1, ACCUM_WIDTH);
        check_accum(expected, "-1000 * -500 = 500000");

        -- Test 7: Mixed accumulation
        report "--- Test: Mixed signs ---" severity note;
        do_clear;
        do_mac(1000, 1000);   -- +1000000
        do_mac(-500, 1000);   -- -500000
        do_mac(200, -300);    -- -60000
        prod1 := to_signed(1000, DATA_WIDTH) * to_signed(1000, DATA_WIDTH);
        prod2 := to_signed(-500, DATA_WIDTH) * to_signed(1000, DATA_WIDTH);
        prod3 := to_signed(200, DATA_WIDTH) * to_signed(-300, DATA_WIDTH);
        expected := resize(prod1, ACCUM_WIDTH) + resize(prod2, ACCUM_WIDTH) + resize(prod3, ACCUM_WIDTH);
        check_accum(expected, "Mixed: 440000");

        -- Test 8: 4-element neuron dot product
        report "--- Test: 4-element neuron ---" severity note;
        do_clear;
        do_mac(8192, 4096);    -- 1.0 * 0.5
        do_mac(4096, -2048);   -- 0.5 * -0.25
        do_mac(-4096, 1024);   -- -0.5 * 0.125
        do_mac(2048, -512);    -- 0.25 * -0.0625
        prod1 := to_signed(8192, DATA_WIDTH) * to_signed(4096, DATA_WIDTH);
        prod2 := to_signed(4096, DATA_WIDTH) * to_signed(-2048, DATA_WIDTH);
        prod3 := to_signed(-4096, DATA_WIDTH) * to_signed(1024, DATA_WIDTH);
        prod4 := to_signed(2048, DATA_WIDTH) * to_signed(-512, DATA_WIDTH);
        expected := resize(prod1, ACCUM_WIDTH) + resize(prod2, ACCUM_WIDTH) + 
                    resize(prod3, ACCUM_WIDTH) + resize(prod4, ACCUM_WIDTH);
        check_accum(expected, "4-element dot");

        -- Test 9: Zero handling
        report "--- Test: Zero handling ---" severity note;
        do_clear;
        do_mac(0, 12345);
        expected := (others => '0');
        check_accum(expected, "0 * value = 0");
        
        do_mac(12345, 0);
        check_accum(expected, "value * 0 = 0");

        -- Test 10: Multiple MACs
        report "--- Test: 10 MACs ---" severity note;
        do_clear;
        for i in 1 to 10 loop
            do_mac(100, 100);
        end loop;
        prod1 := to_signed(100, DATA_WIDTH) * to_signed(100, DATA_WIDTH);
        expected := resize(prod1, ACCUM_WIDTH);
        expected := shift_left(expected, 3) + shift_left(expected, 1);  -- *10
        check_accum(expected, "10 x (100*100) = 100000");

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
