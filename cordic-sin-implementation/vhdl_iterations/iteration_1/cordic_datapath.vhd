library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- CORDIC Datapath Component
-- Performs a single CORDIC iteration: rotation by a specified angle
-- Input: current x, y, z values and iteration index
-- Output: next x, y, z values after one rotation step
-- This component contains only combinational logic

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

    signal direction : std_logic;  -- '1' = rotate left, '0' = rotate right

begin

    -- Determine rotation direction based on z sign
    -- If z < 0, we need to rotate towards positive angles (counterclockwise)
    -- If z >= 0, we need to rotate towards negative angles (clockwise)
    direction <= z_in(z_in'high);  -- '1' if negative, '0' if positive

    -- CORDIC rotation calculation (combinational)
    process(x_in, y_in, z_in, angle, iteration, direction)
        variable x_temp, y_temp : signed(DATA_WIDTH-1 downto 0);
        variable y_shifted, x_shifted : signed(DATA_WIDTH-1 downto 0);
    begin
        -- Pre-compute shifted values for this iteration
        if iteration <= 15 then
            y_shifted := shift_right(y_in, iteration);
            x_shifted := shift_right(x_in, iteration);
        else
            y_shifted := (others => '0');
            x_shifted := (others => '0');
        end if;

        -- Perform rotation based on direction
        -- CORDIC rotation matrix (2D):
        -- [x_new]   [1  -d*2^-i] [x]   where d = ±1 (direction)
        -- [y_new] = [1   d*2^-i] [y]
        -- [z_new]   [          ] [z] = [z - d*angle]

        if direction = '1' then
            -- z < 0: Rotate counterclockwise
            x_out <= x_in + y_shifted;
            y_out <= y_in - x_shifted;
            z_out <= z_in + angle;
        else
            -- z >= 0: Rotate clockwise
            x_out <= x_in - y_shifted;
            y_out <= y_in + x_shifted;
            z_out <= z_in - angle;
        end if;

    end process;

end Behavioral;
