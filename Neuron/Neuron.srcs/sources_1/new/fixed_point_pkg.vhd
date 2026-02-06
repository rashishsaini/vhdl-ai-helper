--------------------------------------------------------------------------------
-- Module: fixed_point_pkg
-- Description: Fixed-point arithmetic package for Q2.13 format
-- Author: FPGA Neural Network Project
-- Date: 2025
--------------------------------------------------------------------------------
-- This package provides:
--   - Q2.13 fixed-point type definitions (16-bit signed)
--   - Q4.26 product type (32-bit signed)
--   - Q10.26 accumulator type (40-bit signed)
--   - Arithmetic functions (multiply, add, saturate)
--   - Conversion functions (float to/from fixed)
--   - Rounding and saturation utilities
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

package fixed_point_pkg is
  
  --------------------------------------------------------------------------------
  -- CONSTANTS: Q2.13 Format Configuration
  --------------------------------------------------------------------------------
  constant DATA_WIDTH    : integer := 16;
  constant WEIGHT_WIDTH  : integer := 16;
  constant FRAC_BITS     : integer := 13;
  constant INT_BITS      : integer := 2;
  constant ACCUM_WIDTH   : integer := 40;
  constant PRODUCT_WIDTH : integer := 32;
  
  constant ACCUM_FRAC_BITS : integer := FRAC_BITS * 2;
  constant ACCUM_INT_BITS  : integer := INT_BITS * 2 + 2;
  
  --------------------------------------------------------------------------------
  -- TYPE DEFINITIONS
  --------------------------------------------------------------------------------
  subtype fx_data_t   is signed(DATA_WIDTH-1 downto 0);
  subtype fx_weight_t is signed(WEIGHT_WIDTH-1 downto 0);
  subtype fx_product_t is signed(PRODUCT_WIDTH-1 downto 0);
  subtype fx_accum_t  is signed(ACCUM_WIDTH-1 downto 0);
  
  --------------------------------------------------------------------------------
  -- CONSTANTS: Range Limits for Q2.13
  --------------------------------------------------------------------------------
  constant FX_MAX : fx_data_t := to_signed(32767, DATA_WIDTH);
  constant FX_MIN : fx_data_t := to_signed(-32768, DATA_WIDTH);
  constant ROUND_CONST : integer := 2**(FRAC_BITS-1);
  constant FX_ZERO : fx_data_t := to_signed(0, DATA_WIDTH);
  constant FX_ONE : fx_data_t := to_signed(2**FRAC_BITS, DATA_WIDTH);
  
  --------------------------------------------------------------------------------
  -- FUNCTION DECLARATIONS
  --------------------------------------------------------------------------------
  
  function fx_mult(a : fx_data_t; b : fx_weight_t) return fx_product_t;
  function fx_add(a : fx_data_t; b : fx_data_t) return fx_data_t;
  function fx_sub(a : fx_data_t; b : fx_data_t) return fx_data_t;
  function saturate(x : fx_accum_t) return fx_data_t;
  function round_and_saturate(x : fx_accum_t) return fx_data_t;
  function to_float(x : fx_data_t) return real;
  function to_fixed(x : real) return fx_data_t;
  function fx_abs(x : fx_data_t) return fx_data_t;
  function fx_compare(a : fx_data_t; b : fx_data_t) return integer;
  function fx_maximum(a : fx_data_t; b : fx_data_t) return fx_data_t;
  function fx_minimum(a : fx_data_t; b : fx_data_t) return fx_data_t;
  
end package fixed_point_pkg;

