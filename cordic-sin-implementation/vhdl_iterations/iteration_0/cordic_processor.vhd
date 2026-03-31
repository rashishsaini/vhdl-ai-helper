library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cordic_processor is
    Generic (
        ITERATIONS : integer := 16;  -- Number of CORDIC iterations
        DATA_WIDTH : integer := 16   -- Data width for fixed-point arithmetic
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
end cordic_processor;

architecture Behavioral of cordic_processor is

    -- CORDIC angle lookup table (arctan(2^-i) in fixed-point)
    type angle_array is array (0 to ITERATIONS-1) of signed(DATA_WIDTH-1 downto 0);
    constant ANGLE_TABLE : angle_array := (
        x"3243", x"1DAC", x"0FAD", x"07F5", x"03FE", x"01FF", x"00FF", x"007F",
        x"003F", x"001F", x"000F", x"0007", x"0003", x"0001", x"0000", x"0000"
    );

    -- Internal signals
    signal x_reg, y_reg, z_reg : signed(DATA_WIDTH-1 downto 0);
    signal x_next, y_next, z_next : signed(DATA_WIDTH-1 downto 0);
    signal iteration_count : integer range 0 to ITERATIONS-1;
    signal computing : std_logic;

begin

    -- CORDIC process
    process(clk, reset)
    begin
        if reset = '1' then
            x_reg <= (others => '0');
            y_reg <= (others => '0');
            z_reg <= (others => '0');
            iteration_count <= 0;
            computing <= '0';
            done <= '0';

        elsif rising_edge(clk) then
            if start = '1' and computing = '0' then
                -- Initialize CORDIC (rotation mode)
                x_reg <= to_signed(60725, DATA_WIDTH);  -- K = 0.60725 in fixed-point (Q1.15)
                y_reg <= (others => '0');
                z_reg <= signed(angle_in);
                iteration_count <= 0;
                computing <= '1';
                done <= '0';

            elsif computing = '1' then
                -- Perform CORDIC iterations
                x_reg <= x_next;
                y_reg <= y_next;
                z_reg <= z_next;

                if iteration_count = ITERATIONS-1 then
                    computing <= '0';
                    done <= '1';
                else
                    iteration_count <= iteration_count + 1;
                end if;
            else
                done <= '0';
            end if;
        end if;
    end process;

    -- CORDIC iteration logic
    process(x_reg, y_reg, z_reg, iteration_count)
        variable x_temp, y_temp : signed(DATA_WIDTH-1 downto 0);
    begin
        x_temp := x_reg;
        y_temp := y_reg;

        if z_reg(z_reg'high) = '1' then  -- z_reg < 0
            x_next <= x_temp + shift_right(y_temp, iteration_count);
            y_next <= y_temp - shift_right(x_temp, iteration_count);
            z_next <= z_reg + ANGLE_TABLE(iteration_count);
        else
            x_next <= x_temp - shift_right(y_temp, iteration_count);
            y_next <= y_temp + shift_right(x_temp, iteration_count);
            z_next <= z_reg - ANGLE_TABLE(iteration_count);
        end if;
    end process;

    -- Output assignments
    sin_out <= std_logic_vector(y_reg);
    cos_out <= std_logic_vector(x_reg);

end Behavioral;
