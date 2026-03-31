--------------------------------------------------------------------------------
-- Module: elu_unit
-- Description: Exponential Linear Unit (ELU) activation function
--              f(x) = x              if x > 0
--              f(x) = α(e^x - 1)     if x ≤ 0
--
-- Features:
--   - Configurable alpha parameter (default α = 1.0)
--   - Uses exp_approximator for negative input path
--   - Smooth activation with non-zero gradient everywhere
--   - Helps push mean activations toward zero
--
-- Format: Q2.13 input/output (16-bit signed)
-- Latency: 1 cycle (positive), ~6 cycles (negative path)
--
-- Key values:
--   ELU(-4) ≈ α(e^(-4) - 1) ≈ α(-0.982) ≈ -0.982 (for α=1)
--   ELU(-1) ≈ α(e^(-1) - 1) ≈ α(-0.632) ≈ -0.632
--   ELU(0)  = 0
--   ELU(1)  = 1
--   ELU(4)  = 4
--
-- Author: FPGA Neural Network Project
-- Complexity: MEDIUM
-- Dependencies: exp_approximator
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity elu_unit is
    generic (
        DATA_WIDTH : integer := 16;
        FRAC_BITS  : integer := 13;
        -- Default alpha = 1.0 in Q2.13 = 8192
        DEFAULT_ALPHA : integer := 8192
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Input interface
        data_in      : in  signed(DATA_WIDTH-1 downto 0);
        alpha        : in  signed(DATA_WIDTH-1 downto 0);  -- Scaling factor
        use_default  : in  std_logic;                       -- Use DEFAULT_ALPHA
        start        : in  std_logic;
        
        -- Output interface
        data_out     : out signed(DATA_WIDTH-1 downto 0);
        done         : out std_logic;
        busy         : out std_logic;
        
        -- Status
        overflow     : out std_logic
    );
end entity elu_unit;

architecture rtl of elu_unit is

    ---------------------------------------------------------------------------
    -- Component: Exponential Approximator
    ---------------------------------------------------------------------------
    component exp_approximator is
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
            overflow     : out std_logic;
            underflow    : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        CHECK_SIGN,
        POSITIVE_PATH,
        START_EXP,
        WAIT_EXP,
        COMPUTE_RESULT,
        OUTPUT_ST
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant ONE : signed(DATA_WIDTH-1 downto 0) := to_signed(2**FRAC_BITS, DATA_WIDTH);
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(2**(DATA_WIDTH-1)-1, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-2**(DATA_WIDTH-1), DATA_WIDTH);
    constant PRODUCT_WIDTH : integer := 2 * DATA_WIDTH;

    ---------------------------------------------------------------------------
    -- Internal Signals
    ---------------------------------------------------------------------------
    signal x_reg         : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal alpha_reg     : signed(DATA_WIDTH-1 downto 0) := to_signed(DEFAULT_ALPHA, DATA_WIDTH);
    
    signal exp_input     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal exp_start     : std_logic := '0';
    signal exp_result    : signed(DATA_WIDTH-1 downto 0);
    signal exp_done      : std_logic;
    signal exp_busy      : std_logic;
    signal exp_overflow  : std_logic;
    signal exp_underflow : std_logic;
    
    signal exp_minus_one : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal product       : signed(PRODUCT_WIDTH-1 downto 0) := (others => '0');
    
    signal result_reg    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal done_reg      : std_logic := '0';
    signal ovf_reg       : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Exponential Approximator Instantiation
    ---------------------------------------------------------------------------
    exp_inst : exp_approximator
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            FRAC_BITS  => FRAC_BITS
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_in      => exp_input,
            start        => exp_start,
            data_out     => exp_result,
            done         => exp_done,
            busy         => exp_busy,
            overflow     => exp_overflow,
            underflow    => exp_underflow
        );

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable scaled_result : signed(PRODUCT_WIDTH-1 downto 0);
        variable rounded       : signed(PRODUCT_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state        <= IDLE;
                x_reg        <= (others => '0');
                alpha_reg    <= to_signed(DEFAULT_ALPHA, DATA_WIDTH);
                exp_input    <= (others => '0');
                exp_start    <= '0';
                exp_minus_one<= (others => '0');
                product      <= (others => '0');
                result_reg   <= (others => '0');
                done_reg     <= '0';
                ovf_reg      <= '0';
            else
                done_reg  <= '0';
                exp_start <= '0';
                
                case state is
                
                    when IDLE =>
                        if start = '1' then
                            x_reg <= data_in;
                            if use_default = '1' then
                                alpha_reg <= to_signed(DEFAULT_ALPHA, DATA_WIDTH);
                            else
                                alpha_reg <= alpha;
                            end if;
                            ovf_reg <= '0';
                            state <= CHECK_SIGN;
                        end if;
                    
                    when CHECK_SIGN =>
                        if x_reg > 0 then
                            state <= POSITIVE_PATH;
                        else
                            state <= START_EXP;
                        end if;
                    
                    when POSITIVE_PATH =>
                        result_reg <= x_reg;
                        state <= OUTPUT_ST;
                    
                    when START_EXP =>
                        exp_input <= x_reg;
                        exp_start <= '1';
                        state <= WAIT_EXP;
                    
                    when WAIT_EXP =>
                        if exp_done = '1' then
                            if exp_overflow = '1' then
                                ovf_reg <= '1';
                            end if;
                            state <= COMPUTE_RESULT;
                        end if;
                    
                    when COMPUTE_RESULT =>
                        exp_minus_one <= exp_result - ONE;
                        product <= (exp_result - ONE) * alpha_reg;
                        scaled_result := (exp_result - ONE) * alpha_reg;
                        rounded := scaled_result + to_signed(2**(FRAC_BITS-1), PRODUCT_WIDTH);
                        
                        if shift_right(rounded, FRAC_BITS) > resize(SAT_MAX, PRODUCT_WIDTH) then
                            result_reg <= SAT_MAX;
                            ovf_reg <= '1';
                        elsif shift_right(rounded, FRAC_BITS) < resize(SAT_MIN, PRODUCT_WIDTH) then
                            result_reg <= SAT_MIN;
                            ovf_reg <= '1';
                        else
                            result_reg <= shift_right(rounded, FRAC_BITS)(DATA_WIDTH-1 downto 0);
                        end if;
                        
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
    data_out <= result_reg;
    done     <= done_reg;
    busy     <= '0' when state = IDLE else '1';
    overflow <= ovf_reg;

end architecture rtl;
