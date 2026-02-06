--------------------------------------------------------------------------------
-- Module: neuron_training_top
-- Description: Top-level controller for 4-2-1 neural network training system
--              Contains FSM control logic and instantiates datapath subsystem
--
-- Hierarchy:
--   neuron_training_top (FSM control - this module)
--     └── neuron_training_subtop (datapath)
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
-- Training Flow:
--   1. Load input sample and target value
--   2. Execute forward propagation (compute output)
--   3. Execute backward propagation (compute gradients)
--   4. Apply weight updates via SGD
--   5. Repeat for all samples in epoch
--
-- Memory Map (13 parameters total):
--   Addr 0-7:   Layer 1 weights (4×2 = 8)
--   Addr 8-9:   Layer 1 biases (2)
--   Addr 10-11: Layer 2 weights (2×1 = 2)
--   Addr 12:    Layer 2 bias (1)
--
-- Author: FPGA Neural Network Project
-- Complexity: VERY HARD (⭐⭐⭐⭐)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity neuron_training_top is
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
        -- Default learning rate: 0.01 in Q2.13 = 82
        DEFAULT_LR     : integer := 82
    );
    port (
        -- Clock and Reset
        clk              : in  std_logic;
        rst              : in  std_logic;

        -- Training Control
        start_training   : in  std_logic;    -- Start training cycle
        stop_training    : in  std_logic;    -- Stop training early

        -- Training Parameters
        learning_rate    : in  signed(DATA_WIDTH-1 downto 0);
        use_default_lr   : in  std_logic;    -- Use default learning rate
        num_epochs       : in  unsigned(15 downto 0);  -- Number of epochs
        num_samples      : in  unsigned(15 downto 0);  -- Samples per epoch

        -- Sample Input Interface
        sample_data      : in  signed(DATA_WIDTH-1 downto 0);
        sample_addr      : in  unsigned(1 downto 0);   -- 0-3 for 4 inputs
        sample_valid     : in  std_logic;
        sample_ready     : out std_logic;

        -- Target Input Interface
        target_data      : in  signed(DATA_WIDTH-1 downto 0);
        target_valid     : in  std_logic;
        target_ready     : out std_logic;

        -- Weight Initialization Interface
        weight_init_data : in  signed(DATA_WIDTH-1 downto 0);
        weight_init_addr : in  unsigned(WEIGHT_ADDR_W-1 downto 0);
        weight_init_en   : in  std_logic;
        weight_init_done : out std_logic;

        -- Weight Output Interface (for reading trained weights)
        weight_out_data  : out signed(DATA_WIDTH-1 downto 0);
        weight_out_addr  : in  unsigned(WEIGHT_ADDR_W-1 downto 0);
        weight_out_en    : in  std_logic;
        weight_out_valid : out std_logic;

        -- Network Output Interface
        output_data      : out signed(DATA_WIDTH-1 downto 0);
        output_valid     : out std_logic;

        -- Status Outputs
        busy             : out std_logic;
        done             : out std_logic;
        current_epoch    : out unsigned(15 downto 0);
        current_sample   : out unsigned(15 downto 0);
        training_error   : out signed(DATA_WIDTH-1 downto 0);  -- Current error
        overflow_flag    : out std_logic
    );
end entity neuron_training_top;

