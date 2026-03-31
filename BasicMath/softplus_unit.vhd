--------------------------------------------------------------------------------
-- Module: softplus_unit
-- Description: Computes softplus activation function
--              softplus(x) = ln(1 + e^x)
--
-- Method: Chains exp_approximator and log_approximator
--         1. Compute e^x using exp_approximator
--         2. Compute 1 + e^x with saturation
--         3. Compute ln(1 + e^x) using log_approximator
--
-- Asymptotic Optimizations:
--   - For large positive x: softplus(x) ≈ x (avoids e^x overflow)
--   - For large negative x: softplus(x) ≈ e^x ≈ 0
--
-- Format: Q2.13 input/output (16-bit signed)
-- Output Range: [0, ~4) - always non-negative
-- Latency: ~11 cycles (normal path), 2 cycles (fast path)
--
-- Key values:
--   softplus(-4) ≈ 0.018
--   softplus(-1) ≈ 0.313
--   softplus(0)  = ln(2) ≈ 0.693
--   softplus(1)  ≈ 1.313
--   softplus(4)  ≈ 4.018 (saturates to ~4)
--
-- Mathematical Properties:
--   - Smooth approximation to ReLU
--   - Derivative is sigmoid: d/dx softplus(x) = σ(x)
--   - Always positive: softplus(x) > 0 for all x
--
-- Author: FPGA Neural Network Project
-- Complexity: MEDIUM (⭐⭐)
-- Dependencies: exp_approximator, log_approximator
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity softplus_unit is
    generic (
        DATA_WIDTH : integer := 16;
        FRAC_BITS  : integer := 13
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Input interface
        data_in      : in  signed(DATA_WIDTH-1 downto 0);
        start        : in  std_logic;
        
        -- Output interface
        data_out     : out signed(DATA_WIDTH-1 downto 0);
        done         : out std_logic;
        busy         : out std_logic;
        
        -- Status
        overflow     : out std_logic;  -- Result saturated
        used_fast_path : out std_logic -- Indicates asymptotic approximation used
    );
end entity softplus_unit;

