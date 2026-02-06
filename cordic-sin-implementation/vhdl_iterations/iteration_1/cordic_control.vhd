library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- CORDIC Control Component
-- Finite State Machine for managing CORDIC iteration sequence
-- Controls iteration counting, state transitions, and done signal

entity cordic_control is
    Generic (
        ITERATIONS : integer := 16
    );
    Port (
        clk            : in  std_logic;
        reset          : in  std_logic;

        -- External interface
        start          : in  std_logic;
        done           : out std_logic;

        -- Internal signals to datapath
        computing      : out std_logic;
        iteration_idx  : out integer range 0 to 31
    );
end cordic_control;

architecture Behavioral of cordic_control is

    type state_type is (IDLE, COMPUTING, DONE_PULSE);
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

            -- Update iteration counter
            case next_state is
                when IDLE =>
                    iteration_count <= 0;
                when COMPUTING =>
                    if current_state = COMPUTING then
                        iteration_count <= iteration_count + 1;
                    else
                        iteration_count <= 0;
                    end if;
                when DONE_PULSE =>
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
                    next_state <= DONE_PULSE;
                else
                    next_state <= COMPUTING;
                end if;

            when DONE_PULSE =>
                next_state <= IDLE;
        end case;
    end process;

    -- Output control signals
    process(current_state)
    begin
        case current_state is
            when IDLE =>
                computing <= '0';
                done <= '0';
            when COMPUTING =>
                computing <= '1';
                done <= '0';
            when DONE_PULSE =>
                computing <= '0';
                done <= '1';
        end case;
    end process;

    -- Output the current iteration index to datapath
    iteration_idx <= iteration_count;

end Behavioral;
