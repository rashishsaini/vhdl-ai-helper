--------------------------------------------------------------------------------
-- Module: sigmoid_unit
-- Description: Computes sigmoid activation function
--              σ(x) = 1 / (1 + e^(-x))
--
-- Method: Uses exp_approximator and reciprocal_unit
--         1. Compute -x (negate input)
--         2. Compute e^(-x) using exp_approximator
--         3. Compute 1 + e^(-x)
--         4. Compute 1 / (1 + e^(-x)) using reciprocal_unit
--
-- Format: Q2.13 input/output (16-bit signed)
-- Output Range: (0, 1) - always positive
-- Latency: ~20-22 clock cycles (exp + add + recip)
--
-- Key values:
--   σ(-4) ≈ 0.018
--   σ(-1) ≈ 0.269
--   σ(0)  = 0.5
--   σ(1)  ≈ 0.731
--   σ(4)  ≈ 0.982
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity sigmoid_unit is
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
        overflow     : out std_logic
    );
end entity sigmoid_unit;

architecture rtl of sigmoid_unit is

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
    -- Component: Reciprocal Unit
    ---------------------------------------------------------------------------
    component reciprocal_unit is
        generic (
            DATA_WIDTH     : integer := 16;
            FRAC_BITS      : integer := 13;
            INTERNAL_WIDTH : integer := 32;
            NUM_ITERATIONS : integer := 3;
            LUT_ADDR_BITS  : integer := 6
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            data_in      : in  signed(DATA_WIDTH-1 downto 0);
            start        : in  std_logic;
            data_out     : out signed(DATA_WIDTH-1 downto 0);
            done         : out std_logic;
            busy         : out std_logic;
            div_by_zero  : out std_logic;
            overflow     : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    -- 1.0 in Q2.13
    constant ONE : signed(DATA_WIDTH-1 downto 0) := to_signed(8192, DATA_WIDTH);
    
    -- Saturation bounds for sigmoid output (theoretically 0 to 1)
    constant SIG_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(8191, DATA_WIDTH);  -- ~0.9999
    constant SIG_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(1, DATA_WIDTH);     -- ~0.0001
    
    -- Thresholds for fast-path (avoid exp computation for extreme inputs)
    -- Critical: e^(-x) overflows Q2.13 when -x > ~1.38 (i.e., x < -1.38)
    -- We use piecewise linear approximation for |x| > 1.35
    -- For x in [-1.35, 1.35], use normal exp + recip computation
    -- 1.35 in Q2.13 = round(1.35 * 8192) = 11059
    constant FAST_POS_THRESH : signed(DATA_WIDTH-1 downto 0) := to_signed(11059, DATA_WIDTH);  -- +1.35 in Q2.13
    constant FAST_NEG_THRESH : signed(DATA_WIDTH-1 downto 0) := to_signed(-11059, DATA_WIDTH); -- -1.35 in Q2.13

    ---------------------------------------------------------------------------
    -- Piecewise Linear Approximation for sigmoid fast-path
    -- For |x| > 1.35, sigmoid changes slowly and can be well approximated
    -- by linear segments. We use 6 segments for each polarity.
    --
    -- Segment boundaries (in Q2.13):
    --   -4.0 <= x < -3.0: σ ≈ 0.033, slope ≈ 0.015 per unit
    --   -3.0 <= x < -2.5: σ ≈ 0.06,  slope ≈ 0.03 per unit
    --   -2.5 <= x < -2.0: σ ≈ 0.10,  slope ≈ 0.05 per unit
    --   -2.0 <= x < -1.5: σ ≈ 0.15,  slope ≈ 0.07 per unit
    --   -1.5 <= x < -1.35:σ ≈ 0.20,  slope ≈ 0.09 per unit
    ---------------------------------------------------------------------------

    -- Piecewise linear approximation coefficients for negative x
    -- Format: slope_i and intercept_i for segment i
    -- σ(x) ≈ slope * x + intercept
    -- Computed from actual sigmoid values at segment boundaries

    -- For x in [-4, -3]: σ(-4)=0.018, σ(-3)=0.047, slope=0.029, int=0.134
    -- For x in [-3, -2.5]: σ(-3)=0.047, σ(-2.5)=0.076, slope=0.058, int=0.221
    -- For x in [-2.5, -2]: σ(-2.5)=0.076, σ(-2)=0.119, slope=0.086, int=0.291
    -- For x in [-2, -1.5]: σ(-2)=0.119, σ(-1.5)=0.182, slope=0.126, int=0.371
    -- For x in [-1.5, -1.35]: σ(-1.5)=0.182, σ(-1.35)=0.206, slope=0.16, int=0.422

    -- Slopes in Q2.13 (multiply by 8192)
    constant SLOPE_SEG0 : signed(DATA_WIDTH-1 downto 0) := to_signed(238, DATA_WIDTH);   -- 0.029
    constant SLOPE_SEG1 : signed(DATA_WIDTH-1 downto 0) := to_signed(475, DATA_WIDTH);   -- 0.058
    constant SLOPE_SEG2 : signed(DATA_WIDTH-1 downto 0) := to_signed(705, DATA_WIDTH);   -- 0.086
    constant SLOPE_SEG3 : signed(DATA_WIDTH-1 downto 0) := to_signed(1032, DATA_WIDTH);  -- 0.126
    constant SLOPE_SEG4 : signed(DATA_WIDTH-1 downto 0) := to_signed(1311, DATA_WIDTH);  -- 0.16

    -- Intercepts in Q2.13
    constant INT_SEG0 : signed(DATA_WIDTH-1 downto 0) := to_signed(1098, DATA_WIDTH);    -- 0.134
    constant INT_SEG1 : signed(DATA_WIDTH-1 downto 0) := to_signed(1811, DATA_WIDTH);    -- 0.221
    constant INT_SEG2 : signed(DATA_WIDTH-1 downto 0) := to_signed(2384, DATA_WIDTH);    -- 0.291
    constant INT_SEG3 : signed(DATA_WIDTH-1 downto 0) := to_signed(3039, DATA_WIDTH);    -- 0.371
    constant INT_SEG4 : signed(DATA_WIDTH-1 downto 0) := to_signed(3457, DATA_WIDTH);    -- 0.422

    -- Boundary thresholds in Q2.13
    constant THRESH_4P0 : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH); -- 4.0 (max)
    constant THRESH_3P0 : signed(DATA_WIDTH-1 downto 0) := to_signed(24576, DATA_WIDTH); -- 3.0
    constant THRESH_2P5 : signed(DATA_WIDTH-1 downto 0) := to_signed(20480, DATA_WIDTH); -- 2.5
    constant THRESH_2P0 : signed(DATA_WIDTH-1 downto 0) := to_signed(16384, DATA_WIDTH); -- 2.0
    constant THRESH_1P5 : signed(DATA_WIDTH-1 downto 0) := to_signed(12288, DATA_WIDTH); -- 1.5
    constant THRESH_1P35: signed(DATA_WIDTH-1 downto 0) := to_signed(11059, DATA_WIDTH); -- 1.35

    -- Saturation values for very extreme x
    constant SIG_NEAR_ZERO : signed(DATA_WIDTH-1 downto 0) := to_signed(148, DATA_WIDTH); -- σ(-4) ≈ 0.018
    constant SIG_NEAR_ONE  : signed(DATA_WIDTH-1 downto 0) := to_signed(8044, DATA_WIDTH);-- σ(4) ≈ 0.982

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        FAST_PATH,       -- New state for fast-path approximation
        START_EXP,
        WAIT_EXP,
        ADD_ONE,
        START_RECIP,
        WAIT_RECIP,
        OUTPUT_ST
    );
    signal state : state_t;

    -- Flag to indicate fast-path was used
    signal use_fast_path : std_logic;

    ---------------------------------------------------------------------------
    -- Internal Signals
    ---------------------------------------------------------------------------
    -- Input storage
    signal x_reg         : signed(DATA_WIDTH-1 downto 0);
    signal neg_x         : signed(DATA_WIDTH-1 downto 0);
    
    -- Exp unit interface
    signal exp_input     : signed(DATA_WIDTH-1 downto 0);
    signal exp_start     : std_logic;
    signal exp_result    : signed(DATA_WIDTH-1 downto 0);
    signal exp_done      : std_logic;
    signal exp_busy      : std_logic;
    signal exp_overflow  : std_logic;
    signal exp_underflow : std_logic;
    
    -- Intermediate: 1 + e^(-x)
    signal one_plus_exp  : signed(DATA_WIDTH-1 downto 0);
    
    -- Reciprocal unit interface
    signal recip_input   : signed(DATA_WIDTH-1 downto 0);
    signal recip_start   : std_logic;
    signal recip_result  : signed(DATA_WIDTH-1 downto 0);
    signal recip_done    : std_logic;
    signal recip_busy    : std_logic;
    signal recip_dbz     : std_logic;
    signal recip_overflow: std_logic;
    
    -- Output registers
    signal result_reg    : signed(DATA_WIDTH-1 downto 0);
    signal done_reg      : std_logic;
    signal ovf_reg       : std_logic;

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
    -- Reciprocal Unit Instantiation
    ---------------------------------------------------------------------------
    recip_inst : reciprocal_unit
        generic map (
            DATA_WIDTH     => DATA_WIDTH,
            FRAC_BITS      => FRAC_BITS,
            INTERNAL_WIDTH => 32,
            NUM_ITERATIONS => 3,
            LUT_ADDR_BITS  => 6
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_in      => recip_input,
            start        => recip_start,
            data_out     => recip_result,
            done         => recip_done,
            busy         => recip_busy,
            div_by_zero  => recip_dbz,
            overflow     => recip_overflow
        );

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable sum_extended : signed(DATA_WIDTH downto 0);
        variable fast_product : signed(2*DATA_WIDTH-1 downto 0);  -- For slope * x multiplication
        variable fast_result  : signed(DATA_WIDTH downto 0);       -- For intermediate result
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state        <= IDLE;
                x_reg        <= (others => '0');
                neg_x        <= (others => '0');
                exp_input    <= (others => '0');
                exp_start    <= '0';
                one_plus_exp <= (others => '0');
                recip_input  <= (others => '0');
                recip_start  <= '0';
                result_reg   <= (others => '0');
                done_reg     <= '0';
                ovf_reg      <= '0';
                use_fast_path <= '0';
            else
                -- Default: clear single-cycle signals
                done_reg    <= '0';
                exp_start   <= '0';
                recip_start <= '0';
                
                case state is
                    when IDLE =>
                        if start = '1' then
                            x_reg <= data_in;
                            ovf_reg <= '0';
                            use_fast_path <= '0';

                            -- Compute -x for e^(-x)
                            -- Handle edge case: -(-32768) would overflow
                            if data_in = to_signed(-32768, DATA_WIDTH) then
                                neg_x <= to_signed(32767, DATA_WIDTH);
                            else
                                neg_x <= -data_in;
                            end if;

                            -- Check if fast-path should be used (|x| > 1.5)
                            -- When x is very negative or very positive, exp(-x) overflows
                            if data_in > FAST_POS_THRESH or data_in < FAST_NEG_THRESH then
                                use_fast_path <= '1';
                                state <= FAST_PATH;
                            else
                                state <= START_EXP;
                            end if;
                        end if;

                    when FAST_PATH =>
                        -- Fast-path: piecewise linear approximation
                        -- For negative x: use direct computation σ(x) = slope*x + intercept
                        -- For positive x: use symmetry σ(x) = 1 - σ(-x) = 1 - (slope*(-x) + int)
                        --                                    = 1 - int + slope*x

                        if x_reg < to_signed(0, DATA_WIDTH) then
                            -- Negative x: σ(x) is small
                            if x_reg <= -THRESH_3P0 then
                                -- x in [-4, -3]: use segment 0
                                -- σ(x) = slope * x + intercept
                                fast_product := SLOPE_SEG0 * x_reg;
                                fast_result := resize(shift_right(fast_product, FRAC_BITS), DATA_WIDTH+1) +
                                              resize(INT_SEG0, DATA_WIDTH+1);
                            elsif x_reg <= -THRESH_2P5 then
                                -- x in [-3, -2.5]: use segment 1
                                fast_product := SLOPE_SEG1 * x_reg;
                                fast_result := resize(shift_right(fast_product, FRAC_BITS), DATA_WIDTH+1) +
                                              resize(INT_SEG1, DATA_WIDTH+1);
                            elsif x_reg <= -THRESH_2P0 then
                                -- x in [-2.5, -2]: use segment 2
                                fast_product := SLOPE_SEG2 * x_reg;
                                fast_result := resize(shift_right(fast_product, FRAC_BITS), DATA_WIDTH+1) +
                                              resize(INT_SEG2, DATA_WIDTH+1);
                            elsif x_reg <= -THRESH_1P5 then
                                -- x in [-2, -1.5]: use segment 3
                                fast_product := SLOPE_SEG3 * x_reg;
                                fast_result := resize(shift_right(fast_product, FRAC_BITS), DATA_WIDTH+1) +
                                              resize(INT_SEG3, DATA_WIDTH+1);
                            else
                                -- x in [-1.5, -1.35]: use segment 4
                                fast_product := SLOPE_SEG4 * x_reg;
                                fast_result := resize(shift_right(fast_product, FRAC_BITS), DATA_WIDTH+1) +
                                              resize(INT_SEG4, DATA_WIDTH+1);
                            end if;

                            -- Saturate result
                            if fast_result < resize(SIG_MIN, DATA_WIDTH+1) then
                                result_reg <= SIG_MIN;
                            elsif fast_result > resize(SIG_MAX, DATA_WIDTH+1) then
                                result_reg <= SIG_MAX;
                            else
                                result_reg <= fast_result(DATA_WIDTH-1 downto 0);
                            end if;
                        else
                            -- Positive x: use symmetry σ(x) = 1 - σ(-x)
                            -- If σ(-x) = slope*(-x) + int = -slope*x + int
                            -- Then σ(x) = 1 - (-slope*x + int) = 1 - int + slope*x
                            --           = (ONE - int) + slope*x
                            if x_reg >= THRESH_3P0 then
                                -- x in [3, 4]: symmetric to segment 0
                                fast_product := SLOPE_SEG0 * x_reg;
                                fast_result := resize(ONE - INT_SEG0, DATA_WIDTH+1) +
                                              resize(shift_right(fast_product, FRAC_BITS), DATA_WIDTH+1);
                            elsif x_reg >= THRESH_2P5 then
                                -- x in [2.5, 3]: symmetric to segment 1
                                fast_product := SLOPE_SEG1 * x_reg;
                                fast_result := resize(ONE - INT_SEG1, DATA_WIDTH+1) +
                                              resize(shift_right(fast_product, FRAC_BITS), DATA_WIDTH+1);
                            elsif x_reg >= THRESH_2P0 then
                                -- x in [2, 2.5]: symmetric to segment 2
                                fast_product := SLOPE_SEG2 * x_reg;
                                fast_result := resize(ONE - INT_SEG2, DATA_WIDTH+1) +
                                              resize(shift_right(fast_product, FRAC_BITS), DATA_WIDTH+1);
                            elsif x_reg >= THRESH_1P5 then
                                -- x in [1.5, 2]: symmetric to segment 3
                                fast_product := SLOPE_SEG3 * x_reg;
                                fast_result := resize(ONE - INT_SEG3, DATA_WIDTH+1) +
                                              resize(shift_right(fast_product, FRAC_BITS), DATA_WIDTH+1);
                            else
                                -- x in [1.35, 1.5]: symmetric to segment 4
                                fast_product := SLOPE_SEG4 * x_reg;
                                fast_result := resize(ONE - INT_SEG4, DATA_WIDTH+1) +
                                              resize(shift_right(fast_product, FRAC_BITS), DATA_WIDTH+1);
                            end if;

                            -- Saturate result
                            if fast_result < resize(SIG_MIN, DATA_WIDTH+1) then
                                result_reg <= SIG_MIN;
                            elsif fast_result > resize(SIG_MAX, DATA_WIDTH+1) then
                                result_reg <= SIG_MAX;
                            else
                                result_reg <= fast_result(DATA_WIDTH-1 downto 0);
                            end if;
                        end if;

                        done_reg <= '1';
                        state <= IDLE;
                    
                    when START_EXP =>
                        -- Start exponential computation with -x
                        exp_input <= neg_x;
                        exp_start <= '1';
                        state <= WAIT_EXP;
                    
                    when WAIT_EXP =>
                        -- Wait for exp_approximator to complete
                        if exp_done = '1' then
                            state <= ADD_ONE;
                        end if;
                    
                    when ADD_ONE =>
                        -- Compute 1 + e^(-x)
                        -- exp_result contains e^(-x) which is always positive
                        sum_extended := resize(ONE, DATA_WIDTH+1) + resize(exp_result, DATA_WIDTH+1);
                        
                        -- Check for overflow (shouldn't happen for valid sigmoid inputs)
                        -- Max value: 1 + e^4 ≈ 1 + 54.6 but e^4 saturates to ~4 in Q2.13
                        -- So max is about 1 + 4 = 5, which fits in Q2.13
                        if sum_extended > to_signed(32767, DATA_WIDTH+1) then
                            one_plus_exp <= to_signed(32767, DATA_WIDTH);
                            ovf_reg <= '1';
                        else
                            one_plus_exp <= resize(sum_extended, DATA_WIDTH);
                        end if;
                        
                        state <= START_RECIP;
                    
                    when START_RECIP =>
                        -- Start reciprocal computation: 1 / (1 + e^(-x))
                        recip_input <= one_plus_exp;
                        recip_start <= '1';
                        state <= WAIT_RECIP;
                    
                    when WAIT_RECIP =>
                        -- Wait for reciprocal_unit to complete
                        if recip_done = '1' then
                            state <= OUTPUT_ST;
                        end if;
                    
                    when OUTPUT_ST =>
                        -- Capture result with saturation to valid sigmoid range [0, 1)
                        if recip_result > SIG_MAX then
                            result_reg <= SIG_MAX;
                        elsif recip_result < SIG_MIN then
                            result_reg <= SIG_MIN;
                        else
                            result_reg <= recip_result;
                        end if;
                        
                        -- Propagate overflow flag
                        if recip_overflow = '1' or recip_dbz = '1' then
                            ovf_reg <= '1';
                        end if;
                        
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
    data_out <= result_reg;
    done     <= done_reg;
    busy     <= '0' when state = IDLE else '1';
    overflow <= ovf_reg;

end architecture rtl;