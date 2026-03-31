--------------------------------------------------------------------------------
-- Module Name: bias_adder - Enhanced Implementation
-- Description: Adds bias term to accumulated sum with pipeline stage
--              Optimized for neural network acceleration systems
--------------------------------------------------------------------------------
-- Features:
--   - Single-cycle pipelined operation
--   - Proper sign extension for different width biases
--   - Overflow detection (optional, configurable)
--   - Valid/enable handshaking
--   - Optimized for DSP48 integration
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bias_adder is
    generic (
        ACCUM_WIDTH : integer := 40;  -- Accumulator width (Q10.26)
        BIAS_WIDTH  : integer := 16;  -- Bias width (Q2.13)
        ENABLE_OVERFLOW_CHECK : boolean := true  -- Enable overflow detection
    );
    port (
        -- Clock and Reset
        clk         : in  std_logic;
        rst         : in  std_logic;  -- Synchronous reset, active high
        
        -- Control Signals
        enable      : in  std_logic;  -- Enable bias addition
        
        -- Data Inputs
        accum_in    : in  signed(ACCUM_WIDTH-1 downto 0);
        bias        : in  signed(BIAS_WIDTH-1 downto 0);
        
        -- Data Outputs
        sum_out     : out signed(ACCUM_WIDTH-1 downto 0);
        valid       : out std_logic;
        
        -- Status Outputs
        overflow    : out std_logic  -- Overflow detected
    );
end bias_adder;

architecture behavioral of bias_adder is
    
    -- Internal signals
    signal bias_extended : signed(ACCUM_WIDTH-1 downto 0);
    signal sum_internal  : signed(ACCUM_WIDTH downto 0);  -- Extra bit for overflow
    signal sum_reg       : signed(ACCUM_WIDTH-1 downto 0);
    signal valid_reg     : std_logic;
    signal overflow_reg  : std_logic;
    
    -- Constants for overflow detection
    constant MAX_POSITIVE : signed(ACCUM_WIDTH downto 0) := 
        resize(to_signed(2**(ACCUM_WIDTH-1)-1, ACCUM_WIDTH), ACCUM_WIDTH+1);
    constant MAX_NEGATIVE : signed(ACCUM_WIDTH downto 0) := 
        resize(to_signed(-2**(ACCUM_WIDTH-1), ACCUM_WIDTH), ACCUM_WIDTH+1);
    
begin

    ----------------------------------------------------------------------------
    -- Sign Extension Process
    -- Extends bias to match accumulator width while preserving sign
    ----------------------------------------------------------------------------
    bias_extended <= resize(bias, ACCUM_WIDTH);
    
    ----------------------------------------------------------------------------
    -- Addition with Overflow Detection
    -- Performs addition in ACCUM_WIDTH+1 bits to detect overflow
    ----------------------------------------------------------------------------
    sum_internal <= resize(accum_in, ACCUM_WIDTH+1) + 
                    resize(bias_extended, ACCUM_WIDTH+1);
    
    ----------------------------------------------------------------------------
    -- Pipeline Register Process
    -- Registers outputs for timing closure and pipeline integration
    ----------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sum_reg      <= (others => '0');
                valid_reg    <= '0';
                overflow_reg <= '0';
            elsif enable = '1' then
                -- Register the sum (truncate to ACCUM_WIDTH)
                sum_reg <= sum_internal(ACCUM_WIDTH-1 downto 0);
                
                -- Register valid signal
                valid_reg <= '1';
                
                -- Overflow detection (if enabled)
                if ENABLE_OVERFLOW_CHECK then
                    if (sum_internal > MAX_POSITIVE) or (sum_internal < MAX_NEGATIVE) then
                        overflow_reg <= '1';
                    else
                        overflow_reg <= '0';
                    end if;
                else
                    overflow_reg <= '0';
                end if;
            else
                -- When not enabled, clear valid but maintain data
                valid_reg <= '0';
            end if;
        end if;
    end process;
    
    ----------------------------------------------------------------------------
    -- Output Assignments
    ----------------------------------------------------------------------------
    sum_out  <= sum_reg;
    valid    <= valid_reg;
    overflow <= overflow_reg;
    
end behavioral;

--------------------------------------------------------------------------------
-- Architecture Notes:
--------------------------------------------------------------------------------
-- 1. TIMING: Single-cycle latency from input to registered output
-- 2. RESOURCES: One ACCUM_WIDTH-bit adder + minimal control logic
-- 3. OVERFLOW: Detection available but doesn't saturate (user decides)
-- 4. INTEGRATION: Compatible with standard neuron datapath pipeline
-- 5. WIDTH HANDLING: Automatic via resize(), supports any bias width <= accum
--------------------------------------------------------------------------------
-- Performance Characteristics:
--   - Latency: 1 clock cycle
--   - Throughput: 1 operation per cycle (when enabled)
--   - Critical Path: Addition + register setup time
--   - Estimated Logic: ~50-80 LUTs (depends on ACCUM_WIDTH)
--------------------------------------------------------------------------------