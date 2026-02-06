--------------------------------------------------------------------------------
-- Module: saturation_unit
-- Description: Clamps input value to Q2.13 representable range
--              Pure combinational logic - no clock required
--
-- Format: Q2.13 (16-bit signed)
--   Range: [-4.0, +3.9998779296875]
--   Min: 0x8000 = -32768 = -4.0
--   Max: 0x7FFF = +32767 = +3.9998779296875
--
-- Use Cases:
--   - Clamp intermediate results after operations
--   - Prevent overflow in activation functions
--   - Ensure valid range before storage
--
-- Author: FPGA Neural Network Project
-- Complexity: EASY (⭐)
-- Dependencies: None
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity saturation_unit is
    generic (
        INPUT_WIDTH  : integer := 20;    -- Wider input (e.g., from additions)
        OUTPUT_WIDTH : integer := 16;    -- Q2.13 output
        -- Saturation bounds (Q2.13 format)
        SAT_MAX      : integer := 32767;  -- +3.9999 in Q2.13
        SAT_MIN      : integer := -32768  -- -4.0 in Q2.13
    );
    port (
        -- Input (wider precision)
        data_in      : in  signed(INPUT_WIDTH-1 downto 0);
        
        -- Output (clamped to Q2.13)
        data_out     : out signed(OUTPUT_WIDTH-1 downto 0);
        
        -- Status flags (active high)
        saturated_pos : out std_logic;  -- Positive saturation occurred
        saturated_neg : out std_logic;  -- Negative saturation occurred
        saturated     : out std_logic   -- Any saturation occurred
    );
end entity saturation_unit;

architecture rtl of saturation_unit is

    -- Extended bounds for comparison with wider input
    constant MAX_EXTENDED : signed(INPUT_WIDTH-1 downto 0) := 
        to_signed(SAT_MAX, INPUT_WIDTH);
    constant MIN_EXTENDED : signed(INPUT_WIDTH-1 downto 0) := 
        to_signed(SAT_MIN, INPUT_WIDTH);

    -- Internal signals for saturation detection
    signal is_pos_overflow : std_logic;
    signal is_neg_overflow : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Saturation Detection (Combinational)
    ---------------------------------------------------------------------------
    is_pos_overflow <= '1' when data_in > MAX_EXTENDED else '0';
    is_neg_overflow <= '1' when data_in < MIN_EXTENDED else '0';

    ---------------------------------------------------------------------------
    -- Output Multiplexer (Combinational)
    ---------------------------------------------------------------------------
    process(data_in, is_pos_overflow, is_neg_overflow)
    begin
        if is_pos_overflow = '1' then
            -- Clamp to maximum
            data_out <= to_signed(SAT_MAX, OUTPUT_WIDTH);
        elsif is_neg_overflow = '1' then
            -- Clamp to minimum
            data_out <= to_signed(SAT_MIN, OUTPUT_WIDTH);
        else
            -- No saturation - pass through lower bits
            data_out <= resize(data_in, OUTPUT_WIDTH);
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Status Flag Outputs
    ---------------------------------------------------------------------------
    saturated_pos <= is_pos_overflow;
    saturated_neg <= is_neg_overflow;
    saturated     <= is_pos_overflow or is_neg_overflow;

end architecture rtl;