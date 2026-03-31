--------------------------------------------------------------------------------
-- Module: exp_approximator
-- Description: Computes e^x using piecewise linear approximation
--              Optimized for neural network activation functions
--
-- Format: Q2.13 input/output (16-bit signed)
-- Method: Piecewise linear interpolation with lookup table
-- Range:  Input x in [-4, 4), Output e^x with saturation
--
-- Key values:
--   e^(-4) ≈ 0.0183  (representable in Q2.13)
--   e^(-1) ≈ 0.368   (representable)
--   e^0    = 1.0     (exact)
--   e^1    ≈ 2.718   (representable)
--   e^1.38 ≈ 3.97    (near saturation)
--   e^x > 4 for x > 1.386 (saturates)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity exp_approximator is
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
        overflow     : out std_logic;  -- Result saturated to max
        underflow    : out std_logic   -- Result saturated to min (near zero)
    );
end entity exp_approximator;

architecture rtl of exp_approximator is

    ---------------------------------------------------------------------------
    -- Constants for Q2.13 format
    ---------------------------------------------------------------------------
    constant ONE       : signed(DATA_WIDTH-1 downto 0) := to_signed(8192, DATA_WIDTH);   -- 1.0
    constant SAT_MAX   : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);  -- ~3.9999
    constant SAT_MIN   : signed(DATA_WIDTH-1 downto 0) := to_signed(1, DATA_WIDTH);      -- ~0.0001 (near zero, not actual zero)
    
    -- Threshold where e^x saturates (x ≈ 1.386 where e^x ≈ 4.0)
    -- 1.386 * 8192 = 11354
    constant SAT_THRESH_POS : signed(DATA_WIDTH-1 downto 0) := to_signed(11354, DATA_WIDTH);
    
    -- Threshold where e^x underflows (x ≈ -9.2 where e^x < 0.0001)
    -- But Q2.13 min is -4.0, so e^(-4) ≈ 0.0183 is representable
    -- We'll use -4.0 * 8192 = -32768 as practical limit
    constant SAT_THRESH_NEG : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH);
    
    ---------------------------------------------------------------------------
    -- Piecewise Linear Approximation LUT
    -- Divide range [-4, 1.5] into 22 segments of 0.25 width each
    -- For each segment, store: slope (m) and y-intercept (b)
    -- e^x ≈ m * x + b for x in segment
    --
    -- Segment index = (x + 4) / 0.25 = (x + 4) * 4
    -- In Q2.13: segment = (data_in + 32768) >> 11  (divide by 2048 = 0.25 in Q2.13)
    ---------------------------------------------------------------------------
    
    -- Number of segments
    constant NUM_SEGMENTS : integer := 24;
    
    -- Slope values in Q2.13 format (derivative of e^x at segment midpoint)
    -- Correctly calculated: slope = e^(x_mid) at midpoint of each segment
    type slope_array_t is array (0 to NUM_SEGMENTS-1) of signed(DATA_WIDTH-1 downto 0);
    constant SLOPES : slope_array_t := (
        to_signed(170, DATA_WIDTH),     -- Segment 0: x in [-4.00, -3.75]
        to_signed(218, DATA_WIDTH),     -- Segment 1: x in [-3.75, -3.50]
        to_signed(280, DATA_WIDTH),     -- Segment 2: x in [-3.50, -3.25]
        to_signed(360, DATA_WIDTH),     -- Segment 3: x in [-3.25, -3.00]
        to_signed(462, DATA_WIDTH),     -- Segment 4: x in [-3.00, -2.75]
        to_signed(593, DATA_WIDTH),     -- Segment 5: x in [-2.75, -2.50]
        to_signed(762, DATA_WIDTH),     -- Segment 6: x in [-2.50, -2.25]
        to_signed(978, DATA_WIDTH),     -- Segment 7: x in [-2.25, -2.00]
        to_signed(1256, DATA_WIDTH),    -- Segment 8: x in [-2.00, -1.75]
        to_signed(1613, DATA_WIDTH),    -- Segment 9: x in [-1.75, -1.50]
        to_signed(2071, DATA_WIDTH),    -- Segment 10: x in [-1.50, -1.25]
        to_signed(2660, DATA_WIDTH),    -- Segment 11: x in [-1.25, -1.00]
        to_signed(3415, DATA_WIDTH),    -- Segment 12: x in [-1.00, -0.75]
        to_signed(4385, DATA_WIDTH),    -- Segment 13: x in [-0.75, -0.50]
        to_signed(5630, DATA_WIDTH),    -- Segment 14: x in [-0.50, -0.25]
        to_signed(7229, DATA_WIDTH),    -- Segment 15: x in [-0.25, 0.00]
        to_signed(9283, DATA_WIDTH),    -- Segment 16: x in [0.00, 0.25]
        to_signed(11919, DATA_WIDTH),   -- Segment 17: x in [0.25, 0.50]
        to_signed(15305, DATA_WIDTH),   -- Segment 18: x in [0.50, 0.75]
        to_signed(19652, DATA_WIDTH),   -- Segment 19: x in [0.75, 1.00]
        to_signed(25233, DATA_WIDTH),   -- Segment 20: x in [1.00, 1.25]
        to_signed(32400, DATA_WIDTH),   -- Segment 21: x in [1.25, 1.50]
        to_signed(32767, DATA_WIDTH),   -- Segment 22: x in [1.50, 1.75] (saturated)
        to_signed(32767, DATA_WIDTH)    -- Segment 23: x in [1.75, 2.00] (saturated)
    );
    
    -- Y-intercept values: b = e^(x_mid) - slope * x_mid = e^(x_mid) * (1 - x_mid)
    -- Correctly calculated for each segment midpoint
    type intercept_array_t is array (0 to NUM_SEGMENTS-1) of signed(DATA_WIDTH-1 downto 0);
    constant INTERCEPTS : intercept_array_t := (
        to_signed(829, DATA_WIDTH),     -- Segment 0: x in [-4.00, -3.75]
        to_signed(1010, DATA_WIDTH),    -- Segment 1: x in [-3.75, -3.50]
        to_signed(1226, DATA_WIDTH),    -- Segment 2: x in [-3.50, -3.25]
        to_signed(1485, DATA_WIDTH),    -- Segment 3: x in [-3.25, -3.00]
        to_signed(1791, DATA_WIDTH),    -- Segment 4: x in [-3.00, -2.75]
        to_signed(2151, DATA_WIDTH),    -- Segment 5: x in [-2.75, -2.50]
        to_signed(2572, DATA_WIDTH),    -- Segment 6: x in [-2.50, -2.25]
        to_signed(3057, DATA_WIDTH),    -- Segment 7: x in [-2.25, -2.00]
        to_signed(3612, DATA_WIDTH),    -- Segment 8: x in [-2.00, -1.75]
        to_signed(4234, DATA_WIDTH),    -- Segment 9: x in [-1.75, -1.50]
        to_signed(4919, DATA_WIDTH),    -- Segment 10: x in [-1.50, -1.25]
        to_signed(5652, DATA_WIDTH),    -- Segment 11: x in [-1.25, -1.00]
        to_signed(6403, DATA_WIDTH),    -- Segment 12: x in [-1.00, -0.75]
        to_signed(7125, DATA_WIDTH),    -- Segment 13: x in [-0.75, -0.50]
        to_signed(7742, DATA_WIDTH),    -- Segment 14: x in [-0.50, -0.25]
        to_signed(8133, DATA_WIDTH),    -- Segment 15: x in [-0.25, 0.00]
        to_signed(8122, DATA_WIDTH),    -- Segment 16: x in [0.00, 0.25]
        to_signed(7450, DATA_WIDTH),    -- Segment 17: x in [0.25, 0.50]
        to_signed(5739, DATA_WIDTH),    -- Segment 18: x in [0.50, 0.75]
        to_signed(2456, DATA_WIDTH),    -- Segment 19: x in [0.75, 1.00]
        to_signed(-3154, DATA_WIDTH),   -- Segment 20: x in [1.00, 1.25]
        to_signed(-12150, DATA_WIDTH),  -- Segment 21: x in [1.25, 1.50]
        to_signed(-26002, DATA_WIDTH),  -- Segment 22: x in [1.50, 1.75]
        to_signed(-32768, DATA_WIDTH)   -- Segment 23: x in [1.75, 2.00]
    );
    
    ---------------------------------------------------------------------------
    -- FSM States
    -- State Machine:
    --   IDLE --> LOOKUP (on start='1')
    --   LOOKUP --> FETCH_LUT (calculate segment index)
    --   FETCH_LUT --> COMPUTE (fetch LUT values - ready next cycle)
    --   COMPUTE --> OUTPUT_ST (compute product with correct LUT values)
    --   OUTPUT_ST --> IDLE (compute final result, assert done)
    -- Total latency: 4 clock cycles from start to done
    ---------------------------------------------------------------------------
    type state_t is (IDLE, LOOKUP, FETCH_LUT, COMPUTE, OUTPUT_ST);
    signal state : state_t;
    
    ---------------------------------------------------------------------------
    -- Internal Signals
    ---------------------------------------------------------------------------
    signal x_reg        : signed(DATA_WIDTH-1 downto 0);
    signal seg_index    : integer range 0 to NUM_SEGMENTS-1;
    signal slope_val    : signed(DATA_WIDTH-1 downto 0);
    signal intercept_val: signed(DATA_WIDTH-1 downto 0);
    
    -- Computation signals
    signal product      : signed(2*DATA_WIDTH-1 downto 0);
    signal sum_val      : signed(DATA_WIDTH+4 downto 0);  -- Extra bits for addition
    
    -- Output registers
    signal result_reg   : signed(DATA_WIDTH-1 downto 0);
    signal done_reg     : std_logic;
    signal ovf_reg      : std_logic;
    signal udf_reg      : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable seg_calc    : signed(DATA_WIDTH+3 downto 0);  -- 20 bits for proper arithmetic
        variable seg_int     : integer;
        variable prod_scaled : signed(DATA_WIDTH+4 downto 0);  -- 21 bits to prevent overflow before saturation
        variable result_val  : signed(DATA_WIDTH+4 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state        <= IDLE;
                x_reg        <= (others => '0');
                seg_index    <= 0;
                slope_val    <= (others => '0');
                intercept_val<= (others => '0');
                result_reg   <= (others => '0');
                done_reg     <= '0';
                ovf_reg      <= '0';
                udf_reg      <= '0';
            else
                done_reg <= '0';
                
                case state is
                    when IDLE =>
                        if start = '1' then
                            x_reg <= data_in;
                            ovf_reg <= '0';
                            udf_reg <= '0';
                            
                            -- Quick saturation check
                            if data_in >= SAT_THRESH_POS then
                                -- e^x overflows for x >= 1.386
                                result_reg <= SAT_MAX;
                                ovf_reg <= '1';
                                done_reg <= '1';
                                -- Stay in IDLE
                            elsif data_in <= to_signed(-30720, DATA_WIDTH) then
                                -- e^x ≈ 0 for very negative x (< -3.75)
                                -- Still compute but expect small result
                                state <= LOOKUP;
                            else
                                state <= LOOKUP;
                            end if;
                        end if;
                    
                    when LOOKUP =>
                        -- Calculate segment index
                        -- segment = (x + 4.0) / 0.25 = (x + 32768) / 2048
                        -- In Q2.13: shift x by adding offset, then divide
                        seg_calc := resize(x_reg, DATA_WIDTH+4) + to_signed(32768, DATA_WIDTH+4);
                        seg_int := to_integer(shift_right(seg_calc, 11));  -- Divide by 2048

                        -- Clamp to valid range
                        if seg_int < 0 then
                            seg_index <= 0;
                        elsif seg_int >= NUM_SEGMENTS then
                            seg_index <= NUM_SEGMENTS - 1;
                        else
                            seg_index <= seg_int;
                        end if;

                        state <= FETCH_LUT;

                    when FETCH_LUT =>
                        -- Fetch LUT values (will be ready next clock cycle)
                        slope_val     <= SLOPES(seg_index);
                        intercept_val <= INTERCEPTS(seg_index);
                        state <= COMPUTE;

                    when COMPUTE =>
                        -- Now slope_val and intercept_val contain correct values
                        -- Compute: result = slope * x + intercept
                        -- slope * x: Q2.13 × Q2.13 = Q4.26
                        product <= slope_val * x_reg;

                        state <= OUTPUT_ST;
                    
                    when OUTPUT_ST =>
                        -- Scale product back to Q2.13 (shift right by 13)
                        -- Add rounding - use wider intermediate to prevent overflow
                        prod_scaled := resize(
                            shift_right(product + to_signed(4096, 2*DATA_WIDTH), FRAC_BITS),
                            DATA_WIDTH+5
                        );

                        -- Add intercept (both are now 21-bit signed)
                        result_val := prod_scaled + resize(intercept_val, DATA_WIDTH+5);
                        
                        -- Saturation
                        if result_val > resize(SAT_MAX, DATA_WIDTH+5) then
                            result_reg <= SAT_MAX;
                            ovf_reg <= '1';
                        elsif result_val < resize(SAT_MIN, DATA_WIDTH+5) then
                            result_reg <= SAT_MIN;
                            udf_reg <= '1';
                        else
                            result_reg <= resize(result_val, DATA_WIDTH);
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
    data_out  <= result_reg;
    done      <= done_reg;
    busy      <= '0' when state = IDLE else '1';
    overflow  <= ovf_reg;
    underflow <= udf_reg;

end architecture rtl;