--------------------------------------------------------------------------------
-- Module: adaptive_lr_unit
-- Description: Computes adaptive learning rate for Adam optimizer
--
-- Formula:
--   update = η × m / (√v + ε)
--
-- Where:
--   m = first moment (or m̂ if bias-corrected)
--   v = second moment (or v̂ if bias-corrected)
--   η = learning rate
--   ε = small constant for numerical stability
--
-- Format: Q2.13 for m, v, update; Q0.15 for η and ε
-- Latency: ~20 cycles
--   - Square root: 5-6 cycles
--   - Division: 8-10 cycles
--   - Multiplication + overhead: ~4 cycles
--
-- Instantiates:
--   - sqrt_unit
--   - division_unit
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity adaptive_lr_unit is
    generic (
        DATA_WIDTH : integer := 16;   -- Q2.13
        LR_WIDTH   : integer := 16    -- Q0.15 for learning rate
    );
    port (
        clk   : in std_logic;
        rst   : in std_logic;
        start : in std_logic;

        -- Inputs (Q2.13 format)
        m_in          : in signed(DATA_WIDTH-1 downto 0);
        v_in          : in signed(DATA_WIDTH-1 downto 0);
        learning_rate : in signed(LR_WIDTH-1 downto 0);  -- Q0.15
        epsilon       : in signed(DATA_WIDTH-1 downto 0); -- Q2.13

        -- Outputs
        update_out   : out signed(DATA_WIDTH-1 downto 0);  -- Q2.13
        done         : out std_logic;
        busy         : out std_logic;
        overflow     : out std_logic;
        div_by_zero  : out std_logic
    );
end entity adaptive_lr_unit;

architecture rtl of adaptive_lr_unit is

    ---------------------------------------------------------------------------
    -- Component Declarations
    ---------------------------------------------------------------------------
    component sqrt_unit is
        generic (
            DATA_WIDTH     : integer := 16;
            FRAC_BITS      : integer := 13;
            NUM_ITERATIONS : integer := 4
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            data_in      : in  signed(15 downto 0);
            start        : in  std_logic;
            data_out     : out signed(15 downto 0);
            done         : out std_logic;
            busy         : out std_logic;
            invalid      : out std_logic;
            overflow     : out std_logic
        );
    end component;

    component division_unit is
        generic (
            DATA_WIDTH     : integer := 16;
            FRAC_BITS      : integer := 13;
            NUM_ITERATIONS : integer := 3
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            dividend     : in  signed(15 downto 0);
            divisor      : in  signed(15 downto 0);
            start        : in  std_logic;
            quotient     : out signed(15 downto 0);
            done         : out std_logic;
            busy         : out std_logic;
            div_by_zero  : out std_logic;
            overflow     : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        START_SQRT,
        WAIT_SQRT,
        ADD_EPS,
        START_DIV,
        WAIT_DIV,
        SCALE_LR,
        OUTPUT_ST
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant Q2_13_FRAC_BITS : integer := 13;
    constant Q0_15_FRAC_BITS : integer := 15;

    -- Saturation limits for Q2.13
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH);

    ---------------------------------------------------------------------------
    -- Square Root Unit Signals
    ---------------------------------------------------------------------------
    signal sqrt_start    : std_logic := '0';
    signal sqrt_input    : signed(DATA_WIDTH-1 downto 0);
    signal sqrt_result   : signed(DATA_WIDTH-1 downto 0);
    signal sqrt_done     : std_logic;
    signal sqrt_busy     : std_logic;
    signal sqrt_invalid  : std_logic;
    signal sqrt_overflow : std_logic;

    ---------------------------------------------------------------------------
    -- Division Unit Signals
    ---------------------------------------------------------------------------
    signal div_start     : std_logic := '0';
    signal div_dividend  : signed(DATA_WIDTH-1 downto 0);
    signal div_divisor   : signed(DATA_WIDTH-1 downto 0);
    signal div_quotient  : signed(DATA_WIDTH-1 downto 0);
    signal div_done      : std_logic;
    signal div_busy      : std_logic;
    signal div_dbz       : std_logic;
    signal div_overflow  : std_logic;

    ---------------------------------------------------------------------------
    -- Internal Registers
    ---------------------------------------------------------------------------
    signal m_reg         : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal v_reg         : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal lr_reg        : signed(LR_WIDTH-1 downto 0) := (others => '0');
    signal eps_reg       : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    signal sqrt_v        : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal denominator   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal ratio         : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- Output Registers
    ---------------------------------------------------------------------------
    signal update_reg    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal done_reg      : std_logic := '0';
    signal ovf_reg       : std_logic := '0';
    signal dbz_reg       : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Multiply Q2.13 × Q0.15 → Q2.13 with saturation
    ---------------------------------------------------------------------------
    function multiply_q2_13_by_q0_15(
        a : signed(DATA_WIDTH-1 downto 0);  -- Q2.13
        b : signed(LR_WIDTH-1 downto 0)     -- Q0.15
    ) return signed is
        variable product     : signed(31 downto 0);
        variable scaled      : signed(DATA_WIDTH-1 downto 0);
        variable product_ext : signed(DATA_WIDTH downto 0);
    begin
        product := a * b;
        scaled := product(Q0_15_FRAC_BITS + DATA_WIDTH - 1 downto Q0_15_FRAC_BITS);

        product_ext := resize(product(Q0_15_FRAC_BITS + DATA_WIDTH downto Q0_15_FRAC_BITS), DATA_WIDTH + 1);
        if product_ext > resize(SAT_MAX, DATA_WIDTH + 1) then
            return SAT_MAX;
        elsif product_ext < resize(SAT_MIN, DATA_WIDTH + 1) then
            return SAT_MIN;
        else
            return scaled;
        end if;
    end function;

    ---------------------------------------------------------------------------
    -- Add with saturation
    ---------------------------------------------------------------------------
    function add_saturate(
        a : signed(DATA_WIDTH-1 downto 0);
        b : signed(DATA_WIDTH-1 downto 0)
    ) return signed is
        variable sum_ext : signed(DATA_WIDTH downto 0);
    begin
        sum_ext := resize(a, DATA_WIDTH + 1) + resize(b, DATA_WIDTH + 1);

        if sum_ext > resize(SAT_MAX, DATA_WIDTH + 1) then
            return SAT_MAX;
        elsif sum_ext < resize(SAT_MIN, DATA_WIDTH + 1) then
            return SAT_MIN;
        else
            return sum_ext(DATA_WIDTH-1 downto 0);
        end if;
    end function;

