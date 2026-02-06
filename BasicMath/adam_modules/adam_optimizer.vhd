--------------------------------------------------------------------------------
-- Module: adam_optimizer
-- Description: Top-level Adam Optimizer - sequences updates for all 13 parameters
--
-- Operation:
--   1. Iterates through all 13 parameters sequentially (param 0 to 12)
--   2. For each parameter:
--      - Read gradient from gradient_register_bank
--      - Read weight from weight_register_bank
--      - Read moments (m, v) from moment_register_bank
--      - Perform Full Adam update (via adam_update_unit)
--      - Write new moments back to moment_register_bank
--      - Write new weight back to weight_register_bank
--   3. Increment global timestep after all 13 parameters updated
--
-- Network: 4-2-1 architecture = 13 trainable parameters
--   - Layer 1 (4→2): 4×2 weights + 2 biases = 10 parameters (indices 0-9)
--   - Layer 2 (2→1): 2×1 weights + 1 bias   = 3 parameters (indices 10-12)
--
-- Format: Q2.13 for weights/gradients/moments, Q0.15 for hyperparameters
-- Latency: ~780 cycles per training step (13 params × 60 cycles/param)
--
-- Instantiates:
--   - moment_register_bank
--   - adam_update_unit
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity adam_optimizer is
    generic (
        DATA_WIDTH : integer := 16;
        BETA_WIDTH : integer := 16;
        NUM_PARAMS : integer := 13;
        ADDR_WIDTH : integer := 4
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- Control
        start    : in  std_logic;  -- Begin 13-parameter update
        timestep : in  unsigned(13 downto 0);  -- Global timestep t

        -- External memory interfaces (gradient and weight banks)
        gradient_addr : out unsigned(ADDR_WIDTH-1 downto 0);
        gradient_data : in  signed(DATA_WIDTH-1 downto 0);

        weight_rd_addr : out unsigned(ADDR_WIDTH-1 downto 0);
        weight_rd_data : in  signed(DATA_WIDTH-1 downto 0);
        weight_wr_addr : out unsigned(ADDR_WIDTH-1 downto 0);
        weight_wr_data : out signed(DATA_WIDTH-1 downto 0);
        weight_wr_en   : out std_logic;

        -- Hyperparameters (Q0.15 format)
        beta1           : in signed(BETA_WIDTH-1 downto 0);
        beta2           : in signed(BETA_WIDTH-1 downto 0);
        one_minus_beta1 : in signed(BETA_WIDTH-1 downto 0);
        one_minus_beta2 : in signed(BETA_WIDTH-1 downto 0);
        learning_rate   : in signed(BETA_WIDTH-1 downto 0);
        epsilon         : in signed(DATA_WIDTH-1 downto 0);  -- Q2.13

        -- Status outputs
        done          : out std_logic;
        busy          : out std_logic;
        current_param : out unsigned(ADDR_WIDTH-1 downto 0);
        overflow      : out std_logic
    );
end entity adam_optimizer;

