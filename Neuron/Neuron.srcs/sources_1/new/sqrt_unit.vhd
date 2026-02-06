--------------------------------------------------------------------------------
-- Module: sqrt_unit
-- Description: Computes sqrt(d) using Newton-Raphson iteration
--              Uses multiplication-only formula for 1/sqrt(d):
--              y_{n+1} = y * (1.5 - 0.5 * d * y^2)
--              Then result = d * y = sqrt(d)
--
-- Format: Q2.13 input/output (16-bit), Q2.26 internal precision
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity sqrt_unit is
    generic (
        DATA_WIDTH     : integer := 16;
        FRAC_BITS      : integer := 13;
        NUM_ITERATIONS : integer := 4
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        data_in      : in  signed(DATA_WIDTH-1 downto 0);
        start        : in  std_logic;
        
        data_out     : out signed(DATA_WIDTH-1 downto 0);
        done         : out std_logic;
        busy         : out std_logic;
        
        invalid      : out std_logic;
        overflow     : out std_logic
    );
end entity sqrt_unit;

architecture rtl of sqrt_unit is

    type state_t is (IDLE, INIT, ITERATE);
    signal state : state_t;
    
    -- Working precision Q2.26
    constant WORK_WIDTH : integer := 32;
    constant WORK_FRAC  : integer := 26;
    
    -- Constants in Q2.26
    constant ONE_POINT_FIVE : signed(WORK_WIDTH-1 downto 0) := 
        to_signed(integer(1.5 * real(2**WORK_FRAC)), WORK_WIDTH);
    constant ONE : signed(WORK_WIDTH-1 downto 0) := 
        to_signed(2**WORK_FRAC, WORK_WIDTH);
    constant HALF : signed(WORK_WIDTH-1 downto 0) := 
        to_signed(2**(WORK_FRAC-1), WORK_WIDTH);
    
    -- Saturation bound
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := 
        to_signed(2**(DATA_WIDTH-1) - 1, DATA_WIDTH);
    
    -- Registers
    signal d_reg      : signed(WORK_WIDTH-1 downto 0) := (others => '0');
    signal y_reg      : signed(WORK_WIDTH-1 downto 0) := (others => '0');
    signal iter_cnt   : integer range 0 to NUM_ITERATIONS := 0;
    
    signal result_reg : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal done_reg   : std_logic := '0';
    signal invalid_reg: std_logic := '0';
    signal ovf_reg    : std_logic := '0';

