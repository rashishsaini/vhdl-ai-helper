--------------------------------------------------------------------------------
-- Testbench: error_calculator_tb
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity error_calculator_tb is
end entity error_calculator_tb;

architecture sim of error_calculator_tb is

    constant DATA_WIDTH : integer := 16;

    signal target    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal actual    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal err_out   : signed(DATA_WIDTH-1 downto 0);
    signal saturated : std_logic;
    signal zero_err  : std_logic;

    signal test_count : integer := 0;
    signal pass_count : integer := 0;
    signal fail_count : integer := 0;

begin

    DUT: entity work.error_calculator
        generic map (DATA_WIDTH => DATA_WIDTH)
        port map (
            target    => target,
            actual    => actual,
            err_out   => err_out,
            saturated => saturated,
            zero_err  => zero_err
        );

    test_proc: process
        
        procedure run_test(
            t_val     : integer;
            a_val     : integer;
            exp_err   : integer;
            exp_sat   : std_logic;
            exp_zero  : std_logic;
            test_name : string
        ) is
        begin
            target <= to_signed(t_val, DATA_WIDTH);
            actual <= to_signed(a_val, DATA_WIDTH);
            wait for 10 ns;
            
            if to_integer(err_out) = exp_err and saturated = exp_sat and zero_err = exp_zero then
                report "PASS: " & test_name severity note;
                pass_count <= pass_count + 1;
            else
                report "FAIL: " & test_name & " | Exp=" & integer'image(exp_err) &
                       " Got=" & integer'image(to_integer(err_out)) severity warning;
                fail_count <= fail_count + 1;
            end if;
            
            test_count <= test_count + 1;
            wait for 10 ns;
        end procedure;

    begin
        report "=== error_calculator testbench ===" severity note;
        wait for 20 ns;

        -- Test 1: Zero error
        report "--- Test: Zero error ---" severity note;
        run_test(0, 0, 0, '0', '1', "Both zero");
        run_test(100, 100, 0, '0', '1', "Equal pos");
        run_test(-100, -100, 0, '0', '1', "Equal neg");
        run_test(8192, 8192, 0, '0', '1', "1.0 = 1.0");

        -- Test 2: Positive errors
        report "--- Test: Positive errors ---" severity note;
        run_test(100, 0, 100, '0', '0', "100 - 0");
        run_test(1000, 500, 500, '0', '0', "1000 - 500");
        run_test(0, -100, 100, '0', '0', "0 - (-100)");
        run_test(100, -100, 200, '0', '0', "100 - (-100)");

        -- Test 3: Negative errors
        report "--- Test: Negative errors ---" severity note;
        run_test(0, 100, -100, '0', '0', "0 - 100");
        run_test(500, 1000, -500, '0', '0', "500 - 1000");
        run_test(-100, 0, -100, '0', '0', "-100 - 0");
        run_test(-100, 100, -200, '0', '0', "-100 - 100");

        -- Test 4: Positive overflow
        report "--- Test: Positive overflow ---" severity note;
        run_test(32767, -1, 32767, '1', '0', "32767 - (-1)");
        run_test(20000, -20000, 32767, '1', '0', "20000 - (-20000)");

        -- Test 5: Negative overflow
        report "--- Test: Negative overflow ---" severity note;
        run_test(-32768, 1, -32768, '1', '0', "-32768 - 1");
        run_test(-20000, 20000, -32768, '1', '0', "-20000 - 20000");

        -- Test 6: Boundary no overflow
        report "--- Test: Boundary ---" severity note;
        run_test(32767, 0, 32767, '0', '0', "Max - 0");
        run_test(-32768, 0, -32768, '0', '0', "Min - 0");
        run_test(16383, -16384, 32767, '0', '0', "Near max");

        -- Test 7: NN typical
        report "--- Test: NN typical ---" severity note;
        run_test(8192, 6000, 2192, '0', '0', "Target 1.0, out 0.73");
        run_test(8192, 4096, 4096, '0', '0', "Target 1.0, out 0.5");
        run_test(0, 2000, -2000, '0', '0', "Target 0, out 0.24");
        run_test(4100, 4096, 4, '0', '0', "Small pos err");
        run_test(4090, 4096, -6, '0', '0', "Small neg err");

        -- Summary
        wait for 20 ns;
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