architecture rtl of adam_optimizer is

    ---------------------------------------------------------------------------
    -- Component Declarations
    ---------------------------------------------------------------------------
    component moment_register_bank is
        generic (
            DATA_WIDTH : integer := 16;
            NUM_PARAMS : integer := 13;
            ADDR_WIDTH : integer := 4
        );
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            clear     : in  std_logic;
            rd_en     : in  std_logic;
            rd_addr   : in  unsigned(3 downto 0);
            m_rd_data : out signed(15 downto 0);
            v_rd_data : out signed(15 downto 0);
            rd_valid  : out std_logic;
            wr_en     : in  std_logic;
            wr_addr   : in  unsigned(3 downto 0);
            m_wr_data : in  signed(15 downto 0);
            v_wr_data : in  signed(15 downto 0)
        );
    end component;

    component adam_update_unit is
        generic (
            DATA_WIDTH : integer := 16;
            BETA_WIDTH : integer := 16;
            EXP_WIDTH  : integer := 14
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            start           : in  std_logic;
            gradient        : in  signed(15 downto 0);
            m_old           : in  signed(15 downto 0);
            v_old           : in  signed(15 downto 0);
            weight_old      : in  signed(15 downto 0);
            timestep        : in  unsigned(13 downto 0);
            beta1           : in  signed(15 downto 0);
            beta2           : in  signed(15 downto 0);
            one_minus_beta1 : in  signed(15 downto 0);
            one_minus_beta2 : in  signed(15 downto 0);
            learning_rate   : in  signed(15 downto 0);
            epsilon         : in  signed(15 downto 0);
            m_new           : out signed(15 downto 0);
            v_new           : out signed(15 downto 0);
            weight_new      : out signed(15 downto 0);
            done            : out std_logic;
            busy            : out std_logic;
            overflow        : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        INIT,
        READ_MOMENTS,
        READ_GRADIENT_WEIGHT,
        WAIT_READ,
        UPDATE_PARAM,
        WAIT_UPDATE,
        WRITE_MOMENTS,
        WRITE_WEIGHT,
        INCREMENT,
        CHECK_DONE,
        DONE_ST
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Moment Register Bank Signals
    ---------------------------------------------------------------------------
    signal moment_clear     : std_logic := '0';
    signal moment_rd_en     : std_logic := '0';
    signal moment_rd_addr   : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal moment_m_rd_data : signed(DATA_WIDTH-1 downto 0);
    signal moment_v_rd_data : signed(DATA_WIDTH-1 downto 0);
    signal moment_rd_valid  : std_logic;

    signal moment_wr_en     : std_logic := '0';
    signal moment_wr_addr   : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal moment_m_wr_data : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal moment_v_wr_data : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- Adam Update Unit Signals
    ---------------------------------------------------------------------------
    signal update_start     : std_logic := '0';
    signal update_gradient  : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal update_m_old     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal update_v_old     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal update_weight_old: signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal update_m_new     : signed(DATA_WIDTH-1 downto 0);
    signal update_v_new     : signed(DATA_WIDTH-1 downto 0);
    signal update_weight_new: signed(DATA_WIDTH-1 downto 0);
    signal update_done      : std_logic;
    signal update_busy      : std_logic;
    signal update_overflow  : std_logic;

    ---------------------------------------------------------------------------
    -- Internal Registers
    ---------------------------------------------------------------------------
    signal param_index      : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal gradient_reg     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal weight_reg       : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal m_old_reg        : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal v_old_reg        : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- Output Registers
    ---------------------------------------------------------------------------
    signal done_reg         : std_logic := '0';
    signal ovf_reg          : std_logic := '0';
    signal weight_wr_en_reg : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Moment Register Bank Instance
    ---------------------------------------------------------------------------
    moment_bank_inst : moment_register_bank
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            NUM_PARAMS => NUM_PARAMS,
            ADDR_WIDTH => ADDR_WIDTH
        )
        port map (
            clk       => clk,
            rst       => rst,
            clear     => moment_clear,
            rd_en     => moment_rd_en,
            rd_addr   => moment_rd_addr,
            m_rd_data => moment_m_rd_data,
            v_rd_data => moment_v_rd_data,
            rd_valid  => moment_rd_valid,
            wr_en     => moment_wr_en,
            wr_addr   => moment_wr_addr,
            m_wr_data => moment_m_wr_data,
            v_wr_data => moment_v_wr_data
        );

    ---------------------------------------------------------------------------
    -- Adam Update Unit Instance
    ---------------------------------------------------------------------------
    adam_update_inst : adam_update_unit
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            BETA_WIDTH => BETA_WIDTH,
            EXP_WIDTH  => 14
        )
        port map (
            clk             => clk,
            rst             => rst,
            start           => update_start,
            gradient        => update_gradient,
            m_old           => update_m_old,
            v_old           => update_v_old,
            weight_old      => update_weight_old,
            timestep        => timestep,
            beta1           => beta1,
            beta2           => beta2,
            one_minus_beta1 => one_minus_beta1,
            one_minus_beta2 => one_minus_beta2,
            learning_rate   => learning_rate,
            epsilon         => epsilon,
            m_new           => update_m_new,
            v_new           => update_v_new,
            weight_new      => update_weight_new,
            done            => update_done,
            busy            => update_busy,
            overflow        => update_overflow
        );

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state            <= IDLE;
                param_index      <= (others => '0');
                done_reg         <= '0';
                ovf_reg          <= '0';
                moment_clear     <= '0';
                moment_rd_en     <= '0';
                moment_wr_en     <= '0';
                update_start     <= '0';
                weight_wr_en_reg <= '0';
            else
                -- Default: clear single-cycle signals
                done_reg         <= '0';
                moment_clear     <= '0';
                moment_rd_en     <= '0';
                moment_wr_en     <= '0';
                update_start     <= '0';
                weight_wr_en_reg <= '0';

                case state is
                    when IDLE =>
                        if start = '1' then
                            param_index <= (others => '0');
                            ovf_reg     <= '0';
                            state       <= INIT;
                        end if;

                    when INIT =>
                        -- Initialize for first parameter
                        state <= READ_MOMENTS;

                    when READ_MOMENTS =>
                        -- Read moments for current parameter
                        moment_rd_en   <= '1';
                        moment_rd_addr <= param_index;
                        state <= READ_GRADIENT_WEIGHT;

                    when READ_GRADIENT_WEIGHT =>
                        -- Capture moments
                        m_old_reg <= moment_m_rd_data;
                        v_old_reg <= moment_v_rd_data;

                        -- Request gradient and weight from external banks
                        -- (These are assumed to be combinational reads)
                        state <= WAIT_READ;

                    when WAIT_READ =>
                        -- Capture gradient and weight
                        gradient_reg <= gradient_data;
                        weight_reg   <= weight_rd_data;
                        state <= UPDATE_PARAM;

                    when UPDATE_PARAM =>
                        -- Start adam_update_unit
                        update_gradient   <= gradient_reg;
                        update_m_old      <= m_old_reg;
                        update_v_old      <= v_old_reg;
                        update_weight_old <= weight_reg;
                        update_start      <= '1';
                        state <= WAIT_UPDATE;

                    when WAIT_UPDATE =>
                        -- Wait for adam_update_unit to complete
                        if update_done = '1' then
                            if update_overflow = '1' then
                                ovf_reg <= '1';
                            end if;
                            state <= WRITE_MOMENTS;
                        end if;

                    when WRITE_MOMENTS =>
                        -- Write new moments back to moment_register_bank
                        moment_wr_en     <= '1';
                        moment_wr_addr   <= param_index;
                        moment_m_wr_data <= update_m_new;
                        moment_v_wr_data <= update_v_new;
                        state <= WRITE_WEIGHT;

                    when WRITE_WEIGHT =>
                        -- Write new weight back to weight_register_bank
                        weight_wr_en_reg <= '1';
                        state <= INCREMENT;

                    when INCREMENT =>
                        -- Move to next parameter
                        param_index <= param_index + 1;
                        state <= CHECK_DONE;

                    when CHECK_DONE =>
                        -- Check if all parameters updated
                        if param_index >= NUM_PARAMS then
                            state <= DONE_ST;
                        else
                            state <= READ_MOMENTS;
                        end if;

                    when DONE_ST =>
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
    -- External gradient/weight bank interfaces
    gradient_addr  <= param_index;
    weight_rd_addr <= param_index;
    weight_wr_addr <= param_index;
    weight_wr_data <= update_weight_new;
    weight_wr_en   <= weight_wr_en_reg;

    -- Status outputs
    done          <= done_reg;
    busy          <= '0' when state = IDLE else '1';
    current_param <= param_index;
    overflow      <= ovf_reg;

end architecture rtl;
