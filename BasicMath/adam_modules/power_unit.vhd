--------------------------------------------------------------------------------
-- Module: power_unit
-- Description: Computes base^exponent using binary exponentiation (fast power)
--              Used for computing β₁^t and β₂^t in Adam bias correction
--
-- Algorithm: Binary exponentiation (exponentiation by squaring)
--            result = 1
--            while exp > 0:
--                if exp is odd: result = result × base
--                base = base × base
--                exp = exp // 2
--
-- Format: Q0.15 input/output (16-bit for beta coefficients in range [0, 1))
-- Latency: O(log₂(exponent)) cycles
--          - exponent=1: 1 cycle
--          - exponent=10: ~4 cycles
--          - exponent=100: ~7 cycles
--          - exponent=1000: ~10 cycles
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity power_unit is
    generic (
        DATA_WIDTH : integer := 16;     -- 16-bit for Q0.15
        EXP_WIDTH  : integer := 14;     -- 14-bit exponent (max 16383)
        MAX_POWER  : integer := 10000   -- Maximum exponent value
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;

        -- Input interface
        base      : in  signed(DATA_WIDTH-1 downto 0);  -- Q0.15 format
        exponent  : in  unsigned(EXP_WIDTH-1 downto 0);
        start     : in  std_logic;

        -- Output interface
        result    : out signed(DATA_WIDTH-1 downto 0);  -- Q0.15 format
        done      : out std_logic;
        busy      : out std_logic;

        -- Status flags
        underflow : out std_logic  -- Result too small (< min representable)
    );
end entity power_unit;

architecture rtl of power_unit is

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (IDLE, INIT, COMPUTE, OUTPUT_ST);
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Constants (Q0.15 format)
    ---------------------------------------------------------------------------
    constant FRAC_BITS : integer := 15;  -- Q0.15 has 15 fractional bits
    constant ONE       : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);  -- 1.0 in Q0.15 (0x7FFF, max positive)

    -- Underflow threshold (very small value close to 0)
    constant UNDERFLOW_THRESHOLD : signed(DATA_WIDTH-1 downto 0) := to_signed(1, DATA_WIDTH);  -- ~0.000031

    ---------------------------------------------------------------------------
    -- Working Registers
    ---------------------------------------------------------------------------
    signal base_reg    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal exp_reg     : unsigned(EXP_WIDTH-1 downto 0) := (others => '0');
    signal result_reg  : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal done_reg    : std_logic := '0';
    signal underflow_reg : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Temporary multiplication result (32-bit to hold Q0.30 product)
    ---------------------------------------------------------------------------
    signal product_temp : signed(2*DATA_WIDTH-1 downto 0);

begin

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable temp_product   : signed(2*DATA_WIDTH-1 downto 0);
        variable scaled_product : signed(DATA_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state         <= IDLE;
                base_reg      <= (others => '0');
                exp_reg       <= (others => '0');
                result_reg    <= (others => '0');
                done_reg      <= '0';
                underflow_reg <= '0';
            else
                -- Default: clear single-cycle signals
                done_reg <= '0';

                case state is
                    ---------------------------------------------------------------------------
                    when IDLE =>
                        if start = '1' then
                            -- Capture inputs
                            base_reg      <= base;
                            exp_reg       <= exponent;
                            underflow_reg <= '0';

                            -- Check for special cases
                            if exponent = 0 then
                                -- base^0 = 1
                                result_reg <= ONE;
                                state <= OUTPUT_ST;
                            elsif exponent = 1 then
                                -- base^1 = base
                                result_reg <= base;
                                state <= OUTPUT_ST;
                            else
                                -- Go to initialization
                                state <= INIT;
                            end if;
                        end if;

                    ---------------------------------------------------------------------------
                    when INIT =>
                        -- Initialize result = 1.0
                        result_reg <= ONE;
                        state <= COMPUTE;

                    ---------------------------------------------------------------------------
                    when COMPUTE =>
                        -- Binary exponentiation main loop

                        if exp_reg = 0 then
                            -- Computation complete

                            -- Check for underflow
                            if result_reg > 0 and result_reg < UNDERFLOW_THRESHOLD then
                                underflow_reg <= '1';
                                result_reg <= UNDERFLOW_THRESHOLD;  -- Clamp to minimum
                            end if;

                            state <= OUTPUT_ST;
                        else
                            -- Check if exponent is odd
                            if exp_reg(0) = '1' then
                                -- result = result × base
                                temp_product := result_reg * base_reg;
                                -- Scale from Q0.30 to Q0.15 (shift right by 15)
                                result_reg <= temp_product(FRAC_BITS + DATA_WIDTH - 1 downto FRAC_BITS);
                            end if;

                            -- base = base × base
                            temp_product := base_reg * base_reg;
                            base_reg <= temp_product(FRAC_BITS + DATA_WIDTH - 1 downto FRAC_BITS);

                            -- exp = exp / 2 (right shift)
                            exp_reg <= shift_right(exp_reg, 1);
                        end if;

                    ---------------------------------------------------------------------------
                    when OUTPUT_ST =>
                        -- Assert done for one cycle
                        done_reg <= '1';
                        state <= IDLE;

                    ---------------------------------------------------------------------------
                    when others =>
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    result    <= result_reg;
    done      <= done_reg;
    busy      <= '0' when state = IDLE else '1';
    underflow <= underflow_reg;

end architecture rtl;
