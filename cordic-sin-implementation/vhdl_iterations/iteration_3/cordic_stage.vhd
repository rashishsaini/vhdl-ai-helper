library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- CORDIC Pipeline Stage
-- Performs one iteration with registered inputs and outputs
-- Enables pipelining by registering both input and output

entity cordic_stage is
    Generic (
        STAGE_NUM  : integer := 0;      -- Which iteration (0-15)
        DATA_WIDTH : integer := 16
    );
    Port (
        clk       : in  std_logic;

        -- Input (registered from previous stage)
        x_in      : in  signed(DATA_WIDTH-1 downto 0);
        y_in      : in  signed(DATA_WIDTH-1 downto 0);
        z_in      : in  signed(DATA_WIDTH-1 downto 0);
        valid_in  : in  std_logic;

        -- Output (registered)
        x_out     : out signed(DATA_WIDTH-1 downto 0);
        y_out     : out signed(DATA_WIDTH-1 downto 0);
        z_out     : out signed(DATA_WIDTH-1 downto 0);
        valid_out : out std_logic
    );
end cordic_stage;

architecture Behavioral of cordic_stage is

    -- Pre-computed CORDIC angles
    constant ANGLE_TABLE : signed(DATA_WIDTH-1 downto 0) := (
        -- This constant would need to be indexed properly in practice
        -- For simplicity, showing the first value (arctan(2^0))
        to_signed(16#3243#, DATA_WIDTH)
    );

    -- Actual angle for this stage (hardcoded per stage)
    function get_angle(stage : integer) return signed is
        variable angle_vals : signed(DATA_WIDTH-1 downto 0);
    begin
        case stage is
            when 0  => return to_signed(16#3243#, DATA_WIDTH);  -- arctan(1)
            when 1  => return to_signed(16#1DAC#, DATA_WIDTH);  -- arctan(0.5)
            when 2  => return to_signed(16#0FAD#, DATA_WIDTH);  -- arctan(0.25)
            when 3  => return to_signed(16#07F5#, DATA_WIDTH);  -- arctan(0.125)
            when 4  => return to_signed(16#03FE#, DATA_WIDTH);  -- arctan(0.0625)
            when 5  => return to_signed(16#01FF#, DATA_WIDTH);  -- arctan(0.03125)
            when 6  => return to_signed(16#00FF#, DATA_WIDTH);  -- arctan(0.015625)
            when 7  => return to_signed(16#007F#, DATA_WIDTH);  -- arctan(0.0078)
            when 8  => return to_signed(16#003F#, DATA_WIDTH);
            when 9  => return to_signed(16#001F#, DATA_WIDTH);
            when 10 => return to_signed(16#000F#, DATA_WIDTH);
            when 11 => return to_signed(16#0007#, DATA_WIDTH);
            when 12 => return to_signed(16#0003#, DATA_WIDTH);
            when 13 => return to_signed(16#0001#, DATA_WIDTH);
            when 14 => return to_signed(16#0000#, DATA_WIDTH);
            when 15 => return to_signed(16#0000#, DATA_WIDTH);
            when others => return (others => '0');
        end case;
    end function;

    constant ANGLE : signed(DATA_WIDTH-1 downto 0) := get_angle(STAGE_NUM);

    -- Registered outputs
    signal x_reg, y_reg, z_reg : signed(DATA_WIDTH-1 downto 0);
    signal valid_reg : std_logic;

begin

    -- Pipeline stage: perform one CORDIC iteration combinationally, then register
    process(clk)
        variable direction : std_logic;
        variable y_shifted, x_shifted : signed(DATA_WIDTH-1 downto 0);
        variable x_next, y_next, z_next : signed(DATA_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if valid_in = '1' then
                -- Determine rotation direction
                direction := z_in(z_in'high);

                -- Pre-compute shifted values
                y_shifted := shift_right(y_in, STAGE_NUM);
                x_shifted := shift_right(x_in, STAGE_NUM);

                -- Perform rotation based on direction
                if direction = '1' then
                    -- z < 0: Rotate counterclockwise
                    x_next := x_in + y_shifted;
                    y_next := y_in - x_shifted;
                    z_next := z_in + ANGLE;
                else
                    -- z >= 0: Rotate clockwise
                    x_next := x_in - y_shifted;
                    y_next := y_in + x_shifted;
                    z_next := z_in - ANGLE;
                end if;

                -- Register the results
                x_reg <= x_next;
                y_reg <= y_next;
                z_reg <= z_next;
            end if;

            -- Register the valid signal
            valid_reg <= valid_in;
        end if;
    end process;

    -- Output assignments
    x_out     <= x_reg;
    y_out     <= y_reg;
    z_out     <= z_reg;
    valid_out <= valid_reg;

end Behavioral;
