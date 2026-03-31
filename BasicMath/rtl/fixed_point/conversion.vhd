library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package conversion_pkg is

    function int_to_q(
        i : integer;
        FRACTION_BITS : integer;
        WIDTH : integer
    ) return signed;

    function q_to_int(
        x : signed;
        FRACTION_BITS : integer
    ) return integer;

end package;

package body conversion_pkg is

    function int_to_q(
        i : integer;
        FRACTION_BITS : integer;
        WIDTH : integer
    ) return signed is
    begin
        return to_signed(i * (2**FRACTION_BITS), WIDTH);
    end function;

    function q_to_int(
        x : signed;
        FRACTION_BITS : integer
    ) return integer is
    begin
        return to_integer(x) / (2**FRACTION_BITS);
    end function;

end package body;