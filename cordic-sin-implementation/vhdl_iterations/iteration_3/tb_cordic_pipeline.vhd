library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity cordic_pipeline_tb is
end cordic_pipeline_tb;

architecture Behavioral of cordic_pipeline_tb is

    component cordic_top_pipelined
        Generic (
            ITERATIONS : integer := 16;
            DATA_WIDTH : integer := 16
        );
        Port (
            clk       : in  std_logic;
            angle_in  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            valid_in  : in  std_logic;
            sin_out   : out std_logic_vector(DATA_WIDTH-1 downto 0);
            cos_out   : out std_logic_vector(DATA_WIDTH-1 downto 0);
            valid_out : out std_logic
        );
    end component;

    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : integer := 16;
    constant ITERATIONS : integer := 16;

    signal clk       : std_logic := '0';
    signal angle_in  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal valid_in  : std_logic := '0';
    signal sin_out   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal cos_out   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal valid_out : std_logic;

    function fixed_to_real(fixed_val : std_logic_vector; width : integer) return real is
        variable temp : signed(width-1 downto 0);
    begin
        temp := signed(fixed_val);
        return real(to_integer(temp)) / real(2**(width-2));
    end function;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut: cordic_top_pipelined
        generic map (
            ITERATIONS => ITERATIONS,
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            clk       => clk,
            angle_in  => angle_in,
            valid_in  => valid_in,
            sin_out   => sin_out,
            cos_out   => cos_out,
            valid_out => valid_out
        );

    stimulus: process
        variable my_line : line;
        variable angle_real : real;
        variable sin_real : real;
        variable cos_real : real;
        variable cycle_count : integer;
    begin
        -- Note: Pipeline has no reset; it streams continuously
        wait for 20 ns;

        write(my_line, string'("=== CORDIC Pipelined Test (Iteration 3) ==="));
        writeline(output, my_line);
        write(my_line, string'("Testing continuous throughput streaming"));
        writeline(output, my_line);
        write(my_line, string'("------------------------------------------"));
        writeline(output, my_line);

        -- Test: Multiple angles in quick succession
        write(my_line, string'("Inputting 5 angles in succession..."));
        writeline(output, my_line);

        for i in 0 to 4 loop
            angle_real := real(i) * 3.14159 / 4.0;
            angle_in <= std_logic_vector(to_signed(integer(angle_real * real(2**(DATA_WIDTH-2))), DATA_WIDTH));
            valid_in <= '1';

            write(my_line, string'("Cycle "));
            write(my_line, i);
            write(my_line, string'(": Input angle = "));
            write(my_line, angle_real, 4, 4);
            writeline(output, my_line);

            wait for CLK_PERIOD;
        end loop;

        valid_in <= '0';

        write(my_line, string'(""));
        writeline(output, my_line);
        write(my_line, string'("Waiting for results to propagate through pipeline..."));
        writeline(output, my_line);
        write(my_line, string'(""));
        writeline(output, my_line);

        cycle_count := 0;

        -- Observe outputs as they emerge from pipeline
        for wait_cycle in 0 to 30 loop
            wait for CLK_PERIOD;
            cycle_count := cycle_count + 1;

            if valid_out = '1' then
                sin_real := fixed_to_real(sin_out, DATA_WIDTH);
                cos_real := fixed_to_real(cos_out, DATA_WIDTH);

                write(my_line, string'("Cycle "));
                write(my_line, cycle_count);
                write(my_line, string'(": Output valid - sin: "));
                write(my_line, sin_real, 4, 6);
                write(my_line, string'(" cos: "));
                write(my_line, cos_real, 4, 6);
                writeline(output, my_line);
            end if;
        end loop;

        write(my_line, string'(""));
        writeline(output, my_line);
        write(my_line, string'("=== Test Complete ==="));
        writeline(output, my_line);
        write(my_line, string'("Note: Latency = 16 cycles (pipeline depth)"));
        writeline(output, my_line);
        write(my_line, string'("      After fill, 1 result per cycle"));
        writeline(output, my_line);

        wait;
    end process;

end Behavioral;
