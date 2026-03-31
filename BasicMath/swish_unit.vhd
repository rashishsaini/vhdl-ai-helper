--------------------------------------------------------------------------------
-- Module: swish_unit
-- Description: Swish (SiLU) activation function
--              f(x) = x * sigmoid(x) = x / (1 + e^(-x))
--
-- Features:
--   - Self-gated activation function
--   - Uses sigmoid_unit for sigmoid(x) computation
--   - Smooth, non-monotonic function
--   - Outperforms ReLU in deep networks (EfficientNet, etc.)
--
-- Format: Q2.13 input/output (16-bit signed)
-- Latency: ~22-24 cycles (sigmoid computation + multiply)
--
-- Key values:
--   Swish(-4) ≈ -4 * 0.018 ≈ -0.072
--   Swish(-1) ≈ -1 * 0.269 ≈ -0.269
--   Swish(0)  = 0 * 0.5 = 0
--   Swish(1)  ≈ 1 * 0.731 ≈ 0.731
--   Swish(4)  ≈ 4 * 0.982 ≈ 3.928
--
-- Properties:
--   - Swish(x) ≈ x for large positive x
--   - Swish(x) ≈ 0 for large negative x
--   - Has a small negative region (non-monotonic)
--   - Minimum at x ≈ -1.278 where Swish ≈ -0.278
--
-- Author: FPGA Neural Network Project
-- Complexity: MEDIUM
-- Dependencies: sigmoid_unit
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity swish_unit is
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
end entity swish_unit;

architecture rtl of swish_unit is

    ---------------------------------------------------------------------------
    -- Component: Sigmoid Unit
    ---------------------------------------------------------------------------
    component sigmoid_unit is
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
            overflow     : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        START_SIGMOID,
        WAIT_SIGMOID,
        COMPUTE_PRODUCT,
        OUTPUT_ST
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(2**(DATA_WIDTH-1)-1, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-2**(DATA_WIDTH-1), DATA_WIDTH);
    constant PRODUCT_WIDTH : integer := 2 * DATA_WIDTH;

    ---------------------------------------------------------------------------
    -- Internal Signals
    ---------------------------------------------------------------------------
    signal x_reg         : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    signal sig_input     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal sig_start     : std_logic := '0';
    signal sig_result    : signed(DATA_WIDTH-1 downto 0);
    signal sig_done      : std_logic;
    signal sig_busy      : std_logic;
    signal sig_overflow  : std_logic;
    
    signal product       : signed(PRODUCT_WIDTH-1 downto 0) := (others => '0');
    
    signal result_reg    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal done_reg      : std_logic := '0';
    signal ovf_reg       : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Sigmoid Unit Instantiation
    ---------------------------------------------------------------------------
    sigmoid_inst : sigmoid_unit
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            FRAC_BITS  => FRAC_BITS
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_in      => sig_input,
            start        => sig_start,
            data_out     => sig_result,
            done         => sig_done,
            busy         => sig_busy,
            overflow     => sig_overflow
        );

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable prod_full   : signed(PRODUCT_WIDTH-1 downto 0);
        variable prod_round  : signed(PRODUCT_WIDTH-1 downto 0);
        variable prod_shift  : signed(PRODUCT_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state       <= IDLE;
                x_reg       <= (others => '0');
                sig_input   <= (others => '0');
                sig_start   <= '0';
                product     <= (others => '0');
                result_reg  <= (others => '0');
                done_reg    <= '0';
                ovf_reg     <= '0';
            else
                done_reg  <= '0';
                sig_start <= '0';
                
                case state is
                
                    when IDLE =>
                        if start = '1' then
                            x_reg   <= data_in;
                            ovf_reg <= '0';
                            state   <= START_SIGMOID;
                        end if;
                    
                    when START_SIGMOID =>
                        sig_input <= x_reg;
                        sig_start <= '1';
                        state     <= WAIT_SIGMOID;
                    
                    when WAIT_SIGMOID =>
                        if sig_done = '1' then
                            if sig_overflow = '1' then
                                ovf_reg <= '1';
                            end if;
                            state <= COMPUTE_PRODUCT;
                        end if;
                    
                    when COMPUTE_PRODUCT =>
                        prod_full := x_reg * sig_result;
                        prod_round := prod_full + to_signed(2**(FRAC_BITS-1), PRODUCT_WIDTH);
                        prod_shift := shift_right(prod_round, FRAC_BITS);
                        
                        if prod_shift > resize(SAT_MAX, PRODUCT_WIDTH) then
                            result_reg <= SAT_MAX;
                            ovf_reg    <= '1';
                        elsif prod_shift < resize(SAT_MIN, PRODUCT_WIDTH) then
                            result_reg <= SAT_MIN;
                            ovf_reg    <= '1';
                        else
                            result_reg <= prod_shift(DATA_WIDTH-1 downto 0);
                        end if;
                        
                        state <= OUTPUT_ST;
                    
                    when OUTPUT_ST =>
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
    data_out <= result_reg;
    done     <= done_reg;
    busy     <= '0' when state = IDLE else '1';
    overflow <= ovf_reg;

end architecture rtl;
