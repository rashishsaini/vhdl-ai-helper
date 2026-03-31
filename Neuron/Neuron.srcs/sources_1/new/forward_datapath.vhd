--------------------------------------------------------------------------------
-- Module: forward_datapath
-- Description: Complete forward propagation datapath for 4-2-1 neural network
--              Computes: z = W×x + b, a = σ(z) for all layers
--
-- Network Architecture:
--   Layer 1: 4 inputs → 2 hidden neurons (8 weights + 2 biases)
--   Layer 2: 2 hidden → 1 output neuron (2 weights + 1 bias)
--
-- Memory Map (weight_register_bank):
--   Addr 0-7:   Layer 1 weights [w00,w01,w02,w03, w10,w11,w12,w13]
--   Addr 8-9:   Layer 1 biases  [b0, b1]
--   Addr 10-11: Layer 2 weights [w20, w21]
--   Addr 12:    Layer 2 bias    [b2]
--
-- Forward Cache Memory Map:
--   Z values: z_hidden[0], z_hidden[1], z_output (3 total)
--   A values: x[0-3], a_hidden[0-1], a_output (7 total)
--
-- Pipeline:
--   IDLE → LOAD_INPUT → LAYER1_NEURON0 → LAYER1_NEURON1 → 
--   LAYER2_OUTPUT → STORE_OUTPUT → DONE
--
-- Author: FPGA Neural Network Project
-- Complexity: HARD (⭐⭐⭐)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity forward_datapath is
    generic (
        DATA_WIDTH   : integer := 16;     -- Q2.13 format
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
        
        -- Input Data Interface
        input_data       : in  signed(DATA_WIDTH-1 downto 0);
        input_addr       : in  unsigned(1 downto 0);  -- 0-3 for 4 inputs
        input_valid      : in  std_logic;
        input_ready      : out std_logic;
        
        -- Weight Memory Interface (directly connected or external)
        weight_rd_data   : in  signed(DATA_WIDTH-1 downto 0);
        weight_rd_addr   : out unsigned(3 downto 0);
        weight_rd_en     : out std_logic;
        
        -- Forward Cache Write Interface (z and a values)
        cache_z_wr_en    : out std_logic;
        cache_z_wr_addr  : out unsigned(1 downto 0);
        cache_z_wr_data  : out signed(DATA_WIDTH-1 downto 0);
        cache_a_wr_en    : out std_logic;
        cache_a_wr_addr  : out unsigned(2 downto 0);
        cache_a_wr_data  : out signed(DATA_WIDTH-1 downto 0);
        
        -- Output Interface
        output_data      : out signed(DATA_WIDTH-1 downto 0);
        output_valid     : out std_logic;
        
        -- Status
        busy             : out std_logic;
        done             : out std_logic;
        layer_complete   : out std_logic;
        current_layer    : out unsigned(1 downto 0);
        overflow         : out std_logic
    );
end entity forward_datapath;

