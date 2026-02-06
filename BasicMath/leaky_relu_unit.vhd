--------------------------------------------------------------------------------
-- Module: leaky_relu_unit
-- Description: Leaky ReLU activation function using power-of-2 slope
--              f(x) = x        if x >= 0
--              f(x) = x >> N   if x < 0  (equivalent to x * 2^(-N))
--
--              Pure combinational logic - no clock required
--
-- Format: Q2.13 (16-bit signed)
--
-- Leaky ReLU Benefits:
--   - Prevents "dying ReLU" problem where neurons become permanently inactive
--   - Small gradient for negative inputs allows recovery during training
--   - Power-of-2 slope enables efficient shift-based implementation
--
-- Configurable Slopes (via LEAK_SHIFT generic):
--   LEAK_SHIFT = 1  → α = 0.5     (aggressive leak)
--   LEAK_SHIFT = 2  → α = 0.25
--   LEAK_SHIFT = 3  → α = 0.125
--   LEAK_SHIFT = 4  → α = 0.0625  (default, good balance)
--   LEAK_SHIFT = 5  → α = 0.03125
--   LEAK_SHIFT = 6  → α = 0.015625
--   LEAK_SHIFT = 7  → α = 0.0078125 (close to standard 0.01)
--
-- Author: FPGA Neural Network Project
-- Complexity: EASY (⭐)
-- Dependencies: None
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity leaky_relu_unit is
    generic (
        DATA_WIDTH : integer := 16;    -- Q2.13 format
        LEAK_SHIFT : integer := 4      -- α = 2^(-LEAK_SHIFT) = 1/16 = 0.0625
    );
    port (
        -- Input data (Q2.13 signed)
        data_in    : in  signed(DATA_WIDTH-1 downto 0);
        
        -- Output data (Q2.13 signed)
        data_out   : out signed(DATA_WIDTH-1 downto 0);
        
        -- Status flags
        is_positive : out std_logic;   -- '1' if input >= 0 (pass-through path)
        is_negative : out std_logic    -- '1' if input < 0 (leak path)
    );
end entity leaky_relu_unit;

architecture rtl of leaky_relu_unit is

    ---------------------------------------------------------------------------
    -- Internal Signals
    ---------------------------------------------------------------------------
    signal sign_bit    : std_logic;
    signal leak_value  : signed(DATA_WIDTH-1 downto 0);

begin

    ---------------------------------------------------------------------------
    -- Sign Detection
    -- MSB = '1' indicates negative number in two's complement
    ---------------------------------------------------------------------------
    sign_bit <= data_in(DATA_WIDTH-1);

    ---------------------------------------------------------------------------
    -- Leak Path Computation
    -- Arithmetic right shift preserves sign for signed type
    -- This effectively multiplies negative input by 2^(-LEAK_SHIFT)
    ---------------------------------------------------------------------------
    leak_value <= shift_right(data_in, LEAK_SHIFT);

    ---------------------------------------------------------------------------
    -- Output Multiplexer
    -- Positive/Zero: pass through unchanged
    -- Negative: apply leak (scaled down version)
    ---------------------------------------------------------------------------
    data_out <= data_in when sign_bit = '0' else leak_value;

    ---------------------------------------------------------------------------
    -- Status Flag Outputs
    ---------------------------------------------------------------------------
    is_positive <= not sign_bit;
    is_negative <= sign_bit;

end architecture rtl;
