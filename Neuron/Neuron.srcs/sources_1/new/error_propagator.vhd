--------------------------------------------------------------------------------
-- Module: error_propagator
-- Description: Backpropagates error signals through neural network layers
--              δ[l-1] = (W[l]^T × δ[l]) ⊙ σ'(z[l-1])
--
-- For a neuron in layer l-1:
--   δ[l-1,i] = Σ(W[l,i,j] × δ[l,j]) × σ'(z[l-1,i])
--              j
--
-- Features:
--   - Computes weighted sum of deltas from next layer
--   - Applies activation derivative element-wise
--   - Supports variable layer sizes
--   - Outputs propagated delta for each neuron
--
-- For 4-2-1 Network (propagating from output to hidden):
--   - 1 output delta → 2 hidden deltas
--   - Each hidden neuron receives: W_out[i] × δ_out × σ'(z_hidden[i])
--
-- Format: Q2.13 input/output (16-bit), Q10.26 accumulator (40-bit)
--
-- Operation Sequence:
--   1. Start with num_neurons (neurons in current layer) and num_deltas (from next)
--   2. For each neuron: 
--      a. Receive weights and deltas, compute weighted sum
--      b. Multiply by activation derivative
--      c. Output propagated delta
--
-- Author: FPGA Neural Network Project
-- Complexity: HARD (⭐⭐⭐)
-- Dependencies: None (self-contained)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity error_propagator is
    generic (
        DATA_WIDTH   : integer := 16;     -- Input width (Q2.13)
        ACCUM_WIDTH  : integer := 40;     -- Accumulator width (Q10.26)
        FRAC_BITS    : integer := 13;     -- Fractional bits
        MAX_NEURONS  : integer := 8;      -- Max neurons in target layer
        MAX_DELTAS   : integer := 8       -- Max deltas from source layer
    );
    port (
        -- Clock and Reset
        clk            : in  std_logic;
        rst            : in  std_logic;
        
        -- Control Interface
        start          : in  std_logic;
        clear          : in  std_logic;
        num_neurons    : in  unsigned(7 downto 0);  -- Neurons in target layer
        num_deltas     : in  unsigned(7 downto 0);  -- Deltas from source layer
        
        -- Weight Input (W[l,i,j] - weights from neuron i to neuron j)
        weight_in      : in  signed(DATA_WIDTH-1 downto 0);
        weight_valid   : in  std_logic;
        weight_ready   : out std_logic;
        
        -- Delta Input (from next layer)
        delta_in       : in  signed(DATA_WIDTH-1 downto 0);
        delta_valid    : in  std_logic;
        delta_ready    : out std_logic;
        
        -- Pre-activation Input (z values for derivative computation)
        z_in           : in  signed(DATA_WIDTH-1 downto 0);
        z_valid        : in  std_logic;
        z_ready        : out std_logic;
        
        -- Propagated Delta Output
        delta_out      : out signed(DATA_WIDTH-1 downto 0);
        delta_out_valid: out std_logic;
        delta_out_ready: in  std_logic;
        neuron_index   : out unsigned(7 downto 0);  -- Which neuron this delta is for
        
        -- Status
        busy           : out std_logic;
        done           : out std_logic;
        overflow       : out std_logic
    );
end entity error_propagator;

architecture rtl of error_propagator is

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,           -- Waiting for start
        LOAD_Z,         -- Load z value for current neuron
        ACCUMULATE,     -- Accumulate weight × delta products
        APPLY_DERIV,    -- Multiply by activation derivative
        OUTPUT_DELTA,   -- Output propagated delta
        NEXT_NEURON,    -- Move to next neuron
        DONE_ST         -- All neurons processed
    );
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
    
    -- Constants for Q2.13
    constant ONE_Q213  : signed(DATA_WIDTH-1 downto 0) := to_signed(2**FRAC_BITS, DATA_WIDTH);
    constant ZERO_Q213 : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Saturation bounds for output
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(2**(DATA_WIDTH-1)-1, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-2**(DATA_WIDTH-1), DATA_WIDTH);
    
    -- Product width
    constant PRODUCT_WIDTH : integer := 2 * DATA_WIDTH;

    ---------------------------------------------------------------------------
    -- Internal Registers
    ---------------------------------------------------------------------------
    signal num_neurons_reg : unsigned(7 downto 0) := (others => '0');
    signal num_deltas_reg  : unsigned(7 downto 0) := (others => '0');
    signal neuron_cnt      : unsigned(7 downto 0) := (others => '0');
    signal delta_cnt       : unsigned(7 downto 0) := (others => '0');
    
    signal accum_reg       : signed(ACCUM_WIDTH-1 downto 0) := (others => '0');
    signal z_reg           : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal delta_out_reg   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal overflow_reg    : std_logic := '0';
    
    -- Activation derivative (for ReLU: 1 if z > 0, else 0)
    signal act_deriv       : signed(DATA_WIDTH-1 downto 0) := (others => '0');

