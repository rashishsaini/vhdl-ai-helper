--------------------------------------------------------------------------------
-- Module: tanh_unit
-- Description: Computes hyperbolic tangent activation function
--              tanh(x) = 2 * σ(2x) - 1
--              where σ is the sigmoid function
--
-- Method: Uses sigmoid_unit with scaled input
--         1. Compute 2x (with saturation)
--         2. Compute σ(2x) using sigmoid_unit
--         3. Compute 2 * σ(2x)
--         4. Subtract 1 to get tanh(x)
--
-- Format: Q2.13 input/output (16-bit signed)
-- Output Range: (-1, 1)
-- Latency: ~22-24 clock cycles (2x + sigmoid + 2*result - 1)
--
-- Key values:
--   tanh(-4) ≈ -0.9993
--   tanh(-1) ≈ -0.7616
--   tanh(0)  = 0
--   tanh(1)  ≈ 0.7616
--   tanh(4)  ≈ 0.9993
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tanh_unit is
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
end entity tanh_unit;

architecture rtl of tanh_unit is

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
    -- Constants
    ---------------------------------------------------------------------------
    -- 1.0 in Q2.13
    constant ONE : signed(DATA_WIDTH-1 downto 0) := to_signed(8192, DATA_WIDTH);
    
    -- 2.0 in Q2.13
    constant TWO : signed(DATA_WIDTH-1 downto 0) := to_signed(16384, DATA_WIDTH);
    
    -- Saturation bounds
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH);
    
    -- Tanh output bounds (should be in range (-1, 1))
    constant TANH_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(8191, DATA_WIDTH);   -- ~0.9999
    constant TANH_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-8191, DATA_WIDTH);  -- ~-0.9999

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        COMPUTE_2X,
        START_SIGMOID,
        WAIT_SIGMOID,
        COMPUTE_RESULT,
        OUTPUT_ST
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Internal Signals
    ---------------------------------------------------------------------------
    -- Input storage
    signal x_reg         : signed(DATA_WIDTH-1 downto 0);
    
    -- 2x computation (with saturation)
    signal two_x         : signed(DATA_WIDTH-1 downto 0);
    
    -- Sigmoid unit interface
    signal sig_input     : signed(DATA_WIDTH-1 downto 0);
    signal sig_start     : std_logic;
    signal sig_result    : signed(DATA_WIDTH-1 downto 0);
    signal sig_done      : std_logic;
    signal sig_busy      : std_logic;
    signal sig_overflow  : std_logic;
    
    -- Final computation: 2 * σ(2x) - 1
    signal two_sigma     : signed(DATA_WIDTH downto 0);  -- Extra bit for 2*sigma
    signal tanh_result   : signed(DATA_WIDTH downto 0);  -- Extra bit for subtraction
    
    -- Output registers
    signal result_reg    : signed(DATA_WIDTH-1 downto 0);
    signal done_reg      : std_logic;
    signal ovf_reg       : std_logic;

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
        variable x_doubled : signed(DATA_WIDTH downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state       <= IDLE;
                x_reg       <= (others => '0');
                two_x       <= (others => '0');
                sig_input   <= (others => '0');
                sig_start   <= '0';
                two_sigma   <= (others => '0');
                tanh_result <= (others => '0');
                result_reg  <= (others => '0');
                done_reg    <= '0';
                ovf_reg     <= '0';
            else
                -- Default: clear single-cycle signals
                done_reg  <= '0';
                sig_start <= '0';
                
                case state is
                    when IDLE =>
                        if start = '1' then
                            x_reg   <= data_in;
                            ovf_reg <= '0';
                            state   <= COMPUTE_2X;
                        end if;
                    
                    when COMPUTE_2X =>
                        -- Compute 2x with saturation
                        -- Multiply by 2 using shift_left
                        x_doubled := shift_left(resize(x_reg, DATA_WIDTH+1), 1);
                        
                        -- Saturate to Q2.13 range
                        if x_doubled > resize(SAT_MAX, DATA_WIDTH+1) then
                            two_x   <= SAT_MAX;
                            ovf_reg <= '1';
                        elsif x_doubled < resize(SAT_MIN, DATA_WIDTH+1) then
                            two_x   <= SAT_MIN;
                            ovf_reg <= '1';
                        else
                            two_x <= x_doubled(DATA_WIDTH-1 downto 0);
                        end if;
                        
                        state <= START_SIGMOID;
                    
                    when START_SIGMOID =>
                        -- Start sigmoid computation with 2x
                        sig_input <= two_x;
                        sig_start <= '1';
                        state <= WAIT_SIGMOID;
                    
                    when WAIT_SIGMOID =>
                        -- Wait for sigmoid_unit to complete
                        if sig_done = '1' then
                            state <= COMPUTE_RESULT;
                        end if;
                    
                    when COMPUTE_RESULT =>
                        -- Compute: tanh(x) = 2 * σ(2x) - 1
                        
                        -- 2 * σ(2x): shift left by 1
                        two_sigma <= shift_left(resize(sig_result, DATA_WIDTH+1), 1);
                        
                        -- Subtract 1.0
                        tanh_result <= shift_left(resize(sig_result, DATA_WIDTH+1), 1) - 
                                       resize(ONE, DATA_WIDTH+1);
                        
                        state <= OUTPUT_ST;
                    
                    when OUTPUT_ST =>
                        -- Saturate result to tanh range (-1, 1)
                        if tanh_result > resize(TANH_MAX, DATA_WIDTH+1) then
                            result_reg <= TANH_MAX;
                        elsif tanh_result < resize(TANH_MIN, DATA_WIDTH+1) then
                            result_reg <= TANH_MIN;
                        else
                            result_reg <= tanh_result(DATA_WIDTH-1 downto 0);
                        end if;
                        
                        -- Propagate overflow from sigmoid
                        if sig_overflow = '1' then
                            ovf_reg <= '1';
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
    data_out <= result_reg;
    done     <= done_reg;
    busy     <= '0' when state = IDLE else '1';
    overflow <= ovf_reg;

end architecture rtl;