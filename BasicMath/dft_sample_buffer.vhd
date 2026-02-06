-- DFT Sample Buffer (256 samples)
-- Buffers resampled outputs for DFT processing
-- Dual-port: Write from resampler, Read from DFT
-- VHDL-93 Compatible
--
-- Operation:
--   1. Receives samples from Interpolation Engine
--   2. Stores in RAM using resampled_index as address
--   3. Signals buffer_full when last sample received
--   4. DFT reads samples via address interface
--
-- Author: Arun's PMU Project
-- Date: December 2024
-- Target: Xilinx ZCU106

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dft_sample_buffer is
    generic (
        BUFFER_SIZE   : integer := 256;
        SAMPLE_WIDTH  : integer := 16
    );
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        
        -- Write Interface (from Interpolation Engine)
        write_sample    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        write_index     : in  std_logic_vector(7 downto 0);
        write_valid     : in  std_logic;
        write_last      : in  std_logic;  -- Last sample indicator
        
        -- Read Interface (to DFT)
        read_addr       : in  std_logic_vector(7 downto 0);
        read_data       : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        
        -- Status
        buffer_full     : out std_logic;  -- Pulses when all 256 samples received
        sample_count    : out std_logic_vector(8 downto 0)  -- 0-256
    );
end dft_sample_buffer;

architecture behavioral of dft_sample_buffer is

    -- Dual-port RAM for sample storage
    type ram_type is array (0 to BUFFER_SIZE-1) of std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal sample_ram : ram_type := (others => (others => '0'));
    
    -- Internal signals
    signal write_addr_int : integer range 0 to BUFFER_SIZE-1;
    signal read_addr_int  : integer range 0 to BUFFER_SIZE-1;
    signal count_reg      : unsigned(8 downto 0) := (others => '0');
    signal full_pulse     : std_logic := '0';
    
    -- Read data register
    signal read_data_reg  : std_logic_vector(SAMPLE_WIDTH-1 downto 0) := (others => '0');

begin

    -- Address conversion
    write_addr_int <= to_integer(unsigned(write_index));
    read_addr_int <= to_integer(unsigned(read_addr));
    
    ---------------------------------------------------------------------------
    -- Write Process (Port A)
    ---------------------------------------------------------------------------
    write_process: process(clk, rst)
    begin
        if rst = '1' then
            count_reg <= (others => '0');
            full_pulse <= '0';
        elsif rising_edge(clk) then
            full_pulse <= '0';  -- Default
            
            if write_valid = '1' then
                -- Write sample to RAM
                sample_ram(write_addr_int) <= write_sample;
                
                -- Track count (reset on last, otherwise increment)
                if write_last = '1' then
                    count_reg <= to_unsigned(256, 9);
                    full_pulse <= '1';
                else
                    if count_reg < 256 then
                        count_reg <= count_reg + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Read Process (Port B)
    ---------------------------------------------------------------------------
    read_process: process(clk)
    begin
        if rising_edge(clk) then
            read_data_reg <= sample_ram(read_addr_int);
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    read_data    <= read_data_reg;
    buffer_full  <= full_pulse;
    sample_count <= std_logic_vector(count_reg);

end behavioral;
