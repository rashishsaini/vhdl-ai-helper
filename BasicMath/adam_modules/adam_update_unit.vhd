--------------------------------------------------------------------------------
-- Module: adam_update_unit
-- Description: Complete single-parameter update for Full Adam Optimizer
--
-- Implements complete Adam update sequence:
--   1. Moment update: m_new = β₁×m_old + (1-β₁)×g
--                     v_new = β₂×v_old + (1-β₂)×g²
--   2. Bias correction: m̂ = m_new/(1-β₁^t)  [FULL ADAM]
--                       v̂ = v_new/(1-β₂^t)  [FULL ADAM]
--   3. Adaptive LR: update = η × m̂/(√v̂ + ε)
--   4. Weight update: W_new = W_old - update
--
-- Format: Q2.13 for weights/gradients/moments, Q0.15 for hyperparameters
-- Latency: ~60 cycles per parameter
--   - Moment update: 4 cycles
--   - Bias correction: ~32 cycles (Full Adam)
--   - Adaptive LR: ~20 cycles
--   - Weight update: 1 cycle
--
-- Instantiates:
--   - moment_update_unit
--   - bias_correction_unit (Full Adam)
--   - adaptive_lr_unit
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity adam_update_unit is
    generic (
        DATA_WIDTH : integer := 16;
        BETA_WIDTH : integer := 16;
        EXP_WIDTH  : integer := 14
    );
    port (
        clk   : in std_logic;
        rst   : in std_logic;
        start : in std_logic;

        -- Inputs (Q2.13 format)
        gradient   : in signed(DATA_WIDTH-1 downto 0);
        m_old      : in signed(DATA_WIDTH-1 downto 0);
        v_old      : in signed(DATA_WIDTH-1 downto 0);
        weight_old : in signed(DATA_WIDTH-1 downto 0);
        timestep   : in unsigned(EXP_WIDTH-1 downto 0);

        -- Hyperparameters
        beta1         : in signed(BETA_WIDTH-1 downto 0);  -- Q0.15
        beta2         : in signed(BETA_WIDTH-1 downto 0);  -- Q0.15
        one_minus_beta1 : in signed(BETA_WIDTH-1 downto 0);
        one_minus_beta2 : in signed(BETA_WIDTH-1 downto 0);
        learning_rate : in signed(BETA_WIDTH-1 downto 0);  -- Q0.15
        epsilon       : in signed(DATA_WIDTH-1 downto 0);  -- Q2.13

        -- Outputs (Q2.13 format)
        m_new      : out signed(DATA_WIDTH-1 downto 0);
        v_new      : out signed(DATA_WIDTH-1 downto 0);
        weight_new : out signed(DATA_WIDTH-1 downto 0);
        done       : out std_logic;
        busy       : out std_logic;
        overflow   : out std_logic
    );
end entity adam_update_unit;

