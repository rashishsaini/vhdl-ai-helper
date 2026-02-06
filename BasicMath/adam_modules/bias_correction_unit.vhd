--------------------------------------------------------------------------------
-- Module: bias_correction_unit
-- Description: Applies bias correction to Adam optimizer moments
--              THIS IS WHAT MAKES IT "FULL ADAM" vs SIMPLIFIED ADAM
--
-- Formulas:
--   m̂ = m / (1 - β₁^t)
--   v̂ = v / (1 - β₂^t)
--
-- The bias correction compensates for initialization bias in early training.
-- Effect diminishes as t increases: at t=1, large multiplier; at t→∞, ~1.0
--
-- Format: Q2.13 for moments, Q0.15 for betas
-- Latency: ~32 cycles
--   - Power computation: ~10 cycles (parallel for β₁^t and β₂^t)
--   - Division 1 (m): ~10 cycles
--   - Division 2 (v): ~10 cycles
--   - Overhead: ~2 cycles
--
-- Instantiates:
--   - 2× power_unit (for β₁^t and β₂^t)
--   - 2× division_unit (for m/(1-β₁^t) and v/(1-β₂^t))
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity bias_correction_unit is
    generic (
        DATA_WIDTH : integer := 16;
        BETA_WIDTH : integer := 16;
        EXP_WIDTH  : integer := 14
    );
    port (
        clk   : in std_logic;
        rst   : in std_logic;
        start : in std_logic;

        -- Inputs
        m_in     : in signed(DATA_WIDTH-1 downto 0);  -- Q2.13
        v_in     : in signed(DATA_WIDTH-1 downto 0);  -- Q2.13
        timestep : in unsigned(EXP_WIDTH-1 downto 0);
        beta1    : in signed(BETA_WIDTH-1 downto 0);  -- Q0.15
        beta2    : in signed(BETA_WIDTH-1 downto 0);  -- Q0.15

        -- Outputs
        m_hat    : out signed(DATA_WIDTH-1 downto 0);  -- Q2.13
        v_hat    : out signed(DATA_WIDTH-1 downto 0);  -- Q2.13
        done     : out std_logic;
        busy     : out std_logic;
        overflow : out std_logic
    );
end entity bias_correction_unit;

