--------------------------------------------------------------------------------
-- Module: reciprocal_unit
-- Description: Computes 1/d using Newton-Raphson iteration
--              x_{n+1} = x_n * (2 - d * x_n)
--
-- Features:
--   - Configurable iteration count (default 3)
--   - LUT-based initial estimate for fast convergence
--   - Handles sign separately (works on absolute value)
--   - Division-by-zero detection
--   - Overflow saturation on output
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity reciprocal_unit is
    generic (
        DATA_WIDTH     : integer := 16;   -- Q2.13 format
        FRAC_BITS      : integer := 13;
        INTERNAL_WIDTH : integer := 32;   -- Internal precision
        NUM_ITERATIONS : integer := 3;    -- Newton-Raphson iterations
        LUT_ADDR_BITS  : integer := 6     -- 64-entry LUT
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
        
        -- Status flags
        div_by_zero  : out std_logic;
        overflow     : out std_logic
    );
end entity reciprocal_unit;

architecture rtl of reciprocal_unit is

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        NORMALIZE,
        ITERATE,
        DENORMALIZE,
        OUTPUT
    );
    signal state : state_t;
    
    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    -- "2.0" in internal Q4.28 format (4 integer bits, 28 fractional)
    constant INTERNAL_FRAC : integer := INTERNAL_WIDTH - 4;  -- 28 frac bits
    constant TWO : signed(INTERNAL_WIDTH-1 downto 0) := 
        to_signed(2 * (2**INTERNAL_FRAC), INTERNAL_WIDTH);
    
    -- Minimum input magnitude to avoid division by zero
    constant MIN_MAGNITUDE : unsigned(DATA_WIDTH-2 downto 0) := 
        to_unsigned(8, DATA_WIDTH-1);  -- ~0.001 in Q2.13
    
    -- Saturation bounds
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := 
        to_signed(2**(DATA_WIDTH-1) - 1, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := 
        to_signed(-2**(DATA_WIDTH-1), DATA_WIDTH);
    
    ---------------------------------------------------------------------------
    -- LUT for initial estimate (covers normalized range [0.5, 1.0))
    -- Index: upper bits of normalized input
    -- Output: approximate 1/x in Q0.16 format
    ---------------------------------------------------------------------------
    type lut_array_t is array (0 to 2**LUT_ADDR_BITS - 1) of 
        unsigned(DATA_WIDTH-1 downto 0);
    
    -- LUT values: 1/x for x in [0.5 + i/64, 0.5 + (i+1)/64)
    -- Computed as: round(32768 / (0.5 + (i+0.5)/64)) for Q1.15 format
    -- Each entry represents reciprocal of midpoint of its segment
    constant INIT_LUT : lut_array_t := (
        -- i=0..7:   x in [0.500, 0.625)
        x"FC0A", x"F4A6", x"ED66", x"E6C5", x"E03B", x"D9E0", x"D41C", x"CE7B",
        -- i=8..15:  x in [0.625, 0.750)
        x"C912", x"C3CE", x"BECC", x"BA0A", x"B595", x"B0E9", x"AC95", x"A896",
        -- i=16..23: x in [0.750, 0.875)
        x"A45A", x"A06D", x"9CBF", x"98EE", x"9558", x"91DC", x"8E78", x"8B2C",
        -- i=24..31: x in [0.875, 1.000)
        x"87F5", x"84D3", x"81C6", x"7ECE", x"7BEB", x"791C", x"7661", x"73B8",
        -- i=32..39: x in [1.000, 1.125) -- Note: these won't be used after normalization
        x"7123", x"6EA0", x"6C2F", x"69CE", x"677D", x"653C", x"630A", x"60E7",
        -- i=40..47: x in [1.125, 1.250)
        x"5ED3", x"5CCC", x"5AD3", x"58E7", x"5708", x"5536", x"5370", x"51B6",
        -- i=48..55: x in [1.250, 1.375)
        x"5007", x"4E64", x"4CCC", x"4B3E", x"49BA", x"4841", x"46D1", x"456B",
        -- i=56..63: x in [1.375, 1.500)
        x"440E", x"42BA", x"416F", x"402C", x"3EF2", x"3DC0", x"3C96", x"3B74"
    );
    
    ---------------------------------------------------------------------------
    -- Internal Registers (with default initializations to prevent metavalues)
    ---------------------------------------------------------------------------
    signal input_sign    : std_logic := '0';
    signal input_abs     : unsigned(DATA_WIDTH-2 downto 0) := (others => '0');
    signal shift_amount  : integer range 0 to DATA_WIDTH-1 := 0;
    signal normalized    : unsigned(DATA_WIDTH-2 downto 0) := (others => '0');

    -- Newton-Raphson working registers (internal precision)
    signal d_norm        : signed(INTERNAL_WIDTH-1 downto 0) := (others => '0');
    signal x_reg         : signed(INTERNAL_WIDTH-1 downto 0) := (others => '0');
    signal iter_count    : integer range 0 to NUM_ITERATIONS := 0;

    -- Intermediate calculation signals (for debug/observation)
    signal mult_result   : signed(2*INTERNAL_WIDTH-1 downto 0) := (others => '0');
    signal d_times_x     : signed(INTERNAL_WIDTH-1 downto 0) := (others => '0');
    signal two_minus_dx  : signed(INTERNAL_WIDTH-1 downto 0) := (others => '0');

    -- Output registers
    signal result_reg    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal done_reg      : std_logic := '0';
    signal dbz_reg       : std_logic := '0';
    signal ovf_reg       : std_logic := '0';
    
    ---------------------------------------------------------------------------
    -- Functions
    ---------------------------------------------------------------------------
    -- Count leading zeros for normalization
    function count_leading_zeros(val : unsigned) return integer is
        variable count : integer := 0;
    begin
        for i in val'high downto val'low loop
            if val(i) = '1' then
                return count;
            end if;
            count := count + 1;
        end loop;
        return count;
    end function;

begin

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable lut_index   : integer range 0 to 2**LUT_ADDR_BITS - 1;
        variable lut_value   : unsigned(DATA_WIDTH-1 downto 0);
        variable temp_wide   : signed(2*INTERNAL_WIDTH-1 downto 0);
        variable final_val   : signed(INTERNAL_WIDTH-1 downto 0);
        variable out_shifted : signed(INTERNAL_WIDTH-1 downto 0);
        -- Variables for NORMALIZE state
        variable clz_count   : integer range 0 to DATA_WIDTH-1;
        variable norm_val    : unsigned(DATA_WIDTH-2 downto 0);
        -- Variable for absolute value computation
        variable neg_data    : signed(DATA_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state        <= IDLE;
                done_reg     <= '0';
                dbz_reg      <= '0';
                ovf_reg      <= '0';
                result_reg   <= (others => '0');
                iter_count   <= 0;
                x_reg        <= (others => '0');
                -- Initialize all internal signals to prevent metavalue propagation
                input_sign   <= '0';
                input_abs    <= (others => '0');
                shift_amount <= 0;
                normalized   <= (others => '0');
                d_norm       <= (others => '0');
                d_times_x    <= (others => '0');
                two_minus_dx <= (others => '0');
                
            else
                -- Default: clear done after one cycle
                done_reg <= '0';
                
                case state is
                
                    -------------------------------------------------------
                    -- IDLE: Wait for start, capture input
                    -------------------------------------------------------
                    when IDLE =>
                        if start = '1' then
                            -- Extract sign and absolute value
                            input_sign <= data_in(DATA_WIDTH-1);

                            if data_in(DATA_WIDTH-1) = '1' then
                                -- Negative: negate to get absolute value
                                -- For signed negation, we negate and take lower 15 bits directly
                                -- This works because Q2.13 positive range fits in 15 bits
                                neg_data := -data_in;
                                input_abs <= unsigned(neg_data(DATA_WIDTH-2 downto 0));
                            else
                                -- Positive: use as-is (lower 15 bits)
                                input_abs <= unsigned(data_in(DATA_WIDTH-2 downto 0));
                            end if;
                            
                            -- Check for division by zero
                            if abs(data_in) < signed('0' & MIN_MAGNITUDE) then
                                dbz_reg  <= '1';
                                ovf_reg  <= '1';
                                -- Saturate based on sign
                                if data_in(DATA_WIDTH-1) = '1' then
                                    result_reg <= SAT_MIN;
                                else
                                    result_reg <= SAT_MAX;
                                end if;
                                state <= OUTPUT;
                            else
                                dbz_reg <= '0';
                                state   <= NORMALIZE;
                            end if;
                        end if;
                    
                    -------------------------------------------------------
                    -- NORMALIZE: Shift input to [0.5, 1.0) range
                    -------------------------------------------------------
                    when NORMALIZE =>
                        -- Use variables for immediate computation in same clock cycle
                        -- Count leading zeros and compute normalized value
                        clz_count := count_leading_zeros(input_abs);
                        norm_val  := shift_left(input_abs, clz_count);

                        -- Save for denormalization
                        -- The shift amount needs to account for format conversion
                        -- input_abs is magnitude of Q2.13 (has 2 integer bits worth of range)
                        -- After normalization to [0.5, 1.0), we need to track total scaling
                        shift_amount <= clz_count;
                        normalized   <= norm_val;

                        -- Convert normalized value to internal format (Q4.28)
                        -- norm_val is 15 bits with MSB='1' representing [0.5, 1.0) in Q0.15
                        -- To convert Q0.15 to Q4.28: shift left by (28-15) = 13 bits
                        d_norm <= signed(shift_left(resize(norm_val, INTERNAL_WIDTH), 13));

                        -- Get initial estimate from LUT
                        -- Extract upper 6 bits after the leading '1' for LUT indexing
                        lut_index := to_integer(norm_val(DATA_WIDTH-3 downto DATA_WIDTH-3-LUT_ADDR_BITS+1));
                        lut_value := INIT_LUT(lut_index);

                        -- Convert LUT output (Q1.15 unsigned) to internal format (Q4.28)
                        -- LUT gives 1/x for x in [0.5, 1.0), so result is in [1.0, 2.0)
                        -- Q1.15 to Q4.28: shift left by (28-15) = 13 bits
                        x_reg <= signed(shift_left(resize(lut_value, INTERNAL_WIDTH), 13));

                        iter_count <= 0;
                        state <= ITERATE;
                    
                    -------------------------------------------------------
                    -- ITERATE: Newton-Raphson iterations
                    -- x_next = x * (2 - d * x)
                    -------------------------------------------------------
                    when ITERATE =>
                        if iter_count < NUM_ITERATIONS then
                            -- Compute d * x (Q4.28 * Q4.28 = Q8.56, take middle 32 bits)
                            temp_wide := d_norm * x_reg;
                            -- Extract 32 bits from position INTERNAL_FRAC (bit 28) to get Q4.28 result
                            d_times_x <= temp_wide(INTERNAL_FRAC + INTERNAL_WIDTH - 1 downto INTERNAL_FRAC);

                            -- Compute 2 - d*x
                            two_minus_dx <= TWO - temp_wide(INTERNAL_FRAC + INTERNAL_WIDTH - 1 downto INTERNAL_FRAC);

                            -- Compute x * (2 - d*x)
                            temp_wide := x_reg * (TWO - temp_wide(INTERNAL_FRAC + INTERNAL_WIDTH - 1 downto INTERNAL_FRAC));
                            x_reg <= temp_wide(INTERNAL_FRAC + INTERNAL_WIDTH - 1 downto INTERNAL_FRAC);

                            iter_count <= iter_count + 1;
                        else
                            state <= DENORMALIZE;
                        end if;
                    
                    -------------------------------------------------------
                    -- DENORMALIZE: Shift result back
                    -------------------------------------------------------
                    when DENORMALIZE =>
                        -- x_reg contains 1/d_normalized (in Q4.28 format)
                        -- Need to adjust by shift_amount to account for normalization
                        -- If d was shifted left by N to normalize (made larger), the reciprocal
                        -- is correspondingly smaller, so we need to shift LEFT to denormalize

                        -- CRITICAL: Check for overflow BEFORE shifting to prevent wrap-around
                        -- The final result in Q2.13 can represent values up to ~4.0
                        -- In Q4.28 format, 4.0 = 4 * 2^28 = 1,073,741,824
                        -- After denormalization and conversion (shift right by 17), we need
                        -- the intermediate value to fit in 32 bits
                        -- Max safe value before shift: (2^31-1) >> shift_amount
                        -- If x_reg shifted left would overflow, saturate early

                        -- Calculate the maximum safe shift amount
                        -- x_reg should be positive here (we handle sign separately)
                        -- If shift would cause the value to exceed Q2.13 max (~4.0), saturate

                        -- First, do the combined operation more carefully:
                        -- We want: final = (x_reg << shift_amount) >> 17
                        -- Rewrite as: final = x_reg >> (17 - shift_amount) if shift_amount < 17
                        --         or: final = x_reg << (shift_amount - 17) if shift_amount >= 17

                        if shift_amount < (INTERNAL_FRAC - FRAC_BITS + 2) then
                            -- Net right shift: compute result then check overflow
                            final_val := shift_right(x_reg, (INTERNAL_FRAC - FRAC_BITS + 2) - shift_amount);

                            -- Even with right shift, result can exceed Q2.13 max for small inputs
                            if final_val > resize(SAT_MAX, INTERNAL_WIDTH) then
                                final_val := resize(SAT_MAX, INTERNAL_WIDTH);
                                ovf_reg <= '1';
                            elsif final_val < resize(SAT_MIN, INTERNAL_WIDTH) then
                                final_val := resize(SAT_MIN, INTERNAL_WIDTH);
                                ovf_reg <= '1';
                            else
                                ovf_reg <= '0';
                            end if;
                        else
                            -- Net left shift: check for overflow
                            -- Check if result would exceed Q2.13 max
                            -- Q2.13 max is ~4.0, which is 32767 in 16-bit signed
                            -- Check if x_reg >> (17 - shift_amount_extra) > SAT_MAX
                            out_shifted := shift_left(x_reg, shift_amount - (INTERNAL_FRAC - FRAC_BITS + 2));

                            -- Check for overflow (value too large for Q2.13)
                            if out_shifted > resize(SAT_MAX, INTERNAL_WIDTH) then
                                final_val := resize(SAT_MAX, INTERNAL_WIDTH);
                                ovf_reg <= '1';
                            elsif out_shifted < resize(SAT_MIN, INTERNAL_WIDTH) then
                                final_val := resize(SAT_MIN, INTERNAL_WIDTH);
                                ovf_reg <= '1';
                            else
                                final_val := out_shifted;
                                ovf_reg <= '0';
                            end if;
                        end if;

                        -- Apply original sign (using variable, so sequential)
                        if input_sign = '1' then
                            if final_val(DATA_WIDTH-1 downto 0) = SAT_MIN then
                                -- -(-32768) would overflow, keep as SAT_MIN
                                result_reg <= SAT_MIN;
                                ovf_reg <= '1';
                            else
                                result_reg <= -final_val(DATA_WIDTH-1 downto 0);
                            end if;
                        else
                            result_reg <= final_val(DATA_WIDTH-1 downto 0);
                        end if;

                        state <= OUTPUT;
                    
                    -------------------------------------------------------
                    -- OUTPUT: Assert done for one cycle
                    -------------------------------------------------------
                    when OUTPUT =>
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
    data_out    <= result_reg;
    done        <= done_reg;
    busy        <= '0' when state = IDLE else '1';
    div_by_zero <= dbz_reg;
    overflow    <= ovf_reg;

end architecture rtl;