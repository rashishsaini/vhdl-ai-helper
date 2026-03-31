--------------------------------------------------------------------------------
-- Module: rounding_saturation
-- Description: Fixed-point rounding and saturation unit for neural network
--              Converts Q10.26 (40-bit) accumulator to Q2.13 (16-bit) output
--              Implements round-to-nearest with symmetric saturation
--
-- Author: FPGA Neural Network Project
-- Version: 2.0
-- 
-- Features:
--   - Configurable input/output widths via generics
--   - Valid/Done handshaking for pipeline integration
--   - Overflow detection and saturation flags
--   - Single-cycle registered operation for timing closure
--   - Symmetric saturation (preserves sign symmetry)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity rounding_saturation is
    generic (
        -- Bit width parameters
        INPUT_WIDTH   : integer := 40;   -- Accumulator width (Q10.26)
        OUTPUT_WIDTH  : integer := 16;   -- Result width (Q2.13)
        FRAC_SHIFT    : integer := 13;   -- Fractional bits to remove (26-13)
        
        -- Saturation bounds (in output format Q2.13)
        -- Max: +3.9998779... = 0x7FFF = 32767
        -- Min: -4.0          = 0x8000 = -32768
        SAT_MAX       : integer := 32767;
        SAT_MIN       : integer := -32768
    );
    port (
        -- Clock and reset
        clk           : in  std_logic;
        rst           : in  std_logic;
        
        -- Input interface
        data_in       : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
        valid_in      : in  std_logic;
        
        -- Output interface
        data_out      : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
        valid_out     : out std_logic;
        done          : out std_logic;
        
        -- Status flags
        overflow_pos  : out std_logic;  -- Positive saturation occurred
        overflow_neg  : out std_logic;  -- Negative saturation occurred
        saturated     : out std_logic   -- Any saturation occurred
    );
end entity rounding_saturation;

architecture rtl of rounding_saturation is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    -- Rounding constant: 0.5 LSB in the bits being removed = 2^(FRAC_SHIFT-1)
    constant ROUND_CONST : signed(INPUT_WIDTH-1 downto 0) := 
        to_signed(2**(FRAC_SHIFT-1), INPUT_WIDTH);
    
    -- Saturation bounds as signed values for comparison
    constant MAX_BOUND : signed(INPUT_WIDTH-1 downto 0) := 
        to_signed(SAT_MAX, INPUT_WIDTH);
    constant MIN_BOUND : signed(INPUT_WIDTH-1 downto 0) := 
        to_signed(SAT_MIN, INPUT_WIDTH);
    
    ---------------------------------------------------------------------------
    -- Internal signals
    ---------------------------------------------------------------------------
    -- Pipeline stage 1: Rounding addition
    signal data_in_reg    : signed(INPUT_WIDTH-1 downto 0);
    signal valid_stage1   : std_logic;
    
    -- Combinational intermediate signals
    signal rounded_val    : signed(INPUT_WIDTH-1 downto 0);
    signal shifted_val    : signed(INPUT_WIDTH-1 downto 0);
    
    -- Saturation detection
    signal sat_pos        : std_logic;
    signal sat_neg        : std_logic;
    
    -- Output registers
    signal data_out_reg   : std_logic_vector(OUTPUT_WIDTH-1 downto 0);
    signal valid_out_reg  : std_logic;
    signal done_reg       : std_logic;
    signal ovf_pos_reg    : std_logic;
    signal ovf_neg_reg    : std_logic;
    signal sat_reg        : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Input Registration (Stage 1)
    -- Register input data for timing closure
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                data_in_reg  <= (others => '0');
                valid_stage1 <= '0';
            else
                data_in_reg  <= signed(data_in);
                valid_stage1 <= valid_in;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Rounding and Shifting (Combinational)
    -- Add rounding constant then arithmetic shift right
    ---------------------------------------------------------------------------
    -- Round to nearest: add 0.5 LSB (in removed bits)
    rounded_val <= data_in_reg + ROUND_CONST;
    
    -- Arithmetic right shift preserves sign
    shifted_val <= shift_right(rounded_val, FRAC_SHIFT);

    ---------------------------------------------------------------------------
    -- Saturation Detection (Combinational)
    -- Check if shifted value exceeds output range
    ---------------------------------------------------------------------------
    sat_pos <= '1' when shifted_val > MAX_BOUND else '0';
    sat_neg <= '1' when shifted_val < MIN_BOUND else '0';

    ---------------------------------------------------------------------------
    -- Output Registration with Saturation (Stage 2)
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                data_out_reg <= (others => '0');
                valid_out_reg <= '0';
                done_reg      <= '0';
                ovf_pos_reg   <= '0';
                ovf_neg_reg   <= '0';
                sat_reg       <= '0';
            else
                -- Valid propagation
                valid_out_reg <= valid_stage1;
                done_reg      <= valid_stage1;  -- Done pulses with valid
                
                -- Status flags
                ovf_pos_reg <= sat_pos and valid_stage1;
                ovf_neg_reg <= sat_neg and valid_stage1;
                sat_reg     <= (sat_pos or sat_neg) and valid_stage1;
                
                -- Output with saturation
                if valid_stage1 = '1' then
                    if sat_pos = '1' then
                        -- Positive overflow: clamp to maximum
                        data_out_reg <= std_logic_vector(to_signed(SAT_MAX, OUTPUT_WIDTH));
                    elsif sat_neg = '1' then
                        -- Negative overflow: clamp to minimum
                        data_out_reg <= std_logic_vector(to_signed(SAT_MIN, OUTPUT_WIDTH));
                    else
                        -- Normal operation: extract output bits
                        data_out_reg <= std_logic_vector(shifted_val(OUTPUT_WIDTH-1 downto 0));
                    end if;
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    data_out     <= data_out_reg;
    valid_out    <= valid_out_reg;
    done         <= done_reg;
    overflow_pos <= ovf_pos_reg;
    overflow_neg <= ovf_neg_reg;
    saturated    <= sat_reg;

end architecture rtl;