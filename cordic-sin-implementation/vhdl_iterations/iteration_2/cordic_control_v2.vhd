library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- CORDIC Control Component v2 - Enhanced Handshake Protocol
-- Implements ready/valid handshake for more robust synchronization
-- Allows pipelined input of new angles while previous computation is finishing

entity cordic_control_v2 is
    Generic (
        ITERATIONS : integer := 16
    );
    Port (
        clk            : in  std_logic;
        reset          : in  std_logic;

        -- Input handshake (ready/valid protocol)
        start          : in  std_logic;       -- Request to start computation
        ready          : out std_logic;       -- Ready to accept new input

        -- Output handshake
        done           : out std_logic;       -- Computation complete (1-cycle pulse)
        valid          : out std_logic;       -- Output valid signal

        -- Internal signals to datapath
        computing      : out std_logic;       -- Currently iterating
        iteration_idx  : out integer range 0 to 31
    );
end cordic_control_v2;

architecture Behavioral of cordic_control_v2 is

    type state_type is (IDLE, COMPUTING, OUTPUT_VALID);
    signal current_state, next_state : state_type;
    signal iteration_count : integer range 0 to ITERATIONS;

begin

    -- State machine: synchronous process
    process(clk, reset)
    begin
        if reset = '1' then
            current_state <= IDLE;
            iteration_count <= 0;
        elsif rising_edge(clk) then
            current_state <= next_state;

            -- Update iteration counter based on state transitions
            case current_state is
                when IDLE =>
                    iteration_count <= 0;
                when COMPUTING =>
                    if iteration_count < ITERATIONS - 1 then
                        iteration_count <= iteration_count + 1;
                    else
                        iteration_count <= 0;
                    end if;
                when OUTPUT_VALID =>
                    iteration_count <= 0;
            end case;
        end if;
    end process;

    -- Next state logic: combinational
    process(current_state, start, iteration_count)
    begin
        case current_state is
            when IDLE =>
                if start = '1' then
                    next_state <= COMPUTING;
                else
                    next_state <= IDLE;
                end if;

            when COMPUTING =>
                if iteration_count = ITERATIONS - 1 then
                    next_state <= OUTPUT_VALID;
                else
                    next_state <= COMPUTING;
                end if;

            when OUTPUT_VALID =>
                -- Always transition back to IDLE after one cycle
                -- Can immediately start new computation if start='1'
                if start = '1' then
                    next_state <= COMPUTING;
                else
                    next_state <= IDLE;
                end if;
        end case;
    end process;

    -- Output control signals
    process(current_state)
    begin
        case current_state is
            when IDLE =>
                -- Ready to accept new input when idle
                ready    <= '1';
                computing <= '0';
                done     <= '0';
                valid    <= '0';

            when COMPUTING =>
                -- Not ready for new input during computation
                ready    <= '0';
                computing <= '1';
                done     <= '0';
                valid    <= '0';

            when OUTPUT_VALID =>
                -- Pulse done/valid signals for 1 cycle
                ready    <= '1';  -- Can accept new input after this cycle
                computing <= '0';
                done     <= '1';  -- 1-cycle pulse: results are ready
                valid    <= '1';  -- Results are valid
        end case;
    end process;

    -- Output the current iteration index to datapath
    iteration_idx <= iteration_count;

end Behavioral;
