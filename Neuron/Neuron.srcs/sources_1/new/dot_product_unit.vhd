--------------------------------------------------------------------------------
-- Module: dot_product_unit
-- Description: Computes dot product of weight and input vectors
--              y = Σ(w[i] × x[i]) for i = 0 to N-1
--
-- Features:
--   - Configurable vector length
--   - Uses internal MAC for multiply-accumulate
--   - Pipelined operation for high throughput
--   - Saturation on overflow
--   - FSM-controlled sequencing
--
-- Use Cases:
--   - Forward pass: z = W × x (pre-activation computation)
--   - Backward pass: error propagation δ = Wᵀ × δ_next
--
-- Format: Q2.13 input (16-bit), Q10.26 accumulator (40-bit)
--
-- Operation Sequence:
--   1. Assert start with num_elements
--   2. Provide weight/input pairs when data_ready='1'
--   3. Result available when done='1'
--
-- Author: FPGA Neural Network Project
-- Complexity: MEDIUM (⭐⭐)
-- Dependencies: None (self-contained MAC logic)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity dot_product_unit is
    generic (
        DATA_WIDTH   : integer := 16;     -- Input width (Q2.13)
        ACCUM_WIDTH  : integer := 40;     -- Accumulator width (Q10.26)
        FRAC_BITS    : integer := 13;     -- Fractional bits
        MAX_ELEMENTS : integer := 16      -- Maximum vector length
    );
    port (
        -- Clock and Reset
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Control Interface
        start        : in  std_logic;     -- Start new dot product
        clear        : in  std_logic;     -- Clear accumulator
        num_elements : in  unsigned(7 downto 0);  -- Vector length
        
        -- Input Interface
        weight_in    : in  signed(DATA_WIDTH-1 downto 0);
        data_in      : in  signed(DATA_WIDTH-1 downto 0);
        data_valid   : in  std_logic;     -- Input pair is valid
        data_ready   : out std_logic;     -- Ready for input pair
        
        -- Output Interface
        result_out   : out signed(ACCUM_WIDTH-1 downto 0);
        result_valid : out std_logic;     -- Result is valid
        out_ready    : in  std_logic;     -- Downstream ready
        
        -- Status
        busy         : out std_logic;
        done         : out std_logic;
        overflow     : out std_logic
    );
end entity dot_product_unit;

architecture rtl of dot_product_unit is

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (IDLE, ACCUMULATE, DONE_ST);
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Constants for saturation
    ---------------------------------------------------------------------------
    function max_accum_val return signed is
        variable result : signed(ACCUM_WIDTH-1 downto 0);
    begin
        result := (others => '1');
        result(ACCUM_WIDTH-1) := '0';
        return result;
    end function;
    
    function min_accum_val return signed is
        variable result : signed(ACCUM_WIDTH-1 downto 0);
    begin
        result := (others => '0');
        result(ACCUM_WIDTH-1) := '1';
        return result;
    end function;
    
    constant MAX_ACCUM : signed(ACCUM_WIDTH-1 downto 0) := max_accum_val;
    constant MIN_ACCUM : signed(ACCUM_WIDTH-1 downto 0) := min_accum_val;
    
    -- Product width: Q2.13 × Q2.13 = Q4.26 (32 bits)
    constant PRODUCT_WIDTH : integer := 2 * DATA_WIDTH;

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
        variable product     : signed(PRODUCT_WIDTH-1 downto 0);
        variable product_ext : signed(ACCUM_WIDTH-1 downto 0);
        variable sum         : signed(ACCUM_WIDTH downto 0);
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
                            -- Initialize for new dot product
                            target_count  <= num_elements;
                            accum_reg     <= (others => '0');
                            current_count <= (others => '0');
                            overflow_reg  <= '0';
                            
                            if num_elements = 0 then
                                -- Zero elements: immediately done with result = 0
                                state <= DONE_ST;
                            else
                                state <= ACCUMULATE;
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- ACCUMULATE: Multiply and accumulate elements
                    ---------------------------------------------------------
                    when ACCUMULATE =>
                        if clear = '1' then
                            accum_reg     <= (others => '0');
                            current_count <= (others => '0');
                            overflow_reg  <= '0';
                            state         <= IDLE;
                        elsif data_valid = '1' then
                            -- Multiply: Q2.13 × Q2.13 = Q4.26
                            product := weight_in * data_in;
                            
                            -- Sign-extend product to accumulator width
                            product_ext := resize(product, ACCUM_WIDTH);
                            
                            -- Accumulate with overflow detection
                            sum := resize(accum_reg, ACCUM_WIDTH+1) + 
                                   resize(product_ext, ACCUM_WIDTH+1);
                            
                            -- Check for overflow and saturate
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
    result_out   <= accum_reg;
    data_ready   <= '1' when state = ACCUMULATE else '0';
    result_valid <= '1' when state = DONE_ST else '0';
    busy         <= '0' when state = IDLE else '1';
    done         <= '1' when state = DONE_ST else '0';
    overflow     <= overflow_reg;

end architecture rtl;