architecture rtl of neuron_training_top is

    ---------------------------------------------------------------------------
    -- Component Declaration: Datapath Subsystem
    ---------------------------------------------------------------------------
    component neuron_training_subtop is
        generic (
            DATA_WIDTH     : integer := 16;
            GRAD_WIDTH     : integer := 32;
            ACCUM_WIDTH    : integer := 40;
            FRAC_BITS      : integer := 13;
            NUM_INPUTS     : integer := 4;
            NUM_HIDDEN     : integer := 2;
            NUM_OUTPUTS    : integer := 1;
            NUM_PARAMS     : integer := 13;
            WEIGHT_ADDR_W  : integer := 4;
            DEFAULT_LR     : integer := 82
        );
        port (
            clk              : in  std_logic;
            rst              : in  std_logic;
            -- Forward Datapath Control
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
            -- Backward Datapath Control
            bwd_start        : in  std_logic;
            bwd_clear        : in  std_logic;
            bwd_target_in    : in  signed(DATA_WIDTH-1 downto 0);
            bwd_target_valid : in  std_logic;
            bwd_actual_in    : in  signed(DATA_WIDTH-1 downto 0);
            bwd_busy         : out std_logic;
            bwd_done         : out std_logic;
            bwd_overflow     : out std_logic;
            -- Weight Update Datapath Control
            upd_start        : in  std_logic;
            upd_clear        : in  std_logic;
            upd_learning_rate: in  signed(DATA_WIDTH-1 downto 0);
            upd_use_default  : in  std_logic;
            upd_busy         : out std_logic;
            upd_done         : out std_logic;
            upd_overflow     : out std_logic;
            -- Input Buffer Interface
            inbuf_clear      : in  std_logic;
            inbuf_load_en    : in  std_logic;
            inbuf_load_addr  : in  unsigned(1 downto 0);
            inbuf_load_data  : in  signed(DATA_WIDTH-1 downto 0);
            inbuf_rd_en      : in  std_logic;
            inbuf_rd_addr    : in  unsigned(1 downto 0);
            inbuf_rd_data    : out signed(DATA_WIDTH-1 downto 0);
            inbuf_ready      : out std_logic;
            -- Forward Cache Interface
            cache_clear      : in  std_logic;
            -- Weight Bank Arbitration Control
            weight_owner     : in  std_logic_vector(1 downto 0);
            -- Weight Bank External Interface
            weight_init_en   : in  std_logic;
            weight_init_addr : in  unsigned(WEIGHT_ADDR_W-1 downto 0);
            weight_init_data : in  signed(DATA_WIDTH-1 downto 0);
            weight_init_done : out std_logic;
            weight_out_addr  : in  unsigned(WEIGHT_ADDR_W-1 downto 0);
            weight_out_en    : in  std_logic;
            weight_out_data  : out signed(DATA_WIDTH-1 downto 0);
            weight_out_valid : out std_logic;
            -- Gradient Bank Overflow
            grad_overflow    : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- FSM States
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,               -- Wait for start
        INIT_WEIGHTS,       -- Initialize weights (optional)
        WAIT_SAMPLE,        -- Wait for sample data
        LOAD_SAMPLE,        -- Load input sample to buffer
        WAIT_TARGET,        -- Wait for target value
        START_FORWARD,      -- Start forward pass
        RUN_FORWARD,        -- Wait for forward pass completion
        START_BACKWARD,     -- Start backward pass
        RUN_BACKWARD,       -- Wait for backward pass completion
        START_UPDATE,       -- Start weight update
        RUN_UPDATE,         -- Wait for weight update completion
        NEXT_SAMPLE,        -- Check if more samples in epoch
        CLEAR_BUFFERS,      -- Clear buffers before next sample
        NEXT_EPOCH,         -- Check if more epochs
        TRAINING_DONE       -- Training complete
    );
    signal state : state_t;

    ---------------------------------------------------------------------------
    -- Weight Owner Constants
    ---------------------------------------------------------------------------
    constant OWNER_EXTERNAL : std_logic_vector(1 downto 0) := "00";
    constant OWNER_FORWARD  : std_logic_vector(1 downto 0) := "01";
    constant OWNER_BACKWARD : std_logic_vector(1 downto 0) := "10";
    constant OWNER_UPDATE   : std_logic_vector(1 downto 0) := "11";

    ---------------------------------------------------------------------------
    -- Training Control Registers
    ---------------------------------------------------------------------------
    signal epoch_cnt       : unsigned(15 downto 0) := (others => '0');
    signal sample_cnt      : unsigned(15 downto 0) := (others => '0');
    signal num_epochs_reg  : unsigned(15 downto 0) := (others => '0');
    signal num_samples_reg : unsigned(15 downto 0) := (others => '0');
    signal lr_reg          : signed(DATA_WIDTH-1 downto 0) := to_signed(DEFAULT_LR, DATA_WIDTH);
    signal use_default_lr_reg : std_logic := '1';

    ---------------------------------------------------------------------------
    -- Target Value Storage
    ---------------------------------------------------------------------------
    signal target_reg      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal target_loaded   : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Subtop Control Signals
    ---------------------------------------------------------------------------
    -- Forward datapath
    signal fwd_start         : std_logic := '0';
    signal fwd_clear         : std_logic := '0';
    signal fwd_input_data    : signed(DATA_WIDTH-1 downto 0);
    signal fwd_input_addr    : unsigned(1 downto 0);
    signal fwd_input_valid   : std_logic;
    signal fwd_input_ready   : std_logic;
    signal fwd_output_data   : signed(DATA_WIDTH-1 downto 0);
    signal fwd_output_valid  : std_logic;
    signal fwd_busy          : std_logic;
    signal fwd_done          : std_logic;
    signal fwd_overflow      : std_logic;

    -- Backward datapath
    signal bwd_start         : std_logic := '0';
    signal bwd_clear         : std_logic := '0';
    signal bwd_target_in     : signed(DATA_WIDTH-1 downto 0);
    signal bwd_target_valid  : std_logic := '0';
    signal bwd_actual_in     : signed(DATA_WIDTH-1 downto 0);
    signal bwd_busy          : std_logic;
    signal bwd_done          : std_logic;
    signal bwd_overflow      : std_logic;

    -- Weight update datapath
    signal upd_start         : std_logic := '0';
    signal upd_clear         : std_logic := '0';
    signal upd_busy          : std_logic;
    signal upd_done          : std_logic;
    signal upd_overflow      : std_logic;

    -- Input buffer
    signal inbuf_clear       : std_logic := '0';
    signal inbuf_load_en     : std_logic;
    signal inbuf_rd_en       : std_logic;
    signal inbuf_rd_addr     : unsigned(1 downto 0);
    signal inbuf_rd_data     : signed(DATA_WIDTH-1 downto 0);
    signal inbuf_ready       : std_logic;

    -- Forward cache
    signal cache_clear       : std_logic := '0';

    -- Weight bank arbitration
    signal weight_owner      : std_logic_vector(1 downto 0) := OWNER_EXTERNAL;

    -- Weight bank outputs
    signal wrb_init_done     : std_logic;
    signal wrb_out_data      : signed(DATA_WIDTH-1 downto 0);
    signal wrb_out_valid     : std_logic;

    -- Gradient overflow
    signal grb_overflow      : std_logic;

    ---------------------------------------------------------------------------
    -- Internal Status
    ---------------------------------------------------------------------------
    signal overflow_internal : std_logic := '0';
    signal actual_output_reg : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal error_reg         : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- Saturation Constants for Error Calculation
    ---------------------------------------------------------------------------
    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);
    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH);

    ---------------------------------------------------------------------------
    -- Input buffer feeding forward datapath
    ---------------------------------------------------------------------------
    signal input_feed_en     : std_logic := '0';
    signal input_feed_addr   : unsigned(1 downto 0) := (others => '0');
    signal input_feed_done   : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Datapath Subsystem Instantiation
    ---------------------------------------------------------------------------
    datapath_inst : neuron_training_subtop
        generic map (
            DATA_WIDTH     => DATA_WIDTH,
            GRAD_WIDTH     => GRAD_WIDTH,
            ACCUM_WIDTH    => ACCUM_WIDTH,
            FRAC_BITS      => FRAC_BITS,
            NUM_INPUTS     => NUM_INPUTS,
            NUM_HIDDEN     => NUM_HIDDEN,
            NUM_OUTPUTS    => NUM_OUTPUTS,
            NUM_PARAMS     => NUM_PARAMS,
            WEIGHT_ADDR_W  => WEIGHT_ADDR_W,
            DEFAULT_LR     => DEFAULT_LR
        )
        port map (
            clk              => clk,
            rst              => rst,
            -- Forward Datapath
            fwd_start        => fwd_start,
            fwd_clear        => fwd_clear,
            fwd_input_data   => fwd_input_data,
            fwd_input_addr   => fwd_input_addr,
            fwd_input_valid  => fwd_input_valid,
            fwd_input_ready  => fwd_input_ready,
            fwd_output_data  => fwd_output_data,
            fwd_output_valid => fwd_output_valid,
            fwd_busy         => fwd_busy,
            fwd_done         => fwd_done,
            fwd_overflow     => fwd_overflow,
            -- Backward Datapath
            bwd_start        => bwd_start,
            bwd_clear        => bwd_clear,
            bwd_target_in    => bwd_target_in,
            bwd_target_valid => bwd_target_valid,
            bwd_actual_in    => bwd_actual_in,
            bwd_busy         => bwd_busy,
            bwd_done         => bwd_done,
            bwd_overflow     => bwd_overflow,
            -- Weight Update Datapath
            upd_start        => upd_start,
            upd_clear        => upd_clear,
            upd_learning_rate=> lr_reg,
            upd_use_default  => use_default_lr_reg,
            upd_busy         => upd_busy,
            upd_done         => upd_done,
            upd_overflow     => upd_overflow,
            -- Input Buffer
            inbuf_clear      => inbuf_clear,
            inbuf_load_en    => inbuf_load_en,
            inbuf_load_addr  => sample_addr,
            inbuf_load_data  => sample_data,
            inbuf_rd_en      => inbuf_rd_en,
            inbuf_rd_addr    => inbuf_rd_addr,
            inbuf_rd_data    => inbuf_rd_data,
            inbuf_ready      => inbuf_ready,
            -- Forward Cache
            cache_clear      => cache_clear,
            -- Weight Bank Arbitration
            weight_owner     => weight_owner,
            -- Weight Bank External Interface
            weight_init_en   => weight_init_en,
            weight_init_addr => weight_init_addr,
            weight_init_data => weight_init_data,
            weight_init_done => wrb_init_done,
            weight_out_addr  => weight_out_addr,
            weight_out_en    => weight_out_en,
            weight_out_data  => wrb_out_data,
            weight_out_valid => wrb_out_valid,
            -- Gradient Overflow
            grad_overflow    => grb_overflow
        );

    ---------------------------------------------------------------------------
    -- Input Buffer Connections
    ---------------------------------------------------------------------------
    inbuf_load_en   <= sample_valid when (state = LOAD_SAMPLE or state = WAIT_SAMPLE) else '0';
    inbuf_rd_en     <= input_feed_en;
    inbuf_rd_addr   <= input_feed_addr;

    -- Feed input buffer data to forward datapath
    fwd_input_data  <= inbuf_rd_data;
    fwd_input_addr  <= input_feed_addr;
    fwd_input_valid <= input_feed_en;

    ---------------------------------------------------------------------------
    -- Backward Datapath Connections
    ---------------------------------------------------------------------------
    bwd_target_in <= target_reg;
    bwd_actual_in <= actual_output_reg;

    ---------------------------------------------------------------------------
    -- Main FSM Process
    ---------------------------------------------------------------------------
    process(clk)
        variable error_diff : signed(DATA_WIDTH downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state              <= IDLE;
                epoch_cnt          <= (others => '0');
                sample_cnt         <= (others => '0');
                num_epochs_reg     <= (others => '0');
                num_samples_reg    <= (others => '0');
                lr_reg             <= to_signed(DEFAULT_LR, DATA_WIDTH);
                use_default_lr_reg <= '1';
                target_reg         <= (others => '0');
                target_loaded      <= '0';
                fwd_start          <= '0';
                fwd_clear          <= '0';
                bwd_start          <= '0';
                bwd_clear          <= '0';
                bwd_target_valid   <= '0';
                upd_start          <= '0';
                upd_clear          <= '0';
                cache_clear        <= '0';
                inbuf_clear        <= '0';
                weight_owner       <= OWNER_EXTERNAL;
                input_feed_en      <= '0';
                input_feed_addr    <= (others => '0');
                input_feed_done    <= '0';
                overflow_internal  <= '0';
                actual_output_reg  <= (others => '0');
                error_reg          <= (others => '0');
            else
                -- Default pulse signals
                fwd_start        <= '0';
                fwd_clear        <= '0';
                bwd_start        <= '0';
                bwd_clear        <= '0';
                bwd_target_valid <= '0';
                upd_start        <= '0';
                upd_clear        <= '0';
                cache_clear      <= '0';
                inbuf_clear      <= '0';
                input_feed_en    <= '0';

                case state is

                    ---------------------------------------------------------
                    -- IDLE: Wait for start signal
                    ---------------------------------------------------------
                    when IDLE =>
                        weight_owner <= OWNER_EXTERNAL;
                        if start_training = '1' then
                            -- Capture training parameters
                            num_epochs_reg     <= num_epochs;
                            num_samples_reg    <= num_samples;
                            lr_reg             <= learning_rate;
                            use_default_lr_reg <= use_default_lr;
                            epoch_cnt          <= (others => '0');
                            sample_cnt         <= (others => '0');
                            overflow_internal  <= '0';

                            -- Clear buffers for new training
                            cache_clear <= '1';
                            inbuf_clear <= '1';

                            state <= WAIT_SAMPLE;
                        end if;

                    ---------------------------------------------------------
                    -- WAIT_SAMPLE: Wait for sample data to start arriving
                    ---------------------------------------------------------
                    when WAIT_SAMPLE =>
                        weight_owner <= OWNER_EXTERNAL;
                        target_loaded <= '0';

                        if stop_training = '1' then
                            state <= TRAINING_DONE;
                        elsif sample_valid = '1' then
                            state <= LOAD_SAMPLE;
                        end if;

                    ---------------------------------------------------------
                    -- LOAD_SAMPLE: Load all input values
                    ---------------------------------------------------------
                    when LOAD_SAMPLE =>
                        if stop_training = '1' then
                            state <= TRAINING_DONE;
                        elsif inbuf_ready = '1' then
                            -- All inputs loaded
                            state <= WAIT_TARGET;
                        end if;
                        -- Note: sample_valid continues to load more values

                    ---------------------------------------------------------
                    -- WAIT_TARGET: Wait for target value
                    ---------------------------------------------------------
                    when WAIT_TARGET =>
                        if stop_training = '1' then
                            state <= TRAINING_DONE;
                        elsif target_valid = '1' then
                            target_reg    <= target_data;
                            target_loaded <= '1';
                            state         <= START_FORWARD;
                        end if;

                    ---------------------------------------------------------
                    -- START_FORWARD: Initialize forward pass
                    ---------------------------------------------------------
                    when START_FORWARD =>
                        weight_owner     <= OWNER_FORWARD;
                        fwd_start        <= '1';
                        input_feed_addr  <= (others => '0');
                        input_feed_done  <= '0';
                        state            <= RUN_FORWARD;

                    ---------------------------------------------------------
                    -- RUN_FORWARD: Execute forward pass, feed inputs
                    -- Fixed: Two-phase handshake to avoid address timing hazard
                    ---------------------------------------------------------
                    when RUN_FORWARD =>
                        weight_owner <= OWNER_FORWARD;

                        -- Feed input buffer to forward datapath with proper handshaking
                        -- Phase 0 (input_feed_en='0'): Present data at current address
                        -- Phase 1 (input_feed_en='1'): Data consumed, increment address
                        if input_feed_done = '0' then
                            if fwd_input_ready = '1' then
                                if input_feed_en = '0' then
                                    -- Phase 0: Assert valid with current stable address
                                    input_feed_en <= '1';
                                else
                                    -- Phase 1: Valid was sampled, now increment address
                                    input_feed_en <= '0';
                                    if input_feed_addr = to_unsigned(NUM_INPUTS-1, 2) then
                                        input_feed_done <= '1';
                                    else
                                        input_feed_addr <= input_feed_addr + 1;
                                    end if;
                                end if;
                            end if;
                        end if;

                        -- Wait for forward pass completion
                        if fwd_done = '1' then
                            actual_output_reg <= fwd_output_data;

                            -- Track overflow
                            if fwd_overflow = '1' then
                                overflow_internal <= '1';
                            end if;

                            -- Calculate error for monitoring with saturation
                            error_diff := resize(target_reg, DATA_WIDTH+1) -
                                          resize(fwd_output_data, DATA_WIDTH+1);
                            if error_diff > resize(SAT_MAX, DATA_WIDTH+1) then
                                error_reg <= SAT_MAX;
                            elsif error_diff < resize(SAT_MIN, DATA_WIDTH+1) then
                                error_reg <= SAT_MIN;
                            else
                                error_reg <= error_diff(DATA_WIDTH-1 downto 0);
                            end if;

                            state <= START_BACKWARD;
                        end if;

                    ---------------------------------------------------------
                    -- START_BACKWARD: Initialize backward pass
                    ---------------------------------------------------------
                    when START_BACKWARD =>
                        weight_owner     <= OWNER_BACKWARD;
                        bwd_start        <= '1';
                        bwd_target_valid <= '1';  -- Assert target valid
                        state            <= RUN_BACKWARD;

                    ---------------------------------------------------------
                    -- RUN_BACKWARD: Execute backward pass
                    -- Note: bwd_target_valid must remain high until backward_datapath
                    -- reaches LOAD_TARGET state (there's a 1-cycle delay from start)
                    ---------------------------------------------------------
                    when RUN_BACKWARD =>
                        weight_owner <= OWNER_BACKWARD;

                        -- Keep target valid while backward datapath is loading target
                        -- backward_datapath transitions: IDLE -> LOAD_TARGET (1 cycle)
                        -- It needs target_valid='1' when it reaches LOAD_TARGET
                        if bwd_busy = '1' and bwd_done = '0' then
                            bwd_target_valid <= '1';
                        end if;

                        if bwd_done = '1' then
                            if bwd_overflow = '1' then
                                overflow_internal <= '1';
                            end if;
                            state <= START_UPDATE;
                        end if;

                    ---------------------------------------------------------
                    -- START_UPDATE: Initialize weight update
                    ---------------------------------------------------------
                    when START_UPDATE =>
                        weight_owner <= OWNER_UPDATE;
                        upd_start    <= '1';
                        state        <= RUN_UPDATE;

                    ---------------------------------------------------------
                    -- RUN_UPDATE: Execute weight update
                    ---------------------------------------------------------
                    when RUN_UPDATE =>
                        weight_owner <= OWNER_UPDATE;

                        if upd_done = '1' then
                            if upd_overflow = '1' then
                                overflow_internal <= '1';
                            end if;
                            state <= NEXT_SAMPLE;
                        end if;

                    ---------------------------------------------------------
                    -- NEXT_SAMPLE: Transition to buffer clearing
                    -- Fixed: Separated counter increment from state transition
                    ---------------------------------------------------------
                    when NEXT_SAMPLE =>
                        -- Transition to clear buffers state
                        state <= CLEAR_BUFFERS;

                    ---------------------------------------------------------
                    -- CLEAR_BUFFERS: Clear buffers before next sample
                    -- Fixed: Ensures clearing completes before accepting new data
                    ---------------------------------------------------------
                    when CLEAR_BUFFERS =>
                        -- Pulse clear signals
                        inbuf_clear <= '1';
                        cache_clear <= '1';

                        -- Check if epoch is complete BEFORE incrementing
                        if sample_cnt + 1 >= num_samples_reg then
                            -- Epoch complete, go to NEXT_EPOCH
                            state <= NEXT_EPOCH;
                        else
                            -- More samples in epoch, increment counter and continue
                            sample_cnt <= sample_cnt + 1;
                            state <= WAIT_SAMPLE;
                        end if;

                    ---------------------------------------------------------
                    -- NEXT_EPOCH: Check for more epochs
                    -- Counter always increments to reflect completed epochs
                    ---------------------------------------------------------
                    when NEXT_EPOCH =>
                        sample_cnt <= (others => '0');
                        epoch_cnt <= epoch_cnt + 1;  -- Always increment (shows completed epochs)

                        if stop_training = '1' then
                            state <= TRAINING_DONE;
                        elsif epoch_cnt + 1 >= num_epochs_reg then
                            -- All epochs complete
                            state <= TRAINING_DONE;
                        else
                            -- More epochs to go
                            state <= WAIT_SAMPLE;
                        end if;

                    ---------------------------------------------------------
                    -- TRAINING_DONE: Training complete
                    ---------------------------------------------------------
                    when TRAINING_DONE =>
                        weight_owner <= OWNER_EXTERNAL;

                        -- Stay in done state until new start
                        if start_training = '1' then
                            -- Restart training
                            num_epochs_reg     <= num_epochs;
                            num_samples_reg    <= num_samples;
                            lr_reg             <= learning_rate;
                            use_default_lr_reg <= use_default_lr;
                            epoch_cnt          <= (others => '0');
                            sample_cnt         <= (others => '0');
                            overflow_internal  <= '0';
                            cache_clear        <= '1';
                            inbuf_clear        <= '1';
                            state              <= WAIT_SAMPLE;
                        end if;

                    when others =>
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------

    -- Status outputs
    busy           <= '0' when (state = IDLE or state = TRAINING_DONE) else '1';
    done           <= '1' when state = TRAINING_DONE else '0';
    current_epoch  <= epoch_cnt;
    current_sample <= sample_cnt;
    training_error <= error_reg;
    overflow_flag  <= overflow_internal or grb_overflow;

    -- Sample/target ready signals
    sample_ready   <= '1' when (state = WAIT_SAMPLE or state = LOAD_SAMPLE) else '0';
    target_ready   <= '1' when state = WAIT_TARGET else '0';

    -- Weight initialization status
    weight_init_done <= wrb_init_done;

    -- Weight output interface
    weight_out_data  <= wrb_out_data;
    weight_out_valid <= wrb_out_valid when weight_owner = OWNER_EXTERNAL else '0';

    -- Network output
    output_data  <= actual_output_reg;
    output_valid <= '1' when state = START_BACKWARD else '0';

end architecture rtl;
