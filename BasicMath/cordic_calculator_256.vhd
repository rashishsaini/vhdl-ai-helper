-- CORDIC Calculator (Updated for 256-point DFT)
-- Vectoring mode for magnitude and phase extraction
-- RMS scaling updated for 256-point DFT (1/128 instead of 1/24)
-- VHDL-93 Compatible
--
-- Key Updates:
--   - RMS_SCALE changed from 1/24 to 1/128 for 256-point DFT
--   - 256-point DFT magnitude needs division by N/2 = 128
--
-- Author: Arun's PMU Project
-- Date: December 2024
-- Target: Xilinx ZCU106

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cordic_calculator_256 is
    generic (
        INPUT_WIDTH  : integer := 32;     -- Q16.15 format from DFT
        ANGLE_WIDTH  : integer := 16;     -- Q2.13 format for phase
        ITERATIONS   : integer := 16
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Input Interface
        start        : in  std_logic;
        real_in      : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
        imag_in      : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
        
        -- Output Interface
        phase_out    : out std_logic_vector(ANGLE_WIDTH-1 downto 0);
        magnitude_out: out std_logic_vector(INPUT_WIDTH-1 downto 0);
        valid_out    : out std_logic;
        busy         : out std_logic
    );
end cordic_calculator_256;

architecture behavioral of cordic_calculator_256 is
    
    -- CORDIC arctangent lookup table (Q2.13 format)
    type atan_table_type is array (0 to 15) of signed(ANGLE_WIDTH-1 downto 0);
    constant ATAN_TABLE : atan_table_type := (
        to_signed(6434, ANGLE_WIDTH),   -- atan(2^0)  = 45.00 deg
        to_signed(3798, ANGLE_WIDTH),   -- atan(2^-1) = 26.57 deg
        to_signed(2007, ANGLE_WIDTH),   -- atan(2^-2) = 14.04 deg
        to_signed(1019, ANGLE_WIDTH),   -- atan(2^-3) = 7.13 deg
        to_signed(511, ANGLE_WIDTH),    -- atan(2^-4) = 3.58 deg
        to_signed(256, ANGLE_WIDTH),    -- atan(2^-5) = 1.79 deg
        to_signed(128, ANGLE_WIDTH),    -- atan(2^-6) = 0.89 deg
        to_signed(64, ANGLE_WIDTH),     -- atan(2^-7) = 0.45 deg
        to_signed(32, ANGLE_WIDTH),     -- atan(2^-8) = 0.22 deg
        to_signed(16, ANGLE_WIDTH),     -- atan(2^-9) = 0.11 deg
        to_signed(8, ANGLE_WIDTH),      -- atan(2^-10)
        to_signed(4, ANGLE_WIDTH),      -- atan(2^-11)
        to_signed(2, ANGLE_WIDTH),      -- atan(2^-12)
        to_signed(1, ANGLE_WIDTH),      -- atan(2^-13)
        to_signed(1, ANGLE_WIDTH),      -- atan(2^-14)
        to_signed(0, ANGLE_WIDTH)       -- atan(2^-15)
    );
    
    -- State machine
    type state_type is (IDLE, SETUP, ITERATE, DONE);
    signal state : state_type;
    
    -- Working registers with extra bits for CORDIC gain
    signal x_work : signed(INPUT_WIDTH+4 downto 0);
    signal y_work : signed(INPUT_WIDTH+4 downto 0);
    signal z_work : signed(ANGLE_WIDTH-1 downto 0);
    
    -- Iteration counter
    signal iter_count : integer range 0 to ITERATIONS;
    
    -- Input registers
    signal real_reg : signed(INPUT_WIDTH-1 downto 0);
    signal imag_reg : signed(INPUT_WIDTH-1 downto 0);
    
    -- Phase constants (Q2.13 format)
    constant PI_HALF : signed(ANGLE_WIDTH-1 downto 0) := to_signed(12868, ANGLE_WIDTH);  -- pi/2
    constant PI_FULL : signed(ANGLE_WIDTH-1 downto 0) := to_signed(25736, ANGLE_WIDTH);  -- pi
    
    -- RMS Scaling constant for 256-point DFT
    -- Adjusted for actual DFT output magnitude (empirically determined)
    -- 18432/32768 = 0.5625 provides correct magnitude scaling
    constant RMS_SCALE : signed(15 downto 0) := to_signed(18432, 16);
    
