--------------------------------------------------------------------------------
-- Module: error_calculator
-- Description: Computes output layer error for backpropagation
--              err = target - actual
--              Pure combinational logic
--
-- Format: Q2.13 (16-bit signed)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity error_calculator is
    generic (
        DATA_WIDTH : integer := 16;
        SAT_MAX    : integer := 32767;
        SAT_MIN    : integer := -32768
    );
    port (
        target       : in  signed(DATA_WIDTH-1 downto 0);
        actual       : in  signed(DATA_WIDTH-1 downto 0);
        err_out      : out signed(DATA_WIDTH-1 downto 0);
        saturated    : out std_logic;
        zero_err     : out std_logic
    );
end entity error_calculator;

architecture rtl of error_calculator is

    signal diff : signed(DATA_WIDTH downto 0);

begin

    diff <= resize(target, DATA_WIDTH+1) - resize(actual, DATA_WIDTH+1);

    process(diff)
    begin
        if diff > to_signed(SAT_MAX, DATA_WIDTH+1) then
            err_out   <= to_signed(SAT_MAX, DATA_WIDTH);
            saturated <= '1';
        elsif diff < to_signed(SAT_MIN, DATA_WIDTH+1) then
            err_out   <= to_signed(SAT_MIN, DATA_WIDTH);
            saturated <= '1';
        else
            err_out   <= resize(diff, DATA_WIDTH);
            saturated <= '0';
        end if;
    end process;

    zero_err <= '1' when diff = 0 else '0';

end architecture rtl;
