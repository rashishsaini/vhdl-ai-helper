library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- CORDIC Lookup Table Component
-- Provides pre-computed angles: arctan(2^-i) for i = 0 to ITERATIONS-1
-- This is a read-only ROM with synchronous output

entity cordic_lut is
    Generic (
        ITERATIONS : integer := 16;
        DATA_WIDTH : integer := 16
    );
    Port (
        clk       : in  std_logic;
        -- Address input: selects which pre-computed angle to output
        addr      : in  integer range 0 to ITERATIONS-1;
        -- Output: the selected angle in Q1.15 fixed-point
        angle_out : out signed(DATA_WIDTH-1 downto 0)
    );
end cordic_lut;

architecture Behavioral of cordic_lut is

    -- Pre-computed CORDIC angles: arctan(2^-i) in Q1.15 fixed-point format
    -- These are the fundamental constants of the CORDIC algorithm
    type angle_array is array (0 to ITERATIONS-1) of signed(DATA_WIDTH-1 downto 0);
    constant ANGLE_TABLE : angle_array := (
        to_signed(16#3243#, DATA_WIDTH),  -- i=0:  arctan(1)      = 45.000°   = 0.7854 rad
        to_signed(16#1DAC#, DATA_WIDTH),  -- i=1:  arctan(0.5)    = 26.565°   = 0.4636 rad
        to_signed(16#0FAD#, DATA_WIDTH),  -- i=2:  arctan(0.25)   = 14.036°   = 0.2450 rad
        to_signed(16#07F5#, DATA_WIDTH),  -- i=3:  arctan(0.125)  = 7.125°    = 0.1244 rad
        to_signed(16#03FE#, DATA_WIDTH),  -- i=4:  arctan(0.0625) = 3.576°    = 0.0624 rad
        to_signed(16#01FF#, DATA_WIDTH),  -- i=5:  arctan(0.03125)= 1.789°    = 0.0312 rad
        to_signed(16#00FF#, DATA_WIDTH),  -- i=6:  arctan(0.015625)= 0.895°   = 0.0156 rad
        to_signed(16#007F#, DATA_WIDTH),  -- i=7:  arctan(0.0078) = 0.447°    = 0.0078 rad
        to_signed(16#003F#, DATA_WIDTH),  -- i=8:  Negligible, approaching zero
        to_signed(16#001F#, DATA_WIDTH),  -- i=9:  Negligible, approaching zero
        to_signed(16#000F#, DATA_WIDTH),  -- i=10: Negligible, approaching zero
        to_signed(16#0007#, DATA_WIDTH),  -- i=11: Negligible, approaching zero
        to_signed(16#0003#, DATA_WIDTH),  -- i=12: Negligible, approaching zero
        to_signed(16#0001#, DATA_WIDTH),  -- i=13: Negligible, approaching zero
        to_signed(16#0000#, DATA_WIDTH),  -- i=14: Zero (no rotation)
        to_signed(16#0000#, DATA_WIDTH)   -- i=15: Zero (no rotation)
    );

    -- Register to hold current angle output
    signal angle_reg : signed(DATA_WIDTH-1 downto 0);

begin

    -- Synchronous table lookup
    process(clk)
    begin
        if rising_edge(clk) then
            angle_reg <= ANGLE_TABLE(addr);
        end if;
    end process;

    -- Output assignment
    angle_out <= angle_reg;

end Behavioral;
