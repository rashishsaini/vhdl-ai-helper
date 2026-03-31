library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- CORDIC Pipeline
-- Cascades multiple cordic_stage components to implement full CORDIC
-- Each stage performs one iteration, enabling one result per cycle throughput

entity cordic_pipeline is
    Generic (
        ITERATIONS : integer := 16;
        DATA_WIDTH : integer := 16
    );
    Port (
        clk       : in  std_logic;

        -- Input (stage 0)
        x_in      : in  signed(DATA_WIDTH-1 downto 0);
        y_in      : in  signed(DATA_WIDTH-1 downto 0);
        z_in      : in  signed(DATA_WIDTH-1 downto 0);
        valid_in  : in  std_logic;

        -- Output (stage ITERATIONS-1)
        x_out     : out signed(DATA_WIDTH-1 downto 0);
        y_out     : out signed(DATA_WIDTH-1 downto 0);
        z_out     : out signed(DATA_WIDTH-1 downto 0);
        valid_out : out std_logic
    );
end cordic_pipeline;

architecture Structural of cordic_pipeline is

    component cordic_stage
        Generic (
            STAGE_NUM  : integer;
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

    -- Interconnect signals between stages
    type x_array is array (0 to ITERATIONS) of signed(DATA_WIDTH-1 downto 0);
    type y_array is array (0 to ITERATIONS) of signed(DATA_WIDTH-1 downto 0);
    type z_array is array (0 to ITERATIONS) of signed(DATA_WIDTH-1 downto 0);
    type valid_array is array (0 to ITERATIONS) of std_logic;

    signal x_pipeline : x_array;
    signal y_pipeline : y_array;
    signal z_pipeline : z_array;
    signal valid_pipeline : valid_array;

begin

    -- Connect stage inputs to pipeline input
    x_pipeline(0)     <= x_in;
    y_pipeline(0)     <= y_in;
    z_pipeline(0)     <= z_in;
    valid_pipeline(0) <= valid_in;

    -- Generate and instantiate all pipeline stages
    stages: for i in 0 to ITERATIONS-1 generate
        stage_inst: cordic_stage
            generic map (
                STAGE_NUM  => i,
                DATA_WIDTH => DATA_WIDTH
            )
            port map (
                clk       => clk,
                x_in      => x_pipeline(i),
                y_in      => y_pipeline(i),
                z_in      => z_pipeline(i),
                valid_in  => valid_pipeline(i),
                x_out     => x_pipeline(i+1),
                y_out     => y_pipeline(i+1),
                z_out     => z_pipeline(i+1),
                valid_out => valid_pipeline(i+1)
            );
    end generate;

    -- Connect pipeline output to stage output
    x_out     <= x_pipeline(ITERATIONS);
    y_out     <= y_pipeline(ITERATIONS);
    z_out     <= z_pipeline(ITERATIONS);
    valid_out <= valid_pipeline(ITERATIONS);

end Structural;
