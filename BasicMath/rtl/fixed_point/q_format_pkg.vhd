library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package q_format_pkg is

    --------------------------------------------------------------------
    -- Q FORMAT CONFIGURATION
    --------------------------------------------------------------------
    constant TOTAL_BITS    : integer := 16;  -- total width
    constant FRACTION_BITS : integer := 8;   -- fractional bits

    subtype q_format is signed(TOTAL_BITS-1 downto 0);

    --------------------------------------------------------------------
    -- CONVERSION FUNCTIONS
    --------------------------------------------------------------------

    -- Integer to fixed-point
    function to_q(i : integer) return q_format;

    -- Fixed-point to integer (truncates fractional part)
    function to_integer_q(x : q_format) return integer;

    --------------------------------------------------------------------
    -- BASIC OPERATIONS
    --------------------------------------------------------------------

    function q_add(a, b : q_format) return q_format;
    function q_sub(a, b : q_format) return q_format;
    function q_mul(a, b : q_format) return q_format;
    function q_div(a, b : q_format) return q_format;

    --------------------------------------------------------------------
    -- UTILITY FUNCTIONS
    --------------------------------------------------------------------

    function q_abs(x : q_format) return q_format;
    function q_min(a, b : q_format) return q_format;
    function q_max(a, b : q_format) return q_format;

    --------------------------------------------------------------------
    -- SATURATION
    --------------------------------------------------------------------

    function q_saturate(x : signed) return q_format;

end package;

--------------------------------------------------------------------
-- PACKAGE BODY
--------------------------------------------------------------------

package body q_format_pkg is

    --------------------------------------------------------------------
    -- CONVERSIONS
    --------------------------------------------------------------------

    function to_q(i : integer) return q_format is
        variable temp : signed(TOTAL_BITS-1 downto 0);
    begin
        temp := to_signed(i * (2 ** FRACTION_BITS), TOTAL_BITS);
        return temp;
    end function;

    function to_integer_q(x : q_format) return integer is
    begin
        return to_integer(x) / (2 ** FRACTION_BITS);
    end function;

    --------------------------------------------------------------------
    -- BASIC OPERATIONS
    --------------------------------------------------------------------

    function q_add(a, b : q_format) return q_format is
        variable result : signed(TOTAL_BITS downto 0);
    begin
        result := resize(a, TOTAL_BITS+1) + resize(b, TOTAL_BITS+1);
        return q_saturate(result);
    end function;

    function q_sub(a, b : q_format) return q_format is
        variable result : signed(TOTAL_BITS downto 0);
    begin
        result := resize(a, TOTAL_BITS+1) - resize(b, TOTAL_BITS+1);
        return q_saturate(result);
    end function;

    function q_mul(a, b : q_format) return q_format is
        variable temp : signed(2*TOTAL_BITS-1 downto 0);
        variable scaled : signed(TOTAL_BITS-1 downto 0);
    begin
        temp := a * b;
        -- scale back (right shift FRACTION_BITS)
        scaled := temp(TOTAL_BITS + FRACTION_BITS - 1 downto FRACTION_BITS);
        return scaled;
    end function;

    function q_div(a, b : q_format) return q_format is
        variable numerator : signed(2*TOTAL_BITS-1 downto 0);
        variable result    : signed(TOTAL_BITS-1 downto 0);
    begin
        if b = 0 then
            return (others => '0');
        end if;

        -- scale numerator before division
        numerator := resize(a, 2*TOTAL_BITS) sll FRACTION_BITS;
        result := numerator(2*TOTAL_BITS-1 downto TOTAL_BITS) / b;

        return result;
    end function;

    --------------------------------------------------------------------
    -- UTILITIES
    --------------------------------------------------------------------

    function q_abs(x : q_format) return q_format is
    begin
        if x < 0 then
            return -x;
        else
            return x;
        end if;
    end function;

    function q_min(a, b : q_format) return q_format is
    begin
        if a < b then
            return a;
        else
            return b;
        end if;
    end function;

    function q_max(a, b : q_format) return q_format is
    begin
        if a > b then
            return a;
        else
            return b;
        end if;
    end function;

    --------------------------------------------------------------------
    -- SATURATION
    --------------------------------------------------------------------

    function q_saturate(x : signed) return q_format is
        variable max_val : signed(TOTAL_BITS-1 downto 0);
        variable min_val : signed(TOTAL_BITS-1 downto 0);
    begin
        max_val := to_signed(2**(TOTAL_BITS-1)-1, TOTAL_BITS);
        min_val := to_signed(-2**(TOTAL_BITS-1), TOTAL_BITS);

        if x > resize(max_val, x'length) then
            return max_val;
        elsif x < resize(min_val, x'length) then
            return min_val;
        else
            return resize(x, TOTAL_BITS);
        end if;
    end function;

end package body;