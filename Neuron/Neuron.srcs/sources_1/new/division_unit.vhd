--------------------------------------------------------------------------------
-- Module: division_unit
-- Description: Fixed-point division using reciprocal unit
--              Computes: result = dividend / divisor = dividend × (1/divisor)
--
-- Format: Q2.13 input/output (16-bit signed)
-- Method: Instantiates reciprocal_unit, then multiplies
-- Latency: ~9-10 clock cycles (reciprocal + multiply + output)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity division_unit is
    generic (
        DATA_WIDTH     : integer := 16;
        FRAC_BITS      : integer := 13;
        NUM_ITERATIONS : integer := 3   -- For reciprocal unit
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Input interface
        dividend     : in  signed(DATA_WIDTH-1 downto 0);  -- Numerator (a)
        divisor      : in  signed(DATA_WIDTH-1 downto 0);  -- Denominator (b)
        start        : in  std_logic;
        
        -- Output interface
        quotient     : out signed(DATA_WIDTH-1 downto 0);  -- Result (a/b)
        done         : out std_logic;
        busy         : out std_logic;
        
        -- Status flags
        div_by_zero  : out std_logic;
        overflow     : out std_logic
    );
end entity division_unit;

architecture rtl of division_unit is

    ---------------------------------------------------------------------------
    -- Component: Reciprocal Unit
    ---------------------------------------------------------------------------
    component reciprocal_unit is
        generic (
            DATA_WIDTH     : integer := 16;
            FRAC_BITS      : integer := 13;
            INTERNAL_WIDTH : integer := 32;
            NUM_ITERATIONS : integer := 3;
            LUT_ADDR_BITS  : integer := 6
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            data_in      : in  signed(DATA_WIDTH-1 downto 0);
            start        : in  std_logic;
            data_out     : out signed(DATA_WIDTH-1 downto 0);
            done         : out std_logic;
            busy         : out std_logic;
            div_by_zero  : out std_logic;
            overflow     : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (IDLE, WAIT_RECIP, MULTIPLY, OUTPUT_ST);
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Internal Signals
    ---------------------------------------------------------------------------
    -- Stored operands
    signal dividend_reg : signed(DATA_WIDTH-1 downto 0);
    signal divisor_reg  : signed(DATA_WIDTH-1 downto 0);
    
    -- Reciprocal unit interface
    signal recip_start    : std_logic;
    signal recip_result   : signed(DATA_WIDTH-1 downto 0);
    signal recip_done     : std_logic;
    signal recip_busy     : std_logic;
    signal recip_dbz      : std_logic;
    signal recip_ovf      : std_logic;
    
    -- Multiplication result (32-bit product, then scaled back)
    signal product        : signed(2*DATA_WIDTH-1 downto 0);
    signal product_scaled : signed(DATA_WIDTH-1 downto 0);
    
    -- Output registers
    signal quotient_reg   : signed(DATA_WIDTH-1 downto 0);
    signal done_reg       : std_logic;
    signal dbz_reg        : std_logic;
    signal ovf_reg        : std_logic;
    
    -- Saturation constants
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := 
        to_signed(2**(DATA_WIDTH-1) - 1, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := 
        to_signed(-2**(DATA_WIDTH-1), DATA_WIDTH);

begin

    ---------------------------------------------------------------------------
    -- Reciprocal Unit Instantiation
    ---------------------------------------------------------------------------
    recip_inst : reciprocal_unit
        generic map (
            DATA_WIDTH     => DATA_WIDTH,
            FRAC_BITS      => FRAC_BITS,
            INTERNAL_WIDTH => 32,
            NUM_ITERATIONS => NUM_ITERATIONS,
            LUT_ADDR_BITS  => 6
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_in      => divisor_reg,
            start        => recip_start,
            data_out     => recip_result,
            done         => recip_done,
            busy         => recip_busy,
            div_by_zero  => recip_dbz,
            overflow     => recip_ovf
        );

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable prod_extended : signed(2*DATA_WIDTH-1 downto 0);
        variable prod_shifted  : signed(2*DATA_WIDTH-1 downto 0);
        variable sat_check     : signed(DATA_WIDTH downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state        <= IDLE;
                dividend_reg <= (others => '0');
                divisor_reg  <= (others => '0');
                quotient_reg <= (others => '0');
                done_reg     <= '0';
                dbz_reg      <= '0';
                ovf_reg      <= '0';
                recip_start  <= '0';
            else
                -- Default: clear single-cycle signals
                done_reg    <= '0';
                recip_start <= '0';
                
                case state is
                    when IDLE =>
                        if start = '1' then
                            -- Capture inputs
                            dividend_reg <= dividend;
                            divisor_reg  <= divisor;
                            dbz_reg      <= '0';
                            ovf_reg      <= '0';
                            
                            -- Start reciprocal computation
                            recip_start <= '1';
                            state <= WAIT_RECIP;
                        end if;
                    
                    when WAIT_RECIP =>
                        -- Wait for reciprocal unit to complete
                        if recip_done = '1' then
                            -- Check for division by zero
                            if recip_dbz = '1' then
                                dbz_reg <= '1';
                                quotient_reg <= (others => '0');
                                done_reg <= '1';
                                state <= IDLE;
                            else
                                -- Proceed to multiplication
                                state <= MULTIPLY;
                            end if;
                        end if;
                    
                    when MULTIPLY =>
                        -- Compute: dividend × (1/divisor)
                        -- Q2.13 × Q2.13 = Q4.26 (32-bit)
                        prod_extended := dividend_reg * recip_result;
                        
                        -- Scale back to Q2.13: shift right by FRAC_BITS (13)
                        -- Add rounding: add 0.5 LSB before shift
                        prod_shifted := shift_right(
                            prod_extended + to_signed(2**(FRAC_BITS-1), 2*DATA_WIDTH),
                            FRAC_BITS
                        );
                        
                        -- Saturation check
                        sat_check := prod_shifted(DATA_WIDTH downto 0);
                        
                        if prod_shifted > resize(SAT_MAX, 2*DATA_WIDTH) then
                            quotient_reg <= SAT_MAX;
                            ovf_reg <= '1';
                        elsif prod_shifted < resize(SAT_MIN, 2*DATA_WIDTH) then
                            quotient_reg <= SAT_MIN;
                            ovf_reg <= '1';
                        else
                            quotient_reg <= prod_shifted(DATA_WIDTH-1 downto 0);
                            ovf_reg <= recip_ovf;  -- Propagate reciprocal overflow
                        end if;
                        
                        state <= OUTPUT_ST;
                    
                    when OUTPUT_ST =>
                        -- Output result
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
    quotient    <= quotient_reg;
    done        <= done_reg;
    busy        <= '0' when state = IDLE else '1';
    div_by_zero <= dbz_reg;
    overflow    <= ovf_reg;

end architecture rtl;