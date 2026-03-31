library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity cordic_handshake_tb is
end cordic_handshake_tb;

architecture Behavioral of cordic_handshake_tb is

    component cordic_top_v2
        Generic (
            ITERATIONS : integer := 16;
            DATA_WIDTH : integer := 16
        );
        Port (
            clk      : in  std_logic;
            reset    : in  std_logic;
            start    : in  std_logic;
            ready    : out std_logic;
            angle_in : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            done     : out std_logic;
            valid    : out std_logic;
            sin_out  : out std_logic_vector(DATA_WIDTH-1 downto 0);
            cos_out  : out std_logic_vector(DATA_WIDTH-1 downto 0)
        );
    end component;

    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : integer := 16;
    constant ITERATIONS : integer := 16;

    signal clk      : std_logic := '0';
    signal reset    : std_logic := '1';
    signal start    : std_logic := '0';
    signal ready    : std_logic;
    signal angle_in : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal sin_out  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal cos_out  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal done     : std_logic;
    signal valid    : std_logic;

    function fixed_to_real(fixed_val : std_logic_vector; width : integer) return real is
        variable temp : signed(width-1 downto 0);
    begin
        temp := signed(fixed_val);
        return real(to_integer(temp)) / real(2**(width-2));
    end function;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut: cordic_top_v2
        generic map (
            ITERATIONS => ITERATIONS,
            DATA_WIDTH => DATA_WIDTH
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

    stimulus: process
        variable my_line : line;
        variable angle_real : real;
        variable sin_real : real;
        variable cos_real : real;
    begin
        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 20 ns;

        write(my_line, string'("=== CORDIC Test (Iteration 2: Handshake Protocol) ==="));
        writeline(output, my_line);
        write(my_line, string'("Testing ready/valid handshake protocol"));
        writeline(output, my_line);
        write(my_line, string'("------------------------------------------------------"));
        writeline(output, my_line);

        -- Test 1: Basic operation
        write(my_line, string'("TEST 1: Basic Angle Computation"));
        writeline(output, my_line);

        for i in 0 to 3 loop
            angle_real := real(i) * 3.14159 / 8.0;
            angle_in <= std_logic_vector(to_signed(integer(angle_real * real(2**(DATA_WIDTH-2))), DATA_WIDTH));

            -- Wait for ready signal
            wait until ready = '1';
            wait for CLK_PERIOD;

            -- Assert start when ready
            start <= '1';
            wait for CLK_PERIOD;
            start <= '0';

            -- Wait for done signal
            wait until done = '1';
            wait for CLK_PERIOD;

            sin_real := fixed_to_real(sin_out, DATA_WIDTH);
            cos_real := fixed_to_real(cos_out, DATA_WIDTH);

            write(my_line, string'("  Angle: "));
            write(my_line, angle_real, 4, 6);
            write(my_line, string'(" → sin: "));
            write(my_line, sin_real, 4, 6);
            write(my_line, string'(" cos: "));
            write(my_line, cos_real, 4, 6);
            writeline(output, my_line);

            wait for 5 * CLK_PERIOD;
        end loop;

        write(my_line, string'("------------------------------------------------------"));
        writeline(output, my_line);

        -- Test 2: Back-to-back operations (pipelined)
        write(my_line, string'("TEST 2: Back-to-Back Operations (if ready allows)"));
        writeline(output, my_line);

        for i in 0 to 2 loop
            angle_real := real(i) * 3.14159 / 4.0;
            angle_in <= std_logic_vector(to_signed(integer(angle_real * real(2**(DATA_WIDTH-2))), DATA_WIDTH));

            if ready = '1' then
                start <= '1';
                wait for CLK_PERIOD;
                start <= '0';
                write(my_line, string'("  Operation "));
                write(my_line, i);
                write(my_line, string'(" started (angle: "));
                write(my_line, angle_real, 4, 4);
                write(my_line, string'(")"));
                writeline(output, my_line);
            else
                write(my_line, string'("  Waiting for ready..."));
                writeline(output, my_line);
            end if;

            wait for CLK_PERIOD;
        end loop;

        -- Wait for last result
        write(my_line, string'("  Waiting for final result..."));
        writeline(output, my_line);
        wait until done = '1';
        wait for CLK_PERIOD;

        sin_real := fixed_to_real(sin_out, DATA_WIDTH);
        cos_real := fixed_to_real(cos_out, DATA_WIDTH);
        write(my_line, string'("  Final result: sin: "));
        write(my_line, sin_real, 4, 6);
        write(my_line, string'(" cos: "));
        write(my_line, cos_real, 4, 6);
        writeline(output, my_line);

        write(my_line, string'("======================================================"));
        writeline(output, my_line);
        write(my_line, string'("Test Complete"));
        writeline(output, my_line);

        wait;
    end process;

end Behavioral;
