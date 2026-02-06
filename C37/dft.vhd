library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dft_complex_calculator is
    generic (
        WINDOW_SIZE       : integer := 256;    -- N = 256 samples
        SAMPLE_WIDTH      : integer := 16;     -- Input sample width
        COEFF_WIDTH       : integer := 16;     -- Coefficient width (Q1.15)
        ACCUMULATOR_WIDTH : integer := 48;     -- Accumulator width (Q33.15)
        OUTPUT_WIDTH      : integer := 32      -- Output width (Q16.15)
    );
    port (
        -- Clock and Reset
        clk            : in  std_logic;
        rst            : in  std_logic;
        
        -- Control Interface
        start          : in  std_logic;     -- Start DFT calculation
        done           : out std_logic;     -- Calculation complete
        
        -- Sample Buffer Interface
        sample_data    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        sample_addr    : out std_logic_vector(7 downto 0);  -- Address to sample buffer
        
        -- Cosine ROM Interface
        cos_coeff      : in  std_logic_vector(COEFF_WIDTH-1 downto 0);
        cos_addr       : out std_logic_vector(7 downto 0);  -- Address to cosine ROM
        cos_valid      : in  std_logic;     -- Cosine data valid
        
        -- Sine ROM Interface
        sin_coeff      : in  std_logic_vector(COEFF_WIDTH-1 downto 0);
        sin_addr       : out std_logic_vector(7 downto 0);  -- Address to sine ROM
        sin_valid      : in  std_logic;     -- Sine data valid
        
        -- Result Outputs
        real_result    : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
        imag_result    : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
        result_valid   : out std_logic
    );
end dft_complex_calculator;

architecture behavioral of dft_complex_calculator is
    
    -- State Machine Definition
    type state_type is (IDLE, INIT, FETCH_ADDR, WAIT_ROM, MULTIPLY, SCALE, ACCUMULATE, DONE_STATE);
    signal current_state, next_state : state_type;
    
    -- Internal Counters and Addresses
    signal sample_counter : unsigned(7 downto 0) := (others => '0');
    signal address_reg    : unsigned(7 downto 0) := (others => '0');
    
    -- ROM wait counter (simplified - no timeout needed for sync ROMs)
    signal rom_wait_counter : unsigned(1 downto 0) := (others => '0');
    
    -- CORRECTED: Improved pipeline registers
    signal sample_data_reg    : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal cos_coeff_reg      : std_logic_vector(COEFF_WIDTH-1 downto 0);
    signal sin_coeff_reg      : std_logic_vector(COEFF_WIDTH-1 downto 0);
    signal data_valid_reg     : std_logic;
    
    -- Multiplier signals for REAL part
    signal multiplier_real_a   : signed(SAMPLE_WIDTH-1 downto 0);
    signal multiplier_real_b   : signed(COEFF_WIDTH-1 downto 0);
    signal product_real        : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);
    signal product_real_scaled : signed(OUTPUT_WIDTH-1 downto 0);
    
    -- Multiplier signals for IMAGINARY part
    signal multiplier_imag_a   : signed(SAMPLE_WIDTH-1 downto 0);
    signal multiplier_imag_b   : signed(COEFF_WIDTH-1 downto 0);
    signal product_imag        : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);
    signal product_imag_scaled : signed(OUTPUT_WIDTH-1 downto 0);
    
    -- Accumulators for REAL and IMAGINARY parts
    signal accumulator_real    : signed(ACCUMULATOR_WIDTH-1 downto 0) := (others => '0');
    signal accumulator_imag    : signed(ACCUMULATOR_WIDTH-1 downto 0) := (others => '0');
    
    -- Control Signals
    signal multiply_enable : std_logic;
    signal accumulate_enable : std_logic;
    signal clear_accumulator : std_logic;
    signal calculation_done : std_logic;
    signal increment_counter : std_logic;
    
