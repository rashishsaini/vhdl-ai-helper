library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity accumulator is
    generic (
        INPUT_WIDTH  : integer := 32;
        ACCUM_WIDTH  : integer := 40;
        ENABLE_SAT   : boolean := true
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Input interface
        data_in      : in  signed(INPUT_WIDTH-1 downto 0);
        data_valid   : in  std_logic;
        data_ready   : out std_logic;
        
        -- Control
        clear        : in  std_logic;
        
        -- Output interface
        accum_out    : out signed(ACCUM_WIDTH-1 downto 0);
        out_valid    : out std_logic;
        out_ready    : in  std_logic;
        
        -- Status
        overflow     : out std_logic;
        saturated    : out std_logic;
        done         : out std_logic
    );
end entity accumulator;

architecture rtl of accumulator is

    type state_t is (IDLE, OUTPUT);
    signal state : state_t;
    
    signal accum_reg   : signed(ACCUM_WIDTH-1 downto 0);
    signal ovf_reg     : std_logic;
    signal sat_reg     : std_logic;

    -- Helper functions for saturation values
    function get_max_val return signed is
        variable result : signed(ACCUM_WIDTH-1 downto 0);
    begin
        result := (others => '1');
        result(ACCUM_WIDTH-1) := '0';
        return result;
    end function;

    function get_min_val return signed is
        variable result : signed(ACCUM_WIDTH-1 downto 0);
    begin
        result := (others => '0');
        result(ACCUM_WIDTH-1) := '1';
        return result;
    end function;

    constant MAX_VAL : signed(ACCUM_WIDTH-1 downto 0) := get_max_val;
    constant MIN_VAL : signed(ACCUM_WIDTH-1 downto 0) := get_min_val;

begin

    process(clk)
        variable temp_sum : signed(ACCUM_WIDTH downto 0);
        variable data_ext : signed(ACCUM_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= IDLE;
                accum_reg <= (others => '0');
                ovf_reg   <= '0';
                sat_reg   <= '0';
            else
                case state is
                    when IDLE =>
                        if clear = '1' then
                            accum_reg <= (others => '0');
                            ovf_reg   <= '0';
                            sat_reg   <= '0';
                        elsif data_valid = '1' then
                            -- Accumulate immediately in IDLE when valid
                            data_ext := resize(data_in, ACCUM_WIDTH);
                            temp_sum := resize(accum_reg, ACCUM_WIDTH+1) + resize(data_ext, ACCUM_WIDTH+1);
                            
                            if ENABLE_SAT then
                                if temp_sum(ACCUM_WIDTH) /= temp_sum(ACCUM_WIDTH-1) then
                                    ovf_reg <= '1';
                                    sat_reg <= '1';
                                    if temp_sum(ACCUM_WIDTH) = '0' then
                                        accum_reg <= MAX_VAL;
                                    else
                                        accum_reg <= MIN_VAL;
                                    end if;
                                else
                                    accum_reg <= temp_sum(ACCUM_WIDTH-1 downto 0);
                                end if;
                            else
                                accum_reg <= temp_sum(ACCUM_WIDTH-1 downto 0);
                                if temp_sum(ACCUM_WIDTH) /= temp_sum(ACCUM_WIDTH-1) then
                                    ovf_reg <= '1';
                                end if;
                            end if;
                            
                            state <= OUTPUT;
                        end if;
                        
                    when OUTPUT =>
                        if out_ready = '1' then
                            state <= IDLE;
                        end if;
                        
                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    -- Output assignments
    accum_out  <= accum_reg;
    data_ready <= '1' when state = IDLE else '0';
    out_valid  <= '1' when state = OUTPUT else '0';
    done       <= '1' when state = OUTPUT else '0';
    overflow   <= ovf_reg;
    saturated  <= sat_reg;

end architecture rtl;