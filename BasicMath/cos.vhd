library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity cosine_single_k_rom is
    generic (
        WINDOW_SIZE : integer := 256;       -- N = 256 samples
        COEFF_WIDTH : integer := 16;        -- Q1.15 format
        K_VALUE     : integer := 1          -- Fixed k value (fundamental frequency)
    );
    port (
        -- Clock and Control
        clk         : in  std_logic;
        rst         : in  std_logic;
        enable      : in  std_logic := '1';
        
        -- Address Interface
        n_addr      : in  std_logic_vector(7 downto 0);  -- Sample index (0 to 255)
        
        -- Data Output
        cos_coeff   : out std_logic_vector(COEFF_WIDTH-1 downto 0);  -- Q1.15 cosine value
        data_valid  : out std_logic
    );
end cosine_single_k_rom;

architecture behavioral of cosine_single_k_rom is
    
    -- ROM Memory Type: 256 locations for one k value
    type single_k_memory_type is array (0 to WINDOW_SIZE-1) of
         std_logic_vector(COEFF_WIDTH-1 downto 0);
    
    -- Function to convert real cosine value to Q1.15 fixed-point
    function real_to_q15(real_val : real) return std_logic_vector is
        variable temp_int : integer;
        variable result : std_logic_vector(15 downto 0);
    begin
        if real_val > 0.99996 then
            temp_int := 32767;
        elsif real_val < -1.0 then
            temp_int := -32768;
        else
            temp_int := integer(real_val * 32767.0);
        end if;
        result := std_logic_vector(to_signed(temp_int, 16));
        return result;
    end function;
    
    -- Function to initialize ROM for single k value
    function init_single_k_rom return single_k_memory_type is
        variable rom_data : single_k_memory_type;
        variable angle : real;
        variable cos_val : real;
        constant PI : real := MATH_PI;
    begin
        for n in 0 to WINDOW_SIZE-1 loop
            -- Calculate cos(2π*K_VALUE*n/N)
            angle := 2.0 * PI * real(K_VALUE) * real(n) / real(WINDOW_SIZE);
            cos_val := cos(angle);
            rom_data(n) := real_to_q15(cos_val);
        end loop;
        return rom_data;
    end function;
    
    -- Initialize ROM with precomputed values for fixed k
    signal coeff_memory : single_k_memory_type := init_single_k_rom;
    
    -- Internal signals
    signal n_int : integer range 0 to WINDOW_SIZE-1;
    signal output_reg : std_logic_vector(COEFF_WIDTH-1 downto 0);
    signal valid_reg : std_logic;
    
begin
    
    -- Convert address to integer
    n_int <= to_integer(unsigned(n_addr));
    
    -- Synchronous ROM read process
    rom_read_process: process(clk, rst)
    begin
        if rst = '1' then
            output_reg <= (others => '0');
            valid_reg <= '0';
        elsif rising_edge(clk) then
            if enable = '1' then
                -- Read coefficient from ROM
                output_reg <= coeff_memory(n_int);
                valid_reg <= '1';
            else
                valid_reg <= '0';
            end if;
        end if;
    end process;
    
    -- Output assignments
    cos_coeff <= output_reg;
    data_valid <= valid_reg;
    
end behavioral;