begin

    process(clk)
        variable temp64     : signed(2*WORK_WIDTH-1 downto 0);
        variable y_squared  : signed(WORK_WIDTH-1 downto 0);
        variable d_times_ysq: signed(WORK_WIDTH-1 downto 0);
        variable half_d_ysq : signed(WORK_WIDTH-1 downto 0);
        variable bracket    : signed(WORK_WIDTH-1 downto 0);
        variable y_next     : signed(WORK_WIDTH-1 downto 0);
        variable sqrt_res   : signed(WORK_WIDTH-1 downto 0);
        variable final_val  : signed(WORK_WIDTH-1 downto 0);
        variable d_val      : signed(WORK_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state       <= IDLE;
                done_reg    <= '0';
                invalid_reg <= '0';
                ovf_reg     <= '0';
                result_reg  <= (others => '0');
                d_reg       <= (others => '0');
                y_reg       <= (others => '0');
                iter_cnt    <= 0;
            else
                done_reg <= '0';
                
                case state is
                    when IDLE =>
                        if start = '1' then
                            -- Check for negative input
                            if data_in(DATA_WIDTH-1) = '1' then
                                invalid_reg <= '1';
                                ovf_reg     <= '0';
                                result_reg  <= (others => '0');
                                done_reg    <= '1';
                                -- Stay in IDLE
                            -- Check for zero
                            elsif data_in = 0 then
                                invalid_reg <= '0';
                                ovf_reg     <= '0';
                                result_reg  <= (others => '0');
                                done_reg    <= '1';
                                -- Stay in IDLE
                            else
                                invalid_reg <= '0';
                                -- Convert Q2.13 to Q2.26: shift left by 13
                                d_reg <= shift_left(resize(data_in, WORK_WIDTH), WORK_FRAC - FRAC_BITS);
                                state <= INIT;
                            end if;
                        end if;
                    
                    when INIT =>
                        -- Initial estimate for 1/sqrt(d)
                        -- For d in [0, 4), sqrt(d) in [0, 2), so 1/sqrt(d) in [0.5, inf)
                        -- Use simple heuristic: y0 = 1.0 / d (approximated)
                        -- Better: y0 ≈ 1.0 for d near 1.0, scale for others
                        
                        d_val := d_reg;
                        
                        -- Adaptive initial estimate based on magnitude
                        if d_val > shift_left(ONE, 1) then
                            -- d > 2.0: 1/sqrt(d) < 0.707, start with 0.5
                            y_reg <= HALF;
                        elsif d_val > ONE then
                            -- d in (1, 2]: 1/sqrt(d) in [0.707, 1), start with 0.75
                            y_reg <= HALF + shift_right(HALF, 1);
                        elsif d_val > HALF then
                            -- d in (0.5, 1]: 1/sqrt(d) in [1, 1.414), start with 1.0
                            y_reg <= ONE;
                        elsif d_val > shift_right(HALF, 1) then
                            -- d in (0.25, 0.5]: 1/sqrt(d) in [1.414, 2), start with 1.5
                            y_reg <= ONE_POINT_FIVE;
                        else
                            -- d < 0.25: 1/sqrt(d) > 2, start with 2.0
                            y_reg <= shift_left(ONE, 1);
                        end if;
                        
                        iter_cnt <= 0;
                        state <= ITERATE;
                    
                    when ITERATE =>
                        if iter_cnt < NUM_ITERATIONS then
                            -- Newton-Raphson: y_next = y * (1.5 - 0.5 * d * y^2)
                            
                            -- y^2
                            temp64 := y_reg * y_reg;
                            y_squared := temp64(WORK_FRAC + WORK_WIDTH - 1 downto WORK_FRAC);
                            
                            -- d * y^2
                            temp64 := d_reg * y_squared;
                            d_times_ysq := temp64(WORK_FRAC + WORK_WIDTH - 1 downto WORK_FRAC);
                            
                            -- 0.5 * d * y^2
                            half_d_ysq := shift_right(d_times_ysq, 1);
                            
                            -- 1.5 - 0.5 * d * y^2
                            bracket := ONE_POINT_FIVE - half_d_ysq;
                            
                            -- y * (1.5 - 0.5 * d * y^2)
                            temp64 := y_reg * bracket;
                            y_next := temp64(WORK_FRAC + WORK_WIDTH - 1 downto WORK_FRAC);
                            
                            y_reg <= y_next;
                            iter_cnt <= iter_cnt + 1;
                        else
                            -- Final step: sqrt(d) = d * y = d * (1/sqrt(d))
                            temp64 := d_reg * y_reg;
                            sqrt_res := temp64(WORK_FRAC + WORK_WIDTH - 1 downto WORK_FRAC);
                            
                            -- Convert Q2.26 back to Q2.13
                            final_val := shift_right(sqrt_res, WORK_FRAC - FRAC_BITS);
                            
                            -- Saturation check
                            if final_val > resize(SAT_MAX, WORK_WIDTH) then
                                result_reg <= SAT_MAX;
                                ovf_reg <= '1';
                            elsif final_val < 0 then
                                result_reg <= (others => '0');
                                ovf_reg <= '1';
                            else
                                result_reg <= final_val(DATA_WIDTH-1 downto 0);
                                ovf_reg <= '0';
                            end if;
                            
                            -- Assert done and return to IDLE in same transition
                            done_reg <= '1';
                            state <= IDLE;
                        end if;
                    
                    when others =>
                        state <= IDLE;
                        
                end case;
            end if;
        end if;
    end process;

    data_out <= result_reg;
    done     <= done_reg;
    busy     <= '0' when state = IDLE else '1';
    invalid  <= invalid_reg;
    overflow <= ovf_reg;

end architecture rtl;