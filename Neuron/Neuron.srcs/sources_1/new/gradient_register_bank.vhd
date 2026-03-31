--------------------------------------------------------------------------------
-- Module: gradient_register_bank
-- Description: Register bank for accumulating gradients during backpropagation
--              Uses wider precision (40-bit) to prevent overflow during summation
--
-- For 4-2-1 Network: 13 entries (same as weight_register_bank)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity gradient_register_bank is
    generic (
        INPUT_WIDTH  : integer := 32;
        ACCUM_WIDTH  : integer := 40;
        NUM_ENTRIES  : integer := 13;
        ADDR_WIDTH   : integer := 4
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        clear        : in  std_logic;
        
        accum_en     : in  std_logic;
        accum_addr   : in  unsigned(ADDR_WIDTH-1 downto 0);
        accum_data   : in  signed(INPUT_WIDTH-1 downto 0);
        
        rd_en        : in  std_logic;
        rd_addr      : in  unsigned(ADDR_WIDTH-1 downto 0);
        rd_data      : out signed(ACCUM_WIDTH-1 downto 0);
        rd_valid     : out std_logic;
        
        overflow     : out std_logic
    );
end entity gradient_register_bank;

architecture rtl of gradient_register_bank is

    type accum_array_t is array (0 to NUM_ENTRIES-1) of signed(ACCUM_WIDTH-1 downto 0);
    signal accumulators : accum_array_t := (others => (others => '0'));
    signal any_overflow : std_logic := '0';

begin

    process(clk)
        variable sum : signed(ACCUM_WIDTH downto 0);
        variable data_ext : signed(ACCUM_WIDTH-1 downto 0);
        variable addr_i : integer;
        variable max_val : signed(ACCUM_WIDTH-1 downto 0);
        variable min_val : signed(ACCUM_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' or clear = '1' then
                accumulators <= (others => (others => '0'));
                any_overflow <= '0';
            elsif accum_en = '1' then
                addr_i := to_integer(accum_addr);
                if addr_i < NUM_ENTRIES then
                    data_ext := resize(accum_data, ACCUM_WIDTH);
                    sum := resize(accumulators(addr_i), ACCUM_WIDTH+1) + 
                           resize(data_ext, ACCUM_WIDTH+1);
                    
                    if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
                        any_overflow <= '1';
                        if sum(ACCUM_WIDTH) = '0' then
                            -- Positive overflow: set to max (0111...1111)
                            max_val := (others => '1');
                            max_val(ACCUM_WIDTH-1) := '0';
                            accumulators(addr_i) <= max_val;
                        else
                            -- Negative overflow: set to min (1000...0000)
                            min_val := (others => '0');
                            min_val(ACCUM_WIDTH-1) := '1';
                            accumulators(addr_i) <= min_val;
                        end if;
                    else
                        accumulators(addr_i) <= sum(ACCUM_WIDTH-1 downto 0);
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(rd_en, rd_addr, accumulators)
        variable addr_i : integer;
    begin
        addr_i := to_integer(rd_addr);
        if rd_en = '1' and addr_i < NUM_ENTRIES then
            rd_data  <= accumulators(addr_i);
            rd_valid <= '1';
        else
            rd_data  <= (others => '0');
            rd_valid <= '0';
        end if;
    end process;

    overflow <= any_overflow;

end architecture rtl;
