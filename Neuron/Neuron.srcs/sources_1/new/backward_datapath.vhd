--------------------------------------------------------------------------------
-- Module: backward_datapath
-- Description: Complete backward propagation datapath for 4-2-1 neural network
--              Computes deltas and gradients for all layers
--
-- Backpropagation Flow:
--   1. Output layer: δ_out = (target - actual) × σ'(z_out)
--   2. Hidden layer: δ_hidden = (W_L2^T × δ_out) × σ'(z_hidden)
--   3. Gradients: ∂L/∂W = δ × a^T (outer product)
--
-- Network Architecture:
--   Layer 1: 4 inputs → 2 hidden neurons (8 weight grads + 2 bias grads)
--   Layer 2: 2 hidden → 1 output neuron (2 weight grads + 1 bias grad)
--
-- Gradient Memory Map (matches weight_register_bank):
--   Addr 0-7:   Layer 1 weight gradients
--   Addr 8-9:   Layer 1 bias gradients
--   Addr 10-11: Layer 2 weight gradients
--   Addr 12:    Layer 2 bias gradient
--
-- Forward Cache Read:
--   Z values: z_hidden[0], z_hidden[1], z_output
--   A values: x[0-3], a_hidden[0-1], a_output
--
-- Pipeline:
--   IDLE → COMPUTE_OUTPUT_ERROR → COMPUTE_OUTPUT_DELTA → 
--   COMPUTE_L2_GRADS → PROPAGATE_ERROR → COMPUTE_HIDDEN_DELTAS →
--   COMPUTE_L1_GRADS → DONE
--
-- Author: FPGA Neural Network Project
-- Complexity: HARD (⭐⭐⭐)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity backward_datapath is
    generic (
        DATA_WIDTH   : integer := 16;     -- Q2.13 format
        GRAD_WIDTH   : integer := 32;     -- Q4.26 gradient
        ACCUM_WIDTH  : integer := 40;     -- Q10.26 accumulator
        FRAC_BITS    : integer := 13;     -- Fractional bits
        NUM_INPUTS   : integer := 4;      -- Input layer size
        NUM_HIDDEN   : integer := 2;      -- Hidden layer size
        NUM_OUTPUTS  : integer := 1       -- Output layer size
    );
    port (
        -- Clock and Reset
        clk              : in  std_logic;
        rst              : in  std_logic;
        
        -- Control Interface
        start            : in  std_logic;
        clear            : in  std_logic;
        
        -- Target Value (for output error computation)
        target_in        : in  signed(DATA_WIDTH-1 downto 0);
        target_valid     : in  std_logic;
        
        -- Actual Output (from forward pass)
        actual_in        : in  signed(DATA_WIDTH-1 downto 0);
        
        -- Weight Memory Read Interface (for error propagation)
        weight_rd_data   : in  signed(DATA_WIDTH-1 downto 0);
        weight_rd_addr   : out unsigned(3 downto 0);
        weight_rd_en     : out std_logic;
        
        -- Forward Cache Read Interface
        cache_z_rd_data  : in  signed(DATA_WIDTH-1 downto 0);
        cache_z_rd_addr  : out unsigned(1 downto 0);
        cache_z_rd_en    : out std_logic;
        cache_a_rd_data  : in  signed(DATA_WIDTH-1 downto 0);
        cache_a_rd_addr  : out unsigned(2 downto 0);
        cache_a_rd_en    : out std_logic;
        
        -- Gradient Output Interface (to gradient_register_bank)
        grad_out         : out signed(GRAD_WIDTH-1 downto 0);
        grad_addr        : out unsigned(3 downto 0);
        grad_valid       : out std_logic;
        grad_ready       : in  std_logic;
        
        -- Status
        busy             : out std_logic;
        done             : out std_logic;
        current_layer    : out unsigned(1 downto 0);
        overflow         : out std_logic
    );
end entity backward_datapath;

