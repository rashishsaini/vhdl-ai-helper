--------------------------------------------------------------------------------
-- Module: weight_update_datapath
-- Description: Weight update datapath for 4-2-1 neural network
--              Applies SGD updates: W_new = W_old - η × gradient
--
-- Features:
--   - Reads accumulated gradients from gradient_register_bank
--   - Applies learning rate scaled update
--   - Writes updated weights back to weight_register_bank
--   - Supports configurable learning rate
--   - Sequential processing of all weights and biases
--
-- Network Architecture:
--   Layer 1: 8 weights + 2 biases = 10 parameters
--   Layer 2: 2 weights + 1 bias = 3 parameters
--   Total: 13 parameters to update
--
-- Memory Map:
--   Addr 0-7:   Layer 1 weights
--   Addr 8-9:   Layer 1 biases
--   Addr 10-11: Layer 2 weights
--   Addr 12:    Layer 2 bias
--
-- Pipeline:
--   IDLE → READ_WEIGHT → WAIT_WEIGHT → READ_GRADIENT → WAIT_GRADIENT →
--   COMPUTE_UPDATE → WRITE_WEIGHT → NEXT_PARAM → CLEAR_GRADS → DONE_ST
--
-- Author: FPGA Neural Network Project
-- Complexity: MEDIUM (⭐⭐)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity weight_update_datapath is
    generic (
        DATA_WIDTH     : integer := 16;    -- Weight width (Q2.13)
        GRAD_WIDTH     : integer := 40;    -- Gradient accumulator width (Q10.26)
        FRAC_BITS      : integer := 13;    -- Fractional bits in weights
        GRAD_FRAC_BITS : integer := 26;    -- Fractional bits in gradients
        NUM_PARAMS     : integer := 13;    -- Total weights + biases
        ADDR_WIDTH     : integer := 4;     -- Address width
        -- Default learning rate: 0.01 in Q2.13 = 82
        DEFAULT_LR     : integer := 82
    );
    port (
        -- Clock and Reset
        clk              : in  std_logic;
        rst              : in  std_logic;
        
        -- Control Interface
        start            : in  std_logic;
        clear            : in  std_logic;
        
        -- Learning Rate (can be adjusted dynamically)
        learning_rate    : in  signed(DATA_WIDTH-1 downto 0);
        use_default_lr   : in  std_logic;  -- '1' to use DEFAULT_LR
        
        -- Weight Register Bank Interface
        weight_rd_data   : in  signed(DATA_WIDTH-1 downto 0);
        weight_rd_addr   : out unsigned(ADDR_WIDTH-1 downto 0);
        weight_rd_en     : out std_logic;
        weight_wr_data   : out signed(DATA_WIDTH-1 downto 0);
        weight_wr_addr   : out unsigned(ADDR_WIDTH-1 downto 0);
        weight_wr_en     : out std_logic;
        
        -- Gradient Register Bank Interface
        grad_rd_data     : in  signed(GRAD_WIDTH-1 downto 0);
        grad_rd_addr     : out unsigned(ADDR_WIDTH-1 downto 0);
        grad_rd_en       : out std_logic;
        grad_clear       : out std_logic;  -- Clear gradients after update
        
        -- Status
        busy             : out std_logic;
        done             : out std_logic;
        param_count      : out unsigned(ADDR_WIDTH-1 downto 0);
        overflow         : out std_logic
    );
end entity weight_update_datapath;

