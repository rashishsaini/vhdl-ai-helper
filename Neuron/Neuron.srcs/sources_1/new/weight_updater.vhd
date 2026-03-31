--------------------------------------------------------------------------------
-- Module: weight_updater
-- Description: Updates weights using Stochastic Gradient Descent (SGD)
--              W_new = W_old - learning_rate × gradient
--
-- Formula:
--   W(t+1) = W(t) - η × ∂L/∂W
--   where:
--     η = learning rate (fixed-point, typically 0.01 to 0.1)
--     ∂L/∂W = gradient from backpropagation
--
-- Features:
--   - Configurable learning rate
--   - Saturation to prevent overflow
--   - Pipelined operation for throughput
--   - Supports both weights and biases
--
-- Format: Q2.13 for weights, Q10.26 for gradients (wider precision)
--
-- Pipeline:
--   Stage 1: Multiply gradient by learning rate
--   Stage 2: Subtract from current weight
--   Stage 3: Saturate and output
--
-- Author: FPGA Neural Network Project
-- Complexity: MEDIUM (⭐⭐)
-- Dependencies: None
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity weight_updater is
    generic (
        DATA_WIDTH     : integer := 16;    -- Weight width (Q2.13)
        GRAD_WIDTH     : integer := 40;    -- Gradient width (Q10.26)
        FRAC_BITS      : integer := 13;    -- Fractional bits in weights
        GRAD_FRAC_BITS : integer := 26;    -- Fractional bits in gradients
        -- Default learning rate: 0.01 in Q2.13 = 82
        DEFAULT_LR     : integer := 82
    );
    port (
        -- Clock and Reset
        clk            : in  std_logic;
        rst            : in  std_logic;
        
        -- Learning rate (can be changed dynamically)
        learning_rate  : in  signed(DATA_WIDTH-1 downto 0);
        
        -- Input: Current weight
        weight_in      : in  signed(DATA_WIDTH-1 downto 0);
        
        -- Input: Gradient for this weight
        gradient_in    : in  signed(GRAD_WIDTH-1 downto 0);
        
        -- Control
        enable         : in  std_logic;    -- Start update computation
        
        -- Output: Updated weight
        weight_out     : out signed(DATA_WIDTH-1 downto 0);
        
        -- Status
        valid          : out std_logic;    -- Output is valid
        overflow       : out std_logic;    -- Overflow occurred during computation
        done           : out std_logic     -- Update complete
    );
end entity weight_updater;