architecture rtl of adam_update_unit is

    ---------------------------------------------------------------------------
    -- Component Declarations
    ---------------------------------------------------------------------------
    component moment_update_unit is
        generic (
            DATA_WIDTH : integer := 16;
            BETA_WIDTH : integer := 16
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            start           : in  std_logic;
            gradient        : in  signed(15 downto 0);
            m_old           : in  signed(15 downto 0);
            v_old           : in  signed(15 downto 0);
            beta1           : in  signed(15 downto 0);
            beta2           : in  signed(15 downto 0);
            one_minus_beta1 : in  signed(15 downto 0);
            one_minus_beta2 : in  signed(15 downto 0);
            m_new           : out signed(15 downto 0);
            v_new           : out signed(15 downto 0);
            done            : out std_logic;
            busy            : out std_logic;
            overflow        : out std_logic
        );
    end component;

    component bias_correction_unit is
        generic (
            DATA_WIDTH : integer := 16;
            BETA_WIDTH : integer := 16;
            EXP_WIDTH  : integer := 14
        );
        port (
            clk      : in  std_logic;
            rst      : in  std_logic;
            start    : in  std_logic;
            m_in     : in  signed(15 downto 0);
            v_in     : in  signed(15 downto 0);
            timestep : in  unsigned(13 downto 0);
            beta1    : in  signed(15 downto 0);
            beta2    : in  signed(15 downto 0);
            m_hat    : out signed(15 downto 0);
            v_hat    : out signed(15 downto 0);
            done     : out std_logic;
            busy     : out std_logic;
            overflow : out std_logic
        );
    end component;

    component adaptive_lr_unit is
        generic (
            DATA_WIDTH : integer := 16;
            LR_WIDTH   : integer := 16
        );
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            start         : in  std_logic;
            m_in          : in  signed(15 downto 0);
            v_in          : in  signed(15 downto 0);
            learning_rate : in  signed(15 downto 0);
            epsilon       : in  signed(15 downto 0);
            update_out    : out signed(15 downto 0);
            done          : out std_logic;
            busy          : out std_logic;
            overflow      : out std_logic;
            div_by_zero   : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        UPDATE_MOMENTS,
        WAIT_MOMENTS,
        BIAS_CORRECT,
        WAIT_BIAS,
        ADAPTIVE_LR,
        WAIT_LR,
        UPDATE_WEIGHT,
        OUTPUT_ST
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Saturation Constants
    ---------------------------------------------------------------------------
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH);

    ---------------------------------------------------------------------------
    -- Moment Update Unit Signals
    ---------------------------------------------------------------------------
    signal moment_start    : std_logic := '0';
    signal moment_m_new    : signed(DATA_WIDTH-1 downto 0);
    signal moment_v_new    : signed(DATA_WIDTH-1 downto 0);
    signal moment_done     : std_logic;
    signal moment_busy     : std_logic;
    signal moment_overflow : std_logic;

    ---------------------------------------------------------------------------
    -- Bias Correction Unit Signals
    ---------------------------------------------------------------------------
    signal bias_start    : std_logic := '0';
    signal bias_m_hat    : signed(DATA_WIDTH-1 downto 0);
    signal bias_v_hat    : signed(DATA_WIDTH-1 downto 0);
    signal bias_done     : std_logic;
    signal bias_busy     : std_logic;
    signal bias_overflow : std_logic;

    ---------------------------------------------------------------------------
    -- Adaptive LR Unit Signals
    ---------------------------------------------------------------------------
    signal lr_start      : std_logic := '0';
    signal lr_update     : signed(DATA_WIDTH-1 downto 0);
    signal lr_done       : std_logic;
    signal lr_busy       : std_logic;
    signal lr_overflow   : std_logic;
    signal lr_dbz        : std_logic;

    ---------------------------------------------------------------------------
    -- Internal Registers
    ---------------------------------------------------------------------------
    signal m_new_reg      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal v_new_reg      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal weight_old_reg : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal update_reg     : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- Output Registers
    ---------------------------------------------------------------------------
    signal weight_new_reg : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal done_reg       : std_logic := '0';
    signal ovf_reg        : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Subtract with saturation
    ---------------------------------------------------------------------------
    function subtract_saturate(
        a : signed(DATA_WIDTH-1 downto 0);
        b : signed(DATA_WIDTH-1 downto 0)
    ) return signed is
        variable diff_ext : signed(DATA_WIDTH downto 0);
    begin
        diff_ext := resize(a, DATA_WIDTH + 1) - resize(b, DATA_WIDTH + 1);

        if diff_ext > resize(SAT_MAX, DATA_WIDTH + 1) then
            return SAT_MAX;
        elsif diff_ext < resize(SAT_MIN, DATA_WIDTH + 1) then
            return SAT_MIN;
        else
            return diff_ext(DATA_WIDTH-1 downto 0);
        end if;
    end function;

