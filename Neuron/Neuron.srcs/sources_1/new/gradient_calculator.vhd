--------------------------------------------------------------------------------
-- Module: gradient_calculator
-- Description: Computes weight gradients for backpropagation
--              ∂L/∂W[i,j] = δ[j] × a[i]
--              where δ is the delta (error signal) and a is the activation
--
-- Features:
--   - Computes gradients for all weights in a layer
--   - Sequentially processes delta × activation pairs
--   - Accumulates gradients across mini-batch (optional)
--   - Outputs gradients one at a time
--
-- For 4-2-1 Network Layer 1 (4 inputs → 2 neurons):
--   - 8 weight gradients (4 × 2)
--   - 2 bias gradients
--   - For each hidden neuron j: ∂L/∂W[i,j] = δ[j] × x[i]
--
-- Format: Q2.13 input (16-bit), Q4.26 product (32-bit)
--
-- Operation:
--   1. Receive delta value for current neuron
--   2. Sequentially receive activation values
--   3. Compute and output gradients: grad = delta × activation
--
-- Author: FPGA Neural Network Project
-- Complexity: MEDIUM (⭐⭐)
-- Dependencies: None (self-contained multiply logic)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity gradient_calculator is
    generic (
        DATA_WIDTH    : integer := 16;    -- Input width (Q2.13)
        PRODUCT_WIDTH : integer := 32;    -- Gradient width (Q4.26)
        FRAC_BITS     : integer := 13;    -- Fractional bits
        MAX_INPUTS    : integer := 8      -- Maximum inputs per neuron
    );
    port (
        -- Clock and Reset
        clk           : in  std_logic;
        rst           : in  std_logic;
        
        -- Control Interface
        start         : in  std_logic;    -- Start gradient computation
        clear         : in  std_logic;    -- Clear state
        num_inputs    : in  unsigned(7 downto 0);  -- Number of input activations
        
        -- Delta Input (error signal for current neuron)
        delta_in      : in  signed(DATA_WIDTH-1 downto 0);
        delta_valid   : in  std_logic;
        delta_ready   : out std_logic;
        
        -- Activation Input (from forward pass cache)
        activation_in : in  signed(DATA_WIDTH-1 downto 0);
        act_valid     : in  std_logic;
        act_ready     : out std_logic;
        
        -- Gradient Output
        gradient_out  : out signed(PRODUCT_WIDTH-1 downto 0);
        grad_valid    : out std_logic;
        grad_ready    : in  std_logic;
        grad_index    : out unsigned(7 downto 0);  -- Which weight this gradient is for
        
        -- Bias Gradient Output (δ itself is the bias gradient)
        bias_grad_out : out signed(DATA_WIDTH-1 downto 0);
        bias_valid    : out std_logic;
        
        -- Status
        busy          : out std_logic;
        done          : out std_logic;
        grad_count    : out unsigned(7 downto 0)   -- Number of gradients computed
    );
end entity gradient_calculator;

architecture rtl of gradient_calculator is

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,           -- Waiting for start
        LOAD_DELTA,     -- Load delta value
        COMPUTE_GRAD,   -- Compute gradients: grad = delta × activation
        OUTPUT_GRAD,    -- Output current gradient
        DONE_ST         -- All gradients computed
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Internal Registers
    ---------------------------------------------------------------------------
    signal delta_reg      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal num_inputs_reg : unsigned(7 downto 0) := (others => '0');
    signal input_count    : unsigned(7 downto 0) := (others => '0');
    signal gradient_reg   : signed(PRODUCT_WIDTH-1 downto 0) := (others => '0');
    signal grad_idx_reg   : unsigned(7 downto 0) := (others => '0');

begin

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable product : signed(PRODUCT_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state         <= IDLE;
                delta_reg     <= (others => '0');
                num_inputs_reg<= (others => '0');
                input_count   <= (others => '0');
                gradient_reg  <= (others => '0');
                grad_idx_reg  <= (others => '0');
            else
                case state is
                    
                    ---------------------------------------------------------
                    -- IDLE: Wait for start
                    ---------------------------------------------------------
                    when IDLE =>
                        if clear = '1' then
                            delta_reg     <= (others => '0');
                            input_count   <= (others => '0');
                            gradient_reg  <= (others => '0');
                            grad_idx_reg  <= (others => '0');
                        elsif start = '1' then
                            num_inputs_reg <= num_inputs;
                            input_count    <= (others => '0');
                            grad_idx_reg   <= (others => '0');
                            
                            if num_inputs = 0 then
                                -- No inputs: go directly to done
                                state <= DONE_ST;
                            else
                                state <= LOAD_DELTA;
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LOAD_DELTA: Capture the delta value
                    ---------------------------------------------------------
                    when LOAD_DELTA =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif delta_valid = '1' then
                            delta_reg <= delta_in;
                            state <= COMPUTE_GRAD;
                        end if;
                    
                    ---------------------------------------------------------
                    -- COMPUTE_GRAD: Compute gradient = delta × activation
                    ---------------------------------------------------------
                    when COMPUTE_GRAD =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif act_valid = '1' then
                            -- Compute: Q2.13 × Q2.13 = Q4.26
                            product := delta_reg * activation_in;
                            gradient_reg <= product;
                            grad_idx_reg <= input_count;
                            state <= OUTPUT_GRAD;
                        end if;
                    
                    ---------------------------------------------------------
                    -- OUTPUT_GRAD: Wait for gradient to be accepted
                    ---------------------------------------------------------
                    when OUTPUT_GRAD =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif grad_ready = '1' then
                            input_count <= input_count + 1;
                            
                            -- Check if more gradients to compute
                            if input_count + 1 = num_inputs_reg then
                                state <= DONE_ST;
                            else
                                state <= COMPUTE_GRAD;
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- DONE_ST: All gradients computed
                    ---------------------------------------------------------
                    when DONE_ST =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif grad_ready = '1' then
                            -- Allow return to IDLE after done acknowledged
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
    gradient_out  <= gradient_reg;
    grad_valid    <= '1' when state = OUTPUT_GRAD else '0';
    grad_index    <= grad_idx_reg;
    
    delta_ready   <= '1' when state = LOAD_DELTA else '0';
    act_ready     <= '1' when state = COMPUTE_GRAD else '0';
    
    -- Bias gradient is simply delta (∂L/∂b = δ)
    bias_grad_out <= delta_reg;
    bias_valid    <= '1' when state = DONE_ST else '0';
    
    busy          <= '0' when state = IDLE else '1';
    done          <= '1' when state = DONE_ST else '0';
    grad_count    <= input_count;

end architecture rtl;
