--------------------------------------------------------------------------------
-- Module: activation_unit
-- Purpose: Simple ReLU - zero for negative, pass positive
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity activation_unit is
    generic (
        DATA_WIDTH : integer := 16
    );
    port (
        data_in    : in  signed(DATA_WIDTH-1 downto 0);
        data_out   : out signed(DATA_WIDTH-1 downto 0)
    );
end entity activation_unit;

architecture rtl of activation_unit is
begin

    -- ReLU: output = 0 if negative, else pass through
    data_out <= (others => '0') when data_in(DATA_WIDTH-1) = '1' else data_in;

end architecture rtl;