library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity accumulator_tb is
end entity accumulator_tb;

architecture behavioral of accumulator_tb is

    constant INPUT_WIDTH  : integer := 32;
    constant ACCUM_WIDTH  : integer := 40;
    constant CLK_PERIOD   : time := 10 ns;
    
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal data_in      : signed(INPUT_WIDTH-1 downto 0) := (others => '0');
    signal data_valid   : std_logic := '0';
    signal data_ready   : std_logic;
    signal clear        : std_logic := '0';
    signal accum_out    : signed(ACCUM_WIDTH-1 downto 0);
    signal out_valid    : std_logic;
    signal out_ready    : std_logic := '1';
    signal overflow     : std_logic;
    signal saturated    : std_logic;
    signal done         : std_logic;
    
    signal sim_done     : boolean := false;

begin

    DUT: entity work.accumulator
        generic map (
            INPUT_WIDTH => INPUT_WIDTH,
            ACCUM_WIDTH => ACCUM_WIDTH,
            ENABLE_SAT  => true
        )
        port map (
            clk        => clk,
            rst        => rst,
            data_in    => data_in,
            data_valid => data_valid,
            data_ready => data_ready,
            clear      => clear,
            accum_out  => accum_out,
            out_valid  => out_valid,
            out_ready  => out_ready,
            overflow   => overflow,
            saturated  => saturated,
            done       => done
        );

    -- Clock
    clk <= not clk after CLK_PERIOD/2 when not sim_done else '0';

    -- Stimulus
    process
    begin
        report "========== ACCUMULATOR TESTBENCH START ==========";
        
        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -------------------------------------------------------
        -- TEST 1: Basic Single Accumulation
        -------------------------------------------------------
        report "TEST 1: Basic Single Accumulation";
        clear <= '1'; wait for CLK_PERIOD; clear <= '0';
        wait for CLK_PERIOD;
        
        data_in <= to_signed(1000, INPUT_WIDTH);
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        assert accum_out = to_signed(1000, ACCUM_WIDTH)
            report "TEST 1 FAILED: Expected 1000, got " & integer'image(to_integer(accum_out))
            severity error;
        assert done = '1' or out_valid = '1'
            report "TEST 1 FAILED: done/out_valid not asserted" severity error;
        report "TEST 1 PASSED";
        wait for CLK_PERIOD * 2;

        -------------------------------------------------------
        -- TEST 2: Multiple Accumulations
        -------------------------------------------------------
        report "TEST 2: Multiple Accumulations (1000+2000+3000+4000+5000=15000)";
        clear <= '1'; wait for CLK_PERIOD; clear <= '0';
        wait for CLK_PERIOD;
        
        for i in 1 to 5 loop
            data_in <= to_signed(i * 1000, INPUT_WIDTH);
            data_valid <= '1';
            wait for CLK_PERIOD;
            data_valid <= '0';
            wait for CLK_PERIOD * 2;
        end loop;
        
        assert accum_out = to_signed(15000, ACCUM_WIDTH)
            report "TEST 2 FAILED: Expected 15000, got " & integer'image(to_integer(accum_out))
            severity error;
        report "TEST 2 PASSED";
        wait for CLK_PERIOD * 2;

        -------------------------------------------------------
        -- TEST 3: Negative Values
        -------------------------------------------------------
        report "TEST 3: Negative Values (-5000 + -3000 = -8000)";
        clear <= '1'; wait for CLK_PERIOD; clear <= '0';
        wait for CLK_PERIOD;
        
        data_in <= to_signed(-5000, INPUT_WIDTH);
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        data_in <= to_signed(-3000, INPUT_WIDTH);
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        assert accum_out = to_signed(-8000, ACCUM_WIDTH)
            report "TEST 3 FAILED: Expected -8000, got " & integer'image(to_integer(accum_out))
            severity error;
        report "TEST 3 PASSED";
        wait for CLK_PERIOD * 2;

        -------------------------------------------------------
        -- TEST 4: Mixed Signs
        -------------------------------------------------------
        report "TEST 4: Mixed Signs (10000 - 3000 = 7000)";
        clear <= '1'; wait for CLK_PERIOD; clear <= '0';
        wait for CLK_PERIOD;
        
        data_in <= to_signed(10000, INPUT_WIDTH);
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        data_in <= to_signed(-3000, INPUT_WIDTH);
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        assert accum_out = to_signed(7000, ACCUM_WIDTH)
            report "TEST 4 FAILED: Expected 7000, got " & integer'image(to_integer(accum_out))
            severity error;
        report "TEST 4 PASSED";
        wait for CLK_PERIOD * 2;

        -------------------------------------------------------
        -- TEST 5: Clear Function
        -------------------------------------------------------
        report "TEST 5: Clear Function";
        clear <= '1'; wait for CLK_PERIOD; clear <= '0';
        wait for CLK_PERIOD;
        
        data_in <= to_signed(5000, INPUT_WIDTH);
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Clear and add new value
        clear <= '1'; wait for CLK_PERIOD; clear <= '0';
        wait for CLK_PERIOD;
        
        data_in <= to_signed(1000, INPUT_WIDTH);
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        assert accum_out = to_signed(1000, ACCUM_WIDTH)
            report "TEST 5 FAILED: Expected 1000 after clear, got " & integer'image(to_integer(accum_out))
            severity error;
        report "TEST 5 PASSED";
        wait for CLK_PERIOD * 2;

        -------------------------------------------------------
        -- TEST 6: Zero Accumulation
        -------------------------------------------------------
        report "TEST 6: Zero Accumulation";
        clear <= '1'; wait for CLK_PERIOD; clear <= '0';
        wait for CLK_PERIOD;
        
        for i in 1 to 3 loop
            data_in <= to_signed(0, INPUT_WIDTH);
            data_valid <= '1';
            wait for CLK_PERIOD;
            data_valid <= '0';
            wait for CLK_PERIOD * 2;
        end loop;
        
        assert accum_out = to_signed(0, ACCUM_WIDTH)
            report "TEST 6 FAILED: Expected 0, got " & integer'image(to_integer(accum_out))
            severity error;
        report "TEST 6 PASSED";
        wait for CLK_PERIOD * 2;

        -------------------------------------------------------
        -- TEST 7: 32 MAC Operations (NN Scenario)
        -------------------------------------------------------
        report "TEST 7: 32 MAC Operations (32 x 16384 = 524288)";
        clear <= '1'; wait for CLK_PERIOD; clear <= '0';
        wait for CLK_PERIOD;
        
        for i in 1 to 32 loop
            data_in <= to_signed(16384, INPUT_WIDTH);
            data_valid <= '1';
            wait for CLK_PERIOD;
            data_valid <= '0';
            wait for CLK_PERIOD * 2;
        end loop;
        
        assert accum_out = to_signed(524288, ACCUM_WIDTH)
            report "TEST 7 FAILED: Expected 524288, got " & integer'image(to_integer(accum_out))
            severity error;
        report "TEST 7 PASSED";
        wait for CLK_PERIOD * 2;

        -------------------------------------------------------
        -- TEST 8: Large Value
        -------------------------------------------------------
        report "TEST 8: Large Value (2147483647)";
        clear <= '1'; wait for CLK_PERIOD; clear <= '0';
        wait for CLK_PERIOD;
        
        data_in <= to_signed(2147483647, INPUT_WIDTH);
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        assert accum_out = to_signed(2147483647, ACCUM_WIDTH)
            report "TEST 8 FAILED" severity error;
        report "TEST 8 PASSED";
        wait for CLK_PERIOD * 2;

        -------------------------------------------------------
        -- TEST 9: Overflow Detection
        -------------------------------------------------------
        report "TEST 9: Overflow Detection";
        clear <= '1'; wait for CLK_PERIOD; clear <= '0';
        wait for CLK_PERIOD;
        
        for i in 1 to 5 loop
            data_in <= to_signed(2147483647, INPUT_WIDTH);
            data_valid <= '1';
            wait for CLK_PERIOD;
            data_valid <= '0';
            wait for CLK_PERIOD * 2;
        end loop;
        
        assert overflow = '1'
            report "TEST 9 FAILED: Overflow not detected" severity error;
        assert saturated = '1'
            report "TEST 9 FAILED: Saturation not detected" severity error;
        report "TEST 9 PASSED";
        wait for CLK_PERIOD * 2;

        -------------------------------------------------------
        -- TEST 10: Alternating Signs Cancel Out
        -------------------------------------------------------
        report "TEST 10: Alternating Signs (should cancel to 0)";
        clear <= '1'; wait for CLK_PERIOD; clear <= '0';
        wait for CLK_PERIOD;
        
        for i in 1 to 5 loop
            data_in <= to_signed(1000, INPUT_WIDTH);
            data_valid <= '1';
            wait for CLK_PERIOD;
            data_valid <= '0';
            wait for CLK_PERIOD * 2;
            
            data_in <= to_signed(-1000, INPUT_WIDTH);
            data_valid <= '1';
            wait for CLK_PERIOD;
            data_valid <= '0';
            wait for CLK_PERIOD * 2;
        end loop;
        
        assert accum_out = to_signed(0, ACCUM_WIDTH)
            report "TEST 10 FAILED: Expected 0, got " & integer'image(to_integer(accum_out))
            severity error;
        report "TEST 10 PASSED";

        -------------------------------------------------------
        report "========== ALL TESTS COMPLETE ==========";
        
        sim_done <= true;
        wait;
    end process;

end architecture behavioral;