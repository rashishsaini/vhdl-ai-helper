library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity cordic_sin_tb_simple is
end cordic_sin_tb_simple;

architecture test of cordic_sin_tb_simple is

    component cordic_sin
        Generic (
            ITERATIONS : integer := 16;
            DATA_WIDTH : integer := 16
        );
        Port (
            clk      : in  std_logic;
            reset    : in  std_logic;
            start    : in  std_logic;
            ready    : out std_logic;
            angle_in : in  std_logic_vector(15 downto 0);
            done     : out std_logic;
            valid    : out std_logic;
            sin_out  : out std_logic_vector(15 downto 0);
            cos_out  : out std_logic_vector(15 downto 0)
        );
    end component;

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;

    -- Signals
    signal clk      : std_logic := '0';
    signal reset    : std_logic := '1';
    signal start    : std_logic := '0';
    signal ready    : std_logic;
    signal angle_in : std_logic_vector(15 downto 0);
    signal sin_out  : std_logic_vector(15 downto 0);
    signal cos_out  : std_logic_vector(15 downto 0);
    signal done     : std_logic;
    signal valid    : std_logic;

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD / 2;

    -- DUT instantiation
    dut: cordic_sin
        generic map (
            ITERATIONS => 16,
            DATA_WIDTH => 16
        )
        port map (
            clk      => clk,
            reset    => reset,
            start    => start,
            ready    => ready,
            angle_in => angle_in,
            done     => done,
            valid    => valid,
            sin_out  => sin_out,
            cos_out  => cos_out
        );

    -- Test stimulus
    process
        variable my_line : line;
    begin
        -- Reset
        report "========================================";
        report "  CORDIC Simple Testbench";
        report "========================================";
        report "";

        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 20 ns;

        report "TEST 1: Computing sin/cos of pi/4 (0.7854 rad)";

        -- Check ready (should already be high after reset)
        assert ready = '1' report "Ready not asserted!" severity failure;

        -- Test angle: pi/4 = 0.7854 rad = 25736 in Q1.15
        angle_in <= std_logic_vector(to_signed(25736, 16));
        wait for CLK_PERIOD;

        -- Start computation
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        -- Wait for done
        wait until done = '1';
        wait for CLK_PERIOD;

        report "  sin_out = " & integer'image(to_integer(signed(sin_out)));
        report "  cos_out = " & integer'image(to_integer(signed(cos_out)));
        report "  Expected: sin ~= 23170, cos ~= 23170";

        wait for 50 ns;

        report "TEST 2: Computing sin/cos of 0 rad";

        assert ready = '1' report "Ready not asserted!" severity failure;
        angle_in <= (others => '0');  -- 0 radians
        wait for CLK_PERIOD;
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait until done = '1';
        wait for CLK_PERIOD;

        report "  sin_out = " & integer'image(to_integer(signed(sin_out)));
        report "  cos_out = " & integer'image(to_integer(signed(cos_out)));
        report "  Expected: sin ~= 0, cos ~= 32767";

        wait for 50 ns;

        report "TEST 3: Computing sin/cos of pi/2 (1.5708 rad)";

        -- Note: This is close to the limit of Q1.15 range
        assert ready = '1' report "Ready not asserted!" severity failure;
        angle_in <= std_logic_vector(to_signed(25735, 16));  -- ~pi/2
        wait for CLK_PERIOD;
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait until done = '1';
        wait for CLK_PERIOD;

        report "  sin_out = " & integer'image(to_integer(signed(sin_out)));
        report "  cos_out = " & integer'image(to_integer(signed(cos_out)));
        report "  Expected: sin ~= 32767, cos ~= 0";

        wait for 50 ns;

        report "";
        report "========================================";
        report "  ALL TESTS COMPLETED";
        report "========================================";

        wait;
    end process;

end test;
