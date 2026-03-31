# Complete Guide: Converting 4-2-1 to 4-8-4-1 Neural Network

## Table of Contents

1. [Introduction](#1-introduction)
2. [Architecture Comparison](#2-architecture-comparison)
3. [Prerequisites](#3-prerequisites)
4. [File Structure Overview](#4-file-structure-overview)
5. [Step-by-Step Conversion](#5-step-by-step-conversion)
   - [5.1 Modify single_neuron.vhd](#51-modify-single_neuronvhd)
   - [5.2 Create neural_network_4841.vhd](#52-create-neural_network_4841vhd)
   - [5.3 Update Testbench Package](#53-update-testbench-package)
6. [Iris Dataset Integration](#6-iris-dataset-integration)
7. [Training and Testing](#7-training-and-testing)
8. [Simulation Commands](#8-simulation-commands)
9. [Troubleshooting](#9-troubleshooting)
10. [Performance Expectations](#10-performance-expectations)

---

## 1. Introduction

This guide provides step-by-step instructions to convert a 4-2-1 VHDL neural network to a 4-8-4-1 architecture and train it on the Iris binary classification problem.

### What You'll Achieve

| Aspect | Before | After |
|--------|--------|-------|
| Architecture | 4-2-1 (3 neurons) | 4-8-4-1 (13 neurons) |
| Complexity | Simple XOR/AND/OR | Real-world classification |
| Dataset | Synthetic patterns | Iris flower dataset |
| Output | Continuous | Binary class (0 or 1) |

### Why 4-8-4-1?

- **4 inputs**: Matches Iris dataset (sepal length, sepal width, petal length, petal width)
- **8 hidden neurons (L1)**: Sufficient capacity to learn feature combinations
- **4 hidden neurons (L2)**: Dimensionality reduction before output
- **1 output**: Binary classification (Setosa vs Non-Setosa)

---

## 2. Architecture Comparison

### Visual Comparison

```
4-2-1 Architecture                    4-8-4-1 Architecture
==================                    ====================

   Input Layer                           Input Layer
   [4 features]                          [4 features]
       │                                     │
       ▼                                     ▼
  ┌─────────┐                        ┌───────────────┐
  │ Layer 1 │                        │   Layer 1     │
  │ 2 neurons│                       │  8 neurons    │
  │ 4 inputs │                       │  4 inputs ea. │
  │  ReLU    │                       │    ReLU       │
  └────┬────┘                        └───────┬───────┘
       │ 2 values                            │ 8 values
       ▼                                     ▼
  ┌─────────┐                        ┌───────────────┐
  │ Layer 2 │                        │   Layer 2     │
  │ 1 neuron │                       │  4 neurons    │
  │ 2 inputs │                       │  8 inputs ea. │
  │  ReLU    │                       │    ReLU       │
  └────┬────┘                        └───────┬───────┘
       │                                     │ 4 values
       ▼                                     ▼
    Output                           ┌───────────────┐
                                     │   Layer 3     │
                                     │  1 neuron     │
                                     │  4 inputs     │
                                     │   LINEAR      │
                                     └───────┬───────┘
                                             │
                                             ▼
                                     ┌───────────────┐
                                     │   Decision    │
                                     │  >0 → Class 1 │
                                     │  ≤0 → Class 0 │
                                     └───────────────┘
```

### Numerical Comparison

| Property | 4-2-1 | 4-8-4-1 | Change |
|----------|-------|---------|--------|
| Total Neurons | 3 | 13 | +333% |
| Layer 1 Neurons | 2 | 8 | +300% |
| Layer 2 Neurons | 1 | 4 | +300% |
| Layer 3 Neurons | - | 1 | New |
| Total Weights | 10 | 68 | +580% |
| Total Biases | 3 | 13 | +333% |
| L1 Weights | 2×4=8 | 8×4=32 | +300% |
| L2 Weights | 1×2=2 | 4×8=32 | +1500% |
| L3 Weights | - | 1×4=4 | New |
| Forward Pass Cycles | ~15 | ~40 | +167% |
| Backward Pass Cycles | ~20 | ~80 | +300% |
| Update Cycles | ~15 | ~100 | +567% |

### Key Architectural Differences

| Feature | 4-2-1 | 4-8-4-1 |
|---------|-------|---------|
| Output Activation | ReLU | Linear |
| Decision Threshold | None | >0 → 8192, ≤0 → 0 |
| Error Backprop Depth | 2 layers | 3 layers |
| L2→L1 Error Sources | 1 neuron | 4 neurons (summed) |

---

## 3. Prerequisites

### Required Files (Existing 4-2-1 Implementation)

```
your_project/
├── sources/
│   ├── single_neuron.vhd        # Parameterized neuron module
│   └── neural_network_421.vhd   # 4-2-1 network top module
├── testbench/
│   ├── neural_network_tb_pkg.vhd    # Testbench utilities
│   └── tb_neural_network_421.vhd    # Original testbench
└── simulation/
    └── (simulation outputs)
```

### Required Tools

- GHDL (recommended) or Vivado Simulator
- Python 3.x with scikit-learn (for dataset generation)
- GTKWave (optional, for waveform viewing)

### Verify Existing Setup

Before starting, ensure your 4-2-1 network passes basic tests:

```bash
# Compile and run existing testbench
ghdl -a --std=08 single_neuron.vhd
ghdl -a --std=08 neural_network_421.vhd
ghdl -a --std=08 neural_network_tb_pkg.vhd
ghdl -a --std=08 tb_neural_network_421.vhd
ghdl -e --std=08 tb_neural_network_421
ghdl -r --std=08 tb_neural_network_421 --stop-time=10ms
```

---

## 4. File Structure Overview

### After Conversion

```
your_project/
├── sources/
│   ├── single_neuron.vhd            # MODIFIED: Added USE_LINEAR_ACT
│   ├── neural_network_421.vhd       # UNCHANGED: Keep for reference
│   └── neural_network_4841.vhd      # NEW: 4-8-4-1 network
├── testbench/
│   ├── neural_network_tb_pkg.vhd    # MODIFIED: Added new utilities
│   ├── iris_dataset_pkg.vhd         # NEW: Iris data constants
│   ├── tb_neural_network_421.vhd    # UNCHANGED: Original tests
│   └── tb_neural_network_4841_iris.vhd  # NEW: Iris training testbench
├── scripts/
│   └── generate_iris_vhdl.py        # NEW: Python dataset generator
└── simulation/
    └── (simulation outputs)
```

---

## 5. Step-by-Step Conversion

### 5.1 Modify single_neuron.vhd

The single_neuron module needs minimal changes to support linear activation for the output layer.

#### Change 1: Add USE_LINEAR_ACT Generic

**Location:** Generic declaration section (around line 20-35)

**Before:**
```vhdl
generic (
    DATA_WIDTH      : integer := 16;
    ACCUM_WIDTH     : integer := 40;
    GRAD_WIDTH      : integer := 32;
    FRAC_BITS       : integer := 13;
    NUM_INPUTS      : integer := 4;
    IS_OUTPUT_LAYER : boolean := false;
    NEURON_ID       : integer := 0;
    DEFAULT_LR      : integer := 82
);
```

**After:**
```vhdl
generic (
    DATA_WIDTH      : integer := 16;
    ACCUM_WIDTH     : integer := 40;
    GRAD_WIDTH      : integer := 32;
    FRAC_BITS       : integer := 13;
    NUM_INPUTS      : integer := 4;
    IS_OUTPUT_LAYER : boolean := false;
    USE_LINEAR_ACT  : boolean := false;  -- NEW: Linear activation when true
    NEURON_ID       : integer := 0;
    DEFAULT_LR      : integer := 82
);
```

#### Change 2: Modify Activation State in Forward FSM

**Location:** FWD_ACTIVATE state (around line 370)

**Before:**
```vhdl
when FWD_ACTIVATE =>
    if fwd_clear = '1' then
        fwd_state <= FWD_IDLE;
    else
        -- Apply ReLU
        a_reg <= relu(z_reg);
        fwd_state <= FWD_DONE_ST;
    end if;
```

**After:**
```vhdl
when FWD_ACTIVATE =>
    if fwd_clear = '1' then
        fwd_state <= FWD_IDLE;
    else
        -- Apply activation based on generic
        if USE_LINEAR_ACT then
            a_reg <= z_reg;  -- Linear: pass through unchanged
        else
            a_reg <= relu(z_reg);  -- ReLU for hidden layers
        end if;
        fwd_state <= FWD_DONE_ST;
    end if;
```

#### Change 3: Modify Backward Pass Delta Calculation

**Location:** BWD_CALC_DELTA state (around line 450)

**Before:**
```vhdl
when BWD_CALC_DELTA =>
    if bwd_clear = '1' then
        bwd_state <= BWD_IDLE;
    elsif error_valid = '1' then
        -- δ = error × σ'(z)
        deriv := relu_derivative(z_reg);
        delta_product := error_in * deriv;
        -- ... rest of code
```

**After:**
```vhdl
when BWD_CALC_DELTA =>
    if bwd_clear = '1' then
        bwd_state <= BWD_IDLE;
    elsif error_valid = '1' then
        -- δ = error × σ'(z)
        -- For linear activation: derivative = 1 always
        if USE_LINEAR_ACT then
            deriv := ONE_Q213;  -- Linear derivative = 1.0
        else
            deriv := relu_derivative(z_reg);
        end if;
        delta_product := error_in * deriv;
        -- ... rest of code unchanged
```

---

### 5.2 Create neural_network_4841.vhd

Create a new file `neural_network_4841.vhd` with the complete 4-8-4-1 implementation.

#### Complete Module Structure

```vhdl
--------------------------------------------------------------------------------
-- Module: neural_network_4841
-- Description: 4-8-4-1 Neural Network for binary classification
--              Input: 4 features (Q2.13)
--              Hidden Layer 1: 8 neurons, ReLU
--              Hidden Layer 2: 4 neurons, ReLU  
--              Output Layer: 1 neuron, Linear
--              Decision: >0 → Class 1, ≤0 → Class 0
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity neural_network_4841 is
    generic (
        DATA_WIDTH : integer := 16
    );
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        
        -- Training control
        start_forward   : in  std_logic;
        start_backward  : in  std_logic;
        start_update    : in  std_logic;
        
        -- Input data (4 features)
        input_data      : in  signed(DATA_WIDTH-1 downto 0);
        input_index     : in  unsigned(1 downto 0);
        input_valid     : in  std_logic;
        
        -- Target for training
        target          : in  signed(DATA_WIDTH-1 downto 0);
        
        -- Learning rate
        learning_rate   : in  signed(DATA_WIDTH-1 downto 0);
        
        -- Network outputs
        output_data     : out signed(DATA_WIDTH-1 downto 0);  -- Raw output
        output_class    : out signed(DATA_WIDTH-1 downto 0);  -- Thresholded (0 or 8192)
        output_valid    : out std_logic;
        
        -- Status
        fwd_done        : out std_logic;
        bwd_done        : out std_logic;
        upd_done        : out std_logic
    );
end entity neural_network_4841;

architecture rtl of neural_network_4841 is

    -- Constants
    constant FRAC_BITS : integer := 13;
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH);
    constant CLASS_ONE : signed(DATA_WIDTH-1 downto 0) := to_signed(8192, DATA_WIDTH);
    constant CLASS_ZERO : signed(DATA_WIDTH-1 downto 0) := to_signed(0, DATA_WIDTH);

    ---------------------------------------------------------------------------
    -- Type Definitions
    ---------------------------------------------------------------------------
    
    -- Layer 1: 8 neurons
    type l1_data_array_t is array (0 to 7) of signed(DATA_WIDTH-1 downto 0);
    
    -- Layer 2: 4 neurons  
    type l2_data_array_t is array (0 to 3) of signed(DATA_WIDTH-1 downto 0);
    
    -- Weight matrix for L2→L1 error propagation (4 neurons × 8 weights each)
    type l2_weight_matrix_t is array (0 to 3, 0 to 7) of signed(DATA_WIDTH-1 downto 0);

    ---------------------------------------------------------------------------
    -- Layer 1 Signals (8 neurons × 4 inputs each)
    ---------------------------------------------------------------------------
    signal l1_a         : l1_data_array_t;
    signal l1_delta     : l1_data_array_t;
    signal l1_error     : l1_data_array_t;
    signal l1_fwd_done  : std_logic_vector(7 downto 0);
    signal l1_bwd_done  : std_logic_vector(7 downto 0);
    signal l1_upd_done  : std_logic_vector(7 downto 0);
    
    -- L1 aggregated signals
    signal l1_all_fwd_done : std_logic;
    signal l1_all_bwd_done : std_logic;
    signal l1_all_upd_done : std_logic;

    ---------------------------------------------------------------------------
    -- Layer 2 Signals (4 neurons × 8 inputs each)
    ---------------------------------------------------------------------------
    signal l2_a         : l2_data_array_t;
    signal l2_delta     : l2_data_array_t;
    signal l2_error     : l2_data_array_t;
    signal l2_fwd_done  : std_logic_vector(3 downto 0);
    signal l2_bwd_done  : std_logic_vector(3 downto 0);
    signal l2_upd_done  : std_logic_vector(3 downto 0);
    
    -- L2 weight propagation (for L1 error calculation)
    type l2_weight_array_t is array (0 to 3) of signed(DATA_WIDTH-1 downto 0);
    signal l2_weight_for_prop : l2_weight_array_t;
    signal l2_weight_prop_idx : unsigned(3 downto 0);
    signal l2_weight_prop_en  : std_logic;
    signal l2_weights_matrix  : l2_weight_matrix_t;
    
    -- L2 aggregated signals
    signal l2_all_fwd_done : std_logic;
    signal l2_all_bwd_done : std_logic;
    signal l2_all_upd_done : std_logic;

    ---------------------------------------------------------------------------
    -- Layer 3 Signals (1 neuron × 4 inputs, LINEAR activation)
    ---------------------------------------------------------------------------
    signal l3_a             : signed(DATA_WIDTH-1 downto 0);
    signal l3_delta         : signed(DATA_WIDTH-1 downto 0);
    signal l3_fwd_done      : std_logic;
    signal l3_bwd_done      : std_logic;
    signal l3_upd_done      : std_logic;
    signal output_error     : signed(DATA_WIDTH-1 downto 0);
    
    -- L3 weight propagation (for L2 error calculation)
    signal l3_weight_for_prop : signed(DATA_WIDTH-1 downto 0);
    signal l3_weight_prop_idx : unsigned(3 downto 0);
    signal l3_weight_prop_en  : std_logic;
    signal l3_weights_captured : l2_data_array_t;

    ---------------------------------------------------------------------------
    -- L2 Input Sequencing FSM (feeds 8 L1 outputs to L2)
    ---------------------------------------------------------------------------
    type l2_input_state_t is (L2_IDLE, L2_START, L2_FEED_INPUTS, L2_WAIT_DONE);
    signal l2_input_state   : l2_input_state_t;
    signal l2_input_data    : signed(DATA_WIDTH-1 downto 0);
    signal l2_input_index   : unsigned(3 downto 0);
    signal l2_input_valid   : std_logic;
    signal l2_fwd_start     : std_logic;
    signal l2_feed_index    : unsigned(3 downto 0);
    signal l1_all_done_prev : std_logic;

    ---------------------------------------------------------------------------
    -- L3 Input Sequencing FSM (feeds 4 L2 outputs to L3)
    ---------------------------------------------------------------------------
    type l3_input_state_t is (L3_IDLE, L3_START, L3_FEED_INPUTS, L3_WAIT_DONE);
    signal l3_input_state   : l3_input_state_t;
    signal l3_input_data    : signed(DATA_WIDTH-1 downto 0);
    signal l3_input_index   : unsigned(3 downto 0);
    signal l3_input_valid   : std_logic;
    signal l3_fwd_start     : std_logic;
    signal l3_feed_index    : unsigned(3 downto 0);
    signal l2_all_done_prev : std_logic;

    ---------------------------------------------------------------------------
    -- L3 Weight Read FSM (reads L3 weights for L2 error calculation)
    ---------------------------------------------------------------------------
    type l3_wr_state_t is (WR3_IDLE, WR3_READ, WR3_DONE);
    signal l3_wr_state      : l3_wr_state_t;
    signal l3_wr_index      : unsigned(3 downto 0);

    ---------------------------------------------------------------------------
    -- L2 Weight Read FSM (reads L2 weights for L1 error calculation)
    ---------------------------------------------------------------------------
    type l2_wr_state_t is (WR2_IDLE, WR2_READ, WR2_NEXT, WR2_COMPUTE, WR2_DONE);
    signal l2_wr_state      : l2_wr_state_t;
    signal l2_wr_neuron_idx : unsigned(2 downto 0);
    signal l2_wr_weight_idx : unsigned(3 downto 0);

    ---------------------------------------------------------------------------
    -- Saturation Helper Function
    ---------------------------------------------------------------------------
    function saturate_multiply(
        a : signed(DATA_WIDTH-1 downto 0);
        b : signed(DATA_WIDTH-1 downto 0)
    ) return signed is
        variable product : signed(2*DATA_WIDTH-1 downto 0);
        variable scaled  : signed(DATA_WIDTH downto 0);
    begin
        product := a * b;
        scaled := resize(shift_right(product, FRAC_BITS), DATA_WIDTH+1);
        
        if scaled > resize(SAT_MAX, DATA_WIDTH+1) then
            return SAT_MAX;
        elsif scaled < resize(SAT_MIN, DATA_WIDTH+1) then
            return SAT_MIN;
        else
            return scaled(DATA_WIDTH-1 downto 0);
        end if;
    end function;

    -- Resized input index for 4-bit neuron ports
    signal input_index_4bit : unsigned(3 downto 0);

begin

    input_index_4bit <= resize(input_index, 4);

    ---------------------------------------------------------------------------
    -- Layer 1: 8 Neurons × 4 Inputs Each (ReLU Activation)
    ---------------------------------------------------------------------------
    gen_layer1 : for i in 0 to 7 generate
        l1_neuron : entity work.single_neuron
            generic map (
                NUM_INPUTS      => 4,
                IS_OUTPUT_LAYER => false,
                USE_LINEAR_ACT  => false,  -- ReLU
                NEURON_ID       => i
            )
            port map (
                clk             => clk,
                rst             => rst,
                fwd_start       => start_forward,
                fwd_clear       => '0',
                input_data      => input_data,
                input_index     => input_index_4bit,
                input_valid     => input_valid,
                input_ready     => open,
                z_out           => open,
                a_out           => l1_a(i),
                fwd_done        => l1_fwd_done(i),
                fwd_busy        => open,
                bwd_start       => start_backward,
                bwd_clear       => '0',
                error_in        => l1_error(i),
                error_valid     => l2_all_bwd_done,
                delta_out       => l1_delta(i),
                delta_valid     => open,
                weight_for_prop => open,
                weight_prop_idx => (others => '0'),
                weight_prop_en  => '0',
                bwd_done        => l1_bwd_done(i),
                bwd_busy        => open,
                upd_start       => start_update,
                upd_clear       => '0',
                learning_rate   => learning_rate,
                upd_done        => l1_upd_done(i),
                upd_busy        => open,
                weight_init_en  => '0',
                weight_init_idx => (others => '0'),
                weight_init_data=> (others => '0'),
                weight_read_en  => '0',
                weight_read_idx => (others => '0'),
                weight_read_data=> open,
                overflow        => open
            );
    end generate gen_layer1;

    ---------------------------------------------------------------------------
    -- Layer 2: 4 Neurons × 8 Inputs Each (ReLU Activation)
    ---------------------------------------------------------------------------
    gen_layer2 : for i in 0 to 3 generate
        l2_neuron : entity work.single_neuron
            generic map (
                NUM_INPUTS      => 8,
                IS_OUTPUT_LAYER => false,
                USE_LINEAR_ACT  => false,  -- ReLU
                NEURON_ID       => 8 + i   -- IDs 8-11
            )
            port map (
                clk             => clk,
                rst             => rst,
                fwd_start       => l2_fwd_start,
                fwd_clear       => '0',
                input_data      => l2_input_data,
                input_index     => l2_input_index,
                input_valid     => l2_input_valid,
                input_ready     => open,
                z_out           => open,
                a_out           => l2_a(i),
                fwd_done        => l2_fwd_done(i),
                fwd_busy        => open,
                bwd_start       => start_backward,
                bwd_clear       => '0',
                error_in        => l2_error(i),
                error_valid     => l3_bwd_done,
                delta_out       => l2_delta(i),
                delta_valid     => open,
                weight_for_prop => l2_weight_for_prop(i),
                weight_prop_idx => l2_weight_prop_idx,
                weight_prop_en  => l2_weight_prop_en,
                bwd_done        => l2_bwd_done(i),
                bwd_busy        => open,
                upd_start       => start_update,
                upd_clear       => '0',
                learning_rate   => learning_rate,
                upd_done        => l2_upd_done(i),
                upd_busy        => open,
                weight_init_en  => '0',
                weight_init_idx => (others => '0'),
                weight_init_data=> (others => '0'),
                weight_read_en  => '0',
                weight_read_idx => (others => '0'),
                weight_read_data=> open,
                overflow        => open
            );
    end generate gen_layer2;

    ---------------------------------------------------------------------------
    -- Layer 3: 1 Neuron × 4 Inputs (LINEAR Activation)
    ---------------------------------------------------------------------------
    l3_output : entity work.single_neuron
        generic map (
            NUM_INPUTS      => 4,
            IS_OUTPUT_LAYER => true,
            USE_LINEAR_ACT  => true,   -- LINEAR activation
            NEURON_ID       => 12
        )
        port map (
            clk             => clk,
            rst             => rst,
            fwd_start       => l3_fwd_start,
            fwd_clear       => '0',
            input_data      => l3_input_data,
            input_index     => l3_input_index,
            input_valid     => l3_input_valid,
            input_ready     => open,
            z_out           => open,
            a_out           => l3_a,
            fwd_done        => l3_fwd_done,
            fwd_busy        => open,
            bwd_start       => start_backward,
            bwd_clear       => '0',
            error_in        => output_error,
            error_valid     => '1',
            delta_out       => l3_delta,
            delta_valid     => open,
            weight_for_prop => l3_weight_for_prop,
            weight_prop_idx => l3_weight_prop_idx,
            weight_prop_en  => l3_weight_prop_en,
            bwd_done        => l3_bwd_done,
            bwd_busy        => open,
            upd_start       => start_update,
            upd_clear       => '0',
            learning_rate   => learning_rate,
            upd_done        => l3_upd_done,
            upd_busy        => open,
            weight_init_en  => '0',
            weight_init_idx => (others => '0'),
            weight_init_data=> (others => '0'),
            weight_read_en  => '0',
            weight_read_idx => (others => '0'),
            weight_read_data=> open,
            overflow        => open
        );

    ---------------------------------------------------------------------------
    -- Aggregated Done Signals
    ---------------------------------------------------------------------------
    l1_all_fwd_done <= '1' when l1_fwd_done = "11111111" else '0';
    l2_all_fwd_done <= '1' when l2_fwd_done = "1111" else '0';
    l1_all_bwd_done <= '1' when l1_bwd_done = "11111111" else '0';
    l2_all_bwd_done <= '1' when l2_bwd_done = "1111" else '0';
    l1_all_upd_done <= '1' when l1_upd_done = "11111111" else '0';
    l2_all_upd_done <= '1' when l2_upd_done = "1111" else '0';

    ---------------------------------------------------------------------------
    -- L2 Input Sequencing FSM
    -- Waits for all L1 neurons, then feeds their outputs to L2 neurons
    ---------------------------------------------------------------------------
    l2_input_fsm : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                l2_input_state <= L2_IDLE;
                l2_feed_index <= (others => '0');
                l2_input_valid <= '0';
                l2_fwd_start <= '0';
                l1_all_done_prev <= '0';
            else
                l1_all_done_prev <= l1_all_fwd_done;
                
                case l2_input_state is
                    when L2_IDLE =>
                        l2_input_valid <= '0';
                        l2_fwd_start <= '0';
                        -- Edge detection: trigger on rising edge of l1_all_fwd_done
                        if l1_all_fwd_done = '1' and l1_all_done_prev = '0' then
                            l2_fwd_start <= '1';
                            l2_input_state <= L2_START;
                        end if;

                    when L2_START =>
                        l2_fwd_start <= '0';
                        l2_feed_index <= (others => '0');
                        l2_input_state <= L2_FEED_INPUTS;

                    when L2_FEED_INPUTS =>
                        l2_input_data <= l1_a(to_integer(l2_feed_index));
                        l2_input_index <= l2_feed_index;
                        l2_input_valid <= '1';
                        
                        if l2_feed_index = 7 then
                            l2_input_state <= L2_WAIT_DONE;
                        else
                            l2_feed_index <= l2_feed_index + 1;
                        end if;

                    when L2_WAIT_DONE =>
                        l2_input_valid <= '0';
                        if l2_all_fwd_done = '1' then
                            l2_input_state <= L2_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- L3 Input Sequencing FSM
    -- Waits for all L2 neurons, then feeds their outputs to L3 neuron
    ---------------------------------------------------------------------------
    l3_input_fsm : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                l3_input_state <= L3_IDLE;
                l3_feed_index <= (others => '0');
                l3_input_valid <= '0';
                l3_fwd_start <= '0';
                l2_all_done_prev <= '0';
            else
                l2_all_done_prev <= l2_all_fwd_done;
                
                case l3_input_state is
                    when L3_IDLE =>
                        l3_input_valid <= '0';
                        l3_fwd_start <= '0';
                        if l2_all_fwd_done = '1' and l2_all_done_prev = '0' then
                            l3_fwd_start <= '1';
                            l3_input_state <= L3_START;
                        end if;

                    when L3_START =>
                        l3_fwd_start <= '0';
                        l3_feed_index <= (others => '0');
                        l3_input_state <= L3_FEED_INPUTS;

                    when L3_FEED_INPUTS =>
                        l3_input_data <= l2_a(to_integer(l3_feed_index));
                        l3_input_index <= l3_feed_index;
                        l3_input_valid <= '1';
                        
                        if l3_feed_index = 3 then
                            l3_input_state <= L3_WAIT_DONE;
                        else
                            l3_feed_index <= l3_feed_index + 1;
                        end if;

                    when L3_WAIT_DONE =>
                        l3_input_valid <= '0';
                        if l3_fwd_done = '1' then
                            l3_input_state <= L3_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Output Error Computation: error = output - target (for gradient descent)
    ---------------------------------------------------------------------------
    output_error_proc : process(target, l3_a)
        variable diff : signed(DATA_WIDTH downto 0);
    begin
        diff := resize(l3_a, DATA_WIDTH+1) - resize(target, DATA_WIDTH+1);
        
        if diff > resize(SAT_MAX, DATA_WIDTH+1) then
            output_error <= SAT_MAX;
        elsif diff < resize(SAT_MIN, DATA_WIDTH+1) then
            output_error <= SAT_MIN;
        else
            output_error <= diff(DATA_WIDTH-1 downto 0);
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- L3 Weight Read FSM (for L2 error calculation)
    ---------------------------------------------------------------------------
    l3_weight_read_fsm : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                l3_wr_state <= WR3_IDLE;
                l3_wr_index <= (others => '0');
                l3_weight_prop_en <= '0';
                l3_weights_captured <= (others => (others => '0'));
            else
                case l3_wr_state is
                    when WR3_IDLE =>
                        l3_weight_prop_en <= '0';
                        if start_backward = '1' then
                            l3_weight_prop_en <= '1';
                            l3_wr_index <= (others => '0');
                            l3_wr_state <= WR3_READ;
                        end if;

                    when WR3_READ =>
                        l3_weight_prop_idx <= l3_wr_index;
                        
                        -- Capture weight (1 cycle delay for read)
                        if l3_wr_index > 0 then
                            l3_weights_captured(to_integer(l3_wr_index - 1)) <= l3_weight_for_prop;
                        end if;
                        
                        if l3_wr_index = 4 then
                            l3_weights_captured(3) <= l3_weight_for_prop;
                            l3_wr_state <= WR3_DONE;
                        else
                            l3_wr_index <= l3_wr_index + 1;
                        end if;

                    when WR3_DONE =>
                        l3_weight_prop_en <= '0';
                        if l3_bwd_done = '1' then
                            l3_wr_state <= WR3_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- L2 Error Computation: l2_error[i] = W_L3[i] × δ_L3
    ---------------------------------------------------------------------------
    gen_l2_error : for i in 0 to 3 generate
        l2_error(i) <= saturate_multiply(l3_weights_captured(i), l3_delta);
    end generate;

    ---------------------------------------------------------------------------
    -- L2 Weight Read FSM (for L1 error calculation)
    -- Reads weights from all 4 L2 neurons (4 × 8 = 32 weights)
    ---------------------------------------------------------------------------
    l2_weight_read_fsm : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                l2_wr_state <= WR2_IDLE;
                l2_wr_neuron_idx <= (others => '0');
                l2_wr_weight_idx <= (others => '0');
                l2_weight_prop_en <= '0';
                l2_weights_matrix <= (others => (others => (others => '0')));
            else
                case l2_wr_state is
                    when WR2_IDLE =>
                        l2_weight_prop_en <= '0';
                        if l3_bwd_done = '1' then
                            l2_weight_prop_en <= '1';
                            l2_wr_neuron_idx <= (others => '0');
                            l2_wr_weight_idx <= (others => '0');
                            l2_wr_state <= WR2_READ;
                        end if;

                    when WR2_READ =>
                        l2_weight_prop_idx <= l2_wr_weight_idx;
                        
                        -- Capture weights from all L2 neurons simultaneously
                        if l2_wr_weight_idx > 0 then
                            for n in 0 to 3 loop
                                l2_weights_matrix(n, to_integer(l2_wr_weight_idx - 1)) 
                                    <= l2_weight_for_prop(n);
                            end loop;
                        end if;
                        
                        if l2_wr_weight_idx = 8 then
                            for n in 0 to 3 loop
                                l2_weights_matrix(n, 7) <= l2_weight_for_prop(n);
                            end loop;
                            l2_wr_state <= WR2_COMPUTE;
                        else
                            l2_wr_weight_idx <= l2_wr_weight_idx + 1;
                        end if;

                    when WR2_COMPUTE =>
                        l2_weight_prop_en <= '0';
                        l2_wr_state <= WR2_DONE;

                    when WR2_DONE =>
                        if l2_all_bwd_done = '1' then
                            l2_wr_state <= WR2_IDLE;
                        end if;
                        
                    when others =>
                        l2_wr_state <= WR2_IDLE;
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- L1 Error Computation: l1_error[i] = Σ(W_L2[j][i] × δ_L2[j]) for j=0..3
    -- Each L1 neuron receives error contributions from ALL 4 L2 neurons
    ---------------------------------------------------------------------------
    gen_l1_error : for i in 0 to 7 generate
        signal term0, term1, term2, term3 : signed(DATA_WIDTH-1 downto 0);
        signal sum01, sum23 : signed(DATA_WIDTH downto 0);
        signal sum_all : signed(DATA_WIDTH+1 downto 0);
    begin
        term0 <= saturate_multiply(l2_weights_matrix(0, i), l2_delta(0));
        term1 <= saturate_multiply(l2_weights_matrix(1, i), l2_delta(1));
        term2 <= saturate_multiply(l2_weights_matrix(2, i), l2_delta(2));
        term3 <= saturate_multiply(l2_weights_matrix(3, i), l2_delta(3));
        
        sum01 <= resize(term0, DATA_WIDTH+1) + resize(term1, DATA_WIDTH+1);
        sum23 <= resize(term2, DATA_WIDTH+1) + resize(term3, DATA_WIDTH+1);
        sum_all <= resize(sum01, DATA_WIDTH+2) + resize(sum23, DATA_WIDTH+2);
        
        l1_error(i) <= SAT_MAX when sum_all > resize(SAT_MAX, DATA_WIDTH+2) else
                       SAT_MIN when sum_all < resize(SAT_MIN, DATA_WIDTH+2) else
                       sum_all(DATA_WIDTH-1 downto 0);
    end generate;

    ---------------------------------------------------------------------------
    -- Decision Threshold: >0 → Class 1 (8192), ≤0 → Class 0
    ---------------------------------------------------------------------------
    decision_proc : process(l3_a)
    begin
        if l3_a > 0 then
            output_class <= CLASS_ONE;   -- 8192 = 1.0 in Q2.13
        else
            output_class <= CLASS_ZERO;  -- 0
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    output_data  <= l3_a;
    output_valid <= l3_fwd_done;
    fwd_done     <= l3_fwd_done;
    bwd_done     <= l1_all_bwd_done;
    upd_done     <= l1_all_upd_done and l2_all_upd_done and l3_upd_done;

end architecture rtl;
```

---

### 5.3 Update Testbench Package

Add new helper functions to `neural_network_tb_pkg.vhd` for Iris testing.

#### Add to Package Declaration

```vhdl
-- Add to neural_network_tb_pkg.vhd

-- Classification accuracy calculation
function calculate_accuracy(
    predictions : test_dataset_t;
    labels : test_dataset_t
) return real;

-- Binary classification check
function is_correct_class(
    prediction : real;
    target : real;
    threshold : real := 0.5
) return boolean;
```

#### Add to Package Body

```vhdl
function calculate_accuracy(
    predictions : test_dataset_t;
    labels : test_dataset_t
) return real is
    variable correct : integer := 0;
    variable total : integer;
    variable pred_class, actual_class : integer;
begin
    total := predictions'length;
    
    for i in predictions'range loop
        -- Threshold at 0.5 (4096 in Q2.13)
        if predictions(i).target > 0.5 then
            pred_class := 1;
        else
            pred_class := 0;
        end if;
        
        if labels(i).target > 0.5 then
            actual_class := 1;
        else
            actual_class := 0;
        end if;
        
        if pred_class = actual_class then
            correct := correct + 1;
        end if;
    end loop;
    
    return real(correct) / real(total) * 100.0;
end function;

function is_correct_class(
    prediction : real;
    target : real;
    threshold : real := 0.5
) return boolean is
    variable pred_class, actual_class : integer;
begin
    if prediction > threshold then
        pred_class := 1;
    else
        pred_class := 0;
    end if;
    
    if target > threshold then
        actual_class := 1;
    else
        actual_class := 0;
    end if;
    
    return pred_class = actual_class;
end function;
```

---

## 6. Iris Dataset Integration

### 6.1 Python Script: generate_iris_vhdl.py

Create this script in your `scripts/` directory:

```python
#!/usr/bin/env python3
"""
Generate VHDL package with Iris dataset for binary classification.
Task: Setosa (class 0) vs Non-Setosa (class 1)

Usage:
    python generate_iris_vhdl.py

Output:
    iris_dataset_pkg.vhd - Full 150-sample dataset
    iris_dataset_small_pkg.vhd - 30-sample subset for quick testing
"""

from sklearn.datasets import load_iris
import numpy as np

def to_q213(value):
    """Convert float to Q2.13 fixed-point integer."""
    result = int(round(value * 8192))
    return max(-32768, min(32767, result))

def normalize_features(X):
    """Normalize features to [0, 1] range."""
    X_min = X.min(axis=0)
    X_max = X.max(axis=0)
    return (X - X_min) / (X_max - X_min + 1e-8)

def generate_vhdl_package(X, y, package_name, filename):
    """Generate VHDL package with dataset constants."""
    
    n_samples = len(y)
    
    with open(filename, 'w') as f:
        # Header
        f.write("-" * 80 + "\n")
        f.write(f"-- Package: {package_name}\n")
        f.write("-- Description: Iris binary classification dataset\n")
        f.write("--              Setosa (0) vs Non-Setosa (1)\n")
        f.write("--              Auto-generated by generate_iris_vhdl.py\n")
        f.write(f"-- Samples: {n_samples}\n")
        f.write("-- Features: 4 (sepal_len, sepal_wid, petal_len, petal_wid)\n")
        f.write("-- Format: Q2.13 fixed-point (16-bit signed)\n")
        f.write("-" * 80 + "\n\n")
        
        f.write("library IEEE;\n")
        f.write("use IEEE.std_logic_1164.all;\n")
        f.write("use IEEE.numeric_std.all;\n\n")
        
        f.write(f"package {package_name} is\n\n")
        
        # Constants
        f.write("    constant DATA_WIDTH   : integer := 16;\n")
        f.write(f"    constant NUM_SAMPLES  : integer := {n_samples};\n")
        f.write("    constant NUM_FEATURES : integer := 4;\n")
        f.write("    constant CLASS_SETOSA : integer := 0;\n")
        f.write("    constant CLASS_OTHER  : integer := 8192;  -- 1.0 in Q2.13\n\n")
        
        # Types
        f.write("    -- Feature array type (4 features per sample)\n")
        f.write("    type feature_array_t is array (0 to NUM_FEATURES-1) of ")
        f.write("signed(DATA_WIDTH-1 downto 0);\n\n")
        
        f.write("    -- Dataset types\n")
        f.write("    type iris_features_t is array (0 to NUM_SAMPLES-1) of feature_array_t;\n")
        f.write("    type iris_labels_t is array (0 to NUM_SAMPLES-1) of ")
        f.write("signed(DATA_WIDTH-1 downto 0);\n\n")
        
        # Features
        f.write("    -- Iris features (normalized to [0,1], Q2.13 format)\n")
        f.write("    constant IRIS_FEATURES : iris_features_t := (\n")
        
        for i in range(n_samples):
            f0, f1, f2, f3 = [to_q213(X[i, j]) for j in range(4)]
            line = f"        {i:3d} => ("
            line += f"to_signed({f0:6d}, DATA_WIDTH), "
            line += f"to_signed({f1:6d}, DATA_WIDTH), "
            line += f"to_signed({f2:6d}, DATA_WIDTH), "
            line += f"to_signed({f3:6d}, DATA_WIDTH))"
            
            if i < n_samples - 1:
                line += ","
            
            f.write(line + "\n")
        
        f.write("    );\n\n")
        
        # Labels
        f.write("    -- Iris labels (0=Setosa, 8192=Non-Setosa)\n")
        f.write("    constant IRIS_LABELS : iris_labels_t := (\n")
        
        for i in range(n_samples):
            label = 0 if y[i] == 0 else 8192
            class_name = "Setosa" if y[i] == 0 else "Non-Setosa"
            line = f"        {i:3d} => to_signed({label:5d}, DATA_WIDTH)"
            
            if i < n_samples - 1:
                line += ","
            
            line += f"  -- {class_name}"
            f.write(line + "\n")
        
        f.write("    );\n\n")
        
        # Train/test split indices
        train_end = int(n_samples * 0.8)
        f.write(f"    -- Train/Test split indices\n")
        f.write(f"    constant TRAIN_START : integer := 0;\n")
        f.write(f"    constant TRAIN_END   : integer := {train_end - 1};\n")
        f.write(f"    constant TEST_START  : integer := {train_end};\n")
        f.write(f"    constant TEST_END    : integer := {n_samples - 1};\n\n")
        
        f.write(f"end package {package_name};\n")
    
    print(f"Generated: {filename}")
    print(f"  Samples: {n_samples}")
    print(f"  Class 0 (Setosa): {sum(y == 0)}")
    print(f"  Class 1 (Non-Setosa): {sum(y != 0)}")
    print()

def main():
    print("=" * 60)
    print("Iris Dataset VHDL Generator")
    print("=" * 60)
    print()
    
    # Load dataset
    iris = load_iris()
    X = iris.data
    y = iris.target
    
    # Binary classification: Setosa (0) vs Non-Setosa (1, 2 → 1)
    y_binary = (y != 0).astype(int)
    
    # Normalize features
    X_norm = normalize_features(X)
    
    # Shuffle with fixed seed for reproducibility
    np.random.seed(42)
    indices = np.random.permutation(len(y))
    X_shuffled = X_norm[indices]
    y_shuffled = y_binary[indices]
    
    # Generate full dataset
    generate_vhdl_package(
        X_shuffled, 
        y_shuffled,
        "iris_dataset_pkg",
        "iris_dataset_pkg.vhd"
    )
    
    # Generate small subset for quick testing
    generate_vhdl_package(
        X_shuffled[:30], 
        y_shuffled[:30],
        "iris_dataset_small_pkg",
        "iris_dataset_small_pkg.vhd"
    )
    
    print("=" * 60)
    print("Dataset Statistics")
    print("=" * 60)
    print(f"Feature ranges (normalized):")
    print(f"  Sepal Length: [{X_norm[:, 0].min():.3f}, {X_norm[:, 0].max():.3f}]")
    print(f"  Sepal Width:  [{X_norm[:, 1].min():.3f}, {X_norm[:, 1].max():.3f}]")
    print(f"  Petal Length: [{X_norm[:, 2].min():.3f}, {X_norm[:, 2].max():.3f}]")
    print(f"  Petal Width:  [{X_norm[:, 3].min():.3f}, {X_norm[:, 3].max():.3f}]")
    print()
    print("Class distribution:")
    print(f"  Setosa:     {sum(y_binary == 0)} samples (33.3%)")
    print(f"  Non-Setosa: {sum(y_binary == 1)} samples (66.7%)")

if __name__ == "__main__":
    main()
```

### 6.2 Run the Script

```bash
cd scripts/
python generate_iris_vhdl.py
mv iris_dataset_pkg.vhd ../testbench/
mv iris_dataset_small_pkg.vhd ../testbench/
```

---

## 7. Training and Testing

### 7.1 Create Iris Testbench: tb_neural_network_4841_iris.vhd

```vhdl
--------------------------------------------------------------------------------
-- Testbench: tb_neural_network_4841_iris
-- Description: Train and test 4-8-4-1 network on Iris binary classification
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;

-- Use small dataset for faster simulation, switch to full later
use work.iris_dataset_small_pkg.all;
-- use work.iris_dataset_pkg.all;  -- Uncomment for full dataset

entity tb_neural_network_4841_iris is
end entity;

architecture behavioral of tb_neural_network_4841_iris is

    constant CLK_PERIOD : time := 10 ns;
    constant FWD_TIMEOUT : integer := 500;
    constant BWD_TIMEOUT : integer := 800;
    constant UPD_TIMEOUT : integer := 1500;
    
    signal clk : std_logic := '0';
    signal rst : std_logic := '0';
    signal sim_done : boolean := false;
    
    -- DUT signals
    signal start_forward  : std_logic := '0';
    signal start_backward : std_logic := '0';
    signal start_update   : std_logic := '0';
    signal input_data     : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal input_index    : unsigned(1 downto 0) := (others => '0');
    signal input_valid    : std_logic := '0';
    signal target         : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal learning_rate  : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal output_data    : signed(DATA_WIDTH-1 downto 0);
    signal output_class   : signed(DATA_WIDTH-1 downto 0);
    signal output_valid   : std_logic;
    signal fwd_done       : std_logic;
    signal bwd_done       : std_logic;
    signal upd_done       : std_logic;

    -- Helper function
    function to_real(s : signed) return real is
    begin
        return real(to_integer(s)) / 8192.0;
    end function;

begin

    -- Clock generation
    clk_proc : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- DUT
    DUT : entity work.neural_network_4841
        generic map (DATA_WIDTH => DATA_WIDTH)
        port map (
            clk            => clk,
            rst            => rst,
            start_forward  => start_forward,
            start_backward => start_backward,
            start_update   => start_update,
            input_data     => input_data,
            input_index    => input_index,
            input_valid    => input_valid,
            target         => target,
            learning_rate  => learning_rate,
            output_data    => output_data,
            output_class   => output_class,
            output_valid   => output_valid,
            fwd_done       => fwd_done,
            bwd_done       => bwd_done,
            upd_done       => upd_done
        );

    -- Main test process
    test_proc : process
        variable correct : integer;
        variable total : integer;
        variable accuracy : real;
        variable train_acc, test_acc : real;
        variable timeout_count : integer;
        
        procedure run_forward(sample_idx : integer) is
        begin
            start_forward <= '1';
            wait until rising_edge(clk);
            start_forward <= '0';
            
            for f in 0 to 3 loop
                input_index <= to_unsigned(f, 2);
                input_data <= IRIS_FEATURES(sample_idx)(f);
                input_valid <= '1';
                wait until rising_edge(clk);
            end loop;
            
            input_valid <= '0';
            
            timeout_count := 0;
            while fwd_done /= '1' and timeout_count < FWD_TIMEOUT loop
                wait until rising_edge(clk);
                timeout_count := timeout_count + 1;
            end loop;
            
            assert timeout_count < FWD_TIMEOUT
                report "Forward pass timeout!" severity error;
                
            wait until rising_edge(clk);
        end procedure;
        
        procedure run_backward(sample_idx : integer) is
        begin
            target <= IRIS_LABELS(sample_idx);
            start_backward <= '1';
            wait until rising_edge(clk);
            start_backward <= '0';
            
            timeout_count := 0;
            while bwd_done /= '1' and timeout_count < BWD_TIMEOUT loop
                wait until rising_edge(clk);
                timeout_count := timeout_count + 1;
            end loop;
            
            assert timeout_count < BWD_TIMEOUT
                report "Backward pass timeout!" severity error;
                
            wait until rising_edge(clk);
        end procedure;
        
        procedure run_update is
        begin
            start_update <= '1';
            wait until rising_edge(clk);
            start_update <= '0';
            
            timeout_count := 0;
            while upd_done /= '1' and timeout_count < UPD_TIMEOUT loop
                wait until rising_edge(clk);
                timeout_count := timeout_count + 1;
            end loop;
            
            assert timeout_count < UPD_TIMEOUT
                report "Update pass timeout!" severity error;
                
            wait until rising_edge(clk);
        end procedure;
        
        procedure train_sample(sample_idx : integer) is
        begin
            run_forward(sample_idx);
            run_backward(sample_idx);
            run_update;
        end procedure;
        
        procedure evaluate(start_idx, end_idx : integer; variable acc : out real) is
            variable pred_class, actual_class : integer;
        begin
            correct := 0;
            total := 0;
            
            for i in start_idx to end_idx loop
                run_forward(i);
                
                if output_class > 0 then
                    pred_class := 1;
                else
                    pred_class := 0;
                end if;
                
                if IRIS_LABELS(i) > 0 then
                    actual_class := 1;
                else
                    actual_class := 0;
                end if;
                
                if pred_class = actual_class then
                    correct := correct + 1;
                end if;
                total := total + 1;
            end loop;
            
            acc := real(correct) / real(total) * 100.0;
        end procedure;

    begin
        report "========================================";
        report "  4-8-4-1 Iris Binary Classification";
        report "  Task: Setosa vs Non-Setosa";
        report "  Samples: " & integer'image(NUM_SAMPLES);
        report "========================================";
        
        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 10;
        rst <= '0';
        wait for CLK_PERIOD * 5;
        
        -- Learning rate: 0.1 = 819 in Q2.13
        learning_rate <= to_signed(819, DATA_WIDTH);
        
        -- Training loop
        for epoch in 1 to 50 loop
            -- Train on training set
            for s in TRAIN_START to TRAIN_END loop
                train_sample(s);
            end loop;
            
            -- Evaluate every 10 epochs
            if epoch mod 10 = 0 then
                evaluate(TRAIN_START, TRAIN_END, train_acc);
                report "Epoch " & integer'image(epoch) & 
                       ": Train Accuracy = " & real'image(train_acc) & "%";
            end if;
        end loop;
        
        -- Final evaluation
        report "========================================";
        report "  Final Results";
        report "========================================";
        
        evaluate(TRAIN_START, TRAIN_END, train_acc);
        report "Training Accuracy: " & real'image(train_acc) & "%";
        
        evaluate(TEST_START, TEST_END, test_acc);
        report "Test Accuracy: " & real'image(test_acc) & "%";
        
        if test_acc >= 90.0 then
            report "*** SUCCESS: Iris classification achieved! ***" severity note;
        else
            report "*** NEEDS IMPROVEMENT: Accuracy below 90% ***" severity warning;
        end if;
        
        report "========================================";
        
        sim_done <= true;
        wait;
    end process;

end architecture;
```

---

## 8. Simulation Commands

### 8.1 GHDL Compilation and Simulation

```bash
#!/bin/bash
# compile_and_run.sh

# Set VHDL standard
VHDL_STD="--std=08"

# Clean previous builds
rm -f *.cf *.o work-obj08.cf

# Compile sources in dependency order
echo "Compiling sources..."
ghdl -a $VHDL_STD single_neuron.vhd
ghdl -a $VHDL_STD neural_network_4841.vhd

# Compile testbench packages
echo "Compiling testbench packages..."
ghdl -a $VHDL_STD neural_network_tb_pkg.vhd
ghdl -a $VHDL_STD iris_dataset_small_pkg.vhd
# ghdl -a $VHDL_STD iris_dataset_pkg.vhd  # For full dataset

# Compile testbench
echo "Compiling testbench..."
ghdl -a $VHDL_STD tb_neural_network_4841_iris.vhd

# Elaborate
echo "Elaborating..."
ghdl -e $VHDL_STD tb_neural_network_4841_iris

# Run simulation
echo "Running simulation..."
ghdl -r $VHDL_STD tb_neural_network_4841_iris \
    --stop-time=50ms \
    --wave=iris_training.ghw

echo "Simulation complete!"
echo "View waveform: gtkwave iris_training.ghw"
```

### 8.2 Vivado TCL Commands

```tcl
# vivado_sim.tcl

# Create project
create_project iris_nn ./iris_nn -part xc7a35tcpg236-1

# Add sources
add_files -norecurse {
    ./sources/single_neuron.vhd
    ./sources/neural_network_4841.vhd
}

# Add testbench files
add_files -fileset sim_1 -norecurse {
    ./testbench/neural_network_tb_pkg.vhd
    ./testbench/iris_dataset_small_pkg.vhd
    ./testbench/tb_neural_network_4841_iris.vhd
}

# Set top module for simulation
set_property top tb_neural_network_4841_iris [get_filesets sim_1]

# Run simulation
launch_simulation
run 50ms
```

---

## 9. Troubleshooting

### Common Issues and Solutions

| Issue | Symptom | Solution |
|-------|---------|----------|
| Compilation error: USE_LINEAR_ACT not found | Generic not recognized | Ensure single_neuron.vhd was updated with new generic |
| Forward pass timeout | fwd_done never asserts | Check L2/L3 input FSMs, verify edge detection logic |
| All outputs are 0 | Network not learning | Check weight initialization, verify gradients are non-zero |
| Accuracy stuck at 50% | Random guessing | Verify error sign (should be output - target), check learning rate |
| Backward pass timeout | bwd_done never asserts | Check error_valid signals, verify L3→L2→L1 error propagation |
| Metavalue warnings | 'X' or 'U' in signals | Initialize all signals, check reset logic |

### Debug Checklist

1. **Verify single_neuron changes compile:**
   ```bash
   ghdl -a --std=08 single_neuron.vhd
   # Should complete without errors
   ```

2. **Check forward pass produces output:**
   ```vhdl
   report "Output: " & integer'image(to_integer(output_data));
   -- Should be non-zero after forward pass
   ```

3. **Verify gradients are computed:**
   - Add debug reports in single_neuron backward FSM
   - Check delta_out is non-zero when z > 0

4. **Monitor weight changes:**
   - Read weights before and after update
   - Verify weights change in correct direction

---

## 10. Performance Expectations

### Training Metrics (Setosa vs Non-Setosa)

| Metric | Expected Value | Notes |
|--------|----------------|-------|
| Training Accuracy | 95-100% | Setosa is linearly separable |
| Test Accuracy | 95-100% | Should generalize well |
| Epochs to Converge | 20-50 | With LR=0.1 |
| Simulation Time | 5-30 seconds | Depends on dataset size |

### Timing (Per Sample)

| Phase | Cycles | Time @ 100MHz |
|-------|--------|---------------|
| Forward Pass | ~40 | 400 ns |
| Backward Pass | ~80 | 800 ns |
| Weight Update | ~100 | 1 μs |
| **Total** | **~220** | **2.2 μs** |

### Resource Estimates (Xilinx 7-Series)

| Resource | 4-2-1 | 4-8-4-1 | Notes |
|----------|-------|---------|-------|
| LUTs | ~2,000 | ~8,000 | Multipliers dominate |
| FFs | ~500 | ~2,000 | Weight storage |
| DSP48 | 3 | 13 | One per neuron |
| BRAM | 0 | 0 | Weights in registers |

---

## Quick Reference Card

### File Changes Summary

| File | Action | Key Changes |
|------|--------|-------------|
| `single_neuron.vhd` | Modify | Add USE_LINEAR_ACT generic, modify activation |
| `neural_network_4841.vhd` | Create | 13 neurons, 3 layers, input FSMs, error backprop |
| `iris_dataset_pkg.vhd` | Generate | Python script creates VHDL constants |
| `tb_neural_network_4841_iris.vhd` | Create | Training loop, accuracy evaluation |

### Command Cheat Sheet

```bash
# Generate dataset
python scripts/generate_iris_vhdl.py

# Compile all
ghdl -a --std=08 single_neuron.vhd
ghdl -a --std=08 neural_network_4841.vhd
ghdl -a --std=08 iris_dataset_small_pkg.vhd
ghdl -a --std=08 tb_neural_network_4841_iris.vhd

# Run simulation
ghdl -e --std=08 tb_neural_network_4841_iris
ghdl -r --std=08 tb_neural_network_4841_iris --stop-time=50ms

# View waveform
gtkwave iris_training.ghw
```

---

## Conclusion

This guide covers the complete conversion from a 4-2-1 to 4-8-4-1 neural network architecture. The key changes are:

1. **single_neuron.vhd**: Add linear activation option
2. **neural_network_4841.vhd**: Create new top module with 13 neurons
3. **Dataset**: Generate Iris data with Python script
4. **Testbench**: Create training and evaluation testbench

After implementing these changes, your network will be capable of classifying Iris flowers with high accuracy, demonstrating that your VHDL neural network can solve real-world problems.

---

*Document Version: 1.0*
*Last Updated: December 2024*
*Author: VHDL Neural Network Project*