architecture rtl of forward_datapath is

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        LOAD_INPUT,           -- Load input values into local buffer
        L1_N0_ADDR,           -- Layer 1, Neuron 0: set address (pipeline wait)
        L1_NEURON0_DOT,       -- Layer 1, Neuron 0: dot product
        L1_N0_BIAS_ADDR,      -- Layer 1, Neuron 0: set bias address
        L1_NEURON0_BIAS,      -- Layer 1, Neuron 0: add bias
        L1_NEURON0_ACT,       -- Layer 1, Neuron 0: activation
        L1_N1_ADDR,           -- Layer 1, Neuron 1: set address (pipeline wait)
        L1_NEURON1_DOT,       -- Layer 1, Neuron 1: dot product
        L1_N1_BIAS_ADDR,      -- Layer 1, Neuron 1: set bias address
        L1_NEURON1_BIAS,      -- Layer 1, Neuron 1: add bias
        L1_NEURON1_ACT,       -- Layer 1, Neuron 1: activation
        L2_OUT_ADDR,          -- Layer 2, Output: set address (pipeline wait)
        L2_OUTPUT_DOT,        -- Layer 2, Output: dot product
        L2_OUT_BIAS_ADDR,     -- Layer 2, Output: set bias address
        L2_OUTPUT_BIAS,       -- Layer 2, Output: add bias
        L2_OUTPUT_ACT,        -- Layer 2, Output: activation
        STORE_OUTPUT,         -- Store final output
        DONE_ST
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    -- Weight address mapping
    constant W_L1_N0_BASE : integer := 0;   -- Layer 1, Neuron 0 weights: addr 0-3
    constant W_L1_N1_BASE : integer := 4;   -- Layer 1, Neuron 1 weights: addr 4-7
    constant B_L1_N0_ADDR : integer := 8;   -- Layer 1, Neuron 0 bias
    constant B_L1_N1_ADDR : integer := 9;   -- Layer 1, Neuron 1 bias
    constant W_L2_BASE    : integer := 10;  -- Layer 2 weights: addr 10-11
    constant B_L2_ADDR    : integer := 12;  -- Layer 2 bias

    -- Saturation bounds
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(2**(DATA_WIDTH-1)-1, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-2**(DATA_WIDTH-1), DATA_WIDTH);

    ---------------------------------------------------------------------------
    -- Internal Buffers
    ---------------------------------------------------------------------------
    -- Input buffer (4 values)
    type input_buffer_t is array (0 to NUM_INPUTS-1) of signed(DATA_WIDTH-1 downto 0);
    signal input_buffer : input_buffer_t := (others => (others => '0'));
    signal inputs_loaded : unsigned(2 downto 0) := (others => '0');
    
    -- Hidden layer activations (2 values)
    type hidden_buffer_t is array (0 to NUM_HIDDEN-1) of signed(DATA_WIDTH-1 downto 0);
    signal hidden_activations : hidden_buffer_t := (others => (others => '0'));

    ---------------------------------------------------------------------------
    -- Dot Product Computation Signals
    ---------------------------------------------------------------------------
    signal dot_accum     : signed(ACCUM_WIDTH-1 downto 0) := (others => '0');
    signal dot_count     : unsigned(2 downto 0) := (others => '0');
    signal dot_target    : unsigned(2 downto 0) := (others => '0');
    signal weight_idx    : unsigned(3 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- Pipeline Registers
    ---------------------------------------------------------------------------
    signal z_value       : signed(DATA_WIDTH-1 downto 0) := (others => '0');  -- Pre-activation
    signal a_value       : signed(DATA_WIDTH-1 downto 0) := (others => '0');  -- Post-activation
    signal bias_value    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    ---------------------------------------------------------------------------
    -- Output Registers
    ---------------------------------------------------------------------------
    signal output_reg    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal output_valid_reg : std_logic := '0';
    signal done_reg      : std_logic := '0';
    signal overflow_reg  : std_logic := '0';
    signal layer_reg     : unsigned(1 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- Helper: Rounding and saturation from accumulator to data width
    ---------------------------------------------------------------------------
    function round_saturate(acc : signed(ACCUM_WIDTH-1 downto 0)) 
        return signed is
        variable rounded : signed(ACCUM_WIDTH-1 downto 0);
        variable shifted : signed(ACCUM_WIDTH-1 downto 0);
        variable result  : signed(DATA_WIDTH-1 downto 0);
    begin
        -- Add rounding constant (0.5 LSB)
        rounded := acc + to_signed(2**(FRAC_BITS-1), ACCUM_WIDTH);
        -- Shift right by FRAC_BITS
        shifted := shift_right(rounded, FRAC_BITS);
        -- Saturate
        if shifted > resize(SAT_MAX, ACCUM_WIDTH) then
            result := SAT_MAX;
        elsif shifted < resize(SAT_MIN, ACCUM_WIDTH) then
            result := SAT_MIN;
        else
            result := shifted(DATA_WIDTH-1 downto 0);
        end if;
        return result;
    end function;

    ---------------------------------------------------------------------------
    -- Helper: ReLU activation
    ---------------------------------------------------------------------------
    function relu(x : signed(DATA_WIDTH-1 downto 0)) 
        return signed is
    begin
        if x(DATA_WIDTH-1) = '1' then
            return to_signed(0, DATA_WIDTH);
        else
            return x;
        end if;
    end function;

begin

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable product     : signed(2*DATA_WIDTH-1 downto 0);
        variable product_ext : signed(ACCUM_WIDTH-1 downto 0);
        variable sum         : signed(ACCUM_WIDTH downto 0);
        variable bias_ext    : signed(ACCUM_WIDTH-1 downto 0);
        variable input_idx   : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state              <= IDLE;
                input_buffer       <= (others => (others => '0'));
                hidden_activations <= (others => (others => '0'));
                inputs_loaded      <= (others => '0');
                dot_accum          <= (others => '0');
                dot_count          <= (others => '0');
                dot_target         <= (others => '0');
                weight_idx         <= (others => '0');
                z_value            <= (others => '0');
                a_value            <= (others => '0');
                bias_value         <= (others => '0');
                output_reg         <= (others => '0');
                output_valid_reg   <= '0';
                done_reg           <= '0';
                overflow_reg       <= '0';
                layer_reg          <= (others => '0');
            else
                -- Default assignments
                output_valid_reg <= '0';
                done_reg         <= '0';
                
                case state is
                
                    ---------------------------------------------------------
                    -- IDLE: Wait for start
                    ---------------------------------------------------------
                    when IDLE =>
                        if clear = '1' then
                            input_buffer       <= (others => (others => '0'));
                            hidden_activations <= (others => (others => '0'));
                            inputs_loaded      <= (others => '0');
                            overflow_reg       <= '0';
                        elsif start = '1' then
                            inputs_loaded <= (others => '0');
                            overflow_reg  <= '0';
                            layer_reg     <= "00";
                            state         <= LOAD_INPUT;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LOAD_INPUT: Buffer all 4 inputs
                    ---------------------------------------------------------
                    when LOAD_INPUT =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif input_valid = '1' then
                            input_idx := to_integer(input_addr);
                            if input_idx < NUM_INPUTS then
                                input_buffer(input_idx) <= input_data;
                            end if;
                            inputs_loaded <= inputs_loaded + 1;
                            
                            if inputs_loaded = to_unsigned(NUM_INPUTS-1, 3) then
                                -- All inputs loaded, start Layer 1
                                dot_accum  <= (others => '0');
                                dot_count  <= (others => '0');
                                dot_target <= to_unsigned(NUM_INPUTS, 3);
                                weight_idx <= to_unsigned(W_L1_N0_BASE, 4);
                                layer_reg  <= "01";
                                state      <= L1_N0_ADDR;  -- Go to address state first
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LAYER 1, NEURON 0: Address setup (wait for memory)
                    ---------------------------------------------------------
                    when L1_N0_ADDR =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Address weight_idx is set, wait one cycle for data
                            -- Pre-increment address for next weight
                            weight_idx <= weight_idx + 1;
                            state <= L1_NEURON0_DOT;
                        end if;

                    ---------------------------------------------------------
                    -- LAYER 1, NEURON 0: Dot Product
                    -- Note: weight_rd_data contains data for address (weight_idx - 1)
                    -- because we pre-increment in previous cycle
                    ---------------------------------------------------------
                    when L1_NEURON0_DOT =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif dot_count < dot_target then
                            -- MAC: accum += weight × input
                            -- weight_rd_data is valid for weight[dot_count]
                            product := weight_rd_data * input_buffer(to_integer(dot_count));
                            product_ext := resize(product, ACCUM_WIDTH);
                            sum := resize(dot_accum, ACCUM_WIDTH+1) + resize(product_ext, ACCUM_WIDTH+1);

                            -- Overflow check
                            if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
                                overflow_reg <= '1';
                            end if;
                            dot_accum <= sum(ACCUM_WIDTH-1 downto 0);

                            dot_count  <= dot_count + 1;
                            -- Pre-fetch next weight only if not on last element
                            if dot_count < dot_target - 1 then
                                weight_idx <= weight_idx + 1;
                            end if;
                        else
                            -- Dot product complete, move to bias address
                            weight_idx <= to_unsigned(B_L1_N0_ADDR, 4);
                            state <= L1_N0_BIAS_ADDR;
                        end if;

                    ---------------------------------------------------------
                    -- LAYER 1, NEURON 0: Bias Address setup
                    ---------------------------------------------------------
                    when L1_N0_BIAS_ADDR =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Wait for bias data
                            state <= L1_NEURON0_BIAS;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LAYER 1, NEURON 0: Add Bias
                    ---------------------------------------------------------
                    when L1_NEURON0_BIAS =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Add bias (sign-extended to accumulator width)
                            bias_ext := resize(weight_rd_data, ACCUM_WIDTH);
                            -- Scale bias from Q2.13 to Q4.26 (shift left by FRAC_BITS)
                            bias_ext := shift_left(bias_ext, FRAC_BITS);
                            sum := resize(dot_accum, ACCUM_WIDTH+1) + resize(bias_ext, ACCUM_WIDTH+1);
                            
                            if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
                                overflow_reg <= '1';
                            end if;
                            
                            -- Round and saturate to get z value
                            z_value <= round_saturate(sum(ACCUM_WIDTH-1 downto 0));
                            state <= L1_NEURON0_ACT;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LAYER 1, NEURON 0: Activation
                    ---------------------------------------------------------
                    when L1_NEURON0_ACT =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Apply ReLU activation
                            a_value <= relu(z_value);
                            hidden_activations(0) <= relu(z_value);

                            -- Setup for Neuron 1
                            dot_accum  <= (others => '0');
                            dot_count  <= (others => '0');
                            dot_target <= to_unsigned(NUM_INPUTS, 3);
                            weight_idx <= to_unsigned(W_L1_N1_BASE, 4);
                            state <= L1_N1_ADDR;  -- Go to address state first
                        end if;

                    ---------------------------------------------------------
                    -- LAYER 1, NEURON 1: Address setup (wait for memory)
                    ---------------------------------------------------------
                    when L1_N1_ADDR =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            weight_idx <= weight_idx + 1;
                            state <= L1_NEURON1_DOT;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LAYER 1, NEURON 1: Dot Product
                    ---------------------------------------------------------
                    when L1_NEURON1_DOT =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif dot_count < dot_target then
                            product := weight_rd_data * input_buffer(to_integer(dot_count));
                            product_ext := resize(product, ACCUM_WIDTH);
                            sum := resize(dot_accum, ACCUM_WIDTH+1) + resize(product_ext, ACCUM_WIDTH+1);

                            if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
                                overflow_reg <= '1';
                            end if;
                            dot_accum <= sum(ACCUM_WIDTH-1 downto 0);

                            dot_count  <= dot_count + 1;
                            if dot_count < dot_target - 1 then
                                weight_idx <= weight_idx + 1;
                            end if;
                        else
                            weight_idx <= to_unsigned(B_L1_N1_ADDR, 4);
                            state <= L1_N1_BIAS_ADDR;
                        end if;

                    ---------------------------------------------------------
                    -- LAYER 1, NEURON 1: Bias Address setup
                    ---------------------------------------------------------
                    when L1_N1_BIAS_ADDR =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            state <= L1_NEURON1_BIAS;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LAYER 1, NEURON 1: Add Bias
                    ---------------------------------------------------------
                    when L1_NEURON1_BIAS =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            bias_ext := resize(weight_rd_data, ACCUM_WIDTH);
                            bias_ext := shift_left(bias_ext, FRAC_BITS);
                            sum := resize(dot_accum, ACCUM_WIDTH+1) + resize(bias_ext, ACCUM_WIDTH+1);
                            
                            if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
                                overflow_reg <= '1';
                            end if;
                            
                            z_value <= round_saturate(sum(ACCUM_WIDTH-1 downto 0));
                            state <= L1_NEURON1_ACT;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LAYER 1, NEURON 1: Activation
                    ---------------------------------------------------------
                    when L1_NEURON1_ACT =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            a_value <= relu(z_value);
                            hidden_activations(1) <= relu(z_value);

                            -- Setup for Layer 2
                            dot_accum  <= (others => '0');
                            dot_count  <= (others => '0');
                            dot_target <= to_unsigned(NUM_HIDDEN, 3);
                            weight_idx <= to_unsigned(W_L2_BASE, 4);
                            layer_reg  <= "10";
                            state <= L2_OUT_ADDR;  -- Go to address state first
                        end if;

                    ---------------------------------------------------------
                    -- LAYER 2, OUTPUT: Address setup (wait for memory)
                    ---------------------------------------------------------
                    when L2_OUT_ADDR =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            weight_idx <= weight_idx + 1;
                            state <= L2_OUTPUT_DOT;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LAYER 2, OUTPUT: Dot Product
                    ---------------------------------------------------------
                    when L2_OUTPUT_DOT =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif dot_count < dot_target then
                            product := weight_rd_data * hidden_activations(to_integer(dot_count));
                            product_ext := resize(product, ACCUM_WIDTH);
                            sum := resize(dot_accum, ACCUM_WIDTH+1) + resize(product_ext, ACCUM_WIDTH+1);

                            if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
                                overflow_reg <= '1';
                            end if;
                            dot_accum <= sum(ACCUM_WIDTH-1 downto 0);

                            dot_count  <= dot_count + 1;
                            if dot_count < dot_target - 1 then
                                weight_idx <= weight_idx + 1;
                            end if;
                        else
                            weight_idx <= to_unsigned(B_L2_ADDR, 4);
                            state <= L2_OUT_BIAS_ADDR;
                        end if;

                    ---------------------------------------------------------
                    -- LAYER 2, OUTPUT: Bias Address setup
                    ---------------------------------------------------------
                    when L2_OUT_BIAS_ADDR =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            state <= L2_OUTPUT_BIAS;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LAYER 2, OUTPUT: Add Bias
                    ---------------------------------------------------------
                    when L2_OUTPUT_BIAS =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            bias_ext := resize(weight_rd_data, ACCUM_WIDTH);
                            bias_ext := shift_left(bias_ext, FRAC_BITS);
                            sum := resize(dot_accum, ACCUM_WIDTH+1) + resize(bias_ext, ACCUM_WIDTH+1);
                            
                            if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
                                overflow_reg <= '1';
                            end if;
                            
                            z_value <= round_saturate(sum(ACCUM_WIDTH-1 downto 0));
                            state <= L2_OUTPUT_ACT;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LAYER 2, OUTPUT: Activation
                    ---------------------------------------------------------
                    when L2_OUTPUT_ACT =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Output layer uses ReLU as well (can be changed)
                            a_value <= relu(z_value);
                            state <= STORE_OUTPUT;
                        end if;
                    
                    ---------------------------------------------------------
                    -- STORE_OUTPUT: Finalize output
                    ---------------------------------------------------------
                    when STORE_OUTPUT =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            output_reg       <= a_value;
                            output_valid_reg <= '1';
                            state <= DONE_ST;
                        end if;
                    
                    ---------------------------------------------------------
                    -- DONE: Forward pass complete
                    ---------------------------------------------------------
                    when DONE_ST =>
                        done_reg <= '1';
                        if clear = '1' then
                            state <= IDLE;
                        elsif start = '1' then
                            -- Allow restart
                            inputs_loaded <= (others => '0');
                            overflow_reg  <= '0';
                            layer_reg     <= "00";
                            state         <= LOAD_INPUT;
                        end if;
                    
                    when others =>
                        state <= IDLE;
                        
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Weight Memory Interface
    ---------------------------------------------------------------------------
    weight_rd_addr <= weight_idx;
    weight_rd_en   <= '1' when (state = L1_N0_ADDR or state = L1_NEURON0_DOT or
                                state = L1_N0_BIAS_ADDR or state = L1_NEURON0_BIAS or
                                state = L1_N1_ADDR or state = L1_NEURON1_DOT or
                                state = L1_N1_BIAS_ADDR or state = L1_NEURON1_BIAS or
                                state = L2_OUT_ADDR or state = L2_OUTPUT_DOT or
                                state = L2_OUT_BIAS_ADDR or state = L2_OUTPUT_BIAS) else '0';

    ---------------------------------------------------------------------------
    -- Forward Cache Write Interface
    -- Z values: 0=z_hidden[0], 1=z_hidden[1], 2=z_output
    -- A values: 0-3=inputs, 4-5=hidden, 6=output
    ---------------------------------------------------------------------------
    cache_z_wr_en   <= '1' when (state = L1_NEURON0_ACT or state = L1_NEURON1_ACT or 
                                 state = L2_OUTPUT_ACT) else '0';
    cache_z_wr_addr <= "00" when state = L1_NEURON0_ACT else
                       "01" when state = L1_NEURON1_ACT else
                       "10";
    cache_z_wr_data <= z_value;
    
    cache_a_wr_en   <= '1' when (state = L1_NEURON0_ACT or state = L1_NEURON1_ACT or 
                                 state = STORE_OUTPUT) else '0';
    cache_a_wr_addr <= "100" when state = L1_NEURON0_ACT else  -- addr 4
                       "101" when state = L1_NEURON1_ACT else  -- addr 5
                       "110";                                   -- addr 6
    cache_a_wr_data <= a_value;

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    output_data    <= output_reg;
    output_valid   <= output_valid_reg;
    input_ready    <= '1' when state = LOAD_INPUT else '0';
    busy           <= '0' when state = IDLE or state = DONE_ST else '1';
    done           <= done_reg;
    layer_complete <= '1' when (state = L1_NEURON1_ACT or state = DONE_ST) else '0';
    current_layer  <= layer_reg;
    overflow       <= overflow_reg;

end architecture rtl;
