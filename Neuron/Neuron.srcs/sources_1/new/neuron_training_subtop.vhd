--------------------------------------------------------------------------------
-- Module: neuron_training_subtop
-- Description: Datapath subsystem for 4-2-1 neural network training
--              Contains all computational components and memory banks
--
-- Hierarchy:
--   neuron_training_top (FSM control)
--     └── neuron_training_subtop (datapath - this module)
--           ├── forward_datapath
--           ├── backward_datapath
--           ├── weight_update_datapath
--           ├── weight_register_bank
--           ├── gradient_register_bank
--           ├── forward_cache
--           └── input_buffer
--
-- Architecture: 4 inputs → 2 hidden neurons → 1 output
--
-- Memory Map (13 parameters total):
--   Addr 0-7:   Layer 1 weights (4×2 = 8)
--   Addr 8-9:   Layer 1 biases (2)
--   Addr 10-11: Layer 2 weights (2×1 = 2)
--   Addr 12:    Layer 2 bias (1)
--
-- Author: FPGA Neural Network Project
-- Complexity: HARD (⭐⭐⭐)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity neuron_training_subtop is
    generic (
        DATA_WIDTH     : integer := 16;    -- Q2.13 format
        GRAD_WIDTH     : integer := 32;    -- Q4.26 gradient from backward
        ACCUM_WIDTH    : integer := 40;    -- Q10.26 accumulator
        FRAC_BITS      : integer := 13;    -- Fractional bits
        NUM_INPUTS     : integer := 4;     -- Input layer size
        NUM_HIDDEN     : integer := 2;     -- Hidden layer size
        NUM_OUTPUTS    : integer := 1;     -- Output layer size
        NUM_PARAMS     : integer := 13;    -- Total weights + biases
        WEIGHT_ADDR_W  : integer := 4;     -- Weight address width
        DEFAULT_LR     : integer := 82     -- Default learning rate (0.01 in Q2.13)
    );
    port (
        -- Clock and Reset
        clk              : in  std_logic;
        rst              : in  std_logic;

        ---------------------------------------------------------------------------
        -- Forward Datapath Control Interface
        ---------------------------------------------------------------------------
        fwd_start        : in  std_logic;
        fwd_clear        : in  std_logic;
        fwd_input_data   : in  signed(DATA_WIDTH-1 downto 0);
        fwd_input_addr   : in  unsigned(1 downto 0);
        fwd_input_valid  : in  std_logic;
        fwd_input_ready  : out std_logic;
        fwd_output_data  : out signed(DATA_WIDTH-1 downto 0);
        fwd_output_valid : out std_logic;
        fwd_busy         : out std_logic;
        fwd_done         : out std_logic;
        fwd_overflow     : out std_logic;

        ---------------------------------------------------------------------------
        -- Backward Datapath Control Interface
        ---------------------------------------------------------------------------
        bwd_start        : in  std_logic;
        bwd_clear        : in  std_logic;
        bwd_target_in    : in  signed(DATA_WIDTH-1 downto 0);
        bwd_target_valid : in  std_logic;
        bwd_actual_in    : in  signed(DATA_WIDTH-1 downto 0);
        bwd_busy         : out std_logic;
        bwd_done         : out std_logic;
        bwd_overflow     : out std_logic;

        ---------------------------------------------------------------------------
        -- Weight Update Datapath Control Interface
        ---------------------------------------------------------------------------
        upd_start        : in  std_logic;
        upd_clear        : in  std_logic;
        upd_learning_rate: in  signed(DATA_WIDTH-1 downto 0);
        upd_use_default  : in  std_logic;
        upd_busy         : out std_logic;
        upd_done         : out std_logic;
        upd_overflow     : out std_logic;

        ---------------------------------------------------------------------------
        -- Input Buffer Interface
        ---------------------------------------------------------------------------
        inbuf_clear      : in  std_logic;
        inbuf_load_en    : in  std_logic;
        inbuf_load_addr  : in  unsigned(1 downto 0);
        inbuf_load_data  : in  signed(DATA_WIDTH-1 downto 0);
        inbuf_rd_en      : in  std_logic;
        inbuf_rd_addr    : in  unsigned(1 downto 0);
        inbuf_rd_data    : out signed(DATA_WIDTH-1 downto 0);
        inbuf_ready      : out std_logic;

        ---------------------------------------------------------------------------
        -- Forward Cache Interface
        ---------------------------------------------------------------------------
        cache_clear      : in  std_logic;

        ---------------------------------------------------------------------------
        -- Weight Bank Arbitration Control
        ---------------------------------------------------------------------------
        weight_owner     : in  std_logic_vector(1 downto 0);  -- 00=EXT, 01=FWD, 10=BWD, 11=UPD

        ---------------------------------------------------------------------------
        -- Weight Bank External Interface
        ---------------------------------------------------------------------------
        weight_init_en   : in  std_logic;
        weight_init_addr : in  unsigned(WEIGHT_ADDR_W-1 downto 0);
        weight_init_data : in  signed(DATA_WIDTH-1 downto 0);
        weight_init_done : out std_logic;
        weight_out_addr  : in  unsigned(WEIGHT_ADDR_W-1 downto 0);
        weight_out_en    : in  std_logic;
        weight_out_data  : out signed(DATA_WIDTH-1 downto 0);
        weight_out_valid : out std_logic;

        ---------------------------------------------------------------------------
        -- Gradient Bank Overflow
        ---------------------------------------------------------------------------
        grad_overflow    : out std_logic
    );