architecture rtl of weight_update_datapath is

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        READ_WEIGHT,      -- Read current weight from weight bank
        WAIT_WEIGHT,      -- Wait cycle for weight read
        READ_GRADIENT,    -- Read gradient from gradient bank
        WAIT_GRADIENT,    -- Wait cycle for gradient read
        COMPUTE_UPDATE,   -- Compute: W_new = W_old - lr × grad
        WRITE_WEIGHT,     -- Write updated weight
        NEXT_PARAM,       -- Move to next parameter
        CLEAR_GRADS,      -- Clear gradient accumulators
        DONE_ST
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) :=
        to_signed(2**(DATA_WIDTH-1) - 1, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) :=
        to_signed(-2**(DATA_WIDTH-1), DATA_WIDTH);

    -- For lr × gradient: need wider intermediate
    constant PRODUCT_WIDTH : integer := DATA_WIDTH + GRAD_WIDTH;

    -- Shift amount: gradient is Q10.26, weight is Q2.13
    -- lr (Q2.13) × grad (Q10.26) = Q12.39
    -- To get Q2.13, shift right by 39-13 = 26 bits
    constant SCALE_SHIFT : integer := GRAD_FRAC_BITS;

    -- Rounding constant: 2^(SCALE_SHIFT-1) for proper rounding before shift
    -- Note: Must be constructed as signed vector to avoid integer overflow
    constant ROUND_CONST : signed(PRODUCT_WIDTH-1 downto 0) :=
        shift_left(to_signed(1, PRODUCT_WIDTH), SCALE_SHIFT-1);

    ---------------------------------------------------------------------------
    -- Internal Registers
    ---------------------------------------------------------------------------
    signal param_idx      : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal lr_reg         : signed(DATA_WIDTH-1 downto 0) := to_signed(DEFAULT_LR, DATA_WIDTH);
    
    -- Current weight and gradient
    signal weight_reg     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal gradient_reg   : signed(GRAD_WIDTH-1 downto 0) := (others => '0');
    
    -- Computed update
    signal product        : signed(PRODUCT_WIDTH-1 downto 0) := (others => '0');
    signal update_term    : signed(DATA_WIDTH+1 downto 0) := (others => '0');
    signal new_weight     : signed(DATA_WIDTH+1 downto 0) := (others => '0');
    signal new_weight_sat : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Status
    signal overflow_reg   : std_logic := '0';
    signal done_reg       : std_logic := '0';
    signal grad_clear_reg : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable scaled_product : signed(PRODUCT_WIDTH-1 downto 0);
        variable rounded        : signed(PRODUCT_WIDTH-1 downto 0);
        variable diff           : signed(DATA_WIDTH+1 downto 0);
        variable sat_flag       : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state          <= IDLE;
                param_idx      <= (others => '0');
                lr_reg         <= to_signed(DEFAULT_LR, DATA_WIDTH);
                weight_reg     <= (others => '0');
                gradient_reg   <= (others => '0');
                product        <= (others => '0');
                update_term    <= (others => '0');
                new_weight     <= (others => '0');
                new_weight_sat <= (others => '0');
                overflow_reg   <= '0';
                done_reg       <= '0';
                grad_clear_reg <= '0';
            else
                -- Default
                done_reg       <= '0';
                grad_clear_reg <= '0';
                
                case state is
                
                    ---------------------------------------------------------
                    -- IDLE: Wait for start
                    ---------------------------------------------------------
                    when IDLE =>
                        if clear = '1' then
                            param_idx    <= (others => '0');
                            overflow_reg <= '0';
                        elsif start = '1' then
                            param_idx    <= (others => '0');
                            overflow_reg <= '0';
                            
                            -- Latch learning rate
                            if use_default_lr = '1' then
                                lr_reg <= to_signed(DEFAULT_LR, DATA_WIDTH);
                            else
                                lr_reg <= learning_rate;
                            end if;
                            
                            state <= READ_WEIGHT;
                        end if;
                    
                    ---------------------------------------------------------
                    -- READ_WEIGHT: Read current weight
                    ---------------------------------------------------------
                    when READ_WEIGHT =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            state <= WAIT_WEIGHT;
                        end if;
                    
                    ---------------------------------------------------------
                    -- WAIT_WEIGHT: Wait for weight data
                    ---------------------------------------------------------
                    when WAIT_WEIGHT =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            weight_reg <= weight_rd_data;
                            state <= READ_GRADIENT;
                        end if;
                    
                    ---------------------------------------------------------
                    -- READ_GRADIENT: Read accumulated gradient
                    ---------------------------------------------------------
                    when READ_GRADIENT =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            state <= WAIT_GRADIENT;
                        end if;
                    
                    ---------------------------------------------------------
                    -- WAIT_GRADIENT: Wait for gradient data
                    ---------------------------------------------------------
                    when WAIT_GRADIENT =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            gradient_reg <= grad_rd_data;
                            state <= COMPUTE_UPDATE;
                        end if;
                    
                    ---------------------------------------------------------
                    -- COMPUTE_UPDATE: W_new = W_old - lr × gradient
                    -- Pipeline: multiply → round → scale → saturate → subtract → saturate
                    ---------------------------------------------------------
                    when COMPUTE_UPDATE =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Initialize saturation flag for this computation
                            sat_flag := '0';

                            -- Multiply: lr (Q2.13) × gradient (Q10.26) = Q12.39
                            -- Compute product ONCE and reuse
                            product <= lr_reg * gradient_reg;
                            rounded := lr_reg * gradient_reg;

                            -- Add rounding before shift (use precomputed ROUND_CONST)
                            if SCALE_SHIFT > 0 then
                                rounded := rounded + ROUND_CONST;
                            end if;

                            -- Scale down from Q12.39 to Q2.13 (shift right by 26)
                            scaled_product := shift_right(rounded, SCALE_SHIFT);

                            -- Saturate scaled_product to DATA_WIDTH using sign-extension check
                            -- If upper bits differ from sign bit, we have overflow
                            if scaled_product > resize(SAT_MAX, PRODUCT_WIDTH) then
                                -- Positive overflow in update term
                                update_term <= resize(SAT_MAX, DATA_WIDTH+2);
                                diff := resize(weight_reg, DATA_WIDTH+2) -
                                        resize(SAT_MAX, DATA_WIDTH+2);
                                sat_flag := '1';
                            elsif scaled_product < resize(SAT_MIN, PRODUCT_WIDTH) then
                                -- Negative overflow in update term
                                update_term <= resize(SAT_MIN, DATA_WIDTH+2);
                                diff := resize(weight_reg, DATA_WIDTH+2) -
                                        resize(SAT_MIN, DATA_WIDTH+2);
                                sat_flag := '1';
                            else
                                -- Value fits, use lower bits
                                update_term <= resize(scaled_product(DATA_WIDTH-1 downto 0), DATA_WIDTH+2);
                                diff := resize(weight_reg, DATA_WIDTH+2) -
                                        resize(scaled_product(DATA_WIDTH-1 downto 0), DATA_WIDTH+2);
                            end if;

                            new_weight <= diff;

                            -- Final saturation check on weight result
                            -- Note: sat_flag uses OR logic - overflow if either stage saturates
                            if diff > resize(SAT_MAX, DATA_WIDTH+2) then
                                new_weight_sat <= SAT_MAX;
                                sat_flag := '1';
                            elsif diff < resize(SAT_MIN, DATA_WIDTH+2) then
                                new_weight_sat <= SAT_MIN;
                                sat_flag := '1';
                            else
                                new_weight_sat <= diff(DATA_WIDTH-1 downto 0);
                            end if;

                            -- Update overflow register (sticky - once set, stays set)
                            if sat_flag = '1' then
                                overflow_reg <= '1';
                            end if;

                            state <= WRITE_WEIGHT;
                        end if;
                    
                    ---------------------------------------------------------
                    -- WRITE_WEIGHT: Write updated weight back
                    ---------------------------------------------------------
                    when WRITE_WEIGHT =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            state <= NEXT_PARAM;
                        end if;
                    
                    ---------------------------------------------------------
                    -- NEXT_PARAM: Move to next parameter
                    ---------------------------------------------------------
                    when NEXT_PARAM =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            param_idx <= param_idx + 1;
                            
                            if param_idx + 1 < NUM_PARAMS then
                                state <= READ_WEIGHT;
                            else
                                -- All parameters updated, clear gradients
                                state <= CLEAR_GRADS;
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- CLEAR_GRADS: Clear gradient accumulators
                    ---------------------------------------------------------
                    when CLEAR_GRADS =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            grad_clear_reg <= '1';
                            state <= DONE_ST;
                        end if;
                    
                    ---------------------------------------------------------
                    -- DONE: Weight update complete
                    ---------------------------------------------------------
                    when DONE_ST =>
                        done_reg <= '1';
                        if clear = '1' then
                            state <= IDLE;
                        elsif start = '1' then
                            param_idx    <= (others => '0');
                            overflow_reg <= '0';
                            
                            if use_default_lr = '1' then
                                lr_reg <= to_signed(DEFAULT_LR, DATA_WIDTH);
                            else
                                lr_reg <= learning_rate;
                            end if;
                            
                            state <= READ_WEIGHT;
                        end if;
                    
                    when others =>
                        state <= IDLE;
                        
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Weight Register Bank Interface
    ---------------------------------------------------------------------------
    weight_rd_addr <= param_idx;
    weight_rd_en   <= '1' when (state = READ_WEIGHT or state = WAIT_WEIGHT) else '0';
    
    weight_wr_addr <= param_idx;
    weight_wr_data <= new_weight_sat;
    weight_wr_en   <= '1' when state = WRITE_WEIGHT else '0';

    ---------------------------------------------------------------------------
    -- Gradient Register Bank Interface
    ---------------------------------------------------------------------------
    grad_rd_addr <= param_idx;
    grad_rd_en   <= '1' when (state = READ_GRADIENT or state = WAIT_GRADIENT) else '0';
    grad_clear   <= grad_clear_reg;

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    busy        <= '0' when (state = IDLE or state = DONE_ST) else '1';
    done        <= done_reg;
    param_count <= param_idx;
    overflow    <= overflow_reg;

end architecture rtl;
