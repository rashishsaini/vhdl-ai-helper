--------------------------------------------------------------------------------
-- Module: fixed_point_pkg_tb
-- Description: Comprehensive testbench for fixed_point_pkg
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;
use IEEE.std_logic_textio.all;

library work;
use work.fixed_point_pkg.all;

entity fixed_point_pkg_tb is
end entity fixed_point_pkg_tb;

architecture behavioral of fixed_point_pkg_tb is
  
  signal test_complete : boolean := false;
  signal test_passed : boolean := true;
  
  shared variable test_count : integer := 0;
  shared variable pass_count : integer := 0;
  shared variable fail_count : integer := 0;
  
  --------------------------------------------------------------------------------
  -- Helper Procedures
  --------------------------------------------------------------------------------
  
  procedure report_test(
    test_name : string;
    passed : boolean
  ) is
    variable l : line;
  begin
    test_count := test_count + 1;
    write(l, string'("Test "));
    write(l, test_count);
    write(l, string'(": "));
    write(l, test_name);
    write(l, string'(" - "));
    if passed then
      write(l, string'("PASSED"));
      pass_count := pass_count + 1;
    else
      write(l, string'("FAILED"));
      fail_count := fail_count + 1;
    end if;
    writeline(output, l);
  end procedure;
  
  procedure check_equal(
    test_name : string;
    actual : fx_data_t;
    expected : fx_data_t;
    signal test_sig : inout boolean
  ) is
    variable l : line;
  begin
    if actual = expected then
      report_test(test_name, true);
    else
      report_test(test_name, false);
      write(l, string'("  Expected: "));
      hwrite(l, std_logic_vector(expected));
      write(l, string'(" = "));
      write(l, to_float(expected));
      writeline(output, l);
      write(l, string'("  Got:      "));
      hwrite(l, std_logic_vector(actual));
      write(l, string'(" = "));
      write(l, to_float(actual));
      writeline(output, l);
      test_sig <= false;
    end if;
  end procedure;
  
  procedure check_equal_prod(
    test_name : string;
    actual : fx_product_t;
    expected : fx_product_t;
    signal test_sig : inout boolean
  ) is
    variable l : line;
  begin
    if actual = expected then
      report_test(test_name, true);
    else
      report_test(test_name, false);
      write(l, string'("  Expected: "));
      hwrite(l, std_logic_vector(expected));
      writeline(output, l);
      write(l, string'("  Got:      "));
      hwrite(l, std_logic_vector(actual));
      writeline(output, l);
      test_sig <= false;
    end if;
  end procedure;
  
  procedure check_close(
    test_name : string;
    actual : real;
    expected : real;
    tolerance : real;
    signal test_sig : inout boolean
  ) is
    variable l : line;
  begin
    if abs(actual - expected) <= tolerance then
      report_test(test_name, true);
    else
      report_test(test_name, false);
      write(l, string'("  Expected: "));
      write(l, expected);
      writeline(output, l);
      write(l, string'("  Got:      "));
      write(l, actual);
      writeline(output, l);
      write(l, string'("  Error:    "));
      write(l, abs(actual - expected));
      writeline(output, l);
      test_sig <= false;
    end if;
  end procedure;
  
begin
  
  --------------------------------------------------------------------------------
  -- Main Test Process
  --------------------------------------------------------------------------------
  test_proc : process
    variable a, b, result : fx_data_t;
    variable prod : fx_product_t;
    variable accum : fx_accum_t;
    variable float_val : real;
    variable l : line;
    
  begin
    
    write(l, string'("========================================================================"));
    writeline(output, l);
    write(l, string'("FIXED-POINT PACKAGE TESTBENCH"));
    writeline(output, l);
    write(l, string'("Format: Q2.13 (16-bit signed)"));
    writeline(output, l);
    write(l, string'("Range: -4.0 to +3.9998779"));
    writeline(output, l);
    write(l, string'("Resolution: 0.0001220703"));
    writeline(output, l);
    write(l, string'("========================================================================"));
    writeline(output, l);
    writeline(output, l);
    
    --------------------------------------------------------------------------------
    -- TEST SECTION 1: Constants and Type Conversions
    --------------------------------------------------------------------------------
    write(l, string'("TEST SECTION 1: Constants"));
    writeline(output, l);
    write(l, string'("------------------------------------------------------------------------"));
    writeline(output, l);
    
    check_equal("FX_MAX value", FX_MAX, to_signed(32767, 16), test_passed);
    check_equal("FX_MIN value", FX_MIN, to_signed(-32768, 16), test_passed);
    check_equal("FX_ZERO value", FX_ZERO, to_signed(0, 16), test_passed);
    check_equal("FX_ONE value", FX_ONE, to_signed(8192, 16), test_passed);
    
    writeline(output, l);
    
    --------------------------------------------------------------------------------
    -- TEST SECTION 2: to_fixed and to_float Conversions
    --------------------------------------------------------------------------------
    write(l, string'("TEST SECTION 2: Conversions"));
    writeline(output, l);
    write(l, string'("------------------------------------------------------------------------"));
    writeline(output, l);
    
    a := to_fixed(0.0);
    check_equal("to_fixed(0.0)", a, to_signed(0, 16), test_passed);
    
    a := to_fixed(1.0);
    check_equal("to_fixed(1.0)", a, to_signed(8192, 16), test_passed);
    
    a := to_fixed(1.5);
    check_equal("to_fixed(1.5)", a, to_signed(12288, 16), test_passed);
    
    a := to_fixed(-1.0);
    check_equal("to_fixed(-1.0)", a, to_signed(-8192, 16), test_passed);
    
    a := to_fixed(2.5);
    check_equal("to_fixed(2.5)", a, to_signed(20480, 16), test_passed);
    
    a := to_fixed(-2.75);
    check_equal("to_fixed(-2.75)", a, to_signed(-22528, 16), test_passed);
    
    a := to_fixed(10.0);
    check_equal("to_fixed(10.0) saturates", a, FX_MAX, test_passed);
    
    a := to_fixed(-10.0);
    check_equal("to_fixed(-10.0) saturates", a, FX_MIN, test_passed);
    
    a := to_fixed(1.5);
    float_val := to_float(a);
    check_close("to_float(to_fixed(1.5))", float_val, 1.5, 0.0001, test_passed);
    
    a := to_fixed(-2.25);
    float_val := to_float(a);
    check_close("to_float(to_fixed(-2.25))", float_val, -2.25, 0.0001, test_passed);
    
    writeline(output, l);
    
    --------------------------------------------------------------------------------
    -- TEST SECTION 3: fx_mult (Multiplication)
    --------------------------------------------------------------------------------
    write(l, string'("TEST SECTION 3: Multiplication"));
    writeline(output, l);
    write(l, string'("------------------------------------------------------------------------"));
    writeline(output, l);
    
    -- 1.0 x 1.0 = 1.0 in Q4.26
    a := to_fixed(1.0);
    b := to_fixed(1.0);
    prod := fx_mult(a, b);
    -- 1.0 in Q4.26 = 1 * 2^26 = 67108864
    check_equal_prod("1.0 x 1.0", prod, to_signed(67108864, 32), test_passed);
    
    -- 2.0 x 1.5 = 3.0 in Q4.26
    a := to_fixed(2.0);
    b := to_fixed(1.5);
    prod := fx_mult(a, b);
    -- 3.0 in Q4.26 = 3 * 2^26 = 201326592
    check_equal_prod("2.0 x 1.5", prod, to_signed(201326592, 32), test_passed);
    
    -- -1.0 x 2.0 = -2.0 in Q4.26
    a := to_fixed(-1.0);
    b := to_fixed(2.0);
    prod := fx_mult(a, b);
    -- -2.0 in Q4.26 = -2 * 2^26 = -134217728
    check_equal_prod("-1.0 x 2.0", prod, to_signed(-134217728, 32), test_passed);
    
    -- 0.5 x 0.5 = 0.25 in Q4.26
    a := to_fixed(0.5);
    b := to_fixed(0.5);
    prod := fx_mult(a, b);
    -- 0.25 in Q4.26 = 0.25 * 2^26 = 16777216
    check_equal_prod("0.5 x 0.5", prod, to_signed(16777216, 32), test_passed);
    
    writeline(output, l);
    
    --------------------------------------------------------------------------------
    -- TEST SECTION 4: fx_add (Addition with Saturation)
    --------------------------------------------------------------------------------
    write(l, string'("TEST SECTION 4: Addition"));
    writeline(output, l);
    write(l, string'("------------------------------------------------------------------------"));
    writeline(output, l);
    
    a := to_fixed(1.0);
    b := to_fixed(1.0);
    result := fx_add(a, b);
    check_equal("1.0 + 1.0", result, to_fixed(2.0), test_passed);
    
    a := to_fixed(2.5);
    b := to_fixed(1.25);
    result := fx_add(a, b);
    check_equal("2.5 + 1.25", result, to_fixed(3.75), test_passed);
    
    a := to_fixed(-1.5);
    b := to_fixed(2.5);
    result := fx_add(a, b);
    check_equal("-1.5 + 2.5", result, to_fixed(1.0), test_passed);
    
    a := to_fixed(3.5);
    b := to_fixed(1.0);
    result := fx_add(a, b);
    check_equal("3.5 + 1.0 saturates", result, FX_MAX, test_passed);
    
    a := to_fixed(-3.5);
    b := to_fixed(-1.0);
    result := fx_add(a, b);
    check_equal("-3.5 + -1.0 saturates", result, FX_MIN, test_passed);
    
    writeline(output, l);
    
    --------------------------------------------------------------------------------
    -- TEST SECTION 5: fx_sub (Subtraction with Saturation)
    --------------------------------------------------------------------------------
    write(l, string'("TEST SECTION 5: Subtraction"));
    writeline(output, l);
    write(l, string'("------------------------------------------------------------------------"));
    writeline(output, l);
    
    a := to_fixed(2.0);
    b := to_fixed(1.0);
    result := fx_sub(a, b);
    check_equal("2.0 - 1.0", result, to_fixed(1.0), test_passed);
    
    a := to_fixed(1.0);
    b := to_fixed(2.0);
    result := fx_sub(a, b);
    check_equal("1.0 - 2.0", result, to_fixed(-1.0), test_passed);
    
    a := to_fixed(3.5);
    b := to_fixed(-1.0);
    result := fx_sub(a, b);
    check_equal("3.5 - (-1.0) saturates", result, FX_MAX, test_passed);
    
    writeline(output, l);
    
    --------------------------------------------------------------------------------
    -- TEST SECTION 6: saturate Function
    --------------------------------------------------------------------------------
    write(l, string'("TEST SECTION 6: Saturation"));
    writeline(output, l);
    write(l, string'("------------------------------------------------------------------------"));
    writeline(output, l);
    
    accum := to_signed(10000, 40);
    result := saturate(accum);
    check_equal("saturate(small value)", result, to_signed(10000, 16), test_passed);
    
    accum := to_signed(100000, 40);
    result := saturate(accum);
    check_equal("saturate(large value)", result, FX_MAX, test_passed);
    
    accum := to_signed(-100000, 40);
    result := saturate(accum);
    check_equal("saturate(large negative)", result, FX_MIN, test_passed);
    
    writeline(output, l);
    
    --------------------------------------------------------------------------------
    -- TEST SECTION 7: round_and_saturate Function
    --------------------------------------------------------------------------------
    write(l, string'("TEST SECTION 7: Round and Saturate"));
    writeline(output, l);
    write(l, string'("------------------------------------------------------------------------"));
    writeline(output, l);
    
    -- 1.3 in Q10.26: shift 1.3 by 26 bits
    accum := shift_left(to_signed(10650, 40), 13);  -- 1.3 in Q2.13, then shift 13
    result := round_and_saturate(accum);
    float_val := to_float(result);
    check_close("round(1.3)", float_val, 1.3, 0.001, test_passed);
    
    -- 1.8 in Q10.26
    accum := shift_left(to_signed(14746, 40), 13);  -- 1.8 in Q2.13, then shift 13
    result := round_and_saturate(accum);
    float_val := to_float(result);
    check_close("round(1.8)", float_val, 1.8, 0.001, test_passed);
    
    -- Very large value
    accum := to_signed(1000000000, 40);
    result := round_and_saturate(accum);
    check_equal("round large value", result, FX_MAX, test_passed);
    
    writeline(output, l);
    
    --------------------------------------------------------------------------------
    -- TEST SECTION 8: fx_abs (Absolute Value)
    --------------------------------------------------------------------------------
    write(l, string'("TEST SECTION 8: Absolute Value"));
    writeline(output, l);
    write(l, string'("------------------------------------------------------------------------"));
    writeline(output, l);
    
    a := to_fixed(2.5);
    result := fx_abs(a);
    check_equal("abs(2.5)", result, to_fixed(2.5), test_passed);
    
    a := to_fixed(-2.5);
    result := fx_abs(a);
    check_equal("abs(-2.5)", result, to_fixed(2.5), test_passed);
    
    a := FX_ZERO;
    result := fx_abs(a);
    check_equal("abs(0)", result, FX_ZERO, test_passed);
    
    a := FX_MIN;
    result := fx_abs(a);
    check_equal("abs(FX_MIN)", result, FX_MAX, test_passed);
    
    writeline(output, l);
    
    --------------------------------------------------------------------------------
    -- TEST SECTION 9: fx_compare, fx_maximum, fx_minimum
    --------------------------------------------------------------------------------
    write(l, string'("TEST SECTION 9: Comparison"));
    writeline(output, l);
    write(l, string'("------------------------------------------------------------------------"));
    writeline(output, l);
    
    a := to_fixed(1.0);
    b := to_fixed(2.0);
    assert fx_compare(a, b) = -1 report "compare failed" severity error;
    report_test("fx_compare(1.0, 2.0) = -1", fx_compare(a, b) = -1);
    
    assert fx_compare(b, a) = 1 report "compare failed" severity error;
    report_test("fx_compare(2.0, 1.0) = +1", fx_compare(b, a) = 1);
    
    assert fx_compare(a, a) = 0 report "compare failed" severity error;
    report_test("fx_compare(1.0, 1.0) = 0", fx_compare(a, a) = 0);
    
    result := fx_maximum(a, b);
    check_equal("fx_maximum(1.0, 2.0)", result, b, test_passed);
    
    result := fx_minimum(a, b);
    check_equal("fx_minimum(1.0, 2.0)", result, a, test_passed);
    
    writeline(output, l);
    
    --------------------------------------------------------------------------------
    -- TEST SECTION 10: Edge Cases
    --------------------------------------------------------------------------------
    write(l, string'("TEST SECTION 10: Edge Cases"));
    writeline(output, l);
    write(l, string'("------------------------------------------------------------------------"));
    writeline(output, l);
    
    a := FX_MAX;
    b := FX_MAX;
    prod := fx_mult(a, b);
    report_test("FX_MAX x FX_MAX positive", prod(31) = '0');
    
    a := FX_MIN;
    b := FX_MIN;
    prod := fx_mult(a, b);
    report_test("FX_MIN x FX_MIN positive", prod(31) = '0');
    
    a := FX_MAX;
    b := FX_MIN;
    prod := fx_mult(a, b);
    report_test("FX_MAX x FX_MIN negative", prod(31) = '1');
    
    writeline(output, l);
    
    --------------------------------------------------------------------------------
    -- FINAL SUMMARY
    --------------------------------------------------------------------------------
    write(l, string'("========================================================================"));
    writeline(output, l);
    write(l, string'("TEST SUMMARY"));
    writeline(output, l);
    write(l, string'("------------------------------------------------------------------------"));
    writeline(output, l);
    write(l, string'("Total Tests:  "));
    write(l, test_count);
    writeline(output, l);
    write(l, string'("Passed:       "));
    write(l, pass_count);
    writeline(output, l);
    write(l, string'("Failed:       "));
    write(l, fail_count);
    writeline(output, l);
    write(l, string'("------------------------------------------------------------------------"));
    writeline(output, l);
    
    if fail_count = 0 then
      write(l, string'("RESULT: ALL TESTS PASSED"));
    else
      write(l, string'("RESULT: SOME TESTS FAILED"));
      test_passed <= false;
    end if;
    writeline(output, l);
    write(l, string'("========================================================================"));
    writeline(output, l);
    
    test_complete <= true;
    wait;
    
  end process test_proc;
  
end architecture behavioral;