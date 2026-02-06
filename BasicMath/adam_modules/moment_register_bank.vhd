--------------------------------------------------------------------------------
-- Module: moment_register_bank
-- Description: Storage for Adam optimizer moment vectors (m and v)
--              Dual-port memory: asynchronous read, synchronous write
--
-- Storage: 13 parameters × 2 moments (m, v) × 16 bits = 416 bits total
--
-- Interface:
--   - Asynchronous read: data available immediately when rd_en = '1'
--   - Synchronous write: data written on rising edge when wr_en = '1'
--   - Clear signal: resets all moments to 0 (for optimizer reset)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity moment_register_bank is
    generic (
        DATA_WIDTH : integer := 16;   -- Q2.13 format
        NUM_PARAMS : integer := 13;   -- 4-2-1 network has 13 trainable parameters
        ADDR_WIDTH : integer := 4     -- log2(13) = 4 bits for addressing
    );
    port (
        clk   : in std_logic;
        rst   : in std_logic;
        clear : in std_logic;  -- Reset all moments to 0

        -- Read port (asynchronous)
        rd_en     : in  std_logic;
        rd_addr   : in  unsigned(ADDR_WIDTH-1 downto 0);
        m_rd_data : out signed(DATA_WIDTH-1 downto 0);
        v_rd_data : out signed(DATA_WIDTH-1 downto 0);
        rd_valid  : out std_logic;

        -- Write port (synchronous)
        wr_en     : in std_logic;
        wr_addr   : in unsigned(ADDR_WIDTH-1 downto 0);
        m_wr_data : in signed(DATA_WIDTH-1 downto 0);
        v_wr_data : in signed(DATA_WIDTH-1 downto 0)
    );
end entity moment_register_bank;

architecture rtl of moment_register_bank is

    ---------------------------------------------------------------------------
    -- Memory Arrays (one for m, one for v)
    ---------------------------------------------------------------------------
    type moment_array_t is array (0 to NUM_PARAMS-1) of signed(DATA_WIDTH-1 downto 0);

    signal m_array : moment_array_t := (others => (others => '0'));
    signal v_array : moment_array_t := (others => (others => '0'));

    ---------------------------------------------------------------------------
    -- Read Valid Flag
    ---------------------------------------------------------------------------
    signal rd_valid_reg : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Synchronous Write Process
    ---------------------------------------------------------------------------
    write_proc : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                -- Reset all moments to 0
                m_array <= (others => (others => '0'));
                v_array <= (others => (others => '0'));

            elsif clear = '1' then
                -- Clear signal: reset all moments (optimizer reset)
                m_array <= (others => (others => '0'));
                v_array <= (others => (others => '0'));

            elsif wr_en = '1' then
                -- Write to specified address
                if to_integer(wr_addr) < NUM_PARAMS then
                    m_array(to_integer(wr_addr)) <= m_wr_data;
                    v_array(to_integer(wr_addr)) <= v_wr_data;
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Asynchronous Read Process
    ---------------------------------------------------------------------------
    read_proc : process(rd_en, rd_addr, m_array, v_array)
    begin
        if rd_en = '1' then
            if to_integer(rd_addr) < NUM_PARAMS then
                m_rd_data <= m_array(to_integer(rd_addr));
                v_rd_data <= v_array(to_integer(rd_addr));
                rd_valid_reg <= '1';
            else
                -- Invalid address: return 0
                m_rd_data <= (others => '0');
                v_rd_data <= (others => '0');
                rd_valid_reg <= '0';
            end if;
        else
            m_rd_data <= (others => '0');
            v_rd_data <= (others => '0');
            rd_valid_reg <= '0';
        end if;
    end process;

    rd_valid <= rd_valid_reg;

end architecture rtl;
