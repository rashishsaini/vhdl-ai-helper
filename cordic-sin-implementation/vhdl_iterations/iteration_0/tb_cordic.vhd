library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity cordic_processor_tb is
end cordic_processor_tb;

architecture Behavioral of cordic_processor_tb is

    component cordic_processor is
        Generic (
            ITERATIONS : integer := 16;
            DATA_WIDTH : integer := 16
        );
        Port (
            clk      : in  std_logic;
            reset    : in  std_logic;
            start    : in  std_logic;
            angle_in : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            sin_out  : out std_logic_vector(DATA_WIDTH-1 downto 0);
            cos_out  : out std_logic_vector(DATA_WIDTH-1 downto 0);
            done     : out std_logic
        );
    end component;

    -- Constants
    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : integer := 16;
    constant ITERATIONS : integer := 16;

    -- Test signals
    signal clk      : std_logic := '0';
    signal reset    : std_logic := '1';
    signal start    : std_logic := '0';
    signal angle_in : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal sin_out  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal cos_out  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal done     : std_logic;

    -- Function to convert fixed-point to real
    function fixed_to_real(fixed_val : std_logic_vector; width : integer) return real is
        variable temp : signed(width-1 downto 0);
    begin
        temp := signed(fixed_val);
        return real(to_integer(temp)) / real(2**(width-2));  -- Q1.15 format
    end function;

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD / 2;

    -- DUT instantiation
    dut: cordic_processor
        generic map (
            ITERATIONS => ITERATIONS,
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            clk      => clk,
            reset    => reset,
            start    => start,
            angle_in => angle_in,
            sin_out  => sin_out,
            cos_out  => cos_out,
            done     => done
        );

    -- Test process
    stimulus: process
        variable my_line : line;
        variable angle_real : real;
        variable sin_real : real;
        variable cos_real : real;
    begin
        -- Reset
        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 20 ns;

        write(my_line, string'("=== CORDIC Algorithm Test Results (Iteration 0: Baseline) ==="));
        writeline(output, my_line);
        write(my_line, string'("Time(ns)  Angle(rad)  Sine       Cosine     Done"));
        writeline(output, my_line);
        write(my_line, string'("-----------------------------------------------------"));
        writeline(output, my_line);

        -- Test multiple angles (0 to PI)
        for i in 0 to 8 loop
            angle_real := real(i) * 3.14159 / 8.0;  -- 0 to pi radians
            angle_in <= std_logic_vector(to_signed(integer(angle_real * real(2**(DATA_WIDTH-2))), DATA_WIDTH));

            start <= '1';
            wait for CLK_PERIOD;
            start <= '0';

            wait until done = '1';
            wait for CLK_PERIOD;

            -- Convert outputs to real values
            sin_real := fixed_to_real(sin_out, DATA_WIDTH);
            cos_real := fixed_to_real(cos_out, DATA_WIDTH);

            -- Display results
            write(my_line, now/1 ns);
            write(my_line, string'("  "));
            write(my_line, angle_real, 4, 6);
            write(my_line, string'("    "));
            write(my_line, sin_real, 4, 6);
            write(my_line, string'("  "));
            write(my_line, cos_real, 4, 6);
            write(my_line, string'("  "));
            write(my_line, done);
            writeline(output, my_line);

            wait for 5 * CLK_PERIOD;
        end loop;

        write(my_line, string'("=== Test Complete ==="));
        writeline(output, my_line);

        wait;
    end process;

end Behavioral;
