--------------------------------------------------------------------------------
-- Testbench: tb_leaky_relu_unit
-- Description: Self-checking testbench for Leaky ReLU activation unit
--              GHDL and VHDL-2008 compatible
--
-- Verification Strategy:
--   1. Exhaustive testing not feasible (2^16 values)
--   2. Focus on corner cases and boundary conditions
--   3. Self-checking with assert statements
--   4. Automatic PASS/FAIL determination
--
-- Test Categories:
--   1. Zero input (boundary)
--   2. Positive inputs (pass-through verification)
--   3. Negative inputs (leak path verification)
--   4. Boundary values (max/min)
--   5. Arithmetic shift correctness (sign preservation)
--   6. Status flag verification
--
-- Author: FPGA Neural Network Project
-- Compatible: GHDL, ModelSim, Vivado XSIM
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_leaky_relu_unit is
end entity tb_leaky_relu_unit;

architecture sim of tb_leaky_relu_unit is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant DATA_WIDTH : integer := 16;
    constant LEAK_SHIFT : integer := 4;   -- α = 1/16 = 0.0625
    constant FRAC_BITS  : integer := 13;
    
    -- Q2.13 format constants
    constant ONE_Q213   : integer := 8192;    -- 1.0
    constant HALF_Q213  : integer := 4096;    -- 0.5
    constant MAX_POS    : integer := 32767;   -- +3.9999
    constant MAX_NEG    : integer := -32768;  -- -4.0

    ---------------------------------------------------------------------------
    -- DUT Signals
    ---------------------------------------------------------------------------
    signal data_in     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal data_out    : signed(DATA_WIDTH-1 downto 0);
    signal is_positive : std_logic;
    signal is_negative : std_logic;

    ---------------------------------------------------------------------------
    -- Test Control
    ---------------------------------------------------------------------------
    signal test_number : integer := 0;
    signal all_passed  : boolean := true;

    ---------------------------------------------------------------------------
    -- Helper Function: Compute expected Leaky ReLU output
    ---------------------------------------------------------------------------
    function expected_output(input_val : signed(DATA_WIDTH-1 downto 0)) 
        return signed is
    begin
        if input_val >= 0 then
            return input_val;
        else
            return shift_right(input_val, LEAK_SHIFT);
        end if;
    end function;

    ---------------------------------------------------------------------------
    -- Helper Function: Convert to real for display
    ---------------------------------------------------------------------------
    function to_real(val : integer) return real is
    begin
        return real(val) / real(2**FRAC_BITS);
    end function;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : entity work.leaky_relu_unit
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            LEAK_SHIFT => LEAK_SHIFT
        )
        port map (
            data_in     => data_in,
            data_out    => data_out,
            is_positive => is_positive,
            is_negative => is_negative
        );

    ---------------------------------------------------------------------------
    -- Main Test Process
    ---------------------------------------------------------------------------
    test_proc : process
        variable expected     : signed(DATA_WIDTH-1 downto 0);
        variable test_input   : signed(DATA_WIDTH-1 downto 0);
        variable exp_positive : std_logic;
        variable exp_negative : std_logic;
        
    begin
        report "================================================";
        report "Leaky ReLU Unit Testbench - Starting";
        report "LEAK_SHIFT = " & integer'image(LEAK_SHIFT) & 
               " (alpha = 1/" & integer'image(2**LEAK_SHIFT) & ")";
        report "================================================";
        
        wait for 10 ns;
        
        -----------------------------------------------------------------------
        -- TEST 1: Zero Input (Boundary Case)
        -----------------------------------------------------------------------
        test_number <= 1;
        report "TEST 1: Zero input";
        
        data_in <= to_signed(0, DATA_WIDTH);
        wait for 10 ns;
        
        expected := to_signed(0, DATA_WIDTH);
        assert data_out = expected
            report "FAIL: Zero input - Expected 0, Got " & 
                   integer'image(to_integer(data_out))
            severity error;
        assert is_positive = '1'
            report "FAIL: Zero should be classified as positive"
            severity error;
        assert is_negative = '0'
            report "FAIL: Zero should not be classified as negative"
            severity error;
            
        if data_out = expected and is_positive = '1' and is_negative = '0' then
            report "PASS: Zero input correctly handled";
        else
            all_passed <= false;
        end if;
        
        wait for 10 ns;
        
        -----------------------------------------------------------------------
        -- TEST 2: Positive Input +1.0 (Pass-through)
        -----------------------------------------------------------------------
        test_number <= 2;
        report "TEST 2: Positive input +1.0";
        
        data_in <= to_signed(ONE_Q213, DATA_WIDTH);
        wait for 10 ns;
        
        expected := to_signed(ONE_Q213, DATA_WIDTH);
        assert data_out = expected
            report "FAIL: +1.0 should pass through unchanged. Got " &
                   integer'image(to_integer(data_out))
            severity error;
        assert is_positive = '1' and is_negative = '0'
            report "FAIL: +1.0 flag mismatch"
            severity error;
            
        if data_out = expected then
            report "PASS: +1.0 passes through correctly";
        else
            all_passed <= false;
        end if;
        
        wait for 10 ns;
        
        -----------------------------------------------------------------------
        -- TEST 3: Maximum Positive Value
        -----------------------------------------------------------------------
        test_number <= 3;
        report "TEST 3: Maximum positive (+3.9999)";
        
        data_in <= to_signed(MAX_POS, DATA_WIDTH);
        wait for 10 ns;
        
        expected := to_signed(MAX_POS, DATA_WIDTH);
        assert data_out = expected
            report "FAIL: Max positive should pass through. Got " &
                   integer'image(to_integer(data_out))
            severity error;
            
        if data_out = expected then
            report "PASS: Maximum positive handled correctly";
        else
            all_passed <= false;
        end if;
        
        wait for 10 ns;
        
        -----------------------------------------------------------------------
        -- TEST 4: Negative Input -1.0 (Leak Path)
        -----------------------------------------------------------------------
        test_number <= 4;
        report "TEST 4: Negative input -1.0 (should become -0.0625)";
        
        data_in <= to_signed(-ONE_Q213, DATA_WIDTH);  -- -8192
        wait for 10 ns;
        
        -- -8192 >> 4 = -512 (arithmetic shift preserves sign)
        expected := to_signed(-512, DATA_WIDTH);
        assert data_out = expected
            report "FAIL: -1.0 should become -0.0625 (-512). Got " &
                   integer'image(to_integer(data_out))
            severity error;
        assert is_positive = '0' and is_negative = '1'
            report "FAIL: -1.0 flag mismatch"
            severity error;
            
        if data_out = expected then
            report "PASS: -1.0 correctly scaled to -0.0625";
        else
            all_passed <= false;
        end if;
        
        wait for 10 ns;
        
        -----------------------------------------------------------------------
        -- TEST 5: Minimum Negative Value (-4.0)
        -----------------------------------------------------------------------
        test_number <= 5;
        report "TEST 5: Minimum negative (-4.0)";
        
        data_in <= to_signed(MAX_NEG, DATA_WIDTH);  -- -32768
        wait for 10 ns;
        
        -- -32768 >> 4 = -2048 (arithmetic shift)
        expected := to_signed(-2048, DATA_WIDTH);
        assert data_out = expected
            report "FAIL: -4.0 should become -0.25 (-2048). Got " &
                   integer'image(to_integer(data_out))
            severity error;
            
        if data_out = expected then
            report "PASS: Minimum negative handled correctly (-4.0 -> -0.25)";
        else
            all_passed <= false;
        end if;
        
        wait for 10 ns;
        
        -----------------------------------------------------------------------
        -- TEST 6: Verify Arithmetic Right Shift (Sign Preservation)
        -- Critical: Ensures shift_right on signed preserves sign bit
        -----------------------------------------------------------------------
        test_number <= 6;
        report "TEST 6: Arithmetic shift sign preservation";
        
        -- Test with -16 (0xFFF0): should become -1 (0xFFFF) after >> 4
        data_in <= to_signed(-16, DATA_WIDTH);
        wait for 10 ns;
        
        expected := to_signed(-1, DATA_WIDTH);
        assert data_out = expected
            report "FAIL: -16 >> 4 should be -1 (sign preserved). Got " &
                   integer'image(to_integer(data_out))
            severity error;
            
        if data_out = expected then
            report "PASS: Arithmetic shift correctly preserves sign";
        else
            all_passed <= false;
        end if;
        
        wait for 10 ns;
        
        -----------------------------------------------------------------------
        -- TEST 7: Small Negative (Underflow Check)
        -----------------------------------------------------------------------
        test_number <= 7;
        report "TEST 7: Small negative value (-1 LSB)";
        
        data_in <= to_signed(-1, DATA_WIDTH);
        wait for 10 ns;
        
        -- -1 >> 4 = -1 (arithmetic shift of -1 is always -1)
        expected := to_signed(-1, DATA_WIDTH);
        assert data_out = expected
            report "FAIL: -1 >> 4 should remain -1. Got " &
                   integer'image(to_integer(data_out))
            severity error;
            
        if data_out = expected then
            report "PASS: Small negative handled correctly";
        else
            all_passed <= false;
        end if;
        
        wait for 10 ns;
        
        -----------------------------------------------------------------------
        -- TEST 8: Positive Small Value (+1 LSB)
        -----------------------------------------------------------------------
        test_number <= 8;
        report "TEST 8: Small positive value (+1 LSB)";
        
        data_in <= to_signed(1, DATA_WIDTH);
        wait for 10 ns;
        
        expected := to_signed(1, DATA_WIDTH);
        assert data_out = expected
            report "FAIL: +1 should pass through. Got " &
                   integer'image(to_integer(data_out))
            severity error;
            
        if data_out = expected then
            report "PASS: Small positive passes through";
        else
            all_passed <= false;
        end if;
        
        wait for 10 ns;
        
        -----------------------------------------------------------------------
        -- TEST 9: Sweep Test - Multiple Values
        -----------------------------------------------------------------------
        test_number <= 9;
        report "TEST 9: Sweep test (21 values from -10000 to +10000)";
        
        for i in -10 to 10 loop
            test_input := to_signed(i * 1000, DATA_WIDTH);
            data_in <= test_input;
            wait for 5 ns;
            
            expected := expected_output(test_input);
            
            if data_out /= expected then
                report "FAIL: Sweep test i=" & integer'image(i) &
                       " Input=" & integer'image(i * 1000) &
                       " Expected=" & integer'image(to_integer(expected)) &
                       " Got=" & integer'image(to_integer(data_out))
                    severity error;
                all_passed <= false;
            end if;
        end loop;
        
        report "Sweep test completed";
        wait for 10 ns;
        
        -----------------------------------------------------------------------
        -- TEST 10: Specific Leak Ratio Verification
        -- Verify that output/input = 1/16 for negative values
        -----------------------------------------------------------------------
        test_number <= 10;
        report "TEST 10: Leak ratio verification";
        
        -- Input: -1024, Expected output: -64 (ratio = 1/16)
        data_in <= to_signed(-1024, DATA_WIDTH);
        wait for 10 ns;
        
        assert data_out = to_signed(-64, DATA_WIDTH)
            report "FAIL: -1024 * (1/16) should be -64. Got " &
                   integer'image(to_integer(data_out))
            severity error;
            
        if data_out = to_signed(-64, DATA_WIDTH) then
            report "PASS: Leak ratio 1/16 verified (-1024 -> -64)";
        else
            all_passed <= false;
        end if;
        
        wait for 10 ns;
        
        -----------------------------------------------------------------------
        -- Final Summary
        -----------------------------------------------------------------------
        report "================================================";
        report "Test Summary:";
        report "  Total Tests: 10 categories";
        
        if all_passed then
            report "  Result: *** ALL TESTS PASSED ***";
        else
            report "  Result: *** SOME TESTS FAILED ***" severity error;
        end if;
        
        report "================================================";
        
        -- End simulation
        wait for 20 ns;
        
        -- Use assert false to stop simulation (GHDL compatible)
        assert false report "Simulation completed" severity failure;
        
        wait;
    end process;

end architecture sim;