architecture rtl of bias_correction_unit is

    ---------------------------------------------------------------------------
    -- Component Declarations
    ---------------------------------------------------------------------------
    component power_unit is
        generic (
            DATA_WIDTH : integer := 16;
            EXP_WIDTH  : integer := 14;
            MAX_POWER  : integer := 10000
        );
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            base      : in  signed(15 downto 0);
            exponent  : in  unsigned(13 downto 0);
            start     : in  std_logic;
            result    : out signed(15 downto 0);
            done      : out std_logic;
            busy      : out std_logic;
            underflow : out std_logic
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
        START_POWER,
        WAIT_POWER,
        COMPUTE_DENOM,
        DIV_M,
        WAIT_DIV_M,
        DIV_V,
        WAIT_DIV_V,
        OUTPUT_ST
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant Q0_15_FRAC_BITS : integer := 15;
    constant Q2_13_FRAC_BITS : integer := 13;
    constant ONE_Q0_15 : signed(BETA_WIDTH-1 downto 0) := to_signed(32767, BETA_WIDTH);  -- 1.0 in Q0.15 (0x7FFF, max positive)
    constant MIN_DENOM : signed(BETA_WIDTH-1 downto 0) := to_signed(33, BETA_WIDTH);  -- ~0.001 in Q0.15 (prevent div by 0)

    ---------------------------------------------------------------------------
    -- Power Unit Signals
    ---------------------------------------------------------------------------
    signal power1_start     : std_logic := '0';
    signal power1_result    : signed(BETA_WIDTH-1 downto 0);
    signal power1_done      : std_logic;
    signal power1_busy      : std_logic;
    signal power1_underflow : std_logic;

    signal power2_start     : std_logic := '0';
    signal power2_result    : signed(BETA_WIDTH-1 downto 0);
    signal power2_done      : std_logic;
    signal power2_busy      : std_logic;
    signal power2_underflow : std_logic;

    ---------------------------------------------------------------------------
    -- Division Unit Signals
    ---------------------------------------------------------------------------
    signal div1_start      : std_logic := '0';
    signal div1_dividend   : signed(DATA_WIDTH-1 downto 0);
    signal div1_divisor    : signed(DATA_WIDTH-1 downto 0);
    signal div1_quotient   : signed(DATA_WIDTH-1 downto 0);
    signal div1_done       : std_logic;
    signal div1_busy       : std_logic;
    signal div1_dbz        : std_logic;
    signal div1_overflow   : std_logic;

    signal div2_start      : std_logic := '0';
    signal div2_dividend   : signed(DATA_WIDTH-1 downto 0);
    signal div2_divisor    : signed(DATA_WIDTH-1 downto 0);
    signal div2_quotient   : signed(DATA_WIDTH-1 downto 0);
    signal div2_done       : std_logic;
    signal div2_busy       : std_logic;
    signal div2_dbz        : std_logic;
    signal div2_overflow   : std_logic;

    ---------------------------------------------------------------------------
    -- Internal Registers
    ---------------------------------------------------------------------------
    signal beta1_t         : signed(BETA_WIDTH-1 downto 0) := (others => '0');
    signal beta2_t         : signed(BETA_WIDTH-1 downto 0) := (others => '0');
    signal one_minus_beta1_t : signed(BETA_WIDTH-1 downto 0) := (others => '0');
    signal one_minus_beta2_t : signed(BETA_WIDTH-1 downto 0) := (others => '0');

    signal m_in_reg        : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal v_in_reg        : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- Output Registers
    ---------------------------------------------------------------------------
    signal m_hat_reg  : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal v_hat_reg  : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal done_reg   : std_logic := '0';
    signal ovf_reg    : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Helper function: Convert Q0.15 to Q2.13
    ---------------------------------------------------------------------------
    function q0_15_to_q2_13(val : signed(BETA_WIDTH-1 downto 0)) return signed is
        variable result : signed(DATA_WIDTH-1 downto 0);
    begin
        -- Right shift by 2 bits (15-13 = 2)
        result := shift_right(val, 2);
        return result;
    end function;

