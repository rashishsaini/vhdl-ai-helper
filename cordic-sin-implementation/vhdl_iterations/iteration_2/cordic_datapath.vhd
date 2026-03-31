library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- CORDIC Datapath Component
-- Performs a single CORDIC iteration: rotation by a specified angle

entity cordic_datapath is
    Generic (
        DATA_WIDTH : integer := 16
    );
    Port (
        -- Current state from registers
        x_in       : in  signed(DATA_WIDTH-1 downto 0);
        y_in       : in  signed(DATA_WIDTH-1 downto 0);
        z_in       : in  signed(DATA_WIDTH-1 downto 0);

        -- Angle to rotate by (from LUT)
        angle      : in  signed(DATA_WIDTH-1 downto 0);

        -- Iteration index (determines shift amount)
        iteration  : in  integer range 0 to 31;

        -- Next state (outputs)
        x_out      : out signed(DATA_WIDTH-1 downto 0);
        y_out      : out signed(DATA_WIDTH-1 downto 0);
        z_out      : out signed(DATA_WIDTH-1 downto 0)
    );
end cordic_datapath;

architecture Behavioral of cordic_datapath is

    signal direction : std_logic;

begin

    direction <= z_in(z_in'high);

    process(x_in, y_in, z_in, angle, iteration, direction)
        variable y_shifted, x_shifted : signed(DATA_WIDTH-1 downto 0);
    begin
        if iteration <= 15 then
            y_shifted := shift_right(y_in, iteration);
            x_shifted := shift_right(x_in, iteration);
        else
            y_shifted := (others => '0');
            x_shifted := (others => '0');
        end if;

        if direction = '1' then
            x_out <= x_in + y_shifted;
            y_out <= y_in - x_shifted;
            z_out <= z_in + angle;
        else
            x_out <= x_in - y_shifted;
            y_out <= y_in + x_shifted;
            z_out <= z_in - angle;
        end if;

    end process;

end Behavioral;
