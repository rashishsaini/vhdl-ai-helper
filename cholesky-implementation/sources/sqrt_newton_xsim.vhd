library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--------------------------------------------------------------------------------
-- XSIM-Compatible Newton-Raphson Square Root
--------------------------------------------------------------------------------
-- Simplified version that avoids XSIM elaboration crashes
-- Uses manual bit slicing instead of shift/resize functions
--------------------------------------------------------------------------------

entity sqrt_newton is
  port (
    clk      : in  std_logic;
    start_rt : in  std_logic;
    x_in     : in  signed(31 downto 0);  -- Q20.12
    x_out    : out signed(31 downto 0);  -- Q20.12
    done     : out std_logic
  );
end entity;

architecture Behavioral of sqrt_newton is
  type state_type is (IDLE, INIT, ITERATE, ZERO, FINISH);
  signal state : state_type := IDLE;

  signal x_current : signed(31 downto 0);
  signal x_next    : signed(31 downto 0);
  signal iteration : integer range 0 to 15;
  signal x_input   : signed(31 downto 0);

  constant Q : integer := 12;
  constant ITERATIONS : integer := 12;

  -- Use integer constants instead of signed constants (XSIM fix)
  constant HALF_INT : integer := 2048;  -- 0.5 in Q20.12
  constant TOLERANCE_INT : integer := 4;  -- ~0.001 in Q20.12
  constant SMALL_INT : integer := 4096;  -- 1.0 in Q20.12
  constant LARGE_INT : integer := 409600;  -- 100 in Q20.12
  constant MIN_DIVISOR_INT : integer := 4;

begin
  process(clk)
    variable temp_div : signed(63 downto 0);
    variable temp_sum : signed(31 downto 0);
    variable temp_mul : signed(63 downto 0);
    variable delta    : signed(31 downto 0);
    variable half_val : signed(31 downto 0);
  begin
    if rising_edge(clk) then
      case state is
        when IDLE =>
          done <= '0';
          if start_rt = '1' then
            x_input   <= x_in;
            iteration <= 0;
            if x_in = 0 then
              state <= ZERO;
            else
              state <= INIT;
            end if;
          end if;

        when INIT =>
          -- Adaptive initial guess using integer constants
          if x_input < SMALL_INT then
            x_current <= x_input;
          elsif x_input > LARGE_INT then
            -- Divide by 4: shift right 2 (manual)
            x_current <= x_input(31) & x_input(31) & x_input(31 downto 2);
          else
            -- Divide by 2: shift right 1 (manual)
            x_current <= x_input(31) & x_input(31 downto 1);
          end if;
          state <= ITERATE;

        when ITERATE =>
          -- Newton-Raphson: x_next = (x_current + input/x_current) / 2

          -- Extend input to 64 bits and shift left by Q (multiply by 4096)
          if x_input(31) = '1' then
            temp_div := (63 downto 44 => '1') & x_input & "000000000000";
          else
            temp_div := (63 downto 44 => '0') & x_input & "000000000000";
          end if;

          -- Clamp divisor to minimum
          if abs(x_current) < MIN_DIVISOR_INT then
            if x_current >= 0 then
              temp_div := temp_div / MIN_DIVISOR_INT;
            else
              temp_div := temp_div / (-MIN_DIVISOR_INT);
            end if;
          else
            temp_div := temp_div / x_current;
          end if;

          -- Saturate to 32-bit range
          if temp_div > 2147483647 then
            temp_sum := to_signed(2147483647, 32);
          elsif temp_div < -2147483648 then
            temp_sum := to_signed(-2147483648, 32);
          else
            temp_sum := temp_div(31 downto 0);
          end if;

          -- Add x_current
          temp_sum := x_current + temp_sum;

          -- Multiply by HALF (0.5 in Q20.12)
          half_val := to_signed(HALF_INT, 32);
          temp_mul := temp_sum * half_val;

          -- Shift right by Q (divide by 4096) - manual
          x_next <= temp_mul(43 downto 12);

          x_current <= x_next;
          iteration <= iteration + 1;

          -- Check convergence
          delta := abs(x_next - x_current);
          if delta < TOLERANCE_INT then
            state <= FINISH;
          elsif iteration >= ITERATIONS - 1 then
            state <= FINISH;
          end if;

        when ZERO =>
          x_out <= (others => '0');
          done  <= '1';
          if start_rt = '0' then
            state <= IDLE;
          end if;

        when FINISH =>
          x_out <= x_current;
          done  <= '1';
          if start_rt = '0' then
            state <= IDLE;
          end if;

        when others =>
          state <= IDLE;
      end case;
    end if;
  end process;
end Behavioral;
