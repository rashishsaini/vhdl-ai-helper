--------------------------------------------------------------------------------
-- Module: moment_update_unit
-- Description: Updates first and second moments for Adam optimizer
--
-- Formulas:
--   m_new = β₁ × m_old + (1-β₁) × g
--   v_new = β₂ × v_old + (1-β₂) × g²
--
-- Format: Q2.13 for gradients and moments, Q0.15 for beta coefficients
-- Latency: 4 clock cycles (pipelined)
--
-- Pipeline:
--   Cycle 1: Compute g² and β₁ × m_old
--   Cycle 2: Compute (1-β₁) × g and β₂ × v_old
--   Cycle 3: Compute (1-β₂) × g² and sum for m_new
--   Cycle 4: Sum for v_new, saturate, assert done
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity moment_update_unit is
    generic (
        DATA_WIDTH : integer := 16;    -- Q2.13 format
        BETA_WIDTH : integer := 16     -- Q0.15 format for beta
    );
    port (
        clk   : in std_logic;
        rst   : in std_logic;
        start : in std_logic;

        -- Inputs (Q2.13 format for gradient and moments)
        gradient        : in signed(DATA_WIDTH-1 downto 0);
        m_old           : in signed(DATA_WIDTH-1 downto 0);
        v_old           : in signed(DATA_WIDTH-1 downto 0);

        -- Beta coefficients (Q0.15 format)
        beta1           : in signed(BETA_WIDTH-1 downto 0);
        beta2           : in signed(BETA_WIDTH-1 downto 0);
        one_minus_beta1 : in signed(BETA_WIDTH-1 downto 0);
        one_minus_beta2 : in signed(BETA_WIDTH-1 downto 0);

        -- Outputs (Q2.13 format)
        m_new    : out signed(DATA_WIDTH-1 downto 0);
        v_new    : out signed(DATA_WIDTH-1 downto 0);
        done     : out std_logic;
        busy     : out std_logic;
        overflow : out std_logic
    );
end entity moment_update_unit;

architecture rtl of moment_update_unit is

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (IDLE, CYCLE1, CYCLE2, CYCLE3, CYCLE4);
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant Q2_13_FRAC_BITS : integer := 13;
    constant Q0_15_FRAC_BITS : integer := 15;

    -- Saturation limits for Q2.13
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);   -- 3.999878
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH);  -- -4.0

    ---------------------------------------------------------------------------
    -- Pipeline Registers
    ---------------------------------------------------------------------------
    signal g_squared         : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal beta1_m           : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal beta2_v           : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal one_minus_beta1_g : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal one_minus_beta2_g2: signed(DATA_WIDTH-1 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- Output Registers
    ---------------------------------------------------------------------------
    signal m_new_reg  : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal v_new_reg  : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal done_reg   : std_logic := '0';
    signal ovf_reg    : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Multiply Helper Function
    -- Multiplies Q2.13 × Q0.15 → Q2.13 with saturation
    ---------------------------------------------------------------------------
    function multiply_q2_13_by_q0_15(
        a : signed(DATA_WIDTH-1 downto 0);  -- Q2.13
        b : signed(BETA_WIDTH-1 downto 0)   -- Q0.15
    ) return signed is
        variable product     : signed(31 downto 0);
        variable scaled      : signed(DATA_WIDTH-1 downto 0);
        variable product_ext : signed(DATA_WIDTH downto 0);
    begin
        -- Multiply (Q2.13 × Q0.15 = Q2.28, stored in 32 bits)
        product := a * b;

        -- Scale to Q2.13 by shifting right 15 bits
        -- Extract bits [28:13] from product
        scaled := product(Q0_15_FRAC_BITS + DATA_WIDTH - 1 downto Q0_15_FRAC_BITS);

        -- Saturate
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
    -- Multiply Q2.13 × Q2.13 → Q2.13 (for g²)
    ---------------------------------------------------------------------------
    function multiply_q2_13(
        a : signed(DATA_WIDTH-1 downto 0);
        b : signed(DATA_WIDTH-1 downto 0)
    ) return signed is
        variable product     : signed(31 downto 0);
        variable scaled      : signed(DATA_WIDTH-1 downto 0);
        variable product_ext : signed(DATA_WIDTH downto 0);
    begin
        product := a * b;
        scaled := product(Q2_13_FRAC_BITS + DATA_WIDTH - 1 downto Q2_13_FRAC_BITS);

        product_ext := resize(product(Q2_13_FRAC_BITS + DATA_WIDTH downto Q2_13_FRAC_BITS), DATA_WIDTH + 1);
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
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable m_temp : signed(DATA_WIDTH-1 downto 0);
        variable v_temp : signed(DATA_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state         <= IDLE;
                m_new_reg     <= (others => '0');
                v_new_reg     <= (others => '0');
                done_reg      <= '0';
                ovf_reg       <= '0';
                g_squared     <= (others => '0');
                beta1_m       <= (others => '0');
                beta2_v       <= (others => '0');
                one_minus_beta1_g  <= (others => '0');
                one_minus_beta2_g2 <= (others => '0');
            else
                -- Default: clear done
                done_reg <= '0';

                case state is
                    when IDLE =>
                        if start = '1' then
                            ovf_reg <= '0';
                            state <= CYCLE1;
                        end if;

                    when CYCLE1 =>
                        -- Compute g² (Q2.13 × Q2.13 → Q2.13)
                        g_squared <= multiply_q2_13(gradient, gradient);

                        -- Compute β₁ × m_old (Q0.15 × Q2.13 → Q2.13)
                        beta1_m <= multiply_q2_13_by_q0_15(m_old, beta1);

                        state <= CYCLE2;

                    when CYCLE2 =>
                        -- Compute (1-β₁) × g
                        one_minus_beta1_g <= multiply_q2_13_by_q0_15(gradient, one_minus_beta1);

                        -- Compute β₂ × v_old
                        beta2_v <= multiply_q2_13_by_q0_15(v_old, beta2);

                        state <= CYCLE3;

                    when CYCLE3 =>
                        -- Compute (1-β₂) × g²
                        one_minus_beta2_g2 <= multiply_q2_13_by_q0_15(g_squared, one_minus_beta2);

                        -- Compute m_new = β₁ × m_old + (1-β₁) × g
                        m_temp := add_saturate(beta1_m, one_minus_beta1_g);
                        m_new_reg <= m_temp;

                        state <= CYCLE4;

                    when CYCLE4 =>
                        -- Compute v_new = β₂ × v_old + (1-β₂) × g²
                        v_temp := add_saturate(beta2_v, one_minus_beta2_g2);

                        -- v must be non-negative (moment of squared gradients)
                        if v_temp < 0 then
                            v_new_reg <= (others => '0');
                            ovf_reg <= '1';
                        else
                            v_new_reg <= v_temp;
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
    m_new    <= m_new_reg;
    v_new    <= v_new_reg;
    done     <= done_reg;
    busy     <= '0' when state = IDLE else '1';
    overflow <= ovf_reg;

end architecture rtl;
