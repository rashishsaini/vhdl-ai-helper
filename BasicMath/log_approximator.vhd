--------------------------------------------------------------------------------
-- Module: log_approximator
-- Description: Computes natural logarithm ln(x) using piecewise linear approx
--              Optimized for neural network applications
--
-- Format: Q2.13 input/output (16-bit signed)
-- Method: Piecewise linear interpolation with lookup table
-- Input Range: x in (0, 4) - positive values only
-- Output Range: ln(x) in (-inf, 1.386) - clamped to Q2.13 range
--
-- Key values:
--   ln(0.05) ≈ -3.0    (representable)
--   ln(0.1)  ≈ -2.303  (representable)
--   ln(0.5)  ≈ -0.693  (representable)
--   ln(1)    = 0       (exact)
--   ln(2)    ≈ 0.693   (representable)
--   ln(e)    = 1       (exact)
--   ln(4)    ≈ 1.386   (representable)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity log_approximator is
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
        invalid      : out std_logic;  -- Input <= 0 (ln undefined)
        overflow     : out std_logic   -- Result out of range
    );
end entity log_approximator;

architecture rtl of log_approximator is

    ---------------------------------------------------------------------------
    -- Constants for Q2.13 format
    ---------------------------------------------------------------------------
    constant ONE       : signed(DATA_WIDTH-1 downto 0) := to_signed(8192, DATA_WIDTH);   -- 1.0
    constant SAT_MAX   : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);  -- ~3.9999
    constant SAT_MIN   : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH); -- -4.0
    
    -- Minimum valid input (ln approaches -inf as x approaches 0)
    -- We'll clamp ln to -4.0 for very small x
    -- Values below ~0.05 are outside the piecewise approximation range
    -- and would require extrapolation with large errors
    constant MIN_INPUT : signed(DATA_WIDTH-1 downto 0) := to_signed(410, DATA_WIDTH);  -- ~0.05

    -- Maximum valid input (design range is [0, 4])
    -- ln(4) ≈ 1.386 which fits in Q2.13
    constant MAX_INPUT : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);  -- ~4.0
    constant LN_4      : signed(DATA_WIDTH-1 downto 0) := to_signed(11356, DATA_WIDTH);  -- ln(4) ≈ 1.386

    ---------------------------------------------------------------------------
    -- Piecewise Linear Approximation LUT
    -- Divide range [0.0625, 4.0] into segments
    -- Use non-uniform segmentation: finer near 0, coarser near 4
    --
    -- Segment boundaries (in Q2.13):
    -- Seg 0:  [0.0625, 0.125)  - very small values
    -- Seg 1:  [0.125, 0.25)
    -- Seg 2:  [0.25, 0.375)
    -- Seg 3:  [0.375, 0.5)
    -- Seg 4:  [0.5, 0.625)
    -- Seg 5:  [0.625, 0.75)
    -- Seg 6:  [0.75, 0.875)
    -- Seg 7:  [0.875, 1.0)
    -- Seg 8:  [1.0, 1.25)
    -- Seg 9:  [1.25, 1.5)
    -- Seg 10: [1.5, 1.75)
    -- Seg 11: [1.75, 2.0)
    -- Seg 12: [2.0, 2.5)
    -- Seg 13: [2.5, 3.0)
    -- Seg 14: [3.0, 3.5)
    -- Seg 15: [3.5, 4.0)
    ---------------------------------------------------------------------------
    
    constant NUM_SEGMENTS : integer := 16;
    
    -- Segment boundaries in Q2.13 format
    type boundary_array_t is array (0 to NUM_SEGMENTS) of signed(DATA_WIDTH-1 downto 0);
    constant BOUNDARIES : boundary_array_t := (
        to_signed(512, DATA_WIDTH),    -- 0: 0.0625
        to_signed(1024, DATA_WIDTH),   -- 1: 0.125
        to_signed(2048, DATA_WIDTH),   -- 2: 0.25
        to_signed(3072, DATA_WIDTH),   -- 3: 0.375
        to_signed(4096, DATA_WIDTH),   -- 4: 0.5
        to_signed(5120, DATA_WIDTH),   -- 5: 0.625
        to_signed(6144, DATA_WIDTH),   -- 6: 0.75
        to_signed(7168, DATA_WIDTH),   -- 7: 0.875
        to_signed(8192, DATA_WIDTH),   -- 8: 1.0
        to_signed(10240, DATA_WIDTH),  -- 9: 1.25
        to_signed(12288, DATA_WIDTH),  -- 10: 1.5
        to_signed(14336, DATA_WIDTH),  -- 11: 1.75
        to_signed(16384, DATA_WIDTH),  -- 12: 2.0
        to_signed(20480, DATA_WIDTH),  -- 13: 2.5
        to_signed(24576, DATA_WIDTH),  -- 14: 3.0
        to_signed(28672, DATA_WIDTH),  -- 15: 3.5
        to_signed(32767, DATA_WIDTH)   -- 16: 4.0 (upper bound)
    );
    
    -- Slope values in Q2.13 format
    -- For ln(x), derivative = 1/x
    -- At segment midpoint x_mid, slope = 1/x_mid
    type slope_array_t is array (0 to NUM_SEGMENTS-1) of signed(DATA_WIDTH-1 downto 0);
    constant SLOPES : slope_array_t := (
        -- Seg 0: midpoint 0.09375, slope = 1/0.09375 = 10.67 (clamped)
        to_signed(32767, DATA_WIDTH),   -- Clamped (actual ~87381)
        -- Seg 1: midpoint 0.1875, slope = 1/0.1875 = 5.33 (clamped)  
        to_signed(32767, DATA_WIDTH),   -- Clamped (actual ~43691)
        -- Seg 2: midpoint 0.3125, slope = 1/0.3125 = 3.2
        to_signed(26214, DATA_WIDTH),   -- 3.2 * 8192
        -- Seg 3: midpoint 0.4375, slope = 1/0.4375 = 2.286
        to_signed(18725, DATA_WIDTH),   -- 2.286 * 8192
        -- Seg 4: midpoint 0.5625, slope = 1/0.5625 = 1.778
        to_signed(14564, DATA_WIDTH),   -- 1.778 * 8192
        -- Seg 5: midpoint 0.6875, slope = 1/0.6875 = 1.455
        to_signed(11916, DATA_WIDTH),   -- 1.455 * 8192
        -- Seg 6: midpoint 0.8125, slope = 1/0.8125 = 1.231
        to_signed(10082, DATA_WIDTH),   -- 1.231 * 8192
        -- Seg 7: midpoint 0.9375, slope = 1/0.9375 = 1.067
        to_signed(8738, DATA_WIDTH),    -- 1.067 * 8192
        -- Seg 8: midpoint 1.125, slope = 1/1.125 = 0.889
        to_signed(7282, DATA_WIDTH),    -- 0.889 * 8192
        -- Seg 9: midpoint 1.375, slope = 1/1.375 = 0.727
        to_signed(5958, DATA_WIDTH),    -- 0.727 * 8192
        -- Seg 10: midpoint 1.625, slope = 1/1.625 = 0.615
        to_signed(5041, DATA_WIDTH),    -- 0.615 * 8192
        -- Seg 11: midpoint 1.875, slope = 1/1.875 = 0.533
        to_signed(4369, DATA_WIDTH),    -- 0.533 * 8192
        -- Seg 12: midpoint 2.25, slope = 1/2.25 = 0.444
        to_signed(3641, DATA_WIDTH),    -- 0.444 * 8192
        -- Seg 13: midpoint 2.75, slope = 1/2.75 = 0.364
        to_signed(2979, DATA_WIDTH),    -- 0.364 * 8192
        -- Seg 14: midpoint 3.25, slope = 1/3.25 = 0.308
        to_signed(2521, DATA_WIDTH),    -- 0.308 * 8192
        -- Seg 15: midpoint 3.75, slope = 1/3.75 = 0.267
        to_signed(2185, DATA_WIDTH)     -- 0.267 * 8192
    );
    
    -- Intercept values in Q2.13 format
    -- For each segment: b = ln(x_mid) - slope * x_mid
    -- Note: For segments 0-1 where slope is clamped, recalculate intercept
    -- using the actual clamped slope value, not the ideal slope
    type intercept_array_t is array (0 to NUM_SEGMENTS-1) of signed(DATA_WIDTH-1 downto 0);
    constant INTERCEPTS : intercept_array_t := (
        -- Seg 0: x_mid=0.09375, ln(0.09375)=-2.368
        -- With clamped slope=3.9999, b = -2.368 - 3.9999*0.09375 = -2.743
        to_signed(-22471, DATA_WIDTH),  -- -2.743 * 8192
        -- Seg 1: x_mid=0.1875, ln(0.1875)=-1.674
        -- With clamped slope=3.9999, b = -1.674 - 3.9999*0.1875 = -2.424
        to_signed(-19858, DATA_WIDTH),  -- -2.424 * 8192
        -- Seg 2: ln(0.3125) - 1 ≈ -1.163 - 1 = -2.163
        to_signed(-17722, DATA_WIDTH),  -- -2.163 * 8192
        -- Seg 3: ln(0.4375) - 1 ≈ -0.827 - 1 = -1.827
        to_signed(-14970, DATA_WIDTH),  -- -1.827 * 8192
        -- Seg 4: ln(0.5625) - 1 ≈ -0.576 - 1 = -1.576
        to_signed(-12910, DATA_WIDTH),  -- -1.576 * 8192
        -- Seg 5: ln(0.6875) - 1 ≈ -0.375 - 1 = -1.375
        to_signed(-11264, DATA_WIDTH),  -- -1.375 * 8192
        -- Seg 6: ln(0.8125) - 1 ≈ -0.208 - 1 = -1.208
        to_signed(-9895, DATA_WIDTH),   -- -1.208 * 8192
        -- Seg 7: ln(0.9375) - 1 ≈ -0.065 - 1 = -1.065
        to_signed(-8724, DATA_WIDTH),   -- -1.065 * 8192
        -- Seg 8: ln(1.125) - 1 ≈ 0.118 - 1 = -0.882
        to_signed(-7225, DATA_WIDTH),   -- -0.882 * 8192
        -- Seg 9: ln(1.375) - 1 ≈ 0.318 - 1 = -0.682
        to_signed(-5590, DATA_WIDTH),   -- -0.682 * 8192
        -- Seg 10: ln(1.625) - 1 ≈ 0.486 - 1 = -0.514
        to_signed(-4211, DATA_WIDTH),   -- -0.514 * 8192
        -- Seg 11: ln(1.875) - 1 ≈ 0.629 - 1 = -0.371
        to_signed(-3040, DATA_WIDTH),   -- -0.371 * 8192
        -- Seg 12: ln(2.25) - 1 ≈ 0.811 - 1 = -0.189
        to_signed(-1549, DATA_WIDTH),   -- -0.189 * 8192
        -- Seg 13: ln(2.75) - 1 ≈ 1.012 - 1 = 0.012
        to_signed(98, DATA_WIDTH),      -- 0.012 * 8192
        -- Seg 14: ln(3.25) - 1 ≈ 1.179 - 1 = 0.179
        to_signed(1466, DATA_WIDTH),    -- 0.179 * 8192
        -- Seg 15: ln(3.75) - 1 ≈ 1.322 - 1 = 0.322
        to_signed(2638, DATA_WIDTH)     -- 0.322 * 8192
    );

    ---------------------------------------------------------------------------
    -- FSM States
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
    
    -- Output registers
    signal result_reg   : signed(DATA_WIDTH-1 downto 0);
    signal done_reg     : std_logic;
    signal invalid_reg  : std_logic;
    signal ovf_reg      : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable seg_found   : boolean;
        variable prod_scaled : signed(DATA_WIDTH+4 downto 0);
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
                invalid_reg  <= '0';
                ovf_reg      <= '0';
            else
                done_reg <= '0';
                
                case state is
                    when IDLE =>
                        if start = '1' then
                            x_reg <= data_in;
                            invalid_reg <= '0';
                            ovf_reg <= '0';
                            
                            -- Check for invalid input (x <= 0)
                            if data_in <= to_signed(0, DATA_WIDTH) then
                                invalid_reg <= '1';
                                result_reg <= SAT_MIN;  -- Return -4.0 for invalid
                                done_reg <= '1';
                                -- Stay in IDLE
                            -- Check for very small input (ln approaches -inf)
                            elsif data_in < MIN_INPUT then
                                ovf_reg <= '1';
                                result_reg <= SAT_MIN;  -- Clamp to -4.0
                                done_reg <= '1';
                                -- Stay in IDLE
                            -- Check for input above valid range (x > 4)
                            elsif data_in >= MAX_INPUT then
                                ovf_reg <= '1';
                                result_reg <= LN_4;  -- Return ln(4) ≈ 1.386
                                done_reg <= '1';
                                -- Stay in IDLE
                            else
                                state <= LOOKUP;
                            end if;
                        end if;
                    
                    when LOOKUP =>
                        -- Find segment index using linear search
                        seg_found := false;

                        -- Handle values below first boundary - use segment 0
                        if x_reg < BOUNDARIES(0) then
                            seg_index <= 0;
                            seg_found := true;
                        else
                            for i in 0 to NUM_SEGMENTS-1 loop
                                if not seg_found then
                                    if x_reg >= BOUNDARIES(i) and x_reg < BOUNDARIES(i+1) then
                                        seg_index <= i;
                                        seg_found := true;
                                    end if;
                                end if;
                            end loop;
                        end if;

                        -- Default to last segment if above upper bound
                        if not seg_found then
                            seg_index <= NUM_SEGMENTS - 1;
                        end if;

                        state <= FETCH_LUT;
                    
                    when FETCH_LUT =>
                        -- Fetch LUT values (will be ready next cycle)
                        slope_val     <= SLOPES(seg_index);
                        intercept_val <= INTERCEPTS(seg_index);
                        state <= COMPUTE;
                    
                    when COMPUTE =>
                        -- Compute: result = slope * x + intercept
                        -- slope * x: Q2.13 × Q2.13 = Q4.26
                        product <= slope_val * x_reg;
                        state <= OUTPUT_ST;
                    
                    when OUTPUT_ST =>
                        -- Scale product back to Q2.13 (shift right by 13)
                        -- Add rounding
                        prod_scaled := resize(
                            shift_right(product + to_signed(4096, 2*DATA_WIDTH), FRAC_BITS),
                            DATA_WIDTH+5
                        );
                        
                        -- Add intercept
                        result_val := prod_scaled + resize(intercept_val, DATA_WIDTH+5);
                        
                        -- Saturation
                        if result_val > resize(SAT_MAX, DATA_WIDTH+5) then
                            result_reg <= SAT_MAX;
                            ovf_reg <= '1';
                        elsif result_val < resize(SAT_MIN, DATA_WIDTH+5) then
                            result_reg <= SAT_MIN;
                            ovf_reg <= '1';
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
    invalid   <= invalid_reg;
    overflow  <= ovf_reg;

end architecture rtl;