--------------------------------------------------------------------------------
-- PACKAGE BODY
--------------------------------------------------------------------------------
package body fixed_point_pkg is
  
  --------------------------------------------------------------------------------
  -- FUNCTION: fx_mult
  --------------------------------------------------------------------------------
  function fx_mult(a : fx_data_t; b : fx_weight_t) return fx_product_t is
    variable result : fx_product_t;
  begin
    result := a * b;
    return result;
  end function fx_mult;
  
  --------------------------------------------------------------------------------
  -- FUNCTION: fx_add
  --------------------------------------------------------------------------------
  function fx_add(a : fx_data_t; b : fx_data_t) return fx_data_t is
    variable sum : signed(DATA_WIDTH downto 0);
    variable result : fx_data_t;
  begin
    sum := resize(a, DATA_WIDTH+1) + resize(b, DATA_WIDTH+1);
    
    if sum > resize(FX_MAX, DATA_WIDTH+1) then
      result := FX_MAX;
    elsif sum < resize(FX_MIN, DATA_WIDTH+1) then
      result := FX_MIN;
    else
      result := resize(sum, DATA_WIDTH);
    end if;
    
    return result;
  end function fx_add;
  
  --------------------------------------------------------------------------------
  -- FUNCTION: fx_sub
  --------------------------------------------------------------------------------
  function fx_sub(a : fx_data_t; b : fx_data_t) return fx_data_t is
    variable diff : signed(DATA_WIDTH downto 0);
    variable result : fx_data_t;
  begin
    diff := resize(a, DATA_WIDTH+1) - resize(b, DATA_WIDTH+1);
    
    if diff > resize(FX_MAX, DATA_WIDTH+1) then
      result := FX_MAX;
    elsif diff < resize(FX_MIN, DATA_WIDTH+1) then
      result := FX_MIN;
    else
      result := resize(diff, DATA_WIDTH);
    end if;
    
    return result;
  end function fx_sub;
  
  --------------------------------------------------------------------------------
  -- FUNCTION: saturate
  --------------------------------------------------------------------------------
  function saturate(x : fx_accum_t) return fx_data_t is
    variable result : fx_data_t;
    variable x_extended_max : fx_accum_t;
    variable x_extended_min : fx_accum_t;
  begin
    x_extended_max := resize(FX_MAX, ACCUM_WIDTH);
    x_extended_min := resize(FX_MIN, ACCUM_WIDTH);
    
    if x > x_extended_max then
      result := FX_MAX;
    elsif x < x_extended_min then
      result := FX_MIN;
    else
      result := resize(x, DATA_WIDTH);
    end if;
    
    return result;
  end function saturate;
  
  --------------------------------------------------------------------------------
  -- FUNCTION: round_and_saturate
  --------------------------------------------------------------------------------
  function round_and_saturate(x : fx_accum_t) return fx_data_t is
    variable rounded : fx_accum_t;
    variable shifted : fx_accum_t;
    variable result : fx_data_t;
  begin
    rounded := x + to_signed(ROUND_CONST, ACCUM_WIDTH);
    shifted := shift_right(rounded, FRAC_BITS);
    result := saturate(shifted);
    
    return result;
  end function round_and_saturate;
  
  --------------------------------------------------------------------------------
  -- FUNCTION: to_float
  --------------------------------------------------------------------------------
  function to_float(x : fx_data_t) return real is
    variable float_val : real;
    variable scale : real;
  begin
    scale := real(2**FRAC_BITS);
    float_val := real(to_integer(x)) / scale;
    return float_val;
  end function to_float;
  
  --------------------------------------------------------------------------------
  -- FUNCTION: to_fixed
  --------------------------------------------------------------------------------
  function to_fixed(x : real) return fx_data_t is
    variable temp : real;
    variable temp_int : integer;
    variable result : fx_data_t;
    variable scale : real;
  begin
    scale := real(2**FRAC_BITS);
    temp := x * scale;
    temp_int := integer(round(temp));
    
    if temp_int > to_integer(FX_MAX) then
      result := FX_MAX;
    elsif temp_int < to_integer(FX_MIN) then
      result := FX_MIN;
    else
      result := to_signed(temp_int, DATA_WIDTH);
    end if;
    
    return result;
  end function to_fixed;
  
  --------------------------------------------------------------------------------
  -- FUNCTION: fx_abs
  --------------------------------------------------------------------------------
  function fx_abs(x : fx_data_t) return fx_data_t is
    variable result : fx_data_t;
  begin
    if x < 0 then
      if x = FX_MIN then
        result := FX_MAX;
      else
        result := -x;
      end if;
    else
      result := x;
    end if;
    return result;
  end function fx_abs;
  
  --------------------------------------------------------------------------------
  -- FUNCTION: fx_compare
  --------------------------------------------------------------------------------
  function fx_compare(a : fx_data_t; b : fx_data_t) return integer is
  begin
    if a < b then
      return -1;
    elsif a > b then
      return 1;
    else
      return 0;
    end if;
  end function fx_compare;
  
  --------------------------------------------------------------------------------
  -- FUNCTION: fx_maximum (renamed from fx_max)
  --------------------------------------------------------------------------------
  function fx_maximum(a : fx_data_t; b : fx_data_t) return fx_data_t is
  begin
    if a > b then
      return a;
    else
      return b;
    end if;
  end function fx_maximum;
  
  --------------------------------------------------------------------------------
  -- FUNCTION: fx_minimum (renamed from fx_min)
  --------------------------------------------------------------------------------
  function fx_minimum(a : fx_data_t; b : fx_data_t) return fx_data_t is
  begin
    if a < b then
      return a;
    else
      return b;
    end if;
  end function fx_minimum;
  
end package body fixed_point_pkg;