library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity saturation is
    generic (
        IN_WIDTH  : integer := 17;
        OUT_WIDTH : integer := 16
    );
    port (
        x : in  signed(IN_WIDTH-1 downto 0);
        y : out signed(OUT_WIDTH-1 downto 0)
    );
end entity;

architecture rtl of saturation is
    signal max_val : signed(OUT_WIDTH-1 downto 0);
    signal min_val : signed(OUT_WIDTH-1 downto 0);
begin

    max_val <= to_signed(2**(OUT_WIDTH-1)-1, OUT_WIDTH);
    min_val <= to_signed(-2**(OUT_WIDTH-1), OUT_WIDTH);

    process(x)
    begin
        if x > resize(max_val, IN_WIDTH) then
            y <= max_val;
        elsif x < resize(min_val, IN_WIDTH) then
            y <= min_val;
        else
            y <= resize(x, OUT_WIDTH);
        end if;
    end process;

end architecture;