begin

    ---------------------------------------------------------------------------
    -- Square Root Unit Instance
    ---------------------------------------------------------------------------
    sqrt_inst : sqrt_unit
        generic map (
            DATA_WIDTH     => DATA_WIDTH,
            FRAC_BITS      => Q2_13_FRAC_BITS,
            NUM_ITERATIONS => 4
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_in      => sqrt_input,
            start        => sqrt_start,
            data_out     => sqrt_result,
            done         => sqrt_done,
            busy         => sqrt_busy,
            invalid      => sqrt_invalid,
            overflow     => sqrt_overflow
        );

    ---------------------------------------------------------------------------
    -- Division Unit Instance
    ---------------------------------------------------------------------------
    div_inst : division_unit
        generic map (
            DATA_WIDTH     => DATA_WIDTH,
            FRAC_BITS      => Q2_13_FRAC_BITS,
            NUM_ITERATIONS => 3
        )
        port map (
            clk          => clk,
            rst          => rst,
            dividend     => div_dividend,
            divisor      => div_divisor,
            start        => div_start,
            quotient     => div_quotient,
            done         => div_done,
            busy         => div_busy,
            div_by_zero  => div_dbz,
            overflow     => div_overflow
        );

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state       <= IDLE;
                sqrt_start  <= '0';
                div_start   <= '0';
                update_reg  <= (others => '0');
                done_reg    <= '0';
                ovf_reg     <= '0';
                dbz_reg     <= '0';
            else
                -- Default: clear single-cycle signals
                done_reg   <= '0';
                sqrt_start <= '0';
                div_start  <= '0';

                case state is
                    when IDLE =>
                        if start = '1' then
                            m_reg   <= m_in;
                            v_reg   <= v_in;
                            lr_reg  <= learning_rate;
                            eps_reg <= epsilon;
                            ovf_reg <= '0';
                            dbz_reg <= '0';
                            state   <= START_SQRT;
                        end if;

                    when START_SQRT =>
                        -- Compute √v
                        sqrt_input <= v_reg;
                        sqrt_start <= '1';
                        state <= WAIT_SQRT;

                    when WAIT_SQRT =>
                        if sqrt_done = '1' then
                            sqrt_v <= sqrt_result;
                            if sqrt_invalid = '1' or sqrt_overflow = '1' then
                                ovf_reg <= '1';
                            end if;
                            state <= ADD_EPS;
                        end if;

                    when ADD_EPS =>
                        -- Compute denominator = √v + ε
                        denominator <= add_saturate(sqrt_v, eps_reg);
                        state <= START_DIV;

                    when START_DIV =>
                        -- Compute ratio = m / (√v + ε)
                        div_dividend <= m_reg;
                        div_divisor  <= denominator;
                        div_start    <= '1';
                        state <= WAIT_DIV;

                    when WAIT_DIV =>
                        if div_done = '1' then
                            ratio <= div_quotient;
                            if div_overflow = '1' then
                                ovf_reg <= '1';
                            end if;
                            if div_dbz = '1' then
                                dbz_reg <= '1';
                            end if;
                            state <= SCALE_LR;
                        end if;

                    when SCALE_LR =>
                        -- Compute update = η × ratio
                        update_reg <= multiply_q2_13_by_q0_15(ratio, lr_reg);
                        state <= OUTPUT_ST;

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
    update_out  <= update_reg;
    done        <= done_reg;
    busy        <= '0' when state = IDLE else '1';
    overflow    <= ovf_reg;
    div_by_zero <= dbz_reg;

end architecture rtl;
