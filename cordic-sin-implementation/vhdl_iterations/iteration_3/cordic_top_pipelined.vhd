library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- CORDIC Top-Level (Pipelined - Iteration 3)
-- High-throughput streaming interface
-- Latency: ITERATIONS cycles, Throughput: 1 result/cycle (after fill)

entity cordic_top_pipelined is
    Generic (
        ITERATIONS : integer := 16;
        DATA_WIDTH : integer := 16
    );
    Port (
        clk      : in  std_logic;
        -- Note: No reset signal - pipelined design streams continuously
        -- To reset pipeline, stop valid_in and wait ITERATIONS+1 cycles

        -- Input data stream (valid indicates angle is present)
        angle_in : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        valid_in : in  std_logic;

        -- Output data stream (valid indicates results are ready)
        sin_out  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        cos_out  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        valid_out : out std_logic
    );
end cordic_top_pipelined;

architecture Structural of cordic_top_pipelined is

    component cordic_pipeline
        Generic (
            ITERATIONS : integer;
            DATA_WIDTH : integer
        );
        Port (
            clk       : in  std_logic;
            x_in      : in  signed(DATA_WIDTH-1 downto 0);
            y_in      : in  signed(DATA_WIDTH-1 downto 0);
            z_in      : in  signed(DATA_WIDTH-1 downto 0);
            valid_in  : in  std_logic;
            x_out     : out signed(DATA_WIDTH-1 downto 0);
            y_out     : out signed(DATA_WIDTH-1 downto 0);
            z_out     : out signed(DATA_WIDTH-1 downto 0);
            valid_out : out std_logic
        );
    end component;

    -- Registered inputs to pipeline
    signal x_init : signed(DATA_WIDTH-1 downto 0);
    signal y_init : signed(DATA_WIDTH-1 downto 0);
    signal z_init : signed(DATA_WIDTH-1 downto 0);
    signal valid_init : std_logic;

    -- Pipeline outputs
    signal x_result : signed(DATA_WIDTH-1 downto 0);
    signal y_result : signed(DATA_WIDTH-1 downto 0);
    signal z_result : signed(DATA_WIDTH-1 downto 0);

begin

    -- Initialize CORDIC state combinationally
    -- Initialization happens every cycle on new valid input
    x_init <= to_signed(60725, DATA_WIDTH);  -- K = 0.60725
    y_init <= (others => '0');
    z_init <= signed(angle_in);
    valid_init <= valid_in;

    -- Instantiate the pipeline
    pipeline_inst: cordic_pipeline
        generic map (
            ITERATIONS => ITERATIONS,
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            clk       => clk,
            x_in      => x_init,
            y_in      => y_init,
            z_in      => z_init,
            valid_in  => valid_init,
            x_out     => x_result,
            y_out     => y_result,
            z_out     => z_result,
            valid_out => valid_out
        );

    -- Output assignments
    sin_out <= std_logic_vector(y_result);
    cos_out <= std_logic_vector(x_result);

end Structural;