architecture rtl of weight_updater is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := 
        to_signed(2**(DATA_WIDTH-1) - 1, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := 
        to_signed(-2**(DATA_WIDTH-1), DATA_WIDTH);
    
    -- Intermediate width for lr × gradient product
    -- Q2.13 × Q10.26 = Q12.39 (needs 52 bits, but we'll work with 56 for safety)
    constant PRODUCT_WIDTH : integer := DATA_WIDTH + GRAD_WIDTH;
    
    -- Shift amount to convert gradient from Q10.26 to Q2.13 for the update
    -- After multiplying lr (Q2.13) × grad (Q10.26) = Q12.39
    -- We need Q2.13, so shift right by 39-13 = 26 bits
    constant SCALE_SHIFT : integer := GRAD_FRAC_BITS;

    ---------------------------------------------------------------------------
    -- Pipeline Registers
    ---------------------------------------------------------------------------
    -- Stage 1: Input capture and multiplication
    signal lr_reg           : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal weight_reg       : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal gradient_reg     : signed(GRAD_WIDTH-1 downto 0) := (others => '0');
    signal stage1_valid     : std_logic := '0';
    
    -- Stage 2: Product computation
    signal product          : signed(PRODUCT_WIDTH-1 downto 0) := (others => '0');
    signal weight_stage2    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal stage2_valid     : std_logic := '0';
    
    -- Stage 3: Scaled update and subtraction
    signal update_term      : signed(DATA_WIDTH+1 downto 0) := (others => '0');
    signal new_weight       : signed(DATA_WIDTH+1 downto 0) := (others => '0');
    signal weight_stage3    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal stage3_valid     : std_logic := '0';
    
    -- Output registers
    signal weight_out_reg   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal valid_reg        : std_logic := '0';
    signal overflow_reg     : std_logic := '0';
    signal done_reg         : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Pipeline Stage 1: Capture inputs
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                lr_reg       <= to_signed(DEFAULT_LR, DATA_WIDTH);
                weight_reg   <= (others => '0');
                gradient_reg <= (others => '0');
                stage1_valid <= '0';
            elsif enable = '1' then
                lr_reg       <= learning_rate;
                weight_reg   <= weight_in;
                gradient_reg <= gradient_in;
                stage1_valid <= '1';
            else
                stage1_valid <= '0';
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Pipeline Stage 2: Multiply learning_rate × gradient
    -- Q2.13 × Q10.26 = Q12.39
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                product       <= (others => '0');
                weight_stage2 <= (others => '0');
                stage2_valid  <= '0';
            elsif stage1_valid = '1' then
                -- Full precision multiplication
                product <= lr_reg * gradient_reg;
                weight_stage2 <= weight_reg;
                stage2_valid <= '1';
            else
                stage2_valid <= '0';
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Pipeline Stage 3: Scale product and subtract from weight
    -- Scale Q12.39 → Q2.13 by shifting right by 26
    -- Then compute: new_weight = old_weight - scaled_product
    ---------------------------------------------------------------------------
    process(clk)
        variable scaled_product : signed(PRODUCT_WIDTH-1 downto 0);
        variable rounded        : signed(PRODUCT_WIDTH-1 downto 0);
        variable update_val     : signed(DATA_WIDTH+1 downto 0);
        variable diff           : signed(DATA_WIDTH+1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                update_term   <= (others => '0');
                new_weight    <= (others => '0');
                weight_stage3 <= (others => '0');
                stage3_valid  <= '0';
            elsif stage2_valid = '1' then
                -- Add rounding before shift
                if SCALE_SHIFT > 0 then
                    rounded := product + to_signed(2**(SCALE_SHIFT-1), PRODUCT_WIDTH);
                else
                    rounded := product;
                end if;
                
                -- Scale down to Q2.13
                scaled_product := shift_right(rounded, SCALE_SHIFT);
                
                -- Extract update term (should fit in DATA_WIDTH+2 bits with margin)
                update_val := resize(scaled_product(DATA_WIDTH downto 0), DATA_WIDTH+2);
                update_term <= update_val;
                
                -- Compute: W_new = W_old - η × gradient
                diff := resize(weight_stage2, DATA_WIDTH+2) - update_val;
                new_weight <= diff;
                
                weight_stage3 <= weight_stage2;
                stage3_valid <= '1';
            else
                stage3_valid <= '0';
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Pipeline Stage 4: Saturation and Output
    ---------------------------------------------------------------------------
    process(clk)
        variable sat_flag : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                weight_out_reg <= (others => '0');
                valid_reg      <= '0';
                overflow_reg   <= '0';
                done_reg       <= '0';
            elsif stage3_valid = '1' then
                sat_flag := '0';
                
                -- Saturation check
                if new_weight > resize(SAT_MAX, DATA_WIDTH+2) then
                    weight_out_reg <= SAT_MAX;
                    sat_flag := '1';
                elsif new_weight < resize(SAT_MIN, DATA_WIDTH+2) then
                    weight_out_reg <= SAT_MIN;
                    sat_flag := '1';
                else
                    weight_out_reg <= new_weight(DATA_WIDTH-1 downto 0);
                end if;
                
                valid_reg    <= '1';
                overflow_reg <= sat_flag;
                done_reg     <= '1';
            else
                valid_reg <= '0';
                done_reg  <= '0';
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    weight_out <= weight_out_reg;
    valid      <= valid_reg;
    overflow   <= overflow_reg;
    done       <= done_reg;

end architecture rtl;