architecture rtl of backward_datapath is

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        LOAD_TARGET,              -- Load target value
        COMPUTE_OUTPUT_ERROR,     -- err = target - actual
        LOAD_Z_OUTPUT,            -- Load z_output for delta
        WAIT_Z_OUTPUT,            -- Wait for z cache read latency
        COMPUTE_OUTPUT_DELTA,     -- δ_out = err × σ'(z_out)
        LOAD_A_HIDDEN,            -- Load activation for L2 gradient
        WAIT_A_HIDDEN,            -- Wait for a cache read latency
        COMPUTE_L2_WEIGHT_GRAD,   -- ∂L/∂W_L2 = δ_out × a_hidden
        COMPUTE_L2_BIAS_GRAD,     -- ∂L/∂b_L2 = δ_out
        LOAD_HIDDEN_Z,            -- Load z_hidden for delta computation
        WAIT_HIDDEN_Z,            -- Wait for z cache read latency
        LOAD_WEIGHT,              -- Load weight for error propagation
        WAIT_WEIGHT,              -- Wait for weight read latency
        PROPAGATE_ERROR,          -- Compute weighted error sum for hidden
        COMPUTE_HIDDEN_DELTA,     -- δ_hidden = prop_err × σ'(z_hidden)
        LOAD_INPUT_A,             -- Load input activation for L1 gradient
        WAIT_INPUT_A,             -- Wait for a cache read latency
        COMPUTE_L1_WEIGHT_GRAD,   -- ∂L/∂W_L1 = δ_hidden × x
        COMPUTE_L1_BIAS_GRAD,     -- ∂L/∂b_L1 = δ_hidden
        DONE_ST
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    -- Weight addresses for Layer 2 (for error propagation)
    constant W_L2_N0_ADDR : integer := 10;  -- Weight from hidden[0] to output
    constant W_L2_N1_ADDR : integer := 11;  -- Weight from hidden[1] to output

    -- Gradient addresses
    constant GRAD_L1_W_BASE : integer := 0;   -- Layer 1 weight grads: addr 0-7
    constant GRAD_L1_B_BASE : integer := 8;   -- Layer 1 bias grads: addr 8-9
    constant GRAD_L2_W_BASE : integer := 10;  -- Layer 2 weight grads: addr 10-11
    constant GRAD_L2_B_ADDR : integer := 12;  -- Layer 2 bias grad

    -- Cache address constants (eliminates magic numbers)
    constant Z_OUTPUT_ADDR   : unsigned(1 downto 0) := "10";  -- z_output at addr 2
    constant A_HIDDEN_BASE   : unsigned(2 downto 0) := "100"; -- a_hidden starts at addr 4

    -- Layer encoding constants
    constant LAYER_OUTPUT : unsigned(1 downto 0) := "10";
    constant LAYER_HIDDEN : unsigned(1 downto 0) := "01";

    -- Saturation bounds
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(2**(DATA_WIDTH-1)-1, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-2**(DATA_WIDTH-1), DATA_WIDTH);
    constant ONE_Q213 : signed(DATA_WIDTH-1 downto 0) := to_signed(2**FRAC_BITS, DATA_WIDTH);
    constant ZERO_Q213 : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- Internal Registers
    ---------------------------------------------------------------------------
    signal target_reg     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal actual_reg     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal error_reg      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Delta values
    signal delta_output   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal delta_hidden   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Z values from forward cache
    signal z_output_reg   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal z_hidden_reg   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Propagated error accumulator
    signal prop_error_accum : signed(ACCUM_WIDTH-1 downto 0) := (others => '0');
    
    -- Gradient computation
    signal grad_reg       : signed(GRAD_WIDTH-1 downto 0) := (others => '0');
    signal grad_addr_reg  : unsigned(3 downto 0) := (others => '0');
    signal grad_valid_reg : std_logic := '0';
    
    -- Counters
    signal weight_idx     : unsigned(2 downto 0) := (others => '0');
    signal hidden_idx     : unsigned(1 downto 0) := (others => '0');
    signal input_idx      : unsigned(2 downto 0) := (others => '0');

    -- Cached activation value for gradient computation
    signal cached_a       : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    -- Status
    signal layer_reg      : unsigned(1 downto 0) := (others => '0');
    signal overflow_reg   : std_logic := '0';
    signal done_reg       : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    -- ReLU derivative: 1 if z > 0, else 0
    function relu_derivative(z : signed(DATA_WIDTH-1 downto 0)) 
        return signed is
    begin
        if z > 0 then
            return ONE_Q213;
        else
            return ZERO_Q213;
        end if;
    end function;

