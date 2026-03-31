library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- CORDIC Top-Level Entity (Modular Version - Iteration 1)
-- Integrates three sub-components:
--   1. cordic_lut: Angle lookup table
--   2. cordic_datapath: Rotation logic
--   3. cordic_control: FSM and iteration control

entity cordic_top is
    Generic (
        ITERATIONS : integer := 16;
        DATA_WIDTH : integer := 16
    );
    Port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        start    : in  std_logic;
        angle_in : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        sin_out  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        cos_out  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        done     : out std_logic
    );
end cordic_top;

architecture Structural of cordic_top is

    -- Component declarations

    component cordic_lut
        Generic (
            ITERATIONS : integer;
            DATA_WIDTH : integer
        );
        Port (
            clk       : in  std_logic;
            addr      : in  integer range 0 to ITERATIONS-1;
            angle_out : out signed(DATA_WIDTH-1 downto 0)
        );
    end component;

    component cordic_datapath
        Generic (
            DATA_WIDTH : integer
        );
        Port (
            x_in      : in  signed(DATA_WIDTH-1 downto 0);
            y_in      : in  signed(DATA_WIDTH-1 downto 0);
            z_in      : in  signed(DATA_WIDTH-1 downto 0);
            angle     : in  signed(DATA_WIDTH-1 downto 0);
            iteration : in  integer range 0 to 31;
            x_out     : out signed(DATA_WIDTH-1 downto 0);
            y_out     : out signed(DATA_WIDTH-1 downto 0);
            z_out     : out signed(DATA_WIDTH-1 downto 0)
        );
    end component;

    component cordic_control
        Generic (
            ITERATIONS : integer
        );
        Port (
            clk           : in  std_logic;
            reset         : in  std_logic;
            start         : in  std_logic;
            done          : out std_logic;
            computing     : out std_logic;
            iteration_idx : out integer range 0 to 31
        );
    end component;

    -- Internal signals

    -- State registers
    signal x_reg, y_reg, z_reg : signed(DATA_WIDTH-1 downto 0);
    signal x_next, y_next, z_next : signed(DATA_WIDTH-1 downto 0);

    -- Control signals
    signal computing : std_logic;
    signal iteration_idx : integer range 0 to 31;
    signal angle_from_lut : signed(DATA_WIDTH-1 downto 0);
    signal done_signal : std_logic;

begin

    -- Instantiate LUT component
    lut_inst: cordic_lut
        generic map (
            ITERATIONS => ITERATIONS,
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            clk       => clk,
            addr      => iteration_idx,
            angle_out => angle_from_lut
        );

    -- Instantiate Datapath component
    datapath_inst: cordic_datapath
        generic map (
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            x_in      => x_reg,
            y_in      => y_reg,
            z_in      => z_reg,
            angle     => angle_from_lut,
            iteration => iteration_idx,
            x_out     => x_next,
            y_out     => y_next,
            z_out     => z_next
        );

    -- Instantiate Control component (FSM)
    control_inst: cordic_control
        generic map (
            ITERATIONS => ITERATIONS
        )
        port map (
            clk           => clk,
            reset         => reset,
            start         => start,
            done          => done_signal,
            computing     => computing,
            iteration_idx => iteration_idx
        );

    -- State register update (sequential logic)
    process(clk, reset)
    begin
        if reset = '1' then
            x_reg <= (others => '0');
            y_reg <= (others => '0');
            z_reg <= (others => '0');
        elsif rising_edge(clk) then
            if start = '1' and computing = '0' then
                -- Initialize CORDIC state
                x_reg <= to_signed(60725, DATA_WIDTH);  -- K = 0.60725
                y_reg <= (others => '0');
                z_reg <= signed(angle_in);
            elsif computing = '1' then
                -- Update state with next values from datapath
                x_reg <= x_next;
                y_reg <= y_next;
                z_reg <= z_next;
            end if;
        end if;
    end process;

    -- Output assignments
    sin_out <= std_logic_vector(y_reg);
    cos_out <= std_logic_vector(x_reg);
    done    <= done_signal;

end Structural;
