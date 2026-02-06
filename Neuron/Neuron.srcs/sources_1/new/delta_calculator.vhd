--------------------------------------------------------------------------------
-- Module: delta_calculator
-- Description: Computes delta (δ) for backpropagation
--              δ = error × σ'(z)
--              where error is either (target - actual) for output layer
--              or propagated error from next layer for hidden layers
--
-- Formula:
--   Output layer: δ = (target - actual) × σ'(z)
--   Hidden layer: δ = (W^T × δ_next) × σ'(z)
--
-- For ReLU activation:
--   σ'(z) = 1 if z > 0, else 0
--   So: δ = error if z > 0, else 0
--
-- This simplification means we can gate the error by the activation derivative
-- which is either pass-through (×1) or zero (×0)
--
-- Format: Q2.13 input/output (16-bit signed)
-- Implementation: Combinational with optional output register
--
-- Author: FPGA Neural Network Project
-- Complexity: MEDIUM (⭐⭐)
-- Dependencies: activation_derivative_unit (internal instantiation)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity delta_calculator is
    generic (
        DATA_WIDTH    : integer := 16;    -- Q2.13 format
        FRAC_BITS     : integer := 13;    -- Fractional bits
        REGISTERED    : boolean := true   -- Register output for timing
    );
    port (
        -- Clock and Reset (only used if REGISTERED = true)
        clk           : in  std_logic;
        rst           : in  std_logic;
        
        -- Input: Error signal (from error_calculator or error_propagator)
        error_in      : in  signed(DATA_WIDTH-1 downto 0);
        
        -- Input: Pre-activation value z (from forward_cache)
        z_in          : in  signed(DATA_WIDTH-1 downto 0);
        
        -- Control
        enable        : in  std_logic;    -- Enable computation
        
        -- Output: Delta value for gradient computation
        delta_out     : out signed(DATA_WIDTH-1 downto 0);
        
        -- Status flags
        valid         : out std_logic;    -- Output is valid
        is_active     : out std_logic;    -- Neuron was active (z > 0)
        zero_delta    : out std_logic     -- Delta is zero (inactive neuron)
    );
end entity delta_calculator;

architecture rtl of delta_calculator is

    ---------------------------------------------------------------------------
    -- Component: Activation Derivative Unit
    ---------------------------------------------------------------------------
    component activation_derivative_unit is
        generic (
            DATA_WIDTH : integer := 16;
            FRAC_BITS  : integer := 13
        );
        port (
            z_in       : in  signed(DATA_WIDTH-1 downto 0);
            derivative : out signed(DATA_WIDTH-1 downto 0);
            is_active  : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant ONE  : signed(DATA_WIDTH-1 downto 0) := to_signed(2**FRAC_BITS, DATA_WIDTH);
    constant ZERO : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Saturation bounds
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(2**(DATA_WIDTH-1) - 1, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-2**(DATA_WIDTH-1), DATA_WIDTH);

    ---------------------------------------------------------------------------
    -- Internal Signals
    ---------------------------------------------------------------------------
    -- Activation derivative signals
    signal act_derivative : signed(DATA_WIDTH-1 downto 0);
    signal act_is_active  : std_logic;
    
    -- Multiplication result (error × derivative)
    -- For ReLU, derivative is 0 or 1, so product is 0 or error
    -- But we implement general multiplication for other activations
    signal product        : signed(2*DATA_WIDTH-1 downto 0);
    signal product_scaled : signed(DATA_WIDTH-1 downto 0);
    
    -- Combinational delta value
    signal delta_comb     : signed(DATA_WIDTH-1 downto 0);
    signal delta_is_zero  : std_logic;
    
    -- Registered outputs
    signal delta_reg      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal valid_reg      : std_logic := '0';
    signal active_reg     : std_logic := '0';
    signal zero_reg       : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Activation Derivative Unit Instantiation
    ---------------------------------------------------------------------------
    act_deriv_inst : activation_derivative_unit
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            FRAC_BITS  => FRAC_BITS
        )
        port map (
            z_in       => z_in,
            derivative => act_derivative,
            is_active  => act_is_active
        );

    ---------------------------------------------------------------------------
    -- Delta Computation (Combinational)
    -- δ = error × σ'(z)
    --
    -- For ReLU: σ'(z) = 1 or 0, so this is effectively a gate
    -- For general case: full Q2.13 × Q2.13 multiplication
    ---------------------------------------------------------------------------
    
    -- Full multiplication: Q2.13 × Q2.13 = Q4.26
    product <= error_in * act_derivative;
    
    -- Scale back to Q2.13: shift right by FRAC_BITS with rounding
    process(product)
        variable rounded : signed(2*DATA_WIDTH-1 downto 0);
        variable shifted : signed(2*DATA_WIDTH-1 downto 0);
    begin
        -- Add 0.5 LSB for rounding
        rounded := product + to_signed(2**(FRAC_BITS-1), 2*DATA_WIDTH);
        shifted := shift_right(rounded, FRAC_BITS);
        
        -- Saturation check
        if shifted > resize(SAT_MAX, 2*DATA_WIDTH) then
            product_scaled <= SAT_MAX;
        elsif shifted < resize(SAT_MIN, 2*DATA_WIDTH) then
            product_scaled <= SAT_MIN;
        else
            product_scaled <= shifted(DATA_WIDTH-1 downto 0);
        end if;
    end process;
    
    -- For ReLU optimization: since derivative is 0 or 1,
    -- we can simplify: delta = error when active, 0 otherwise
    -- But we use the general multiplication for flexibility
    delta_comb <= product_scaled;
    
    -- Check if delta is zero
    delta_is_zero <= '1' when delta_comb = ZERO else '0';

    ---------------------------------------------------------------------------
    -- Output Generation
    ---------------------------------------------------------------------------
    gen_registered : if REGISTERED generate
        -- Registered output for timing closure
        process(clk)
        begin
            if rising_edge(clk) then
                if rst = '1' then
                    delta_reg  <= (others => '0');
                    valid_reg  <= '0';
                    active_reg <= '0';
                    zero_reg   <= '0';
                elsif enable = '1' then
                    delta_reg  <= delta_comb;
                    valid_reg  <= '1';
                    active_reg <= act_is_active;
                    zero_reg   <= delta_is_zero;
                else
                    valid_reg <= '0';
                end if;
            end if;
        end process;
        
        delta_out  <= delta_reg;
        valid      <= valid_reg;
        is_active  <= active_reg;
        zero_delta <= zero_reg;
    end generate;
    
    gen_combinational : if not REGISTERED generate
        -- Purely combinational output
        delta_out  <= delta_comb when enable = '1' else ZERO;
        valid      <= enable;
        is_active  <= act_is_active;
        zero_delta <= delta_is_zero;
    end generate;

end architecture rtl;
