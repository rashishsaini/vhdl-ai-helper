--------------------------------------------------------------------------------
-- Module: mac_unit
-- Description: Multiply-Accumulate unit for neural network computations
--              Computes: accumulator += weight * input
--              
-- Format: 
--   Input/Weight: Q2.13 (16-bit signed)
--   Product: Q4.26 (32-bit signed)
--   Accumulator: Q10.26 (40-bit signed)
--
-- Pipeline: 2 stages
--   Stage 1: Multiply (registered)
--   Stage 2: Accumulate (registered)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity mac_unit is
    generic (
        DATA_WIDTH   : integer := 16;
        PRODUCT_WIDTH: integer := 32;
        ACCUM_WIDTH  : integer := 40;
        ENABLE_SAT   : boolean := true
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        clear        : in  std_logic;
        enable       : in  std_logic;
        
        data_in      : in  signed(DATA_WIDTH-1 downto 0);
        weight       : in  signed(DATA_WIDTH-1 downto 0);
        
        accum_out    : out signed(ACCUM_WIDTH-1 downto 0);
        valid        : out std_logic;
        overflow     : out std_logic;
        busy         : out std_logic
    );
end entity mac_unit;

architecture rtl of mac_unit is

    signal mult_result   : signed(PRODUCT_WIDTH-1 downto 0) := (others => '0');
    signal mult_valid    : std_logic := '0';
    signal accum_reg     : signed(ACCUM_WIDTH-1 downto 0) := (others => '0');
    signal accum_valid   : std_logic := '0';
    signal overflow_reg  : std_logic := '0';
    signal clear_d1      : std_logic := '0';

begin

    -- Stage 1: Multiply
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                mult_result <= (others => '0');
                mult_valid  <= '0';
                clear_d1    <= '0';
            else
                clear_d1 <= clear;
                if enable = '1' then
                    mult_result <= data_in * weight;
                    mult_valid  <= '1';
                else
                    mult_valid <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Stage 2: Accumulate
    process(clk)
        variable sum : signed(ACCUM_WIDTH downto 0);
        variable product_ext : signed(ACCUM_WIDTH-1 downto 0);
        variable max_val : signed(ACCUM_WIDTH-1 downto 0);
        variable min_val : signed(ACCUM_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                accum_reg    <= (others => '0');
                accum_valid  <= '0';
                overflow_reg <= '0';
            elsif clear = '1' or clear_d1 = '1' then
                accum_reg    <= (others => '0');
                accum_valid  <= '0';
                overflow_reg <= '0';
            elsif mult_valid = '1' then
                product_ext := resize(mult_result, ACCUM_WIDTH);
                sum := resize(accum_reg, ACCUM_WIDTH+1) + resize(product_ext, ACCUM_WIDTH+1);
                
                if ENABLE_SAT then
                    if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
                        overflow_reg <= '1';
                        if sum(ACCUM_WIDTH) = '0' then
                            max_val := (others => '1');
                            max_val(ACCUM_WIDTH-1) := '0';
                            accum_reg <= max_val;
                        else
                            min_val := (others => '0');
                            min_val(ACCUM_WIDTH-1) := '1';
                            accum_reg <= min_val;
                        end if;
                    else
                        accum_reg <= sum(ACCUM_WIDTH-1 downto 0);
                    end if;
                else
                    accum_reg <= sum(ACCUM_WIDTH-1 downto 0);
                    if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then
                        overflow_reg <= '1';
                    end if;
                end if;
                
                accum_valid <= '1';
            else
                accum_valid <= '0';
            end if;
        end if;
    end process;

    accum_out <= accum_reg;
    valid     <= accum_valid;
    overflow  <= overflow_reg;
    busy      <= mult_valid;

end architecture rtl;