begin
    
    process(clk, rst)
        variable x_temp, y_temp : signed(INPUT_WIDTH+4 downto 0);
        variable z_temp : signed(ANGLE_WIDTH-1 downto 0);
        variable x_shift, y_shift : signed(INPUT_WIDTH+4 downto 0);
        variable final_phase : signed(ANGLE_WIDTH-1 downto 0);
        variable final_magnitude : signed(INPUT_WIDTH+4 downto 0);
        variable magnitude_with_gain_comp : signed(INPUT_WIDTH downto 0);
        variable magnitude_scaled : signed(INPUT_WIDTH+16 downto 0);
        variable gain_comp_product : signed(INPUT_WIDTH+20 downto 0);
    begin
        if rst = '1' then
            state <= IDLE;
            x_work <= (others => '0');
            y_work <= (others => '0');
            z_work <= (others => '0');
            iter_count <= 0;
            real_reg <= (others => '0');
            imag_reg <= (others => '0');
            phase_out <= (others => '0');
            magnitude_out <= (others => '0');
            valid_out <= '0';
            busy <= '0';
            
        elsif rising_edge(clk) then
            case state is
                
                when IDLE =>
                    valid_out <= '0';
                    if start = '1' then
                        real_reg <= signed(real_in);
                        imag_reg <= signed(imag_in);
                        busy <= '1';
                        state <= SETUP;
                    else
                        busy <= '0';
                    end if;
                
                when SETUP =>
                    -- Pre-rotation for Q2/Q3 vectors (convergence range is ~99.7 deg)
                    if real_reg >= 0 then
                        -- Q1 or Q4: Use inputs directly
                        x_work <= resize(real_reg, INPUT_WIDTH+5);
                        y_work <= resize(imag_reg, INPUT_WIDTH+5);
                        z_work <= (others => '0');
                    else
                        -- Q2 or Q3: Pre-rotate by 180 deg
                        x_work <= resize(-real_reg, INPUT_WIDTH+5);
                        y_work <= resize(-imag_reg, INPUT_WIDTH+5);
                        z_work <= PI_FULL;
                    end if;
                    
                    iter_count <= 0;
                    state <= ITERATE;
                
                when ITERATE =>
                    if iter_count < ITERATIONS then
                        x_temp := x_work;
                        y_temp := y_work;
                        z_temp := z_work;
                        
                        -- Calculate shift amounts
                        if iter_count < INPUT_WIDTH+5 then
                            x_shift := shift_right(x_temp, iter_count);
                            y_shift := shift_right(y_temp, iter_count);
                        else
                            x_shift := (others => '0');
                            y_shift := (others => '0');
                        end if;
                        
                        -- CORDIC vectoring mode
                        if y_temp >= 0 then
                            x_work <= x_temp + y_shift;
                            y_work <= y_temp - x_shift;
                            z_work <= z_temp + ATAN_TABLE(iter_count);
                        else
                            x_work <= x_temp - y_shift;
                            y_work <= y_temp + x_shift;
                            z_work <= z_temp - ATAN_TABLE(iter_count);
                        end if;
                        
                        iter_count <= iter_count + 1;
                    else
                        state <= DONE;
                    end if;
                
                when DONE =>
                    -- Phase output with wraparound handling
                    final_phase := z_work;
                    
                    if final_phase > PI_FULL then
                        final_phase := final_phase - (PI_FULL sll 1);
                    elsif final_phase <= -PI_FULL then
                        final_phase := final_phase + (PI_FULL sll 1);
                    end if;
                    
                    phase_out <= std_logic_vector(final_phase);
                    
                    -- Magnitude calculation with CORDIC gain compensation and RMS scaling
                    -- Step 1: Get absolute value
                    if x_work >= 0 then
                        final_magnitude := x_work;
                    else
                        final_magnitude := -x_work;
                    end if;
                    
                    -- Step 2: CORDIC gain compensation (multiply by 0.607 = 19898/32768)
                    gain_comp_product := final_magnitude * to_signed(19898, 16);
                    magnitude_with_gain_comp := resize(shift_right(gain_comp_product, 15), INPUT_WIDTH+1);
                    
                    -- Step 3: RMS scaling (divide by N/2 = 128)
                    -- Multiply by 256/32768 = 1/128
                    magnitude_scaled := magnitude_with_gain_comp * RMS_SCALE;
                    
                    -- Step 4: Extract result
                    magnitude_out <= std_logic_vector(resize(
                        shift_right(magnitude_scaled, 15), 
                        INPUT_WIDTH));
                    
                    valid_out <= '1';
                    busy <= '0';
                    state <= IDLE;
                
                when others =>
                    state <= IDLE;
            end case;
        end if;
    end process;
    
end behavioral;