begin

    ---------------------------------------------------------------------------
    -- Moment Update Unit Instance
    ---------------------------------------------------------------------------
    moment_inst : moment_update_unit
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            BETA_WIDTH => BETA_WIDTH
        )
        port map (
            clk             => clk,
            rst             => rst,
            start           => moment_start,
            gradient        => gradient,
            m_old           => m_old,
            v_old           => v_old,
            beta1           => beta1,
            beta2           => beta2,
            one_minus_beta1 => one_minus_beta1,
            one_minus_beta2 => one_minus_beta2,
            m_new           => moment_m_new,
            v_new           => moment_v_new,
            done            => moment_done,
            busy            => moment_busy,
            overflow        => moment_overflow
        );

    ---------------------------------------------------------------------------
    -- Bias Correction Unit Instance (FULL ADAM)
    ---------------------------------------------------------------------------
    bias_inst : bias_correction_unit
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            BETA_WIDTH => BETA_WIDTH,
            EXP_WIDTH  => EXP_WIDTH
        )
        port map (
            clk      => clk,
            rst      => rst,
            start    => bias_start,
            m_in     => m_new_reg,
            v_in     => v_new_reg,
            timestep => timestep,
            beta1    => beta1,
            beta2    => beta2,
            m_hat    => bias_m_hat,
            v_hat    => bias_v_hat,
            done     => bias_done,
            busy     => bias_busy,
            overflow => bias_overflow
        );

    ---------------------------------------------------------------------------
    -- Adaptive Learning Rate Unit Instance
    ---------------------------------------------------------------------------
    lr_inst : adaptive_lr_unit
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            LR_WIDTH   => BETA_WIDTH
        )
        port map (
            clk           => clk,
            rst           => rst,
            start         => lr_start,
            m_in          => bias_m_hat,
            v_in          => bias_v_hat,
            learning_rate => learning_rate,
            epsilon       => epsilon,
            update_out    => lr_update,
            done          => lr_done,
            busy          => lr_busy,
            overflow      => lr_overflow,
            div_by_zero   => lr_dbz
        );

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state         <= IDLE;
                moment_start  <= '0';
                bias_start    <= '0';
                lr_start      <= '0';
                m_new_reg     <= (others => '0');
                v_new_reg     <= (others => '0');
                weight_new_reg <= (others => '0');
                done_reg      <= '0';
                ovf_reg       <= '0';
            else
                -- Default: clear single-cycle signals
                done_reg     <= '0';
                moment_start <= '0';
                bias_start   <= '0';
                lr_start     <= '0';

                case state is
                    when IDLE =>
                        if start = '1' then
                            weight_old_reg <= weight_old;
                            ovf_reg        <= '0';
                            state          <= UPDATE_MOMENTS;
                        end if;

                    when UPDATE_MOMENTS =>
                        moment_start <= '1';
                        state <= WAIT_MOMENTS;

                    when WAIT_MOMENTS =>
                        if moment_done = '1' then
                            m_new_reg <= moment_m_new;
                            v_new_reg <= moment_v_new;
                            if moment_overflow = '1' then
                                ovf_reg <= '1';
                            end if;
                            state <= BIAS_CORRECT;
                        end if;

                    when BIAS_CORRECT =>
                        -- Full Adam: Apply bias correction
                        bias_start <= '1';
                        state <= WAIT_BIAS;

                    when WAIT_BIAS =>
                        if bias_done = '1' then
                            if bias_overflow = '1' then
                                ovf_reg <= '1';
                            end if;
                            state <= ADAPTIVE_LR;
                        end if;

                    when ADAPTIVE_LR =>
                        lr_start <= '1';
                        state <= WAIT_LR;

                    when WAIT_LR =>
                        if lr_done = '1' then
                            update_reg <= lr_update;
                            if lr_overflow = '1' or lr_dbz = '1' then
                                ovf_reg <= '1';
                            end if;
                            state <= UPDATE_WEIGHT;
                        end if;

                    when UPDATE_WEIGHT =>
                        -- W_new = W_old - update
                        weight_new_reg <= subtract_saturate(weight_old_reg, update_reg);
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
    m_new      <= m_new_reg;
    v_new      <= v_new_reg;
    weight_new <= weight_new_reg;
    done       <= done_reg;
    busy       <= '0' when state = IDLE else '1';
    overflow   <= ovf_reg;

end architecture rtl;