architecture rtl of softplus_unit is

    ---------------------------------------------------------------------------
    -- Component: Exponential Approximator
    ---------------------------------------------------------------------------
    component exp_approximator is
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
            overflow     : out std_logic;
            underflow    : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- Component: Logarithm Approximator
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
    -- Constants
    ---------------------------------------------------------------------------
    -- 1.0 in Q2.13
    constant ONE : signed(DATA_WIDTH-1 downto 0) := to_signed(2**FRAC_BITS, DATA_WIDTH);
    
    -- Saturation bounds
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);  -- ~3.9999
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(0, DATA_WIDTH);      -- 0 (softplus >= 0)
    
    -- Fast path thresholds
    -- For x > 1.35: e^x overflows Q2.13, use softplus(x) ≈ x
    -- 1.35 * 8192 = 11059
    constant FAST_THRESH_POS : signed(DATA_WIDTH-1 downto 0) := to_signed(11059, DATA_WIDTH);
    
    -- For x < -3.5: softplus(x) ≈ e^x which is very small
    -- We compute normally but could optimize further
    -- -3.5 * 8192 = -28672
    constant FAST_THRESH_NEG : signed(DATA_WIDTH-1 downto 0) := to_signed(-28672, DATA_WIDTH);
    
    -- Minimum output (softplus approaches 0 but never reaches it)
    -- For x = -4: softplus(-4) ≈ 0.0183, in Q2.13 ≈ 150
    constant MIN_OUTPUT : signed(DATA_WIDTH-1 downto 0) := to_signed(1, DATA_WIDTH);

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        CHECK_BOUNDS,
        START_EXP,
        WAIT_EXP,
        ADD_ONE,
        START_LOG,
        WAIT_LOG,
        OUTPUT_ST
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Internal Signals
    ---------------------------------------------------------------------------
    -- Input storage
    signal x_reg           : signed(DATA_WIDTH-1 downto 0);
    
    -- Exp unit interface
    signal exp_input       : signed(DATA_WIDTH-1 downto 0);
    signal exp_start       : std_logic;
    signal exp_result      : signed(DATA_WIDTH-1 downto 0);
    signal exp_done        : std_logic;
    signal exp_busy        : std_logic;
    signal exp_overflow    : std_logic;
    signal exp_underflow   : std_logic;
    
    -- Intermediate: 1 + e^x
    signal one_plus_exp    : signed(DATA_WIDTH-1 downto 0);
    signal add_overflow    : std_logic;
    
    -- Log unit interface
    signal log_input       : signed(DATA_WIDTH-1 downto 0);
    signal log_start       : std_logic;
    signal log_result      : signed(DATA_WIDTH-1 downto 0);
    signal log_done        : std_logic;
    signal log_busy        : std_logic;
    signal log_invalid     : std_logic;
    signal log_overflow    : std_logic;
    
    -- Output registers
    signal result_reg      : signed(DATA_WIDTH-1 downto 0);
    signal done_reg        : std_logic;
    signal ovf_reg         : std_logic;
    signal fast_path_reg   : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Exp Approximator Instantiation
    ---------------------------------------------------------------------------
    exp_inst : exp_approximator
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            FRAC_BITS  => FRAC_BITS
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_in      => exp_input,
            start        => exp_start,
            data_out     => exp_result,
            done         => exp_done,
            busy         => exp_busy,
            overflow     => exp_overflow,
            underflow    => exp_underflow
        );

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
        variable sum_extended : signed(DATA_WIDTH downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state         <= IDLE;
                x_reg         <= (others => '0');
                exp_input     <= (others => '0');
                exp_start     <= '0';
                one_plus_exp  <= (others => '0');
                add_overflow  <= '0';
                log_input     <= (others => '0');
                log_start     <= '0';
                result_reg    <= (others => '0');
                done_reg      <= '0';
                ovf_reg       <= '0';
                fast_path_reg <= '0';
            else
                -- Default: clear single-cycle signals
                done_reg  <= '0';
                exp_start <= '0';
                log_start <= '0';
                
                case state is
                
                    ---------------------------------------------------------
                    -- IDLE: Wait for start signal
                    ---------------------------------------------------------
                    when IDLE =>
                        if start = '1' then
                            x_reg         <= data_in;
                            ovf_reg       <= '0';
                            fast_path_reg <= '0';
                            add_overflow  <= '0';
                            state         <= CHECK_BOUNDS;
                        end if;
                    
                    ---------------------------------------------------------
                    -- CHECK_BOUNDS: Determine computation path
                    ---------------------------------------------------------
                    when CHECK_BOUNDS =>
                        if x_reg > FAST_THRESH_POS then
                            -- Fast path: softplus(x) ≈ x for large positive x
                            -- This avoids e^x overflow
                            result_reg    <= x_reg;
                            fast_path_reg <= '1';
                            done_reg      <= '1';
                            state         <= IDLE;
                        elsif x_reg < FAST_THRESH_NEG then
                            -- For very negative x: softplus(x) ≈ e^x ≈ 0
                            -- Still compute via exp for accuracy, but we know
                            -- the result will be very small
                            exp_input <= x_reg;
                            exp_start <= '1';
                            state     <= WAIT_EXP;
                        else
                            -- Normal computation path
                            exp_input <= x_reg;
                            exp_start <= '1';
                            state     <= WAIT_EXP;
                        end if;
                    
                    ---------------------------------------------------------
                    -- WAIT_EXP: Wait for exp_approximator to complete
                    ---------------------------------------------------------
                    when WAIT_EXP =>
                        if exp_done = '1' then
                            state <= ADD_ONE;
                        end if;
                    
                    ---------------------------------------------------------
                    -- ADD_ONE: Compute 1 + e^x with saturation
                    ---------------------------------------------------------
                    when ADD_ONE =>
                        -- Compute 1 + e^x
                        -- exp_result is e^x in Q2.13
                        -- ONE is 1.0 in Q2.13 = 8192
                        sum_extended := resize(ONE, DATA_WIDTH+1) + 
                                        resize(exp_result, DATA_WIDTH+1);
                        
                        -- Check for overflow (sum > 3.9999)
                        if sum_extended > resize(SAT_MAX, DATA_WIDTH+1) then
                            one_plus_exp <= SAT_MAX;
                            add_overflow <= '1';
                        elsif sum_extended < 0 then
                            -- Should never happen since e^x >= 0 and ONE > 0
                            one_plus_exp <= ONE;  -- Minimum is 1.0
                            add_overflow <= '1';
                        else
                            one_plus_exp <= sum_extended(DATA_WIDTH-1 downto 0);
                        end if;
                        
                        state <= START_LOG;
                    
                    ---------------------------------------------------------
                    -- START_LOG: Start logarithm computation
                    ---------------------------------------------------------
                    when START_LOG =>
                        log_input <= one_plus_exp;
                        log_start <= '1';
                        state     <= WAIT_LOG;
                    
                    ---------------------------------------------------------
                    -- WAIT_LOG: Wait for log_approximator to complete
                    ---------------------------------------------------------
                    when WAIT_LOG =>
                        if log_done = '1' then
                            state <= OUTPUT_ST;
                        end if;
                    
                    ---------------------------------------------------------
                    -- OUTPUT_ST: Capture result and signal done
                    ---------------------------------------------------------
                    when OUTPUT_ST =>
                        -- Softplus is always non-negative
                        if log_result < 0 then
                            -- Should not happen mathematically, but safety check
                            result_reg <= MIN_OUTPUT;
                            ovf_reg    <= '1';
                        elsif log_result > SAT_MAX then
                            result_reg <= SAT_MAX;
                            ovf_reg    <= '1';
                        else
                            result_reg <= log_result;
                        end if;
                        
                        -- Propagate overflow flags
                        if exp_overflow = '1' or add_overflow = '1' or log_overflow = '1' then
                            ovf_reg <= '1';
                        end if;
                        
                        done_reg <= '1';
                        state    <= IDLE;
                    
                    when others =>
                        state <= IDLE;
                        
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    data_out       <= result_reg;
    done           <= done_reg;
    busy           <= '0' when state = IDLE else '1';
    overflow       <= ovf_reg;
    used_fast_path <= fast_path_reg;

end architecture rtl;