begin

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable product     : signed(PRODUCT_WIDTH-1 downto 0);
        variable product_ext : signed(ACCUM_WIDTH-1 downto 0);
        variable sum         : signed(ACCUM_WIDTH downto 0);
        variable scaled      : signed(ACCUM_WIDTH-1 downto 0);
        variable deriv_prod  : signed(PRODUCT_WIDTH-1 downto 0);
        variable final_val   : signed(DATA_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state          <= IDLE;
                num_neurons_reg<= (others => '0');
                num_deltas_reg <= (others => '0');
                neuron_cnt     <= (others => '0');
                delta_cnt      <= (others => '0');
                accum_reg      <= (others => '0');
                z_reg          <= (others => '0');
                delta_out_reg  <= (others => '0');
                overflow_reg   <= '0';
                act_deriv      <= (others => '0');
            else
                case state is
                    
                    ---------------------------------------------------------
                    -- IDLE: Wait for start
                    ---------------------------------------------------------
                    when IDLE =>
                        if clear = '1' then
                            accum_reg     <= (others => '0');
                            neuron_cnt    <= (others => '0');
                            delta_cnt     <= (others => '0');
                            overflow_reg  <= '0';
                        elsif start = '1' then
                            num_neurons_reg <= num_neurons;
                            num_deltas_reg  <= num_deltas;
                            neuron_cnt      <= (others => '0');
                            delta_cnt       <= (others => '0');
                            overflow_reg    <= '0';
                            
                            if num_neurons = 0 then
                                state <= DONE_ST;
                            else
                                state <= LOAD_Z;
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- LOAD_Z: Load z value for current neuron
                    ---------------------------------------------------------
                    when LOAD_Z =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif z_valid = '1' then
                            z_reg <= z_in;
                            
                            -- Compute ReLU derivative: σ'(z) = 1 if z > 0, else 0
                            if z_in > 0 then
                                act_deriv <= ONE_Q213;
                            else
                                act_deriv <= ZERO_Q213;
                            end if;
                            
                            -- Initialize accumulator for this neuron
                            accum_reg <= (others => '0');
                            delta_cnt <= (others => '0');
                            
                            if num_deltas_reg = 0 then
                                -- No deltas to accumulate
                                state <= APPLY_DERIV;
                            else
                                state <= ACCUMULATE;
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- ACCUMULATE: Sum up weight × delta products
                    ---------------------------------------------------------
                    when ACCUMULATE =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif weight_valid = '1' and delta_valid = '1' then
                            -- Compute weight × delta
                            product := weight_in * delta_in;
                            product_ext := resize(product, ACCUM_WIDTH);
                            
                            -- Accumulate
                            sum := resize(accum_reg, ACCUM_WIDTH+1) + 
                                   resize(product_ext, ACCUM_WIDTH+1);
                            
                            -- Check overflow and saturate
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
                            
                            delta_cnt <= delta_cnt + 1;
                            
                            -- Check if all deltas accumulated
                            if delta_cnt + 1 = num_deltas_reg then
                                state <= APPLY_DERIV;
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- APPLY_DERIV: Multiply by activation derivative
                    ---------------------------------------------------------
                    when APPLY_DERIV =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            -- Scale accumulator from Q4.26 to Q2.13
                            -- Shift right by FRAC_BITS with rounding
                            scaled := shift_right(accum_reg + to_signed(2**(FRAC_BITS-1), ACCUM_WIDTH), FRAC_BITS);
                            
                            -- Multiply by activation derivative
                            -- For ReLU, this is either passthrough or zero
                            if act_deriv = ONE_Q213 then
                                -- Active neuron: pass the weighted sum
                                if scaled > resize(SAT_MAX, ACCUM_WIDTH) then
                                    delta_out_reg <= SAT_MAX;
                                    overflow_reg <= '1';
                                elsif scaled < resize(SAT_MIN, ACCUM_WIDTH) then
                                    delta_out_reg <= SAT_MIN;
                                    overflow_reg <= '1';
                                else
                                    delta_out_reg <= scaled(DATA_WIDTH-1 downto 0);
                                end if;
                            else
                                -- Inactive neuron: zero output
                                delta_out_reg <= ZERO_Q213;
                            end if;
                            
                            state <= OUTPUT_DELTA;
                        end if;
                    
                    ---------------------------------------------------------
                    -- OUTPUT_DELTA: Wait for delta to be accepted
                    ---------------------------------------------------------
                    when OUTPUT_DELTA =>
                        if clear = '1' then
                            state <= IDLE;
                        elsif delta_out_ready = '1' then
                            state <= NEXT_NEURON;
                        end if;
                    
                    ---------------------------------------------------------
                    -- NEXT_NEURON: Move to next neuron or finish
                    ---------------------------------------------------------
                    when NEXT_NEURON =>
                        if clear = '1' then
                            state <= IDLE;
                        else
                            neuron_cnt <= neuron_cnt + 1;
                            
                            if neuron_cnt + 1 = num_neurons_reg then
                                state <= DONE_ST;
                            else
                                state <= LOAD_Z;
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- DONE_ST: All neurons processed
                    ---------------------------------------------------------
                    when DONE_ST =>
                        if clear = '1' or delta_out_ready = '1' then
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
    delta_out       <= delta_out_reg;
    delta_out_valid <= '1' when state = OUTPUT_DELTA else '0';
    neuron_index    <= neuron_cnt;
    
    weight_ready    <= '1' when state = ACCUMULATE else '0';
    delta_ready     <= '1' when state = ACCUMULATE else '0';
    z_ready         <= '1' when state = LOAD_Z else '0';
    
    busy            <= '0' when state = IDLE else '1';
    done            <= '1' when state = DONE_ST else '0';
    overflow        <= overflow_reg;

end architecture rtl;
