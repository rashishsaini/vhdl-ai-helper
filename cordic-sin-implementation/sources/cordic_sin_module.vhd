library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================================
-- CORDIC (COordinate Rotation DIgital Computer) Module
-- ============================================================================
-- Computes sine and cosine using the CORDIC algorithm
--
-- Features:
--   • Modular architecture with LUT, datapath, and control integrated
--   • Ready/Valid handshake protocol for robust integration
--   • 16 iterations of CORDIC rotation mode
--   • Q1.15 fixed-point arithmetic (16-bit)
--   • No multipliers - only shifts and additions
--
-- Interface:
--   Inputs:  clk, reset, start (request), angle_in
--   Outputs: sin_out, cos_out, done (1-cycle pulse), ready (grant), valid
--
-- Example Usage:
--   wait until ready = '1';
--   start <= '1';
--   wait for CLK_PERIOD;
--   start <= '0';
--   wait until done = '1';
--   result_sin := sin_out;
--   result_cos := cos_out;
-- ============================================================================

entity cordic_sin is
    Generic (
        ITERATIONS : integer := 16;     -- Number of CORDIC iterations (fixed point bits)
        DATA_WIDTH : integer := 16      -- Data width for Q1.15 fixed-point
    );
    Port (
        -- Clock and reset
        clk      : in  std_logic;
        reset    : in  std_logic;

        -- Input handshake (start request, ready grant)
        start    : in  std_logic;       -- Request to compute
        ready    : out std_logic;       -- Ready to accept new angle

        -- Input data
        angle_in : in  std_logic_vector(DATA_WIDTH-1 downto 0);  -- Input angle [Q1.15]

        -- Output handshake (done and valid pulses)
        done     : out std_logic;       -- Output ready (1-cycle pulse)
        valid    : out std_logic;       -- Output valid (same as done)

        -- Output data
        sin_out  : out std_logic_vector(DATA_WIDTH-1 downto 0);  -- sin(angle) [Q1.15]
        cos_out  : out std_logic_vector(DATA_WIDTH-1 downto 0)   -- cos(angle) [Q1.15]
    );
end cordic_sin;

