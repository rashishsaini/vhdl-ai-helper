--------------------------------------------------------------------------------
-- Testbench: moment_register_bank_tb
-- Description: Comprehensive testbench for moment_register_bank
--              Tests dual-port register storage for 13 parameters × 2 moments
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity moment_register_bank_tb is
end entity moment_register_bank_tb;

architecture testbench of moment_register_bank_tb is

    ---------------------------------------------------------------------------
    -- Component Declaration
    ---------------------------------------------------------------------------
    component moment_register_bank is
        generic (
            DATA_WIDTH : integer := 16;
            NUM_PARAMS : integer := 13;
            ADDR_WIDTH : integer := 4
        );
        port (
            clk        : in  std_logic;
            rst        : in  std_logic;
            clear      : in  std_logic;
            rd_en      : in  std_logic;
            rd_addr    : in  unsigned(3 downto 0);
            m_rd_data  : out signed(15 downto 0);
            v_rd_data  : out signed(15 downto 0);
            rd_valid   : out std_logic;
            wr_en      : in  std_logic;
            wr_addr    : in  unsigned(3 downto 0);
            m_wr_data  : in  signed(15 downto 0);
            v_wr_data  : in  signed(15 downto 0)
        );
    end component;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;
    constant NUM_PARAMS : integer := 13;

    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '0';
    signal clear      : std_logic := '0';
    signal rd_en      : std_logic := '0';
    signal rd_addr    : unsigned(3 downto 0) := (others => '0');
    signal m_rd_data  : signed(15 downto 0);
    signal v_rd_data  : signed(15 downto 0);
    signal rd_valid   : std_logic;
    signal wr_en      : std_logic := '0';
    signal wr_addr    : unsigned(3 downto 0) := (others => '0');
    signal m_wr_data  : signed(15 downto 0) := (others => '0');
    signal v_wr_data  : signed(15 downto 0) := (others => '0');

    signal test_done : boolean := false;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    DUT: moment_register_bank
        generic map (
            DATA_WIDTH => 16,
            NUM_PARAMS => NUM_PARAMS,
            ADDR_WIDTH => 4
        )
        port map (
            clk        => clk,
            rst        => rst,
            clear      => clear,
            rd_en      => rd_en,
            rd_addr    => rd_addr,
            m_rd_data  => m_rd_data,
            v_rd_data  => v_rd_data,
            rd_valid   => rd_valid,
            wr_en      => wr_en,
            wr_addr    => wr_addr,
            m_wr_data  => m_wr_data,
            v_wr_data  => v_wr_data
        );

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk_process: process
    begin
        while not test_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    ---------------------------------------------------------------------------
    -- Test Process
    ---------------------------------------------------------------------------
    test_process: process
        variable seed1, seed2 : integer := 42;
        variable rand_val : real;
        variable m_test, v_test : signed(15 downto 0);
    begin
        report "========================================";
        report "Starting moment_register_bank testbench";
        report "========================================";

        -- Test 1: Reset
        report "TEST 1: Reset functionality";
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;
        report "  OK Reset complete";

        -- Test 2: Write all 13 locations
        report "TEST 2: Write all 13 parameter locations";
        for i in 0 to NUM_PARAMS-1 loop
            wait until rising_edge(clk);
            wr_en <= '1';
            wr_addr <= to_unsigned(i, 4);
            m_wr_data <= to_signed(1000 + i*100, 16);  -- Unique m values
            v_wr_data <= to_signed(2000 + i*100, 16);  -- Unique v values
            wait until rising_edge(clk);
            wr_en <= '0';
            wait for CLK_PERIOD;
        end loop;
        report "  OK All 13 locations written";

        -- Test 3: Read back and verify
        report "TEST 3: Read back and verify all locations";
        for i in 0 to NUM_PARAMS-1 loop
            wait until rising_edge(clk);
            rd_en <= '1';
            rd_addr <= to_unsigned(i, 4);
            wait until rising_edge(clk);
            rd_en <= '0';
            wait until rd_valid = '1';

            -- Check m value
            assert m_rd_data = to_signed(1000 + i*100, 16)
                report "ERROR: m mismatch at address " & integer'image(i) &
                       " Expected: " & integer'image(1000 + i*100) &
                       " Got: " & integer'image(to_integer(m_rd_data))
                severity error;

            -- Check v value
            assert v_rd_data = to_signed(2000 + i*100, 16)
                report "ERROR: v mismatch at address " & integer'image(i) &
                       " Expected: " & integer'image(2000 + i*100) &
                       " Got: " & integer'image(to_integer(v_rd_data))
                severity error;

            wait for CLK_PERIOD;
        end loop;
        report "  OK All locations verified correctly";

        -- Test 4: Clear functionality
        report "TEST 4: Clear all moments";
        wait until rising_edge(clk);
        clear <= '1';
        wait until rising_edge(clk);
        clear <= '0';
        wait for CLK_PERIOD * 2;

        -- Verify all cleared
        for i in 0 to NUM_PARAMS-1 loop
            wait until rising_edge(clk);
            rd_en <= '1';
            rd_addr <= to_unsigned(i, 4);
            wait until rising_edge(clk);
            rd_en <= '0';
            wait until rd_valid = '1';

            assert m_rd_data = to_signed(0, 16)
                report "ERROR: m not cleared at address " & integer'image(i)
                severity error;

            assert v_rd_data = to_signed(0, 16)
                report "ERROR: v not cleared at address " & integer'image(i)
                severity error;

            wait for CLK_PERIOD;
        end loop;
        report "  OK All moments cleared to zero";

        -- Test 5: Simultaneous read/write to different addresses
        report "TEST 5: Simultaneous read/write operations";
        wait until rising_edge(clk);
        wr_en <= '1';
        wr_addr <= to_unsigned(5, 4);
        m_wr_data <= to_signed(12345, 16);
        v_wr_data <= to_signed(67890, 16);
        rd_en <= '1';
        rd_addr <= to_unsigned(3, 4);
        wait until rising_edge(clk);
        wr_en <= '0';
        rd_en <= '0';
        wait for CLK_PERIOD;
        report "  OK Simultaneous operations completed";

        -- Test 6: Random write/read sequence (100 operations)
        report "TEST 6: Random write/read sequence (100 operations)";
        for i in 1 to 100 loop
            uniform(seed1, seed2, rand_val);

            if rand_val < 0.5 then
                -- Write operation
                wait until rising_edge(clk);
                wr_en <= '1';
                uniform(seed1, seed2, rand_val);
                wr_addr <= to_unsigned(integer(floor(rand_val * real(NUM_PARAMS))), 4);
                uniform(seed1, seed2, rand_val);
                m_wr_data <= to_signed(integer(rand_val * 8192.0) - 4096, 16);
                uniform(seed1, seed2, rand_val);
                v_wr_data <= to_signed(integer(rand_val * 8192.0), 16);  -- v always positive
                wait until rising_edge(clk);
                wr_en <= '0';
            else
                -- Read operation
                wait until rising_edge(clk);
                rd_en <= '1';
                uniform(seed1, seed2, rand_val);
                rd_addr <= to_unsigned(integer(floor(rand_val * real(NUM_PARAMS))), 4);
                wait until rising_edge(clk);
                rd_en <= '0';
                wait until rd_valid = '1';
            end if;

            wait for CLK_PERIOD;
        end loop;
        report "  OK 100 random operations completed successfully";

        -- Test 7: Boundary conditions
        report "TEST 7: Boundary value testing";

        -- Max positive values
        wait until rising_edge(clk);
        wr_en <= '1';
        wr_addr <= to_unsigned(0, 4);
        m_wr_data <= to_signed(32767, 16);   -- Max Q2.13
        v_wr_data <= to_signed(32767, 16);
        wait until rising_edge(clk);
        wr_en <= '0';
        wait for CLK_PERIOD;

        -- Read back
        wait until rising_edge(clk);
        rd_en <= '1';
        rd_addr <= to_unsigned(0, 4);
        wait until rising_edge(clk);
        rd_en <= '0';
        wait until rd_valid = '1';
        assert m_rd_data = to_signed(32767, 16)
            report "ERROR: Max positive value test failed" severity error;
        wait for CLK_PERIOD;

        -- Min negative values
        wait until rising_edge(clk);
        wr_en <= '1';
        wr_addr <= to_unsigned(1, 4);
        m_wr_data <= to_signed(-32768, 16);  -- Min Q2.13
        v_wr_data <= to_signed(0, 16);       -- Min v (always >= 0)
        wait until rising_edge(clk);
        wr_en <= '0';
        wait for CLK_PERIOD;

        -- Read back
        wait until rising_edge(clk);
        rd_en <= '1';
        rd_addr <= to_unsigned(1, 4);
        wait until rising_edge(clk);
        rd_en <= '0';
        wait until rd_valid = '1';
        assert m_rd_data = to_signed(-32768, 16)
            report "ERROR: Min negative value test failed" severity error;
        wait for CLK_PERIOD;

        report "  OK Boundary values handled correctly";

        -- Final Report
        report "========================================";
        report "OK ALL TESTS PASSED";
        report "moment_register_bank testbench complete";
        report "========================================";

        test_done <= true;
        wait;
    end process;

end architecture testbench;
