--------------------------------------------------------------------------------
-- Module: activation_derivative_unit
-- Description: Computes derivative of activation function
--              Currently implements ReLU derivative: σ'(z) = 1 if z > 0, else 0
--              Pure combinational logic - no clock required
--
-- Format: Q2.13 (16-bit signed)
--
-- ReLU Derivative:
--   σ(z) = max(0, z)
--   σ'(z) = 1 if z > 0
--   σ'(z) = 0 if z <= 0
--
-- Note: At z = 0, derivative is technically undefined, but we use 0
--       (subgradient convention common in deep learning)
--
-- Use Cases:
--   - Computing delta in backpropagation: δ = error × σ'(z)
--   - Chain rule application in gradient computation
--
-- Author: FPGA Neural Network Project
-- Complexity: EASY (⭐)
-- Dependencies: None
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity activation_derivative_unit is
    generic (
        DATA_WIDTH : integer := 16;    -- Q2.13 format
        FRAC_BITS  : integer := 13     -- Fractional bits
    );
    port (
        -- Pre-activation input (z value from forward pass)
        z_in         : in  signed(DATA_WIDTH-1 downto 0);
        
        -- Derivative output
        -- For ReLU: 1.0 (0x2000 in Q2.13) or 0.0
        derivative   : out signed(DATA_WIDTH-1 downto 0);
        
        -- Status flag
        is_active    : out std_logic   -- '1' if neuron was active (z > 0)
    );
end entity activation_derivative_unit;

architecture rtl of activation_derivative_unit is

    -- Constant for 1.0 in Q2.13 format
    -- 1.0 = 2^13 = 8192 = 0x2000
    constant ONE : signed(DATA_WIDTH-1 downto 0) := 
        to_signed(2**FRAC_BITS, DATA_WIDTH);
    
    -- Constant for 0.0
    constant ZERO : signed(DATA_WIDTH-1 downto 0) := 
        to_signed(0, DATA_WIDTH);

    -- Internal signal for activation detection
    signal active : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Activation Detection (Combinational)
    -- ReLU is active when z > 0 (sign bit is '0' and value is non-zero)
    ---------------------------------------------------------------------------
    -- Check if z > 0: sign bit must be '0' AND value must be non-zero
    active <= '1' when (z_in(DATA_WIDTH-1) = '0') and (z_in /= ZERO) else '0';

    ---------------------------------------------------------------------------
    -- Derivative Output (Combinational)
    -- σ'(z) = 1 if z > 0, else 0
    ---------------------------------------------------------------------------
    derivative <= ONE when active = '1' else ZERO;

    ---------------------------------------------------------------------------
    -- Status Output
    ---------------------------------------------------------------------------
    is_active <= active;

end architecture rtl;