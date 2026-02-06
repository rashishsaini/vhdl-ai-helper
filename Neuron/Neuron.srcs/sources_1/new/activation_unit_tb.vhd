--------------------------------------------------------------------------------
-- Testbench: activation_unit_tb
-- Purpose: Basic ReLU verification using report statements
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity activation_unit_tb is
end entity activation_unit_tb;

architecture behavioral of activation_unit_tb is

    constant DATA_WIDTH : integer := 16;
    
    signal data_in  : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal data_out : signed(DATA_WIDTH-1 downto 0);

begin

    -- Instantiate DUT
    DUT: entity work.activation_unit
        generic map (DATA_WIDTH => DATA_WIDTH)
        port map (
            data_in  => data_in,
            data_out => data_out
        );

    -- Test process
    test_proc: process
        variable errors : integer := 0;
        variable expected : signed(DATA_WIDTH-1 downto 0);
    begin
        report "===== ReLU Activation Unit Test Start =====";
        
        ---------------------------------------------------------------
        -- Test 1: Zero input
        ---------------------------------------------------------------
        data_in <= x"0000";
        wait for 10 ns;
        expected := x"0000";
        if data_out = expected then
            report "PASS: Zero input";
        else
            report "FAIL: Zero input" severity error;
            errors := errors + 1;
        end if;
        
        ---------------------------------------------------------------
        -- Test 2: Maximum positive
        ---------------------------------------------------------------
        data_in <= x"7FFF";
        wait for 10 ns;
        expected := x"7FFF";
        if data_out = expected then
            report "PASS: Max positive (0x7FFF)";
        else
            report "FAIL: Max positive" severity error;
            errors := errors + 1;
        end if;
        
        ---------------------------------------------------------------
        -- Test 3: Maximum negative (should output zero)
        ---------------------------------------------------------------
        data_in <= x"8000";
        wait for 10 ns;
        expected := x"0000";
        if data_out = expected then
            report "PASS: Max negative (0x8000 -> 0x0000)";
        else
            report "FAIL: Max negative" severity error;
            errors := errors + 1;
        end if;
        
        ---------------------------------------------------------------
        -- Test 4: Small negative (-1 LSB)
        ---------------------------------------------------------------
        data_in <= x"FFFF";
        wait for 10 ns;
        expected := x"0000";
        if data_out = expected then
            report "PASS: Small negative (0xFFFF -> 0x0000)";
        else
            report "FAIL: Small negative" severity error;
            errors := errors + 1;
        end if;
        
        ---------------------------------------------------------------
        -- Test 5: Small positive (+1 LSB)
        ---------------------------------------------------------------
        data_in <= x"0001";
        wait for 10 ns;
        expected := x"0001";
        if data_out = expected then
            report "PASS: Small positive (0x0001)";
        else
            report "FAIL: Small positive" severity error;
            errors := errors + 1;
        end if;
        
        ---------------------------------------------------------------
        -- Test 6: Positive 1.0 (Q2.13: 0x2000)
        ---------------------------------------------------------------
        data_in <= x"2000";
        wait for 10 ns;
        expected := x"2000";
        if data_out = expected then
            report "PASS: Positive 1.0 (0x2000)";
        else
            report "FAIL: Positive 1.0" severity error;
            errors := errors + 1;
        end if;
        
        ---------------------------------------------------------------
        -- Test 7: Negative -1.0 (Q2.13: 0xE000)
        ---------------------------------------------------------------
        data_in <= x"E000";
        wait for 10 ns;
        expected := x"0000";
        if data_out = expected then
            report "PASS: Negative -1.0 (0xE000 -> 0x0000)";
        else
            report "FAIL: Negative -1.0" severity error;
            errors := errors + 1;
        end if;
        
        ---------------------------------------------------------------
        -- Test 8: Positive 2.0 (Q2.13: 0x4000)
        ---------------------------------------------------------------
        data_in <= x"4000";
        wait for 10 ns;
        expected := x"4000";
        if data_out = expected then
            report "PASS: Positive 2.0 (0x4000)";
        else
            report "FAIL: Positive 2.0" severity error;
            errors := errors + 1;
        end if;
        
        ---------------------------------------------------------------
        -- Test 9: Negative -2.0 (Q2.13: 0xC000)
        ---------------------------------------------------------------
        data_in <= x"C000";
        wait for 10 ns;
        expected := x"0000";
        if data_out = expected then
            report "PASS: Negative -2.0 (0xC000 -> 0x0000)";
        else
            report "FAIL: Negative -2.0" severity error;
            errors := errors + 1;
        end if;
        
        ---------------------------------------------------------------
        -- Test 10: Random positive
        ---------------------------------------------------------------
        data_in <= x"1234";
        wait for 10 ns;
        expected := x"1234";
        if data_out = expected then
            report "PASS: Random positive (0x1234)";
        else
            report "FAIL: Random positive" severity error;
            errors := errors + 1;
        end if;
        
        ---------------------------------------------------------------
        -- Test 11: Random negative
        ---------------------------------------------------------------
        data_in <= x"ABCD";
        wait for 10 ns;
        expected := x"0000";
        if data_out = expected then
            report "PASS: Random negative (0xABCD -> 0x0000)";
        else
            report "FAIL: Random negative" severity error;
            errors := errors + 1;
        end if;
        
        ---------------------------------------------------------------
        -- Summary
        ---------------------------------------------------------------
        report "===== Test Summary =====";
        report "Total tests: 11";
        
        if errors = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "FAILED TESTS: " & integer'image(errors) severity error;
        end if;
        
        report "===== Test Complete =====";
        
        wait;
    end process;

end architecture behavioral;