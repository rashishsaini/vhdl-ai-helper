--------------------------------------------------------------------------------
-- Module: cross_entropy_unit
-- Description: Binary cross-entropy loss for classification
--              L = -[y * log(p) + (1-y) * log(1-p)]
--              
-- Features:
--   - Computes binary cross-entropy loss
--   - Outputs gradient for backpropagation: grad = p - y
--   - Numerical stability via probability clipping
--   - Uses log_approximator for logarithm computation
--   - Handles edge cases (p near 0 or 1, y=0 or y=1)
--
-- Format: Q2.13 (16-bit signed)
--   - Probability p: expected in range (0, 1), typically sigmoid output
--   - Target y: 0 or 1 in Q2.13 (0x0000 or 0x2000)
--   - Loss output: positive value
--   - Gradient: p - y (simplified for sigmoid output layer)
--
-- Mathematical Notes:
--   - For p ∈ (0,1): log(p) < 0 (negative)
--   - For 1-p ∈ (0,1): log(1-p) < 0 (negative)
--   - Cross-entropy = -[negative + negative] = positive ✓
--
-- Latency: ~12-15 clock cycles (2× log_approximator + arithmetic)
--
-- Author: FPGA Neural Network Project
-- Complexity: HARD (⭐⭐⭐)
-- Dependencies: log_approximator
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity cross_entropy_unit is
    generic (
        DATA_WIDTH : integer := 16;
        FRAC_BITS  : integer := 13
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Input interface
        predicted    : in  signed(DATA_WIDTH-1 downto 0);  -- p: sigmoid output [0,1]
        target       : in  signed(DATA_WIDTH-1 downto 0);  -- y: 0 or 1 (Q2.13)
        start        : in  std_logic;
        
        -- Output interface
        loss_out     : out signed(DATA_WIDTH-1 downto 0);  -- Cross-entropy loss (positive)
        gradient_out : out signed(DATA_WIDTH-1 downto 0);  -- Gradient: p - y
        done         : out std_logic;
        busy         : out std_logic;
        
        -- Status
        overflow     : out std_logic;
        invalid      : out std_logic   -- Input out of valid range
    );
end entity cross_entropy_unit;