architecture RTL of cordic_sin is

    -- Synthesis attributes for retiming optimization
    attribute RETIMING_OPTIMIZATION : string;
    attribute RETIMING_OPTIMIZATION of RTL : architecture is "TRUE";

    -- ========================================================================
    -- TYPE DEFINITIONS
    -- ========================================================================

    -- FSM states
    type state_type is (IDLE, INIT, COMPUTING, OUTPUT_VALID);

    -- Angle lookup table array type
    type angle_array is array (0 to ITERATIONS-1) of signed(DATA_WIDTH-1 downto 0);

    -- ========================================================================
    -- CONSTANTS
    -- ========================================================================

    -- Pre-computed CORDIC angles: arctan(2^-i) in Q1.15 fixed-point format
    -- These are the fundamental constants of the CORDIC algorithm
    constant ANGLE_TABLE : angle_array := (
        to_signed(16#3243#, DATA_WIDTH),  -- i=0:  arctan(1)       = 45.000°   = 0.7854 rad
        to_signed(16#1DAC#, DATA_WIDTH),  -- i=1:  arctan(0.5)     = 26.565°   = 0.4636 rad
        to_signed(16#0FAD#, DATA_WIDTH),  -- i=2:  arctan(0.25)    = 14.036°   = 0.2450 rad
        to_signed(16#07F5#, DATA_WIDTH),  -- i=3:  arctan(0.125)   = 7.125°    = 0.1244 rad
        to_signed(16#03FE#, DATA_WIDTH),  -- i=4:  arctan(0.0625)  = 3.576°    = 0.0624 rad
        to_signed(16#01FF#, DATA_WIDTH),  -- i=5:  arctan(0.03125) = 1.789°    = 0.0312 rad
        to_signed(16#00FF#, DATA_WIDTH),  -- i=6:  arctan(0.015625)= 0.895°    = 0.0156 rad
        to_signed(16#007F#, DATA_WIDTH),  -- i=7:  arctan(2^-7)    = 0.447°    = 0.0078 rad
        to_signed(16#0080#, DATA_WIDTH),  -- i=8:  arctan(2^-8)    = 0.224°    = 0.0039 rad
        to_signed(16#0040#, DATA_WIDTH),  -- i=9:  arctan(2^-9)    = 0.112°    = 0.0020 rad
        to_signed(16#0020#, DATA_WIDTH),  -- i=10: arctan(2^-10)   = 0.056°    = 0.0010 rad
        to_signed(16#0010#, DATA_WIDTH),  -- i=11: arctan(2^-11)   = 0.028°    = 0.0005 rad
        to_signed(16#0008#, DATA_WIDTH),  -- i=12: arctan(2^-12)   = 0.014°    = 0.0002 rad
        to_signed(16#0004#, DATA_WIDTH),  -- i=13: arctan(2^-13)   = 0.007°    = 0.0001 rad
        to_signed(16#0002#, DATA_WIDTH),  -- i=14: arctan(2^-14)   = 0.003°    = 0.00006 rad
        to_signed(16#0001#, DATA_WIDTH)   -- i=15: arctan(2^-15)   = 0.002°    = 0.00003 rad
    );

    -- CORDIC gain constant K = product(1/sqrt(1 + 2^(-2*i))) ≈ 0.607252935
    -- In Q1.15 format: 0.607252935 * 2^15 = 19898 decimal = 0x4DBB hex
    constant K_CONSTANT : signed(DATA_WIDTH-1 downto 0) := to_signed(19898, DATA_WIDTH);

    -- ========================================================================
    -- SIGNALS: FSM Control
    -- ========================================================================

    signal current_state, next_state : state_type;
    signal iteration_count : integer range 0 to ITERATIONS-1;

    -- FSM encoding attribute (must be after signal declaration)
    attribute FSM_ENCODING : string;
    attribute FSM_ENCODING of current_state : signal is "ONE_HOT";

    -- ========================================================================
    -- SIGNALS: Data Path
    -- ========================================================================

    -- State registers
    signal x_reg, y_reg, z_reg : signed(DATA_WIDTH-1 downto 0);

    -- Next state from datapath
    signal x_next, y_next, z_next : signed(DATA_WIDTH-1 downto 0);

    -- Synthesis attributes for fast arithmetic
    attribute USE_CARRY_CHAIN : string;
    attribute USE_CARRY_CHAIN of x_next : signal is "YES";
    attribute USE_CARRY_CHAIN of y_next : signal is "YES";
    attribute USE_CARRY_CHAIN of z_next : signal is "YES";

    -- Current angle from LUT
    signal current_angle : signed(DATA_WIDTH-1 downto 0);

    -- ========================================================================
    -- SIGNALS: Output Control
    -- ========================================================================

    signal computing_sig : std_logic;
    signal done_sig      : std_logic;
    signal valid_sig     : std_logic;
    signal ready_sig     : std_logic;

begin

    -- ========================================================================
    -- LUT: Lookup Table
    -- Provides current angle for this iteration
    -- ========================================================================

    current_angle <= ANGLE_TABLE(iteration_count) when iteration_count < ITERATIONS else
                     (others => '0');

    -- ========================================================================
    -- CONTROL: Finite State Machine
    -- Manages iteration sequencing and handshake signals
    -- ========================================================================

    -- Sequential: State and counter update
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                current_state <= IDLE;
                iteration_count <= 0;
            else
                current_state <= next_state;

                -- Update iteration counter
                case current_state is
                    when IDLE =>
                        iteration_count <= 0;
                    when INIT =>
                        iteration_count <= 0;
                    when COMPUTING =>
                        -- Count through all 16 iterations (0 to 15)
                        if iteration_count < ITERATIONS - 1 then
                            iteration_count <= iteration_count + 1;
                        end if;
                    when OUTPUT_VALID =>
                        iteration_count <= 0;
                end case;
            end if;
        end if;
    end process;

    -- Combinational: Next state logic
    process(current_state, start, iteration_count)
    begin
        case current_state is
            when IDLE =>
                if start = '1' then
                    next_state <= INIT;
                else
                    next_state <= IDLE;
                end if;

            when INIT =>
                next_state <= COMPUTING;

            when COMPUTING =>
                if iteration_count = ITERATIONS - 1 then
                    next_state <= OUTPUT_VALID;
                else
                    next_state <= COMPUTING;
                end if;

            when OUTPUT_VALID =>
                if start = '1' then
                    next_state <= INIT;
                else
                    next_state <= IDLE;
                end if;
        end case;
    end process;

    -- Combinational: Output control signals
    process(current_state)
    begin
        case current_state is
            when IDLE =>
                ready_sig      <= '1';
                computing_sig  <= '0';
                done_sig       <= '0';
                valid_sig      <= '0';

            when INIT =>
                ready_sig      <= '0';
                computing_sig  <= '0';
                done_sig       <= '0';
                valid_sig      <= '0';

            when COMPUTING =>
                ready_sig      <= '0';
                computing_sig  <= '1';
                done_sig       <= '0';
                valid_sig      <= '0';

            when OUTPUT_VALID =>
                ready_sig      <= '1';
                computing_sig  <= '0';
                done_sig       <= '1';
                valid_sig      <= '1';
        end case;
    end process;

    -- ========================================================================
    -- DATAPATH: CORDIC Rotation Logic (Combinational)
    -- Performs one CORDIC iteration based on current z sign
    -- ========================================================================

    process(x_reg, y_reg, z_reg, current_angle, iteration_count)
        variable direction : std_logic;
        variable y_shifted, x_shifted : signed(DATA_WIDTH-1 downto 0);
    begin
        -- Determine rotation direction based on z sign
        -- If z < 0, rotate counterclockwise (add angle to z)
        -- If z >= 0, rotate clockwise (subtract angle from z)
        direction := z_reg(z_reg'high);

        -- Pre-compute shifted values for this iteration
        if iteration_count <= 15 then
            y_shifted := shift_right(y_reg, iteration_count);
            x_shifted := shift_right(x_reg, iteration_count);
        else
            y_shifted := (others => '0');
            x_shifted := (others => '0');
        end if;

        -- Perform CORDIC rotation
        if direction = '1' then
            -- z < 0: Rotate counterclockwise
            x_next <= x_reg + y_shifted;
            y_next <= y_reg - x_shifted;
            z_next <= z_reg + current_angle;
        else
            -- z >= 0: Rotate clockwise
            x_next <= x_reg - y_shifted;
            y_next <= y_reg + x_shifted;
            z_next <= z_reg - current_angle;
        end if;
    end process;

    -- ========================================================================
    -- STATE REGISTERS: Update x, y, z based on control signals
    -- ========================================================================

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                x_reg <= (others => '0');
                y_reg <= (others => '0');
                z_reg <= (others => '0');
            -- Initialization: During INIT state
            elsif current_state = INIT then
                x_reg <= K_CONSTANT;       -- Initialize x to K (CORDIC gain)
                y_reg <= (others => '0');  -- Initialize y to 0
                z_reg <= signed(angle_in); -- Initialize z to input angle
            -- Iteration: Update state with datapath results
            elsif computing_sig = '1' then
                x_reg <= x_next;
                y_reg <= y_next;
                z_reg <= z_next;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- OUTPUT ASSIGNMENTS
    -- ========================================================================

    sin_out <= std_logic_vector(y_reg);
    cos_out <= std_logic_vector(x_reg);
    done    <= done_sig;
    valid   <= valid_sig;
    ready   <= ready_sig;

end RTL;