begin

    ---------------------------------------------------------------------------
    -- Power Unit Instance 1: β₁^t
    ---------------------------------------------------------------------------
    power1_inst : power_unit
        generic map (
            DATA_WIDTH => BETA_WIDTH,
            EXP_WIDTH  => EXP_WIDTH,
            MAX_POWER  => 10000
        )
        port map (
            clk       => clk,
            rst       => rst,
            base      => beta1,
            exponent  => timestep,
            start     => power1_start,
            result    => power1_result,
            done      => power1_done,
            busy      => power1_busy,
            underflow => power1_underflow
        );

    ---------------------------------------------------------------------------
    -- Power Unit Instance 2: β₂^t
    ---------------------------------------------------------------------------
    power2_inst : power_unit
        generic map (
            DATA_WIDTH => BETA_WIDTH,
            EXP_WIDTH  => EXP_WIDTH,
            MAX_POWER  => 10000
        )
        port map (
            clk       => clk,
            rst       => rst,
            base      => beta2,
            exponent  => timestep,
            start     => power2_start,
            result    => power2_result,
            done      => power2_done,
            busy      => power2_busy,
            underflow => power2_underflow
        );

    ---------------------------------------------------------------------------
    -- Division Unit Instance 1: m / (1 - β₁^t)
    ---------------------------------------------------------------------------
    div1_inst : division_unit
        generic map (
            DATA_WIDTH     => DATA_WIDTH,
            FRAC_BITS      => Q2_13_FRAC_BITS,
            NUM_ITERATIONS => 13  -- Full precision for Q2.13 (16-bit / 2 bits per iteration ≈ 8, use 13 for safety)
        )
        port map (
            clk          => clk,
            rst          => rst,
            dividend     => div1_dividend,
            divisor      => div1_divisor,
            start        => div1_start,
            quotient     => div1_quotient,
            done         => div1_done,
            busy         => div1_busy,
            div_by_zero  => div1_dbz,
            overflow     => div1_overflow
        );

    ---------------------------------------------------------------------------
    -- Division Unit Instance 2: v / (1 - β₂^t)
    ---------------------------------------------------------------------------
    div2_inst : division_unit
        generic map (
            DATA_WIDTH     => DATA_WIDTH,
            FRAC_BITS      => Q2_13_FRAC_BITS,
            NUM_ITERATIONS => 13  -- Full precision for Q2.13
        )
        port map (
            clk          => clk,
            rst          => rst,
            dividend     => div2_dividend,
            divisor      => div2_divisor,
            start        => div2_start,
            quotient     => div2_quotient,
            done         => div2_done,
            busy         => div2_busy,
            div_by_zero  => div2_dbz,
            overflow     => div2_overflow
        );

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable temp_denom : signed(BETA_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state          <= IDLE;
                power1_start   <= '0';
                power2_start   <= '0';
                div1_start     <= '0';
                div2_start     <= '0';
                m_hat_reg      <= (others => '0');
                v_hat_reg      <= (others => '0');
                done_reg       <= '0';
                ovf_reg        <= '0';
            else
                -- Default: clear single-cycle signals
                done_reg     <= '0';
                power1_start <= '0';
                power2_start <= '0';
                div1_start   <= '0';
                div2_start   <= '0';

                case state is
                    when IDLE =>
                        if start = '1' then
                            m_in_reg <= m_in;
                            v_in_reg <= v_in;
                            ovf_reg  <= '0';
                            state    <= START_POWER;
                        end if;

                    when START_POWER =>
                        -- Start both power computations in parallel
                        power1_start <= '1';
                        power2_start <= '1';
                        state <= WAIT_POWER;

                    when WAIT_POWER =>
                        -- Wait for both power units to complete
                        if power1_done = '1' and power2_done = '1' then
                            beta1_t <= power1_result;
                            beta2_t <= power2_result;
                            state <= COMPUTE_DENOM;
                        end if;

                    when COMPUTE_DENOM =>
                        -- Compute 1 - β₁^t and 1 - β₂^t
                        temp_denom := ONE_Q0_15 - beta1_t;
                        if temp_denom < MIN_DENOM and temp_denom >= 0 then
                            one_minus_beta1_t <= MIN_DENOM;
                        elsif temp_denom < 0 then
                            one_minus_beta1_t <= MIN_DENOM;
                        else
                            one_minus_beta1_t <= temp_denom;
                        end if;

                        temp_denom := ONE_Q0_15 - beta2_t;
                        if temp_denom < MIN_DENOM and temp_denom >= 0 then
                            one_minus_beta2_t <= MIN_DENOM;
                        elsif temp_denom < 0 then
                            one_minus_beta2_t <= MIN_DENOM;
                        else
                            one_minus_beta2_t <= temp_denom;
                        end if;

                        state <= DIV_M;

                    when DIV_M =>
                        -- Start division: m / (1 - β₁^t)
                        div1_dividend <= m_in_reg;
                        div1_divisor  <= q0_15_to_q2_13(one_minus_beta1_t);
                        div1_start    <= '1';
                        state <= WAIT_DIV_M;

                    when WAIT_DIV_M =>
                        if div1_done = '1' then
                            m_hat_reg <= div1_quotient;
                            if div1_overflow = '1' or div1_dbz = '1' then
                                ovf_reg <= '1';
                            end if;
                            state <= DIV_V;
                        end if;

                    when DIV_V =>
                        -- Start division: v / (1 - β₂^t)
                        div2_dividend <= v_in_reg;
                        div2_divisor  <= q0_15_to_q2_13(one_minus_beta2_t);
                        div2_start    <= '1';
                        state <= WAIT_DIV_V;

                    when WAIT_DIV_V =>
                        if div2_done = '1' then
                            v_hat_reg <= div2_quotient;
                            if div2_overflow = '1' or div2_dbz = '1' then
                                ovf_reg <= '1';
                            end if;
                            state <= OUTPUT_ST;
                        end if;

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
    m_hat    <= m_hat_reg;
    v_hat    <= v_hat_reg;
    done     <= done_reg;
    busy     <= '0' when state = IDLE else '1';
    overflow <= ovf_reg;

end architecture rtl;
