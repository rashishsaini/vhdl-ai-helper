--------------------------------------------------------------------------------
-- Module: weight_register_bank
-- Description: Register bank for storing neural network weights and biases
--              Supports read/write operations for forward pass and weight update
--
-- Features:
--   - Parameterized size for different network topologies
--   - Asynchronous read (combinational) for fast access
--   - Synchronous write for reliable updates
--   - Optional initialization port for loading pre-trained weights
--   - Read-during-write returns OLD value (read-first behavior)
--
-- For 4-2-1 Network:
--   Layer 1: 8 weights (4 inputs × 2 neurons) + 2 biases = 10 values
--   Layer 2: 2 weights (2 inputs × 1 neuron)  + 1 bias   = 3 values
--   Total: 13 entries
--
-- Memory Map (example for 4-2-1):
--   Addr 0-7:   Layer 1 weights [w00, w01, w02, w03, w10, w11, w12, w13]
--   Addr 8-9:   Layer 1 biases  [b0, b1]
--   Addr 10-11: Layer 2 weights [w20, w21]
--   Addr 12:    Layer 2 bias    [b2]
--
-- Author: FPGA Neural Network Project
-- Complexity: EASY (⭐)
-- Dependencies: None
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity weight_register_bank is
    generic (
        DATA_WIDTH   : integer := 16;     -- Q2.13 format
        NUM_ENTRIES  : integer := 13;     -- Total weights + biases
        ADDR_WIDTH   : integer := 4       -- ceil(log2(NUM_ENTRIES))
    );
    port (
        -- Clock and Reset
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Read Port (asynchronous/combinational)
        rd_en        : in  std_logic;
        rd_addr      : in  unsigned(ADDR_WIDTH-1 downto 0);
        rd_data      : out signed(DATA_WIDTH-1 downto 0);
        rd_valid     : out std_logic;
        
        -- Write Port (synchronous)
        wr_en        : in  std_logic;
        wr_addr      : in  unsigned(ADDR_WIDTH-1 downto 0);
        wr_data      : in  signed(DATA_WIDTH-1 downto 0);
        
        -- Initialization Port (for loading pre-trained weights)
        init_en      : in  std_logic;
        init_addr    : in  unsigned(ADDR_WIDTH-1 downto 0);
        init_data    : in  signed(DATA_WIDTH-1 downto 0);
        init_done    : out std_logic      -- Directly connected to init_en for now
    );
end entity weight_register_bank;

architecture rtl of weight_register_bank is

    ---------------------------------------------------------------------------
    -- Register Array
    ---------------------------------------------------------------------------
    type reg_array_t is array (0 to NUM_ENTRIES-1) of signed(DATA_WIDTH-1 downto 0);
    signal registers : reg_array_t := (others => (others => '0'));

    ---------------------------------------------------------------------------
    -- Internal Signals
    ---------------------------------------------------------------------------
    signal rd_addr_int : integer range 0 to NUM_ENTRIES-1;
    signal wr_addr_int : integer range 0 to NUM_ENTRIES-1;
    signal init_addr_int : integer range 0 to NUM_ENTRIES-1;
    
    signal rd_addr_valid : std_logic;
    signal wr_addr_valid : std_logic;
    signal init_addr_valid : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Address Conversion and Validation
    ---------------------------------------------------------------------------
    rd_addr_int <= to_integer(rd_addr) when to_integer(rd_addr) < NUM_ENTRIES else 0;
    wr_addr_int <= to_integer(wr_addr) when to_integer(wr_addr) < NUM_ENTRIES else 0;
    init_addr_int <= to_integer(init_addr) when to_integer(init_addr) < NUM_ENTRIES else 0;
    
    rd_addr_valid <= '1' when to_integer(rd_addr) < NUM_ENTRIES else '0';
    wr_addr_valid <= '1' when to_integer(wr_addr) < NUM_ENTRIES else '0';
    init_addr_valid <= '1' when to_integer(init_addr) < NUM_ENTRIES else '0';

    ---------------------------------------------------------------------------
    -- Synchronous Write Process
    -- Priority: rst > init > write
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                -- Reset all registers to zero
                registers <= (others => (others => '0'));
            elsif init_en = '1' and init_addr_valid = '1' then
                -- Initialization has priority over normal writes
                registers(init_addr_int) <= init_data;
            elsif wr_en = '1' and wr_addr_valid = '1' then
                -- Normal write operation
                registers(wr_addr_int) <= wr_data;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Synchronous Read Process (for better Vivado compatibility)
    -- Registered read for consistent timing across simulators
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rd_data <= (others => '0');
                rd_valid <= '0';
            elsif rd_en = '1' and rd_addr_valid = '1' then
                rd_data <= registers(rd_addr_int);
                rd_valid <= '1';
            else
                rd_valid <= '0';
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Initialization Status
    ---------------------------------------------------------------------------
    init_done <= init_en and init_addr_valid;

end architecture rtl;