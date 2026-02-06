--------------------------------------------------------------------------------
-- Module: forward_cache
-- Description: Stores z (pre-activation) and a (activation) values during
--              forward pass for use in backpropagation
--
-- For 4-2-1 Network:
--   z values: 3 (hidden: 2, output: 1)
--   a values: 7 (input: 4, hidden: 2, output: 1)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity forward_cache is
    generic (
        DATA_WIDTH       : integer := 16;
        NUM_Z_VALUES     : integer := 3;
        NUM_A_VALUES     : integer := 7;
        Z_ADDR_WIDTH     : integer := 2;
        A_ADDR_WIDTH     : integer := 3
    );
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        clear            : in  std_logic;
        
        z_wr_en          : in  std_logic;
        z_wr_addr        : in  unsigned(Z_ADDR_WIDTH-1 downto 0);
        z_wr_data        : in  signed(DATA_WIDTH-1 downto 0);
        z_rd_en          : in  std_logic;
        z_rd_addr        : in  unsigned(Z_ADDR_WIDTH-1 downto 0);
        z_rd_data        : out signed(DATA_WIDTH-1 downto 0);
        z_rd_valid       : out std_logic;
        
        a_wr_en          : in  std_logic;
        a_wr_addr        : in  unsigned(A_ADDR_WIDTH-1 downto 0);
        a_wr_data        : in  signed(DATA_WIDTH-1 downto 0);
        a_rd_en          : in  std_logic;
        a_rd_addr        : in  unsigned(A_ADDR_WIDTH-1 downto 0);
        a_rd_data        : out signed(DATA_WIDTH-1 downto 0);
        a_rd_valid       : out std_logic
    );
end entity forward_cache;

architecture rtl of forward_cache is

    type z_cache_t is array (0 to NUM_Z_VALUES-1) of signed(DATA_WIDTH-1 downto 0);
    type a_cache_t is array (0 to NUM_A_VALUES-1) of signed(DATA_WIDTH-1 downto 0);
    
    signal z_cache : z_cache_t := (others => (others => '0'));
    signal a_cache : a_cache_t := (others => (others => '0'));

begin

    -- Z Cache Write
    process(clk)
        variable addr_i : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' or clear = '1' then
                z_cache <= (others => (others => '0'));
            elsif z_wr_en = '1' then
                addr_i := to_integer(z_wr_addr);
                if addr_i < NUM_Z_VALUES then
                    z_cache(addr_i) <= z_wr_data;
                end if;
            end if;
        end if;
    end process;

    -- A Cache Write
    process(clk)
        variable addr_i : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' or clear = '1' then
                a_cache <= (others => (others => '0'));
            elsif a_wr_en = '1' then
                addr_i := to_integer(a_wr_addr);
                if addr_i < NUM_A_VALUES then
                    a_cache(addr_i) <= a_wr_data;
                end if;
            end if;
        end if;
    end process;

    -- Z Cache Read
    process(z_rd_en, z_rd_addr, z_cache)
        variable addr_i : integer;
    begin
        addr_i := to_integer(z_rd_addr);
        if z_rd_en = '1' and addr_i < NUM_Z_VALUES then
            z_rd_data  <= z_cache(addr_i);
            z_rd_valid <= '1';
        else
            z_rd_data  <= (others => '0');
            z_rd_valid <= '0';
        end if;
    end process;

    -- A Cache Read
    process(a_rd_en, a_rd_addr, a_cache)
        variable addr_i : integer;
    begin
        addr_i := to_integer(a_rd_addr);
        if a_rd_en = '1' and addr_i < NUM_A_VALUES then
            a_rd_data  <= a_cache(addr_i);
            a_rd_valid <= '1';
        else
            a_rd_data  <= (others => '0');
            a_rd_valid <= '0';
        end if;
    end process;

end architecture rtl;
