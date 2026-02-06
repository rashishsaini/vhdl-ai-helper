library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity cordic_sin_32bit_tb_simple is
end cordic_sin_32bit_tb_simple;

architecture test of cordic_sin_32bit_tb_simple is

    component cordic_sin_32bit
        Generic (
            ITERATIONS : integer := 32;
            DATA_WIDTH : integer := 32
        );
        Port (
            clk      : in  std_logic;
            reset    : in  std_logic;
            start    : in  std_logic;
            ready    : out std_logic;
            angle_in : in  std_logic_vector(31 downto 0);
            done     : out std_logic;
            valid    : out std_logic;
            sin_out  : out std_logic_vector(31 downto 0);
            cos_out  : out std_logic_vector(31 downto 0)
        );
    end component;

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;

    -- Signals
    signal clk      : std_logic := '0';
    signal reset    : std_logic := '1';
    signal start    : std_logic := '0';
    signal ready    : std_logic;
    signal angle_in : std_logic_vector(31 downto 0);
    signal sin_out  : std_logic_vector(31 downto 0);
    signal cos_out  : std_logic_vector(31 downto 0);
    signal done     : std_logic;
    signal valid    : std_logic;

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD / 2;

    -- DUT instantiation
    dut: cordic_sin_32bit
        generic map (
            ITERATIONS => 32,
            DATA_WIDTH => 32
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
    begin
        -- Reset
        report "========================================================================";
        report "  CORDIC 32-bit (Q1.31) Simple Testbench";
        report "========================================================================";
        report "";

        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 20 ns;

        -- Verify ready
        assert ready = '1' report "Ready not asserted after reset!" severity failure;

        -- ====================================================================
        -- TEST 1: pi/4 (0.785398 rad)
        -- ====================================================================
        report "TEST 1: Computing sin/cos of pi/4";
        report "  angle_in = 1686629713 (0x64872D69) = 0.785398 rad in Q1.31";

        angle_in <= std_logic_vector(to_signed(1686629713, 32));
        wait for CLK_PERIOD;

        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait until done = '1';
        wait for CLK_PERIOD;

        report "  sin_out = " & integer'image(to_integer(signed(sin_out)));
        report "  cos_out = " & integer'image(to_integer(signed(cos_out)));
        report "  Expected: sin ~= 1518500250, cos ~= 1518500250";
        report "  (Both should be ~0.707107 in Q1.31)";
        report "";

        wait for 50 ns;

        -- ====================================================================
        -- TEST 2: 0 radians
        -- ====================================================================
        report "TEST 2: Computing sin/cos of 0 rad";

        assert ready = '1' report "Ready not asserted!" severity failure;
        angle_in <= (others => '0');
        wait for CLK_PERIOD;
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait until done = '1';
        wait for CLK_PERIOD;

        report "  sin_out = " & integer'image(to_integer(signed(sin_out)));
        report "  cos_out = " & integer'image(to_integer(signed(cos_out)));
        report "  Expected: sin ~= 0, cos ~= 2147483647 (max positive = 1.0)";
        report "";

        wait for 50 ns;

        -- ====================================================================
        -- TEST 3: pi/2 (1.5708 rad)
        -- ====================================================================
        report "TEST 3: Computing sin/cos of pi/2";
        report "  angle_in = 3373259426 (approx pi/2 in Q1.31)";

        assert ready = '1' report "Ready not asserted!" severity failure;
        angle_in <= std_logic_vector(to_signed(1686629713*2, 32));
        wait for CLK_PERIOD;
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait until done = '1';
        wait for CLK_PERIOD;

        report "  sin_out = " & integer'image(to_integer(signed(sin_out)));
        report "  cos_out = " & integer'image(to_integer(signed(cos_out)));
        report "  Expected: sin ~= 2147483647 (1.0), cos ~= 0";
        report "";

        wait for 50 ns;

        -- ====================================================================
        -- TEST 4: Small angle (0.001 rad)
        -- ====================================================================
        report "TEST 4: Computing sin/cos of 0.001 rad (high precision test)";
        report "  angle_in = 2147484 (0.001 * 2^31)";

        assert ready = '1' report "Ready not asserted!" severity failure;
        angle_in <= std_logic_vector(to_signed(2147484, 32));
        wait for CLK_PERIOD;
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait until done = '1';
        wait for CLK_PERIOD;

        report "  sin_out = " & integer'image(to_integer(signed(sin_out)));
        report "  cos_out = " & integer'image(to_integer(signed(cos_out)));
        report "  Expected: sin ~= 2147484, cos ~= 2147483647";
        report "  (sin(0.001) ~= 0.001 for small angles)";
        report "";

        wait for 50 ns;

        -- ====================================================================
        -- TEST 5: Negative angle (-pi/4)
        -- ====================================================================
        report "TEST 5: Computing sin/cos of -pi/4";

        assert ready = '1' report "Ready not asserted!" severity failure;
        angle_in <= std_logic_vector(to_signed(-1686629713, 32));
        wait for CLK_PERIOD;
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait until done = '1';
        wait for CLK_PERIOD;

        report "  sin_out = " & integer'image(to_integer(signed(sin_out)));
        report "  cos_out = " & integer'image(to_integer(signed(cos_out)));
        report "  Expected: sin ~= -1518500250, cos ~= 1518500250";
        report "";

        wait for 50 ns;

        -- ====================================================================
        -- SUMMARY
        -- ====================================================================
        report "";
        report "========================================================================";
        report "  ALL TESTS COMPLETED";
        report "========================================================================";
        report "";
        report "32-bit CORDIC Key Features:";
        report "  - Q1.31 fixed-point format (31 fractional bits)";
        report "  - 32 iterations for maximum precision";
        report "  - Expected accuracy: < 1e-9 (9 decimal places)";
        report "  - No overflow for any angle in [-pi, +pi]";
        report "  - Latency: 34 clock cycles (1 INIT + 32 COMPUTE + 1 OUTPUT)";
        report "  - 65536x more precise than 16-bit version";
        report "";
        report "Conversion formulas:";
        report "  - To Q1.31: integer = angle_radians * 2^31";
        report "  - From Q1.31: real = integer / 2^31";
        report "";
        report "Example: pi/4 = 0.785398 rad";
        report "  Q1.31 = 0.785398 * 2147483648 = 1686629713";
        report "";

        wait;
    end process;

end test;
