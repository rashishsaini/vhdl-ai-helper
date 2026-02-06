--------------------------------------------------------------------------------
-- Module: input_buffer
-- Description: Buffers input samples for neural network forward pass
--              Simple register array with load and read interfaces
--
-- Features:
--   - Parameterized for different input sizes
--   - Sequential or random address loading
--   - Ready flag indicates buffer has valid data
--   - Clear function for new samples
--
-- For 4-2-1 Network:
--   4 input values per sample
--
-- Author: FPGA Neural Network Project
-- Complexity: EASY (⭐)
-- Dependencies: None
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity input_buffer is
    generic (
        DATA_WIDTH   : integer := 16;    -- Q2.13 format
        NUM_INPUTS   : integer := 4;     -- Number of input features
        ADDR_WIDTH   : integer := 2      -- ceil(log2(NUM_INPUTS))
    );
    port (
        -- Clock and Reset
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Control
        clear        : in  std_logic;    -- Clear buffer for new sample
        
        -- Load Interface (write)
        load_en      : in  std_logic;
        load_addr    : in  unsigned(ADDR_WIDTH-1 downto 0);
        load_data    : in  signed(DATA_WIDTH-1 downto 0);
        
        -- Read Interface
        rd_en        : in  std_logic;
        rd_addr      : in  unsigned(ADDR_WIDTH-1 downto 0);
        rd_data      : out signed(DATA_WIDTH-1 downto 0);
        
        -- Status
        ready        : out std_logic;    -- All inputs loaded
        count        : out unsigned(ADDR_WIDTH downto 0)  -- Number of loaded values
    );
end entity input_buffer;

architecture rtl of input_buffer is

    ---------------------------------------------------------------------------
    -- Buffer Storage
    ---------------------------------------------------------------------------
    type buffer_t is array (0 to NUM_INPUTS-1) of signed(DATA_WIDTH-1 downto 0);
    signal buffer_reg : buffer_t := (others => (others => '0'));

    ---------------------------------------------------------------------------
    -- Load Tracking
    ---------------------------------------------------------------------------
    -- Track which addresses have been written (bitmask)
    signal loaded_mask : std_logic_vector(NUM_INPUTS-1 downto 0) := (others => '0');
    signal load_count  : unsigned(ADDR_WIDTH downto 0) := (others => '0');
    signal all_loaded  : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Internal Signals
    ---------------------------------------------------------------------------
    signal load_addr_int : integer range 0 to NUM_INPUTS-1;
    signal rd_addr_int   : integer range 0 to NUM_INPUTS-1;
    signal load_addr_valid : std_logic;
    signal rd_addr_valid   : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Address Validation
    ---------------------------------------------------------------------------
    load_addr_int <= to_integer(load_addr) when to_integer(load_addr) < NUM_INPUTS else 0;
    rd_addr_int   <= to_integer(rd_addr) when to_integer(rd_addr) < NUM_INPUTS else 0;
    
    load_addr_valid <= '1' when to_integer(load_addr) < NUM_INPUTS else '0';
    rd_addr_valid   <= '1' when to_integer(rd_addr) < NUM_INPUTS else '0';

    ---------------------------------------------------------------------------
    -- Load Process (Synchronous)
    ---------------------------------------------------------------------------
    process(clk)
        variable new_mask : std_logic_vector(NUM_INPUTS-1 downto 0);
        variable cnt : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' or clear = '1' then
                -- Clear buffer and tracking
                buffer_reg  <= (others => (others => '0'));
                loaded_mask <= (others => '0');
                load_count  <= (others => '0');
                all_loaded  <= '0';
            elsif load_en = '1' and load_addr_valid = '1' then
                -- Store data
                buffer_reg(load_addr_int) <= load_data;
                
                -- Update loaded mask
                new_mask := loaded_mask;
                new_mask(load_addr_int) := '1';
                loaded_mask <= new_mask;
                
                -- Count loaded values
                cnt := 0;
                for i in 0 to NUM_INPUTS-1 loop
                    if new_mask(i) = '1' then
                        cnt := cnt + 1;
                    end if;
                end loop;
                load_count <= to_unsigned(cnt, ADDR_WIDTH+1);
                
                -- Check if all loaded
                if cnt = NUM_INPUTS then
                    all_loaded <= '1';
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Read Output (Combinational)
    ---------------------------------------------------------------------------
    rd_data <= buffer_reg(rd_addr_int) when (rd_en = '1' and rd_addr_valid = '1')
               else (others => '0');

    ---------------------------------------------------------------------------
    -- Status Outputs
    ---------------------------------------------------------------------------
    ready <= all_loaded;
    count <= load_count;

end architecture rtl;