begin
    
    -- State Machine: Sequential Process
    state_machine_sync: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
        elsif rising_edge(clk) then
            current_state <= next_state;
        end if;
    end process;
    
    -- CORRECTED: Simplified state machine with proper ROM handling
    state_machine_comb: process(current_state, start, sample_counter, data_valid_reg, rom_wait_counter)
    begin
        -- Default assignments
        next_state <= current_state;
        multiply_enable <= '0';
        accumulate_enable <= '0';
        clear_accumulator <= '0';
        calculation_done <= '0';
        increment_counter <= '0';
        
        case current_state is
            when IDLE =>
                if start = '1' then
                    next_state <= INIT;
                end if;
                
            when INIT =>
                clear_accumulator <= '1';
                next_state <= FETCH_ADDR;
                
            when FETCH_ADDR =>
                -- Address is set, wait for ROM and sample data
                next_state <= WAIT_ROM;
                
            when WAIT_ROM =>
                -- CORRECTED: Wait for data to be valid (synchronous ROMs need 1-2 cycles)
                if data_valid_reg = '1' or rom_wait_counter >= 2 then
                    next_state <= MULTIPLY;
                end if;
                
            when MULTIPLY =>
                multiply_enable <= '1';
                next_state <= SCALE;

            when SCALE =>
                -- CRITICAL FIX: Wait one cycle for product_real_scaled to be ready
                -- This allows the multiplication result from MULTIPLY state to
                -- propagate through the scaling logic before accumulation
                next_state <= ACCUMULATE;

            when ACCUMULATE =>
                accumulate_enable <= '1';
                increment_counter <= '1';
                
                -- Check if all samples processed
                if sample_counter = WINDOW_SIZE - 1 then
                    next_state <= DONE_STATE;
                else
                    next_state <= FETCH_ADDR;
                end if;
                
            when DONE_STATE =>
                calculation_done <= '1';
                if start = '0' then  -- Wait for start to go low
                    next_state <= IDLE;
                end if;
                
            when others =>
                next_state <= IDLE;
        end case;
    end process;
    
    -- CORRECTED: ROM wait counter (simplified)
    rom_wait_process: process(clk, rst)
    begin
        if rst = '1' then
            rom_wait_counter <= (others => '0');
        elsif rising_edge(clk) then
            if current_state = WAIT_ROM then
                if data_valid_reg = '1' then
                    rom_wait_counter <= (others => '0');
                else
                    rom_wait_counter <= rom_wait_counter + 1;
                end if;
            else
                rom_wait_counter <= (others => '0');
            end if;
        end if;
    end process;
    
    -- Sample Counter Management
    counter_process: process(clk, rst)
    begin
        if rst = '1' then
            sample_counter <= (others => '0');
            address_reg <= (others => '0');
        elsif rising_edge(clk) then
            case current_state is
                when INIT =>
                    sample_counter <= (others => '0');
                    address_reg <= (others => '0');
                    
                when ACCUMULATE =>
                    if increment_counter = '1' then
                        if sample_counter = WINDOW_SIZE - 1 then
                            sample_counter <= (others => '0');
                            address_reg <= (others => '0');
                        else
                            sample_counter <= sample_counter + 1;
                            address_reg <= address_reg + 1;
                        end if;
                    end if;
                    
                when others =>
                    null;
            end case;
        end if;
    end process;
    
    -- CORRECTED: Improved pipeline registers for proper data alignment
    pipeline_process: process(clk, rst)
    begin
        if rst = '1' then
            sample_data_reg <= (others => '0');
            cos_coeff_reg <= (others => '0');
            sin_coeff_reg <= (others => '0');
            data_valid_reg <= '0';
        elsif rising_edge(clk) then
            -- Register data when address is stable and in WAIT_ROM state
            if current_state = WAIT_ROM then
                sample_data_reg <= sample_data;
                
                -- Register ROM coefficients when they become valid
                if cos_valid = '1' and sin_valid = '1' then
                    cos_coeff_reg <= cos_coeff;
                    sin_coeff_reg <= sin_coeff;
                    data_valid_reg <= '1';
                end if;
            else
                data_valid_reg <= '0';
            end if;
        end if;
    end process;
    
    -- REAL Part Multiplier Process
    real_multiplier_process: process(clk, rst)
    begin
        if rst = '1' then
            multiplier_real_a <= (others => '0');
            multiplier_real_b <= (others => '0');
            product_real <= (others => '0');
            product_real_scaled <= (others => '0');
        elsif rising_edge(clk) then
            -- Stage 1: Multiply (on multiply_enable)
            if multiply_enable = '1' then
                -- Assign inputs to multiplier for REAL part
                multiplier_real_a <= signed(sample_data_reg);
                multiplier_real_b <= signed(cos_coeff_reg);

                -- CORRECTED: Perform multiplication directly from registers
                -- This avoids using stale multiplier_real_a/b values
                product_real <= signed(sample_data_reg) * signed(cos_coeff_reg);
            end if;

            -- Stage 2: Scale (always, so it's ready for accumulate_enable)
            -- Proper scaling for Q1.15 format
            -- Q15 * Q1.15 = Q16.30, shift right by 15 to get Q16.15
            product_real_scaled <= resize(shift_right(product_real, 15), OUTPUT_WIDTH);
        end if;
    end process;
    
    -- IMAGINARY Part Multiplier Process
    imag_multiplier_process: process(clk, rst)
    begin
        if rst = '1' then
            multiplier_imag_a <= (others => '0');
            multiplier_imag_b <= (others => '0');
            product_imag <= (others => '0');
            product_imag_scaled <= (others => '0');
        elsif rising_edge(clk) then
            -- Stage 1: Multiply (on multiply_enable)
            if multiply_enable = '1' then
                -- Assign inputs to multiplier for IMAGINARY part
                multiplier_imag_a <= signed(sample_data_reg);
                multiplier_imag_b <= signed(sin_coeff_reg);

                -- CORRECTED: Perform multiplication directly from registers
                -- This avoids using stale multiplier_imag_a/b values
                -- Standard DFT imaginary part is -j*sin, so we negate
                product_imag <= -(signed(sample_data_reg) * signed(sin_coeff_reg));
            end if;

            -- Stage 2: Scale (always, so it's ready for accumulate_enable)
            -- Proper scaling for Q1.15 format
            -- Q15 * Q1.15 = Q16.30, shift right by 15 to get Q16.15
            product_imag_scaled <= resize(shift_right(product_imag, 15), OUTPUT_WIDTH);
        end if;
    end process;
    
    -- REAL Accumulator Process
    real_accumulator_process: process(clk, rst)
    begin
        if rst = '1' then
            accumulator_real <= (others => '0');
        elsif rising_edge(clk) then
            if clear_accumulator = '1' then
                accumulator_real <= (others => '0');
            elsif accumulate_enable = '1' then
                -- Add scaled product to accumulator
                accumulator_real <= accumulator_real + resize(product_real_scaled, ACCUMULATOR_WIDTH);
            end if;
        end if;
    end process;
    
    -- IMAGINARY Accumulator Process
    imag_accumulator_process: process(clk, rst)
    begin
        if rst = '1' then
            accumulator_imag <= (others => '0');
        elsif rising_edge(clk) then
            if clear_accumulator = '1' then
                accumulator_imag <= (others => '0');
            elsif accumulate_enable = '1' then
                -- Add scaled product to accumulator
                accumulator_imag <= accumulator_imag + resize(product_imag_scaled, ACCUMULATOR_WIDTH);
            end if;
        end if;
    end process;
    
    -- CORRECTED: Output Assignment Process - CRITICAL FIX
    output_process: process(clk, rst)
    begin
        if rst = '1' then
            real_result <= (others => '0');
            imag_result <= (others => '0');
            result_valid <= '0';
        elsif rising_edge(clk) then
            if calculation_done = '1' then
                -- CRITICAL FIX: Extract the correct bits from 48-bit accumulator
                -- Accumulator is Q33.15 format, extract lower 32 bits for Q16.15 output
                -- For 256-point DFT, expect magnitude ~128x input amplitude (256/2)
                real_result <= std_logic_vector(accumulator_real(OUTPUT_WIDTH-1 downto 0));
                imag_result <= std_logic_vector(accumulator_imag(OUTPUT_WIDTH-1 downto 0));
                result_valid <= '1';
            elsif current_state = IDLE then
                result_valid <= '0';
            end if;
        end if;
    end process;
    
    -- Address Output Assignments (same address for all ROMs and buffer)
    sample_addr <= std_logic_vector(address_reg);
    cos_addr <= std_logic_vector(address_reg);
    sin_addr <= std_logic_vector(address_reg);
    
    -- Status Output
    done <= calculation_done;
    
end behavioral;
