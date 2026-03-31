-- Circular Buffer Controller for PMU Resampling System
-- Continuously stores incoming ADC samples in circular fashion
-- Provides random read access for resampler interpolation
-- VHDL-93 Compatible (No VHDL-2008 features)
--
-- Key Features:
--   - Dual-port operation: write at ADC rate, read at any time
--   - No "full" signal - always accepting samples (overwrites oldest)
--   - 32-bit absolute sample counter for position tracking
--   - Automatic wrap-around on both read and write
--
-- Author: Arun's PMU Project
-- Date: December 2024
-- Target: Xilinx ZCU106

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity circular_buffer_controller is
    generic (
        BUFFER_DEPTH      : integer := 512;   -- Number of storage locations
        BUFFER_ADDR_WIDTH : integer := 9;     -- Address bits (log2(512) = 9)
        SAMPLE_WIDTH      : integer := 16     -- Bits per sample
    );
    port (
        -- Clock and Reset
        clk             : in  std_logic;
        rst             : in  std_logic;
        
        -- Write Interface (from ADC, runs at 15 kHz)
        sample_in       : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        sample_valid    : in  std_logic;      -- Sample valid strobe
        
        -- Read Interface (from Sample Fetcher)
        read_addr       : in  std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
        read_enable     : in  std_logic;
        read_data       : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        read_valid      : out std_logic;
        
        -- Status Outputs
        write_addr_out  : out std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
        sample_count    : out std_logic_vector(31 downto 0);  -- Absolute counter
        
        -- Buffer offset for resampler (oldest valid sample position)
        buffer_oldest   : out std_logic_vector(31 downto 0)
    );
end circular_buffer_controller;

architecture behavioral of circular_buffer_controller is

    -- Memory Array for circular buffer
    -- Using block RAM inference style for Xilinx
    type memory_array is array (0 to BUFFER_DEPTH-1) of 
        std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal sample_memory : memory_array := (others => (others => '0'));
    
    -- Write pointer (wraps at BUFFER_DEPTH)
    signal write_ptr : unsigned(BUFFER_ADDR_WIDTH-1 downto 0) := (others => '0');
    
    -- Absolute sample counter (never wraps, 32-bit)
    signal abs_sample_count : unsigned(31 downto 0) := (others => '0');
    
    -- Read pipeline registers (1-cycle latency for synchronous BRAM)
    signal read_data_reg   : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal read_valid_reg  : std_logic;
    
    -- Buffer filled flag (set after first wrap-around)
    signal buffer_filled : std_logic := '0';
    
    -- Oldest sample position calculation
    signal oldest_sample_pos : unsigned(31 downto 0);

begin

    ---------------------------------------------------------------------------
    -- Write Process: Store samples at write pointer, increment pointer
    -- Runs continuously at ADC rate (15 kHz)
    ---------------------------------------------------------------------------
    write_process: process(clk, rst)
    begin
        if rst = '1' then
            write_ptr <= (others => '0');
            abs_sample_count <= (others => '0');
            buffer_filled <= '0';
        elsif rising_edge(clk) then
            if sample_valid = '1' then
                -- Write sample to current pointer location
                sample_memory(to_integer(write_ptr)) <= sample_in;
                
                -- Increment write pointer with wrap-around
                if write_ptr = BUFFER_DEPTH - 1 then
                    write_ptr <= (others => '0');
                    buffer_filled <= '1';  -- Buffer has wrapped at least once
                else
                    write_ptr <= write_ptr + 1;
                end if;
                
                -- Increment absolute counter (never wraps in practice)
                abs_sample_count <= abs_sample_count + 1;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Read Process: Synchronous read from buffer
    -- 1-cycle latency: data available on next clock after read_enable
    ---------------------------------------------------------------------------
    read_process: process(clk, rst)
    begin
        if rst = '1' then
            read_data_reg <= (others => '0');
            read_valid_reg <= '0';
        elsif rising_edge(clk) then
            -- Valid follows read_enable with 1-cycle delay
            read_valid_reg <= read_enable;
            
            -- Read from memory on read_enable (synchronous BRAM)
            if read_enable = '1' then
                read_data_reg <= sample_memory(to_integer(unsigned(read_addr)));
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Oldest Sample Position Calculation
    -- The oldest sample in buffer is at position (abs_count - BUFFER_DEPTH)
    -- but only after buffer has been filled at least once
    ---------------------------------------------------------------------------
    oldest_calc_process: process(clk, rst)
    begin
        if rst = '1' then
            oldest_sample_pos <= (others => '0');
        elsif rising_edge(clk) then
            if buffer_filled = '1' then
                -- After first wrap, oldest is BUFFER_DEPTH samples behind current
                oldest_sample_pos <= abs_sample_count - to_unsigned(BUFFER_DEPTH, 32);
            else
                -- Before first wrap, oldest is sample 0
                oldest_sample_pos <= (others => '0');
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    read_data <= read_data_reg;
    read_valid <= read_valid_reg;
    write_addr_out <= std_logic_vector(write_ptr);
    sample_count <= std_logic_vector(abs_sample_count);
    buffer_oldest <= std_logic_vector(oldest_sample_pos);

end behavioral;