begin

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable diff        : signed(DATA_WIDTH downto 0);
        variable product     : signed(2*DATA_WIDTH-1 downto 0);
        variable product_ext : signed(ACCUM_WIDTH-1 downto 0);
        variable sum         : signed(ACCUM_WIDTH downto 0);
        variable scaled      : signed(DATA_WIDTH-1 downto 0);
        variable deriv       : signed(DATA_WIDTH-1 downto 0);
        variable delta_prod  : signed(2*DATA_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state           <= IDLE;
                target_reg      <= (others => '0');
                actual_reg      <= (others => '0');
                error_reg       <= (others => '0');
                delta_output    <= (others => '0');
                delta_hidden    <= (others => '0');
                z_output_reg    <= (others => '0');
                z_hidden_reg    <= (others => '0');
                prop_error_accum <= (others => '0');
                grad_reg        <= (others => '0');
                grad_addr_reg   <= (others => '0');
                grad_valid_reg  <= '0';
                weight_idx      <= (others => '0');
                hidden_idx      <= (others => '0');
                input_idx       <= (others => '0');
                layer_reg       <= (others => '0');
                overflow_reg    <= '0';
                done_reg        <= '0';
            else
                -- Default
                grad_valid_reg <= '0';
                done_reg       <= '0';
                
                case state is
                
                    ---------------------------------------------------------
                    -- IDLE: Wait for start
                    ---------------------------------------------------------
                    when IDLE =>
                        if clear = '1' then
                            error_reg    <= (others => '0');
                            delta_output <= (others => '0');
                            delta_hidden <= (others => '0');
                            overflow_reg <= '0';
                        elsif start = '1' then
                            actual_reg   <= actual_in;
                            overflow_reg <= '0';
                            layer_reg    <= LAYER_OUTPUT;  -- Start with output layer
                            state        <= LOAD_TARGET;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LOAD_TARGET: Wait for target value
                    ---------------------------------------------------------
                    when LOAD_TARGET =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif target_valid = '1' then
                            target_reg <= target_in;
                            state <= COMPUTE_OUTPUT_ERROR;
                        end if;
                    
                    ---------------------------------------------------------
                    -- COMPUTE_OUTPUT_ERROR: err = target - actual
                    ---------------------------------------------------------
                    when COMPUTE_OUTPUT_ERROR =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            diff := resize(target_reg, DATA_WIDTH+1) - resize(actual_reg, DATA_WIDTH+1);
                            
                            -- Saturate error
                            if diff > resize(SAT_MAX, DATA_WIDTH+1) then
                                error_reg <= SAT_MAX;
                                overflow_reg <= '1';
                            elsif diff < resize(SAT_MIN, DATA_WIDTH+1) then
                                error_reg <= SAT_MIN;
                                overflow_reg <= '1';
                            else
                                error_reg <= diff(DATA_WIDTH-1 downto 0);
                            end if;
                            
                            state <= LOAD_Z_OUTPUT;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LOAD_Z_OUTPUT: Set address for z_output cache read
                    ---------------------------------------------------------
                    when LOAD_Z_OUTPUT =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Address is set combinationally, wait 1 cycle for data
                            state <= WAIT_Z_OUTPUT;
                        end if;

                    ---------------------------------------------------------
                    -- WAIT_Z_OUTPUT: Wait for cache read latency
                    ---------------------------------------------------------
                    when WAIT_Z_OUTPUT =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            z_output_reg <= cache_z_rd_data;
                            state <= COMPUTE_OUTPUT_DELTA;
                        end if;
                    
                    ---------------------------------------------------------
                    -- COMPUTE_OUTPUT_DELTA: δ_out = err × σ'(z_out)
                    ---------------------------------------------------------
                    when COMPUTE_OUTPUT_DELTA =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Get activation derivative
                            deriv := relu_derivative(z_output_reg);

                            -- δ = error × derivative
                            -- Q2.13 × Q2.13 = Q4.26, then shift back
                            delta_prod := error_reg * deriv;
                            scaled := delta_prod(DATA_WIDTH+FRAC_BITS-1 downto FRAC_BITS);
                            delta_output <= scaled;

                            -- Start Layer 2 gradient computation
                            hidden_idx <= (others => '0');
                            state <= LOAD_A_HIDDEN;
                        end if;

                    ---------------------------------------------------------
                    -- LOAD_A_HIDDEN: Set address for hidden activation read
                    ---------------------------------------------------------
                    when LOAD_A_HIDDEN =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Address is set combinationally, wait 1 cycle for data
                            state <= WAIT_A_HIDDEN;
                        end if;

                    ---------------------------------------------------------
                    -- WAIT_A_HIDDEN: Wait for cache read latency
                    ---------------------------------------------------------
                    when WAIT_A_HIDDEN =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            cached_a <= cache_a_rd_data;
                            state <= COMPUTE_L2_WEIGHT_GRAD;
                        end if;
                    
                    ---------------------------------------------------------
                    -- COMPUTE_L2_WEIGHT_GRAD: ∂L/∂W_L2[i] = δ_out × a_hidden[i]
                    ---------------------------------------------------------
                    when COMPUTE_L2_WEIGHT_GRAD =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif hidden_idx < NUM_HIDDEN then
                            -- Compute gradient using cached activation value
                            -- Only compute when valid is not already asserted (proper handshaking)
                            if grad_valid_reg = '0' then
                                product := delta_output * cached_a;
                                grad_reg <= product;
                                grad_addr_reg <= to_unsigned(GRAD_L2_W_BASE + to_integer(hidden_idx), 4);
                                grad_valid_reg <= '1';
                            end if;

                            if grad_ready = '1' and grad_valid_reg = '1' then
                                grad_valid_reg <= '0';
                                hidden_idx <= hidden_idx + 1;
                                if hidden_idx + 1 < NUM_HIDDEN then
                                    -- More hidden neurons - load next activation
                                    state <= LOAD_A_HIDDEN;
                                else
                                    -- Done with L2 weight grads
                                    state <= COMPUTE_L2_BIAS_GRAD;
                                end if;
                            end if;
                        else
                            state <= COMPUTE_L2_BIAS_GRAD;
                        end if;
                    
                    ---------------------------------------------------------
                    -- COMPUTE_L2_BIAS_GRAD: ∂L/∂b_L2 = δ_out
                    ---------------------------------------------------------
                    when COMPUTE_L2_BIAS_GRAD =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Only compute when valid is not already asserted (proper handshaking)
                            if grad_valid_reg = '0' then
                                -- Bias gradient is delta shifted to Q4.26 format for consistency
                                grad_reg <= shift_left(resize(delta_output, GRAD_WIDTH), FRAC_BITS);
                                grad_addr_reg <= to_unsigned(GRAD_L2_B_ADDR, 4);
                                grad_valid_reg <= '1';
                            end if;

                            if grad_ready = '1' and grad_valid_reg = '1' then
                                grad_valid_reg <= '0';
                                -- Setup for error propagation to hidden layer
                                hidden_idx <= (others => '0');
                                prop_error_accum <= (others => '0');
                                layer_reg <= LAYER_HIDDEN;
                                state <= LOAD_HIDDEN_Z;
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LOAD_HIDDEN_Z: Set address for z_hidden cache read
                    ---------------------------------------------------------
                    when LOAD_HIDDEN_Z =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            prop_error_accum <= (others => '0');
                            state <= WAIT_HIDDEN_Z;
                        end if;

                    ---------------------------------------------------------
                    -- WAIT_HIDDEN_Z: Wait for z cache read latency
                    ---------------------------------------------------------
                    when WAIT_HIDDEN_Z =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            z_hidden_reg <= cache_z_rd_data;
                            state <= LOAD_WEIGHT;
                        end if;

                    ---------------------------------------------------------
                    -- LOAD_WEIGHT: Set address for weight read
                    ---------------------------------------------------------
                    when LOAD_WEIGHT =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Address is set combinationally, wait 1 cycle for data
                            state <= WAIT_WEIGHT;
                        end if;

                    ---------------------------------------------------------
                    -- WAIT_WEIGHT: Wait for weight read latency
                    ---------------------------------------------------------
                    when WAIT_WEIGHT =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            state <= PROPAGATE_ERROR;
                        end if;

                    ---------------------------------------------------------
                    -- PROPAGATE_ERROR: δ_hidden[i] weighted sum
                    -- prop_err = W_L2[i] × δ_out
                    ---------------------------------------------------------
                    when PROPAGATE_ERROR =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- For 4-2-1 network, each hidden neuron connects to
                            -- output with one weight. prop_err = W × δ_out
                            product := weight_rd_data * delta_output;
                            product_ext := resize(product, ACCUM_WIDTH);
                            prop_error_accum <= product_ext;

                            state <= COMPUTE_HIDDEN_DELTA;
                        end if;
                    
                    ---------------------------------------------------------
                    -- COMPUTE_HIDDEN_DELTA: δ_hidden = prop_err × σ'(z)
                    ---------------------------------------------------------
                    when COMPUTE_HIDDEN_DELTA =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Scale accumulated error back to Q2.13
                            scaled := prop_error_accum(DATA_WIDTH+FRAC_BITS-1 downto FRAC_BITS);

                            -- Apply activation derivative
                            deriv := relu_derivative(z_hidden_reg);
                            delta_prod := scaled * deriv;
                            delta_hidden <= delta_prod(DATA_WIDTH+FRAC_BITS-1 downto FRAC_BITS);

                            -- Start Layer 1 gradient computation for this hidden neuron
                            input_idx <= (others => '0');
                            state <= LOAD_INPUT_A;
                        end if;

                    ---------------------------------------------------------
                    -- LOAD_INPUT_A: Set address for input activation read
                    ---------------------------------------------------------
                    when LOAD_INPUT_A =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Address is set combinationally, wait 1 cycle for data
                            state <= WAIT_INPUT_A;
                        end if;

                    ---------------------------------------------------------
                    -- WAIT_INPUT_A: Wait for cache read latency
                    ---------------------------------------------------------
                    when WAIT_INPUT_A =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            cached_a <= cache_a_rd_data;
                            state <= COMPUTE_L1_WEIGHT_GRAD;
                        end if;
                    
                    ---------------------------------------------------------
                    -- COMPUTE_L1_WEIGHT_GRAD: ∂L/∂W_L1[i,j] = δ_hidden[j] × x[i]
                    ---------------------------------------------------------
                    when COMPUTE_L1_WEIGHT_GRAD =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif input_idx < NUM_INPUTS then
                            -- Compute gradient using cached activation value
                            -- Only compute when valid is not already asserted (proper handshaking)
                            if grad_valid_reg = '0' then
                                product := delta_hidden * cached_a;
                                grad_reg <= product;
                                -- Address: base + hidden_idx*NUM_INPUTS + input_idx
                                grad_addr_reg <= to_unsigned(GRAD_L1_W_BASE +
                                                 to_integer(hidden_idx)*NUM_INPUTS +
                                                 to_integer(input_idx), 4);
                                grad_valid_reg <= '1';
                            end if;

                            if grad_ready = '1' and grad_valid_reg = '1' then
                                grad_valid_reg <= '0';
                                input_idx <= input_idx + 1;
                                if input_idx + 1 < NUM_INPUTS then
                                    -- More inputs - load next activation
                                    state <= LOAD_INPUT_A;
                                else
                                    -- Done with L1 weight grads for this hidden neuron
                                    state <= COMPUTE_L1_BIAS_GRAD;
                                end if;
                            end if;
                        else
                            state <= COMPUTE_L1_BIAS_GRAD;
                        end if;
                    
                    ---------------------------------------------------------
                    -- COMPUTE_L1_BIAS_GRAD: ∂L/∂b_L1[j] = δ_hidden[j]
                    ---------------------------------------------------------
                    when COMPUTE_L1_BIAS_GRAD =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Only compute when valid is not already asserted (proper handshaking)
                            if grad_valid_reg = '0' then
                                -- Bias gradient is delta shifted to Q4.26 format for consistency
                                grad_reg <= shift_left(resize(delta_hidden, GRAD_WIDTH), FRAC_BITS);
                                grad_addr_reg <= to_unsigned(GRAD_L1_B_BASE + to_integer(hidden_idx), 4);
                                grad_valid_reg <= '1';
                            end if;

                            if grad_ready = '1' and grad_valid_reg = '1' then
                                grad_valid_reg <= '0';
                                hidden_idx <= hidden_idx + 1;

                                if hidden_idx + 1 < NUM_HIDDEN then
                                    -- More hidden neurons to process
                                    state <= LOAD_HIDDEN_Z;
                                else
                                    -- All done
                                    state <= DONE_ST;
                                end if;
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- DONE: Backward pass complete
                    ---------------------------------------------------------
                    when DONE_ST =>
                        done_reg <= '1';
                        if clear = '1' then
                            state <= IDLE;
                        elsif start = '1' then
                            actual_reg   <= actual_in;
                            overflow_reg <= '0';
                            layer_reg    <= LAYER_OUTPUT;
                            state        <= LOAD_TARGET;
                        end if;
                    
                    when others =>
                        state <= IDLE;
                        
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Memory Read Address Generation
    ---------------------------------------------------------------------------
    -- Weight read for error propagation (set address 1 cycle before use)
    weight_rd_addr <= to_unsigned(W_L2_N0_ADDR + to_integer(hidden_idx), 4)
                      when (state = LOAD_WEIGHT or state = WAIT_WEIGHT or state = PROPAGATE_ERROR) else (others => '0');
    weight_rd_en   <= '1' when (state = LOAD_WEIGHT or state = WAIT_WEIGHT) else '0';

    -- Z cache read (set address 1 cycle before use)
    cache_z_rd_addr <= Z_OUTPUT_ADDR when (state = LOAD_Z_OUTPUT or state = WAIT_Z_OUTPUT) else
                       hidden_idx;   -- z_hidden[0] or z_hidden[1]
    cache_z_rd_en   <= '1' when (state = LOAD_Z_OUTPUT or state = LOAD_HIDDEN_Z) else '0';

    -- A cache read (set address 1 cycle before use)
    cache_a_rd_addr <= A_HIDDEN_BASE + resize(hidden_idx, 3) when (state = LOAD_A_HIDDEN or state = WAIT_A_HIDDEN) else
                       resize(input_idx, 3);  -- x inputs (addr 0-3)
    cache_a_rd_en   <= '1' when (state = LOAD_A_HIDDEN or state = LOAD_INPUT_A) else '0';

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    grad_out      <= grad_reg;
    grad_addr     <= grad_addr_reg;
    grad_valid    <= grad_valid_reg;
    
    busy          <= '0' when (state = IDLE or state = DONE_ST) else '1';
    done          <= done_reg;
    current_layer <= layer_reg;
    overflow      <= overflow_reg;

end architecture rtl;
