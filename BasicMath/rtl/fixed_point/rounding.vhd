library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rounding is
    generic (
        IN_WIDTH      : integer := 32;
        OUT_WIDTH     : integer := 16;
        FRACTION_BITS : integer := 8
    );
    port (
        x : in  signed(IN_WIDTH-1 downto 0);
        y : out signed(OUT_WIDTH-1 downto 0)
    );
end entity;

architecture rtl of rounding is
    signal rounded : signed(IN_WIDTH-1 downto 0);
begin

    process(x)
    begin
        -- Add half LSB for rounding
        rounded <= x + to_signed(2**(FRACTION_BITS-1), IN_WIDTH);

        -- Truncate to desired width
        y <= rounded(IN_WIDTH-1 downto FRACTION_BITS);
    end process;

end architecture;