architecture rtl of cross_entropy_unit is

    ---------------------------------------------------------------------------
    -- Component: Log Approximator (from log_approximator.vhd)
    ---------------------------------------------------------------------------
    component log_approximator is
        generic (
            DATA_WIDTH : integer := 16;
            FRAC_BITS  : integer := 13
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            data_in      : in  signed(DATA_WIDTH-1 downto 0);
            start        : in  std_logic;
            data_out     : out signed(DATA_WIDTH-1 downto 0);
            done         : out std_logic;
            busy         : out std_logic;
            invalid      : out std_logic;
            overflow     : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        CLIP_INPUT,        -- Clip p to safe range [epsilon, 1-epsilon]
        START_LOG_P,       -- Start computing log(p)
        WAIT_LOG_P,        -- Wait for log(p)
        COMPUTE_ONE_MINUS, -- Compute 1-p
        START_LOG_1MP,     -- Start computing log(1-p)
        WAIT_LOG_1MP,      -- Wait for log(1-p)
        COMPUTE_TERMS,     -- Compute y*log(p) and (1-y)*log(1-p)
        COMPUTE_LOSS,      -- Sum terms and negate
        OUTPUT_ST          -- Output results
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Constants in Q2.13 format
    ---------------------------------------------------------------------------
    -- 1.0 in Q2.13 = 8192
    constant ONE : signed(DATA_WIDTH-1 downto 0) := to_signed(2**FRAC_BITS, DATA_WIDTH);
    
    -- Epsilon for numerical stability: ~0.001 in Q2.13 = 8
    -- Prevents log(0) which is undefined
    constant EPSILON : signed(DATA_WIDTH-1 downto 0) := to_signed(8, DATA_WIDTH);
    
    -- 1 - epsilon ≈ 0.999
    constant ONE_MINUS_EPS : signed(DATA_WIDTH-1 downto 0) := 
        to_signed(2**FRAC_BITS - 8, DATA_WIDTH);
    
    -- Zero
    constant ZERO : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Saturation bounds
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH);

    ---------------------------------------------------------------------------
    -- Internal Registers
    ---------------------------------------------------------------------------
    -- Input storage
    signal p_reg         : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal y_reg         : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal p_clipped     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Intermediate values
    signal one_minus_p   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal one_minus_y   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal log_p         : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal log_1mp       : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Term computation
    -- Q2.13 × Q2.13 = Q4.26 (32 bits)
    signal term1         : signed(2*DATA_WIDTH-1 downto 0) := (others => '0');
    signal term2         : signed(2*DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Log approximator interface
    signal log_input     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal log_start     : std_logic := '0';
    signal log_result    : signed(DATA_WIDTH-1 downto 0);
    signal log_done      : std_logic;
    signal log_busy      : std_logic;
    signal log_invalid   : std_logic;
    signal log_overflow  : std_logic;
    
    -- Output registers
    signal loss_reg      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal grad_reg      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal done_reg      : std_logic := '0';
    signal ovf_reg       : std_logic := '0';
    signal inv_reg       : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Log Approximator Instantiation
    ---------------------------------------------------------------------------
    log_inst : log_approximator
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            FRAC_BITS  => FRAC_BITS
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_in      => log_input,
            start        => log_start,
            data_out     => log_result,
            done         => log_done,
            busy         => log_busy,
            invalid      => log_invalid,
            overflow     => log_overflow
        );

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable term1_scaled : signed(DATA_WIDTH-1 downto 0);
        variable term2_scaled : signed(DATA_WIDTH-1 downto 0);
        variable loss_sum     : signed(DATA_WIDTH downto 0);
        variable grad_diff    : signed(DATA_WIDTH downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state        <= IDLE;
                p_reg        <= (others => '0');
                y_reg        <= (others => '0');
                p_clipped    <= (others => '0');
                one_minus_p  <= (others => '0');
                one_minus_y  <= (others => '0');
                log_p        <= (others => '0');
                log_1mp      <= (others => '0');
                term1        <= (others => '0');
                term2        <= (others => '0');
                log_input    <= (others => '0');
                log_start    <= '0';
                loss_reg     <= (others => '0');
                grad_reg     <= (others => '0');
                done_reg     <= '0';
                ovf_reg      <= '0';
                inv_reg      <= '0';
            else
                -- Default: clear single-cycle signals
                done_reg  <= '0';
                log_start <= '0';
                
                case state is
                
                    ---------------------------------------------------------
                    -- IDLE: Wait for start
                    ---------------------------------------------------------
                    when IDLE =>
                        if start = '1' then
                            p_reg   <= predicted;
                            y_reg   <= target;
                            ovf_reg <= '0';
                            inv_reg <= '0';
                            
                            -- Input validation
                            if predicted <= ZERO then
                                -- p <= 0 is invalid for log
                                inv_reg  <= '1';
                                loss_reg <= SAT_MAX;  -- Large loss for invalid input
                                -- Gradient: approximate as p - y ≈ 0 - y = -y
                                grad_reg <= -target;
                                done_reg <= '1';
                                -- Stay in IDLE
                            elsif predicted >= ONE then
                                -- p >= 1 is invalid (log(1-p) undefined)
                                inv_reg  <= '1';
                                loss_reg <= SAT_MAX;
                                -- Gradient: approximate as p - y ≈ 1 - y
                                grad_reg <= ONE - target;
                                done_reg <= '1';
                                -- Stay in IDLE
                            else
                                state <= CLIP_INPUT;
                            end if;
                        end if;
                    
                    ---------------------------------------------------------
                    -- CLIP_INPUT: Clip p to [epsilon, 1-epsilon] for stability
                    ---------------------------------------------------------
                    when CLIP_INPUT =>
                        -- Clip for numerical stability
                        if p_reg < EPSILON then
                            p_clipped <= EPSILON;
                        elsif p_reg > ONE_MINUS_EPS then
                            p_clipped <= ONE_MINUS_EPS;
                        else
                            p_clipped <= p_reg;
                        end if;
                        
                        -- Precompute 1-y (needed for second term)
                        one_minus_y <= ONE - y_reg;
                        
                        -- Compute gradient: p - y (always valid, no clipping)
                        -- This is the beauty of sigmoid + cross-entropy!
                        grad_diff := resize(p_reg, DATA_WIDTH+1) - resize(y_reg, DATA_WIDTH+1);
                        if grad_diff > resize(SAT_MAX, DATA_WIDTH+1) then
                            grad_reg <= SAT_MAX;
                        elsif grad_diff < resize(SAT_MIN, DATA_WIDTH+1) then
                            grad_reg <= SAT_MIN;
                        else
                            grad_reg <= grad_diff(DATA_WIDTH-1 downto 0);
                        end if;
                        
                        state <= START_LOG_P;
                    
                    ---------------------------------------------------------
                    -- START_LOG_P: Start computing log(p)
                    ---------------------------------------------------------
                    when START_LOG_P =>
                        log_input <= p_clipped;
                        log_start <= '1';
                        state <= WAIT_LOG_P;
                    
                    ---------------------------------------------------------
                    -- WAIT_LOG_P: Wait for log(p) result
                    -- Note: log(p) will be negative since p < 1
                    ---------------------------------------------------------
                    when WAIT_LOG_P =>
                        if log_done = '1' then
                            log_p <= log_result;
                            
                            if log_invalid = '1' or log_overflow = '1' then
                                ovf_reg <= '1';
                            end if;
                            
                            state <= COMPUTE_ONE_MINUS;
                        end if;
                    
                    ---------------------------------------------------------
                    -- COMPUTE_ONE_MINUS: Compute 1-p for second log
                    ---------------------------------------------------------
                    when COMPUTE_ONE_MINUS =>
                        one_minus_p <= ONE - p_clipped;
                        state <= START_LOG_1MP;
                    
                    ---------------------------------------------------------
                    -- START_LOG_1MP: Start computing log(1-p)
                    ---------------------------------------------------------
                    when START_LOG_1MP =>
                        log_input <= one_minus_p;
                        log_start <= '1';
                        state <= WAIT_LOG_1MP;
                    
                    ---------------------------------------------------------
                    -- WAIT_LOG_1MP: Wait for log(1-p) result
                    -- Note: log(1-p) will be negative since 1-p < 1
                    ---------------------------------------------------------
                    when WAIT_LOG_1MP =>
                        if log_done = '1' then
                            log_1mp <= log_result;
                            
                            if log_invalid = '1' or log_overflow = '1' then
                                ovf_reg <= '1';
                            end if;
                            
                            state <= COMPUTE_TERMS;
                        end if;
                    
                    ---------------------------------------------------------
                    -- COMPUTE_TERMS: Compute y*log(p) and (1-y)*log(1-p)
                    -- Both log values are negative, products will be:
                    --   term1 = y * log(p) ≤ 0
                    --   term2 = (1-y) * log(1-p) ≤ 0
                    ---------------------------------------------------------
                    when COMPUTE_TERMS =>
                        -- Q2.13 × Q2.13 = Q4.26 (32-bit signed)
                        term1 <= y_reg * log_p;           -- y * log(p)
                        term2 <= one_minus_y * log_1mp;   -- (1-y) * log(1-p)
                        
                        state <= COMPUTE_LOSS;
                    
                    ---------------------------------------------------------
                    -- COMPUTE_LOSS: L = -[y*log(p) + (1-y)*log(1-p)]
                    -- Since both terms are ≤ 0, their sum is ≤ 0
                    -- Negating gives positive loss
                    ---------------------------------------------------------
                    when COMPUTE_LOSS =>
                        -- Scale terms from Q4.26 back to Q2.13
                        -- Shift right by FRAC_BITS (13) with sign extension
                        term1_scaled := term1(DATA_WIDTH+FRAC_BITS-1 downto FRAC_BITS);
                        term2_scaled := term2(DATA_WIDTH+FRAC_BITS-1 downto FRAC_BITS);
                        
                        -- Sum: (term1 + term2) is negative or zero
                        loss_sum := resize(term1_scaled, DATA_WIDTH+1) + 
                                    resize(term2_scaled, DATA_WIDTH+1);
                        
                        -- Negate to get positive loss: L = -(negative sum)
                        loss_sum := -loss_sum;
                        
                        -- Saturate to Q2.13 range
                        if loss_sum > resize(SAT_MAX, DATA_WIDTH+1) then
                            loss_reg <= SAT_MAX;
                            ovf_reg <= '1';
                        elsif loss_sum < ZERO then
                            -- Loss should never be negative, clamp to 0
                            loss_reg <= ZERO;
                        else
                            loss_reg <= loss_sum(DATA_WIDTH-1 downto 0);
                        end if;
                        
                        state <= OUTPUT_ST;
                    
                    ---------------------------------------------------------
                    -- OUTPUT_ST: Assert done for one cycle
                    ---------------------------------------------------------
                    when OUTPUT_ST =>
                        done_reg <= '1';
                        state <= IDLE;
                    
                    when others =>
                        state <= IDLE;
                        
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    loss_out     <= loss_reg;
    gradient_out <= grad_reg;
    done         <= done_reg;
    busy         <= '0' when state = IDLE else '1';
    overflow     <= ovf_reg;
    invalid      <= inv_reg;

end architecture rtl;