end entity neuron_training_subtop;

architecture rtl of neuron_training_subtop is

    ---------------------------------------------------------------------------
    -- Component Declarations
    ---------------------------------------------------------------------------

    -- Forward Datapath
    component forward_datapath is
        generic (
            DATA_WIDTH   : integer := 16;
            ACCUM_WIDTH  : integer := 40;
            FRAC_BITS    : integer := 13;
            NUM_INPUTS   : integer := 4;
            NUM_HIDDEN   : integer := 2;
            NUM_OUTPUTS  : integer := 1
        );
        port (
            clk              : in  std_logic;
            rst              : in  std_logic;
            start            : in  std_logic;
            clear            : in  std_logic;
            input_data       : in  signed(DATA_WIDTH-1 downto 0);
            input_addr       : in  unsigned(1 downto 0);
            input_valid      : in  std_logic;
            input_ready      : out std_logic;
            weight_rd_data   : in  signed(DATA_WIDTH-1 downto 0);
            weight_rd_addr   : out unsigned(3 downto 0);
            weight_rd_en     : out std_logic;
            cache_z_wr_en    : out std_logic;
            cache_z_wr_addr  : out unsigned(1 downto 0);
            cache_z_wr_data  : out signed(DATA_WIDTH-1 downto 0);
            cache_a_wr_en    : out std_logic;
            cache_a_wr_addr  : out unsigned(2 downto 0);
            cache_a_wr_data  : out signed(DATA_WIDTH-1 downto 0);
            output_data      : out signed(DATA_WIDTH-1 downto 0);
            output_valid     : out std_logic;
            busy             : out std_logic;
            done             : out std_logic;
            layer_complete   : out std_logic;
            current_layer    : out unsigned(1 downto 0);
            overflow         : out std_logic
        );
    end component;

    -- Backward Datapath
    component backward_datapath is
        generic (
            DATA_WIDTH   : integer := 16;
            GRAD_WIDTH   : integer := 32;
            ACCUM_WIDTH  : integer := 40;
            FRAC_BITS    : integer := 13;
            NUM_INPUTS   : integer := 4;
            NUM_HIDDEN   : integer := 2;
            NUM_OUTPUTS  : integer := 1
        );
        port (
            clk              : in  std_logic;
            rst              : in  std_logic;
            start            : in  std_logic;
            clear            : in  std_logic;
            target_in        : in  signed(DATA_WIDTH-1 downto 0);
            target_valid     : in  std_logic;
            actual_in        : in  signed(DATA_WIDTH-1 downto 0);
            weight_rd_data   : in  signed(DATA_WIDTH-1 downto 0);
            weight_rd_addr   : out unsigned(3 downto 0);
            weight_rd_en     : out std_logic;
            cache_z_rd_data  : in  signed(DATA_WIDTH-1 downto 0);
            cache_z_rd_addr  : out unsigned(1 downto 0);
            cache_z_rd_en    : out std_logic;
            cache_a_rd_data  : in  signed(DATA_WIDTH-1 downto 0);
            cache_a_rd_addr  : out unsigned(2 downto 0);
            cache_a_rd_en    : out std_logic;
            grad_out         : out signed(GRAD_WIDTH-1 downto 0);
            grad_addr        : out unsigned(3 downto 0);
            grad_valid       : out std_logic;
            grad_ready       : in  std_logic;
            busy             : out std_logic;
            done             : out std_logic;
            current_layer    : out unsigned(1 downto 0);
            overflow         : out std_logic
        );
    end component;

    -- Weight Update Datapath
    component weight_update_datapath is
        generic (
            DATA_WIDTH     : integer := 16;
            GRAD_WIDTH     : integer := 40;
            FRAC_BITS      : integer := 13;
            GRAD_FRAC_BITS : integer := 26;
            NUM_PARAMS     : integer := 13;
            ADDR_WIDTH     : integer := 4;
            DEFAULT_LR     : integer := 82
        );
        port (
            clk              : in  std_logic;
            rst              : in  std_logic;
            start            : in  std_logic;
            clear            : in  std_logic;
            learning_rate    : in  signed(DATA_WIDTH-1 downto 0);
            use_default_lr   : in  std_logic;
            weight_rd_data   : in  signed(DATA_WIDTH-1 downto 0);
            weight_rd_addr   : out unsigned(ADDR_WIDTH-1 downto 0);
            weight_rd_en     : out std_logic;
            weight_wr_data   : out signed(DATA_WIDTH-1 downto 0);
            weight_wr_addr   : out unsigned(ADDR_WIDTH-1 downto 0);
            weight_wr_en     : out std_logic;
            grad_rd_data     : in  signed(GRAD_WIDTH-1 downto 0);
            grad_rd_addr     : out unsigned(ADDR_WIDTH-1 downto 0);
            grad_rd_en       : out std_logic;
            grad_clear       : out std_logic;
            busy             : out std_logic;
            done             : out std_logic;
            param_count      : out unsigned(ADDR_WIDTH-1 downto 0);
            overflow         : out std_logic
        );
    end component;

    -- Weight Register Bank
    component weight_register_bank is
        generic (
            DATA_WIDTH   : integer := 16;
            NUM_ENTRIES  : integer := 13;
            ADDR_WIDTH   : integer := 4
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            rd_en        : in  std_logic;
            rd_addr      : in  unsigned(ADDR_WIDTH-1 downto 0);
            rd_data      : out signed(DATA_WIDTH-1 downto 0);
            rd_valid     : out std_logic;
            wr_en        : in  std_logic;
            wr_addr      : in  unsigned(ADDR_WIDTH-1 downto 0);
            wr_data      : in  signed(DATA_WIDTH-1 downto 0);
            init_en      : in  std_logic;
            init_addr    : in  unsigned(ADDR_WIDTH-1 downto 0);
            init_data    : in  signed(DATA_WIDTH-1 downto 0);
            init_done    : out std_logic
        );
    end component;

    -- Gradient Register Bank
    component gradient_register_bank is
        generic (
            INPUT_WIDTH  : integer := 32;
            ACCUM_WIDTH  : integer := 40;
            NUM_ENTRIES  : integer := 13;
            ADDR_WIDTH   : integer := 4
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            clear        : in  std_logic;
            accum_en     : in  std_logic;
            accum_addr   : in  unsigned(ADDR_WIDTH-1 downto 0);
            accum_data   : in  signed(INPUT_WIDTH-1 downto 0);
            rd_en        : in  std_logic;
            rd_addr      : in  unsigned(ADDR_WIDTH-1 downto 0);
            rd_data      : out signed(ACCUM_WIDTH-1 downto 0);
            rd_valid     : out std_logic;
            overflow     : out std_logic
        );
    end component;

    -- Forward Cache
    component forward_cache is
        generic (
            DATA_WIDTH       : integer := 16;
            NUM_Z_VALUES     : integer := 3;
            NUM_A_VALUES     : integer := 7;
            Z_ADDR_WIDTH     : integer := 2;
            A_ADDR_WIDTH     : integer := 3
        );
        port (
            clk              : in  std_logic;
            rst              : in  std_logic;
            clear            : in  std_logic;
            z_wr_en          : in  std_logic;
            z_wr_addr        : in  unsigned(Z_ADDR_WIDTH-1 downto 0);
            z_wr_data        : in  signed(DATA_WIDTH-1 downto 0);
            z_rd_en          : in  std_logic;
            z_rd_addr        : in  unsigned(Z_ADDR_WIDTH-1 downto 0);
            z_rd_data        : out signed(DATA_WIDTH-1 downto 0);
            z_rd_valid       : out std_logic;
            a_wr_en          : in  std_logic;
            a_wr_addr        : in  unsigned(A_ADDR_WIDTH-1 downto 0);
            a_wr_data        : in  signed(DATA_WIDTH-1 downto 0);
            a_rd_en          : in  std_logic;
            a_rd_addr        : in  unsigned(A_ADDR_WIDTH-1 downto 0);
            a_rd_data        : out signed(DATA_WIDTH-1 downto 0);
            a_rd_valid       : out std_logic
        );
    end component;

    -- Input Buffer
    component input_buffer is
        generic (
            DATA_WIDTH   : integer := 16;
            NUM_INPUTS   : integer := 4;
            ADDR_WIDTH   : integer := 2
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            clear        : in  std_logic;
            load_en      : in  std_logic;
            load_addr    : in  unsigned(ADDR_WIDTH-1 downto 0);
            load_data    : in  signed(DATA_WIDTH-1 downto 0);
            rd_en        : in  std_logic;
            rd_addr      : in  unsigned(ADDR_WIDTH-1 downto 0);
            rd_data      : out signed(DATA_WIDTH-1 downto 0);
            ready        : out std_logic;
            count        : out unsigned(ADDR_WIDTH downto 0)
        );
    end component;

    ---------------------------------------------------------------------------
    -- Weight Owner Constants
    ---------------------------------------------------------------------------
    constant OWNER_EXTERNAL : std_logic_vector(1 downto 0) := "00";
    constant OWNER_FORWARD  : std_logic_vector(1 downto 0) := "01";
    constant OWNER_BACKWARD : std_logic_vector(1 downto 0) := "10";
    constant OWNER_UPDATE   : std_logic_vector(1 downto 0) := "11";

    ---------------------------------------------------------------------------
    -- Forward Datapath Internal Signals
    ---------------------------------------------------------------------------
    signal fwd_weight_rd_data : signed(DATA_WIDTH-1 downto 0);
    signal fwd_weight_rd_addr : unsigned(3 downto 0);
    signal fwd_weight_rd_en   : std_logic;
    signal fwd_cache_z_wr_en  : std_logic;
    signal fwd_cache_z_wr_addr: unsigned(1 downto 0);
    signal fwd_cache_z_wr_data: signed(DATA_WIDTH-1 downto 0);
    signal fwd_cache_a_wr_en  : std_logic;
    signal fwd_cache_a_wr_addr: unsigned(2 downto 0);
    signal fwd_cache_a_wr_data: signed(DATA_WIDTH-1 downto 0);

    ---------------------------------------------------------------------------
    -- Backward Datapath Internal Signals
    ---------------------------------------------------------------------------
    signal bwd_weight_rd_data : signed(DATA_WIDTH-1 downto 0);
    signal bwd_weight_rd_addr : unsigned(3 downto 0);
    signal bwd_weight_rd_en   : std_logic;
    signal bwd_cache_z_rd_data: signed(DATA_WIDTH-1 downto 0);
    signal bwd_cache_z_rd_addr: unsigned(1 downto 0);
    signal bwd_cache_z_rd_en  : std_logic;
    signal bwd_cache_a_rd_data: signed(DATA_WIDTH-1 downto 0);
    signal bwd_cache_a_rd_addr: unsigned(2 downto 0);
    signal bwd_cache_a_rd_en  : std_logic;
    signal bwd_grad_out       : signed(GRAD_WIDTH-1 downto 0);
    signal bwd_grad_addr      : unsigned(3 downto 0);
    signal bwd_grad_valid     : std_logic;
    signal bwd_grad_ready     : std_logic := '1';

    ---------------------------------------------------------------------------
    -- Weight Update Datapath Internal Signals
    ---------------------------------------------------------------------------
    signal upd_weight_rd_data : signed(DATA_WIDTH-1 downto 0);
    signal upd_weight_rd_addr : unsigned(WEIGHT_ADDR_W-1 downto 0);
    signal upd_weight_rd_en   : std_logic;
    signal upd_weight_wr_data : signed(DATA_WIDTH-1 downto 0);
    signal upd_weight_wr_addr : unsigned(WEIGHT_ADDR_W-1 downto 0);
    signal upd_weight_wr_en   : std_logic;
    signal upd_grad_rd_data   : signed(ACCUM_WIDTH-1 downto 0);
    signal upd_grad_rd_addr   : unsigned(WEIGHT_ADDR_W-1 downto 0);
    signal upd_grad_rd_en     : std_logic;
    signal upd_grad_clear     : std_logic;

    ---------------------------------------------------------------------------
    -- Weight Register Bank Signals
    ---------------------------------------------------------------------------
    signal wrb_rd_en          : std_logic;
    signal wrb_rd_addr        : unsigned(WEIGHT_ADDR_W-1 downto 0);
    signal wrb_rd_data        : signed(DATA_WIDTH-1 downto 0);
    signal wrb_rd_valid       : std_logic;
    signal wrb_wr_en          : std_logic;
    signal wrb_wr_addr        : unsigned(WEIGHT_ADDR_W-1 downto 0);
    signal wrb_wr_data        : signed(DATA_WIDTH-1 downto 0);
    signal wrb_init_done      : std_logic;

    ---------------------------------------------------------------------------
    -- Gradient Register Bank Signals
    ---------------------------------------------------------------------------
    signal grb_clear          : std_logic;
    signal grb_accum_en       : std_logic;
    signal grb_accum_addr     : unsigned(WEIGHT_ADDR_W-1 downto 0);
    signal grb_accum_data     : signed(GRAD_WIDTH-1 downto 0);
    signal grb_rd_en          : std_logic;
    signal grb_rd_addr        : unsigned(WEIGHT_ADDR_W-1 downto 0);
    signal grb_rd_data        : signed(ACCUM_WIDTH-1 downto 0);
    signal grb_rd_valid       : std_logic;
    signal grb_overflow       : std_logic;

    ---------------------------------------------------------------------------
    -- Forward Cache Signals
    ---------------------------------------------------------------------------
    signal cache_z_wr_en      : std_logic;
    signal cache_z_wr_addr    : unsigned(1 downto 0);
    signal cache_z_wr_data    : signed(DATA_WIDTH-1 downto 0);
    signal cache_z_rd_en      : std_logic;
    signal cache_z_rd_addr    : unsigned(1 downto 0);
    signal cache_z_rd_data    : signed(DATA_WIDTH-1 downto 0);
    signal cache_z_rd_valid   : std_logic;
    signal cache_a_wr_en      : std_logic;
    signal cache_a_wr_addr    : unsigned(2 downto 0);
    signal cache_a_wr_data    : signed(DATA_WIDTH-1 downto 0);
    signal cache_a_rd_en      : std_logic;
    signal cache_a_rd_addr    : unsigned(2 downto 0);
    signal cache_a_rd_data    : signed(DATA_WIDTH-1 downto 0);
    signal cache_a_rd_valid   : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Component Instantiations
    ---------------------------------------------------------------------------

    -- Forward Datapath Instance
    fwd_datapath_inst : forward_datapath
        generic map (
            DATA_WIDTH   => DATA_WIDTH,
            ACCUM_WIDTH  => ACCUM_WIDTH,
            FRAC_BITS    => FRAC_BITS,
            NUM_INPUTS   => NUM_INPUTS,
            NUM_HIDDEN   => NUM_HIDDEN,
            NUM_OUTPUTS  => NUM_OUTPUTS
        )
        port map (
            clk              => clk,
            rst              => rst,
            start            => fwd_start,
            clear            => fwd_clear,
            input_data       => fwd_input_data,
            input_addr       => fwd_input_addr,
            input_valid      => fwd_input_valid,
            input_ready      => fwd_input_ready,
            weight_rd_data   => fwd_weight_rd_data,
            weight_rd_addr   => fwd_weight_rd_addr,
            weight_rd_en     => fwd_weight_rd_en,
            cache_z_wr_en    => fwd_cache_z_wr_en,
            cache_z_wr_addr  => fwd_cache_z_wr_addr,
            cache_z_wr_data  => fwd_cache_z_wr_data,
            cache_a_wr_en    => fwd_cache_a_wr_en,
            cache_a_wr_addr  => fwd_cache_a_wr_addr,
            cache_a_wr_data  => fwd_cache_a_wr_data,
            output_data      => fwd_output_data,
            output_valid     => fwd_output_valid,
            busy             => fwd_busy,
            done             => fwd_done,
            layer_complete   => open,
            current_layer    => open,
            overflow         => fwd_overflow
        );

    -- Backward Datapath Instance
    bwd_datapath_inst : backward_datapath
        generic map (
            DATA_WIDTH   => DATA_WIDTH,
            GRAD_WIDTH   => GRAD_WIDTH,
            ACCUM_WIDTH  => ACCUM_WIDTH,
            FRAC_BITS    => FRAC_BITS,
            NUM_INPUTS   => NUM_INPUTS,
            NUM_HIDDEN   => NUM_HIDDEN,
            NUM_OUTPUTS  => NUM_OUTPUTS
        )
        port map (
            clk              => clk,
            rst              => rst,
            start            => bwd_start,
            clear            => bwd_clear,
            target_in        => bwd_target_in,
            target_valid     => bwd_target_valid,
            actual_in        => bwd_actual_in,
            weight_rd_data   => bwd_weight_rd_data,
            weight_rd_addr   => bwd_weight_rd_addr,
            weight_rd_en     => bwd_weight_rd_en,
            cache_z_rd_data  => bwd_cache_z_rd_data,
            cache_z_rd_addr  => bwd_cache_z_rd_addr,
            cache_z_rd_en    => bwd_cache_z_rd_en,
            cache_a_rd_data  => bwd_cache_a_rd_data,
            cache_a_rd_addr  => bwd_cache_a_rd_addr,
            cache_a_rd_en    => bwd_cache_a_rd_en,
            grad_out         => bwd_grad_out,
            grad_addr        => bwd_grad_addr,
            grad_valid       => bwd_grad_valid,
            grad_ready       => bwd_grad_ready,
            busy             => bwd_busy,
            done             => bwd_done,
            current_layer    => open,
            overflow         => bwd_overflow
        );

    -- Weight Update Datapath Instance
    upd_datapath_inst : weight_update_datapath
        generic map (
            DATA_WIDTH     => DATA_WIDTH,
            GRAD_WIDTH     => ACCUM_WIDTH,  -- Uses accumulated gradient width
            FRAC_BITS      => FRAC_BITS,
            GRAD_FRAC_BITS => 26,           -- Q10.26 accumulator format
            NUM_PARAMS     => NUM_PARAMS,
            ADDR_WIDTH     => WEIGHT_ADDR_W,
            DEFAULT_LR     => DEFAULT_LR
        )
        port map (
            clk              => clk,
            rst              => rst,
            start            => upd_start,
            clear            => upd_clear,
            learning_rate    => upd_learning_rate,
            use_default_lr   => upd_use_default,
            weight_rd_data   => upd_weight_rd_data,
            weight_rd_addr   => upd_weight_rd_addr,
            weight_rd_en     => upd_weight_rd_en,
            weight_wr_data   => upd_weight_wr_data,
            weight_wr_addr   => upd_weight_wr_addr,
            weight_wr_en     => upd_weight_wr_en,
            grad_rd_data     => upd_grad_rd_data,
            grad_rd_addr     => upd_grad_rd_addr,
            grad_rd_en       => upd_grad_rd_en,
            grad_clear       => upd_grad_clear,
            busy             => upd_busy,
            done             => upd_done,
            param_count      => open,
            overflow         => upd_overflow
        );

    -- Weight Register Bank Instance
    wrb_inst : weight_register_bank
        generic map (
            DATA_WIDTH   => DATA_WIDTH,
            NUM_ENTRIES  => NUM_PARAMS,
            ADDR_WIDTH   => WEIGHT_ADDR_W
        )
        port map (
            clk          => clk,
            rst          => rst,
            rd_en        => wrb_rd_en,
            rd_addr      => wrb_rd_addr,
            rd_data      => wrb_rd_data,
            rd_valid     => wrb_rd_valid,
            wr_en        => wrb_wr_en,
            wr_addr      => wrb_wr_addr,
            wr_data      => wrb_wr_data,
            init_en      => weight_init_en,
            init_addr    => weight_init_addr,
            init_data    => weight_init_data,
            init_done    => wrb_init_done
        );

    -- Gradient Register Bank Instance
    grb_inst : gradient_register_bank
        generic map (
            INPUT_WIDTH  => GRAD_WIDTH,
            ACCUM_WIDTH  => ACCUM_WIDTH,
            NUM_ENTRIES  => NUM_PARAMS,
            ADDR_WIDTH   => WEIGHT_ADDR_W
        )
        port map (
            clk          => clk,
            rst          => rst,
            clear        => grb_clear,
            accum_en     => grb_accum_en,
            accum_addr   => grb_accum_addr,
            accum_data   => grb_accum_data,
            rd_en        => grb_rd_en,
            rd_addr      => grb_rd_addr,
            rd_data      => grb_rd_data,
            rd_valid     => grb_rd_valid,
            overflow     => grb_overflow
        );

    -- Forward Cache Instance
    cache_inst : forward_cache
        generic map (
            DATA_WIDTH       => DATA_WIDTH,
            NUM_Z_VALUES     => 3,
            NUM_A_VALUES     => 7,
            Z_ADDR_WIDTH     => 2,
            A_ADDR_WIDTH     => 3
        )
        port map (
            clk              => clk,
            rst              => rst,
            clear            => cache_clear,
            z_wr_en          => cache_z_wr_en,
            z_wr_addr        => cache_z_wr_addr,
            z_wr_data        => cache_z_wr_data,
            z_rd_en          => cache_z_rd_en,
            z_rd_addr        => cache_z_rd_addr,
            z_rd_data        => cache_z_rd_data,
            z_rd_valid       => cache_z_rd_valid,
            a_wr_en          => cache_a_wr_en,
            a_wr_addr        => cache_a_wr_addr,
            a_wr_data        => cache_a_wr_data,
            a_rd_en          => cache_a_rd_en,
            a_rd_addr        => cache_a_rd_addr,
            a_rd_data        => cache_a_rd_data,
            a_rd_valid       => cache_a_rd_valid
        );

    -- Input Buffer Instance
    inbuf_inst : input_buffer
        generic map (
            DATA_WIDTH   => DATA_WIDTH,
            NUM_INPUTS   => NUM_INPUTS,
            ADDR_WIDTH   => 2
        )
        port map (
            clk          => clk,
            rst          => rst,
            clear        => inbuf_clear,
            load_en      => inbuf_load_en,
            load_addr    => inbuf_load_addr,
            load_data    => inbuf_load_data,
            rd_en        => inbuf_rd_en,
            rd_addr      => inbuf_rd_addr,
            rd_data      => inbuf_rd_data,
            ready        => inbuf_ready,
            count        => open
        );

    ---------------------------------------------------------------------------
    -- Weight Bank Arbitration Multiplexer
    -- Selects which datapath has access to weight bank read port
    ---------------------------------------------------------------------------
    process(weight_owner, fwd_weight_rd_addr, fwd_weight_rd_en,
            bwd_weight_rd_addr, bwd_weight_rd_en,
            upd_weight_rd_addr, upd_weight_rd_en,
            weight_out_addr, weight_out_en)
    begin
        case weight_owner is
            when OWNER_EXTERNAL =>
                wrb_rd_addr <= weight_out_addr;
                wrb_rd_en   <= weight_out_en;
            when OWNER_FORWARD =>
                wrb_rd_addr <= fwd_weight_rd_addr;
                wrb_rd_en   <= fwd_weight_rd_en;
            when OWNER_BACKWARD =>
                wrb_rd_addr <= bwd_weight_rd_addr;
                wrb_rd_en   <= bwd_weight_rd_en;
            when OWNER_UPDATE =>
                wrb_rd_addr <= upd_weight_rd_addr;
                wrb_rd_en   <= upd_weight_rd_en;
            when others =>
                wrb_rd_addr <= (others => '0');
                wrb_rd_en   <= '0';
        end case;
    end process;

    -- Route weight data back to appropriate datapath
    fwd_weight_rd_data <= wrb_rd_data;
    bwd_weight_rd_data <= wrb_rd_data;
    upd_weight_rd_data <= wrb_rd_data;

    -- Weight bank write port (only update datapath writes)
    wrb_wr_en   <= upd_weight_wr_en;
    wrb_wr_addr <= upd_weight_wr_addr;
    wrb_wr_data <= upd_weight_wr_data;

    ---------------------------------------------------------------------------
    -- Forward Cache Connections
    -- Forward datapath writes, backward datapath reads
    ---------------------------------------------------------------------------
    cache_z_wr_en   <= fwd_cache_z_wr_en;
    cache_z_wr_addr <= fwd_cache_z_wr_addr;
    cache_z_wr_data <= fwd_cache_z_wr_data;
    cache_z_rd_en   <= bwd_cache_z_rd_en;
    cache_z_rd_addr <= bwd_cache_z_rd_addr;
    bwd_cache_z_rd_data <= cache_z_rd_data;

    cache_a_wr_en   <= fwd_cache_a_wr_en;
    cache_a_wr_addr <= fwd_cache_a_wr_addr;
    cache_a_wr_data <= fwd_cache_a_wr_data;
    cache_a_rd_en   <= bwd_cache_a_rd_en;
    cache_a_rd_addr <= bwd_cache_a_rd_addr;
    bwd_cache_a_rd_data <= cache_a_rd_data;

    ---------------------------------------------------------------------------
    -- Gradient Bank Connections
    -- Backward datapath accumulates, update datapath reads
    ---------------------------------------------------------------------------
    grb_accum_en   <= bwd_grad_valid;
    grb_accum_addr <= bwd_grad_addr;
    grb_accum_data <= bwd_grad_out;
    grb_rd_en      <= upd_grad_rd_en;
    grb_rd_addr    <= upd_grad_rd_addr;
    upd_grad_rd_data <= grb_rd_data;
    grb_clear      <= upd_grad_clear;

    -- Backward gradient ready (always accept gradients)
    bwd_grad_ready <= '1';

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    weight_init_done <= wrb_init_done;
    weight_out_data  <= wrb_rd_data;
    weight_out_valid <= wrb_rd_valid when weight_owner = OWNER_EXTERNAL else '0';
    grad_overflow    <= grb_overflow;

end architecture rtl;
