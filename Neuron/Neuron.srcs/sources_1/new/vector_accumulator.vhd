--------------------------------------------------------------------------------
-- Module: vector_accumulator
-- Description: Accumulates multiple vector elements into a single sum
--              y = Σ x[i] for i = 0 to N-1
--
-- Features:
--   - Configurable vector length
--   - Running accumulation with clear capability
--   - FSM-based control for variable-length vectors
--   - Saturation on overflow
--   - Completion detection
--
-- Use Cases:
--   - Batch normalization (computing mean)
--   - Loss aggregation across samples
--   - Feature aggregation in neural networks
--   - Gradient accumulation across mini-batches
--
-- Format: Q2.13 input (16-bit), Q10.26 accumulator (40-bit)
--
-- FSM States:
--   IDLE      - Waiting for start or data
--   ACCUM     - Actively accumulating elements
--   DONE_ST   - Accumulation complete, output valid
--
-- Author: FPGA Neural Network Project
-- Complexity: MEDIUM (⭐⭐)
-- Dependencies: None (self-contained)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity vector_accumulator is
    generic (
        DATA_WIDTH   : integer := 16;     -- Input element width (Q2.13)
        ACCUM_WIDTH  : integer := 40;     -- Accumulator width (Q10.26)
        FRAC_BITS    : integer := 13;     -- Input fractional bits
        MAX_ELEMENTS : integer := 16;     -- Maximum vector length
        ENABLE_SAT   : boolean := true    -- Enable saturation
    );
    port (
        -- Clock and Reset
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Control Interface
        start        : in  std_logic;     -- Start new accumulation
        clear        : in  std_logic;     -- Clear accumulator
        num_elements : in  unsigned(7 downto 0);  -- Number of elements to sum
        
        -- Input Interface
        data_in      : in  signed(DATA_WIDTH-1 downto 0);
        data_valid   : in  std_logic;     -- Input is valid
        data_ready   : out std_logic;     -- Ready for input
        
        -- Output Interface
        accum_out    : out signed(ACCUM_WIDTH-1 downto 0);
        result_valid : out std_logic;     -- Final result is valid
        out_ready    : in  std_logic;     -- Downstream ready for result
        
        -- Status
        busy         : out std_logic;     -- Accumulator is busy
        done         : out std_logic;     -- Accumulation complete
        overflow     : out std_logic;     -- Overflow occurred
        elem_count   : out unsigned(7 downto 0)  -- Number of accumulated elements
    );
end entity vector_accumulator;

architecture rtl of vector_accumulator is

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (IDLE, ACCUM, DONE_ST);
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    -- Maximum positive value for signed ACCUM_WIDTH-bit number
    function max_accum_val return signed is
        variable result : signed(ACCUM_WIDTH-1 downto 0);
    begin
        result := (others => '1');
        result(ACCUM_WIDTH-1) := '0';
        return result;
    end function;
    
    -- Minimum negative value for signed ACCUM_WIDTH-bit number
    function min_accum_val return signed is
        variable result : signed(ACCUM_WIDTH-1 downto 0);
    begin
        result := (others => '0');
        result(ACCUM_WIDTH-1) := '1';
        return result;
    end function;
    
    constant MAX_ACCUM : signed(ACCUM_WIDTH-1 downto 0) := max_accum_val;
    constant MIN_ACCUM : signed(ACCUM_WIDTH-1 downto 0) := min_accum_val;

    ---------------------------------------------------------------------------
    -- Internal Registers
    ---------------------------------------------------------------------------
    signal accum_reg      : signed(ACCUM_WIDTH-1 downto 0) := (others => '0');
    signal target_count   : unsigned(7 downto 0) := (others => '0');
    signal current_count  : unsigned(7 downto 0) := (others => '0');
    signal overflow_reg   : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable data_ext : signed(ACCUM_WIDTH-1 downto 0);
        variable sum      : signed(ACCUM_WIDTH downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state         <= IDLE;
                accum_reg     <= (others => '0');
                target_count  <= (others => '0');
                current_count <= (others => '0');
                overflow_reg  <= '0';
            else
                case state is
                    
                    ---------------------------------------------------------
                    -- IDLE: Wait for start signal
                    ---------------------------------------------------------
                    when IDLE =>
                        if clear = '1' then
                            accum_reg     <= (others => '0');
                            current_count <= (others => '0');
                            overflow_reg  <= '0';
                        elsif start = '1' then
                            -- Initialize for new accumulation
                            target_count  <= num_elements;
                            accum_reg     <= (others => '0');
                            current_count <= (others => '0');
                            overflow_reg  <= '0';
                            
                            if num_elements = 0 then
                                -- Zero elements: immediately done
                                state <= DONE_ST;
                            else
                                state <= ACCUM;
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- ACCUM: Accumulate elements
                    ---------------------------------------------------------
                    when ACCUM =>
                        if clear = '1' then
                            accum_reg     <= (others => '0');
                            current_count <= (others => '0');
                            overflow_reg  <= '0';
                            state         <= IDLE;
                        elsif data_valid = '1' then
                            -- Sign-extend input to accumulator width
                            data_ext := resize(data_in, ACCUM_WIDTH);
                            
                            -- Perform addition with overflow detection
                            sum := resize(accum_reg, ACCUM_WIDTH+1) + 
                                   resize(data_ext, ACCUM_WIDTH+1);
                            
                            -- Check for overflow and saturate if enabled
                            if ENABLE_SAT then
                                if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
                                    overflow_reg <= '1';
                                    if sum(ACCUM_WIDTH) = '0' then
                                        accum_reg <= MAX_ACCUM;
                                    else
                                        accum_reg <= MIN_ACCUM;
                                    end if;
                                else
                                    accum_reg <= sum(ACCUM_WIDTH-1 downto 0);
                                end if;
                            else
                                accum_reg <= sum(ACCUM_WIDTH-1 downto 0);
                                if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
                                    overflow_reg <= '1';
                                end if;
                            end if;
                            
                            -- Update count
                            current_count <= current_count + 1;
                            
                            -- Check if done
                            if current_count + 1 = target_count then
                                state <= DONE_ST;
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- DONE_ST: Output result
                    ---------------------------------------------------------
                    when DONE_ST =>
                        if clear = '1' then
                            accum_reg     <= (others => '0');
                            current_count <= (others => '0');
                            overflow_reg  <= '0';
                            state         <= IDLE;
                        elsif out_ready = '1' then
                            -- Return to IDLE after result accepted
                            state <= IDLE;
                        end if;
                    
                    when others =>
                        state <= IDLE;
                        
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    accum_out    <= accum_reg;
    data_ready   <= '1' when state = ACCUM else '0';
    result_valid <= '1' when state = DONE_ST else '0';
    busy         <= '0' when state = IDLE else '1';
    done         <= '1' when state = DONE_ST else '0';
    overflow     <= overflow_reg;
    elem_count   <= current_count;

end architecture rtl;
