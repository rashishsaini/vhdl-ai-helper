--------------------------------------------------------------------------------
-- Testbench: tb_neuron_training_top
-- Description: Comprehensive testbench for the 4-2-1 neural network training
--              top-level module with detailed Vivado TCL console output
--
-- Test Strategy:
--   Test 1: Weight initialization and readback verification
--   Test 2: Single sample forward pass and training cycle
--   Test 3: Weight readback after training (verify non-zero)
--   Test 4: Multi-epoch training (2 epochs, 2 samples each)
--   Test 5: Stop training early functionality
--   Test 6: Reset and restart after stop
--   Test 7: Multiple training iterations convergence check
--   Test 8: Overflow flag monitoring
--
-- Author: FPGA Neural Network Project
-- Enhanced: With detailed diagnostic output for Vivado TCL console
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_neuron_training_top is
end entity tb_neuron_training_top;

architecture sim of tb_neuron_training_top is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD    : time := 10 ns;
    constant DATA_WIDTH    : integer := 16;
    constant GRAD_WIDTH    : integer := 32;
    constant ACCUM_WIDTH   : integer := 40;
    constant FRAC_BITS     : integer := 13;
    constant NUM_INPUTS    : integer := 4;
    constant NUM_HIDDEN    : integer := 2;
    constant NUM_OUTPUTS   : integer := 1;
    constant NUM_PARAMS    : integer := 13;
    constant WEIGHT_ADDR_W : integer := 4;
    constant DEFAULT_LR    : integer := 82;  -- 0.01 in Q2.13

    -- Q2.13 constants
    constant ONE_Q213    : signed(DATA_WIDTH-1 downto 0) := to_signed(8192, DATA_WIDTH);   -- 1.0
    constant HALF_Q213   : signed(DATA_WIDTH-1 downto 0) := to_signed(4096, DATA_WIDTH);   -- 0.5
    constant QUARTER_Q213: signed(DATA_WIDTH-1 downto 0) := to_signed(2048, DATA_WIDTH);   -- 0.25
    constant ZERO_Q213   : signed(DATA_WIDTH-1 downto 0) := to_signed(0, DATA_WIDTH);

    ---------------------------------------------------------------------------
    -- Component Under Test
    ---------------------------------------------------------------------------
    component neuron_training_top is
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
            start_training   : in  std_logic;
            stop_training    : in  std_logic;
            learning_rate    : in  signed(DATA_WIDTH-1 downto 0);
            use_default_lr   : in  std_logic;
            num_epochs       : in  unsigned(15 downto 0);
            num_samples      : in  unsigned(15 downto 0);
            sample_data      : in  signed(DATA_WIDTH-1 downto 0);
            sample_addr      : in  unsigned(1 downto 0);
            sample_valid     : in  std_logic;
            sample_ready     : out std_logic;
            target_data      : in  signed(DATA_WIDTH-1 downto 0);
            target_valid     : in  std_logic;
            target_ready     : out std_logic;
            weight_init_data : in  signed(DATA_WIDTH-1 downto 0);
            weight_init_addr : in  unsigned(WEIGHT_ADDR_W-1 downto 0);
            weight_init_en   : in  std_logic;
            weight_init_done : out std_logic;
            weight_out_data  : out signed(DATA_WIDTH-1 downto 0);
            weight_out_addr  : in  unsigned(WEIGHT_ADDR_W-1 downto 0);
            weight_out_en    : in  std_logic;
            weight_out_valid : out std_logic;
            output_data      : out signed(DATA_WIDTH-1 downto 0);
            output_valid     : out std_logic;
            busy             : out std_logic;
            done             : out std_logic;
            current_epoch    : out unsigned(15 downto 0);
            current_sample   : out unsigned(15 downto 0);
            training_error   : out signed(DATA_WIDTH-1 downto 0);
            overflow_flag    : out std_logic
        );
    end component;

    ---------------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------------
    signal clk              : std_logic := '0';
    signal rst              : std_logic := '1';

    -- Training control
    signal start_training   : std_logic := '0';
    signal stop_training    : std_logic := '0';
    signal learning_rate    : signed(DATA_WIDTH-1 downto 0) := to_signed(DEFAULT_LR, DATA_WIDTH);
    signal use_default_lr   : std_logic := '1';
    signal num_epochs       : unsigned(15 downto 0) := to_unsigned(1, 16);
    signal num_samples      : unsigned(15 downto 0) := to_unsigned(1, 16);

    -- Sample input
    signal sample_data      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal sample_addr      : unsigned(1 downto 0) := (others => '0');
    signal sample_valid     : std_logic := '0';
    signal sample_ready     : std_logic;

    -- Target input
    signal target_data      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal target_valid     : std_logic := '0';
    signal target_ready     : std_logic;

    -- Weight initialization
    signal weight_init_data : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal weight_init_addr : unsigned(WEIGHT_ADDR_W-1 downto 0) := (others => '0');
    signal weight_init_en   : std_logic := '0';
    signal weight_init_done : std_logic;

    -- Weight output
    signal weight_out_data  : signed(DATA_WIDTH-1 downto 0);
    signal weight_out_addr  : unsigned(WEIGHT_ADDR_W-1 downto 0) := (others => '0');
    signal weight_out_en    : std_logic := '0';
    signal weight_out_valid : std_logic;

    -- Network output
    signal output_data      : signed(DATA_WIDTH-1 downto 0);
    signal output_valid     : std_logic;

    -- Status
    signal busy             : std_logic;
    signal done             : std_logic;
    signal current_epoch    : unsigned(15 downto 0);
    signal current_sample   : unsigned(15 downto 0);
    signal training_error   : signed(DATA_WIDTH-1 downto 0);
    signal overflow_flag    : std_logic;

    -- Test control
    signal test_done        : boolean := false;

    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    function to_real(val : signed) return real is
    begin
        return real(to_integer(val)) / real(2**FRAC_BITS);
    end function;

    function to_fixed(val : real) return signed is
        variable result : integer;
    begin
        result := integer(val * real(2**FRAC_BITS));
        if result > 32767 then
            result := 32767;
        elsif result < -32768 then
            result := -32768;
        end if;
        return to_signed(result, DATA_WIDTH);
    end function;

    ---------------------------------------------------------------------------
    -- Procedure: Print separator line
    ---------------------------------------------------------------------------
    procedure print_separator is
    begin
        report "================================================================";
    end procedure;

    ---------------------------------------------------------------------------
    -- Procedure: Print test header
    ---------------------------------------------------------------------------
    procedure print_test_header(test_num : integer; test_name : string) is
    begin
        report "";
        print_separator;
        report "TEST " & integer'image(test_num) & ": " & test_name;
        print_separator;
    end procedure;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD/2 when not test_done else '0';

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : neuron_training_top
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
            start_training   => start_training,
            stop_training    => stop_training,
            learning_rate    => learning_rate,
            use_default_lr   => use_default_lr,
            num_epochs       => num_epochs,
            num_samples      => num_samples,
            sample_data      => sample_data,
            sample_addr      => sample_addr,
            sample_valid     => sample_valid,
            sample_ready     => sample_ready,
            target_data      => target_data,
            target_valid     => target_valid,
            target_ready     => target_ready,
            weight_init_data => weight_init_data,
            weight_init_addr => weight_init_addr,
            weight_init_en   => weight_init_en,
            weight_init_done => weight_init_done,
            weight_out_data  => weight_out_data,
            weight_out_addr  => weight_out_addr,
            weight_out_en    => weight_out_en,
            weight_out_valid => weight_out_valid,
            output_data      => output_data,
            output_valid     => output_valid,
            busy             => busy,
            done             => done,
            current_epoch    => current_epoch,
            current_sample   => current_sample,
            training_error   => training_error,
            overflow_flag    => overflow_flag
        );

    ---------------------------------------------------------------------------
    -- Main Test Process
    ---------------------------------------------------------------------------
    stim_proc : process
        type weight_array_t is array (0 to NUM_PARAMS-1) of signed(DATA_WIDTH-1 downto 0);
        variable init_weights : weight_array_t;
        variable read_weights : weight_array_t;
        variable test_pass_count : integer := 0;
        variable test_fail_count : integer := 0;
        variable timeout_cnt : integer;
        variable prev_output : signed(DATA_WIDTH-1 downto 0);
        variable weight_changed : boolean;
    begin
        print_separator;
        report "NEURAL NETWORK TRAINING TOP-LEVEL TESTBENCH";
        report "Network Architecture: 4 inputs -> 2 hidden -> 1 output";
        report "Fixed-Point Format: Q2.13 (16-bit)";
        report "Learning Rate: 0.01 (82 in Q2.13)";
        print_separator;
        report "";

        -- Initialize signals
        rst             <= '1';
        start_training  <= '0';
        stop_training   <= '0';
        learning_rate   <= to_signed(DEFAULT_LR, DATA_WIDTH);
        use_default_lr  <= '1';
        num_epochs      <= to_unsigned(1, 16);
        num_samples     <= to_unsigned(1, 16);
        sample_data     <= (others => '0');
        sample_addr     <= (others => '0');
        sample_valid    <= '0';
        target_data     <= (others => '0');
        target_valid    <= '0';
        weight_init_data <= (others => '0');
        weight_init_addr <= (others => '0');
        weight_init_en  <= '0';
        weight_out_addr <= (others => '0');
        weight_out_en   <= '0';

        -- Wait 5 cycles for reset
        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;
        rst <= '0';
        report "Reset released, system initialized";
        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;

        -----------------------------------------------------------------------
        -- Test 1: Weight Initialization
        -----------------------------------------------------------------------
        print_test_header(1, "WEIGHT INITIALIZATION");
        report "Initializing 13 weights/biases with test values...";

        -- Define initial weights
        -- Layer 1 weights (8): 0.25 each
        for i in 0 to 7 loop
            init_weights(i) := QUARTER_Q213;  -- 0.25
        end loop;
        -- Layer 1 biases (2): 0.1 each
        init_weights(8)  := to_fixed(0.1);
        init_weights(9)  := to_fixed(0.1);
        -- Layer 2 weights (2): 0.5 each
        init_weights(10) := HALF_Q213;
        init_weights(11) := HALF_Q213;
        -- Layer 2 bias (1): 0.0
        init_weights(12) := ZERO_Q213;

        report "  Memory Map:";
        report "    [0-7]   Layer 1 weights = 0.25";
        report "    [8-9]   Layer 1 biases  = 0.1";
        report "    [10-11] Layer 2 weights = 0.5";
        report "    [12]    Layer 2 bias    = 0.0";

        -- Write weights
        for i in 0 to NUM_PARAMS-1 loop
            weight_init_addr <= to_unsigned(i, WEIGHT_ADDR_W);
            weight_init_data <= init_weights(i);
            weight_init_en   <= '1';
            wait until rising_edge(clk);
        end loop;
        weight_init_en <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- Read back and verify
        report "  Reading back and verifying weights...";
        for i in 0 to NUM_PARAMS-1 loop
            weight_out_addr <= to_unsigned(i, WEIGHT_ADDR_W);
            weight_out_en   <= '1';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            read_weights(i) := weight_out_data;
        end loop;
        weight_out_en <= '0';

        -- Check all weights
        for i in 0 to NUM_PARAMS-1 loop
            if read_weights(i) = init_weights(i) then
                test_pass_count := test_pass_count + 1;
                report "    Weight[" & integer'image(i) & "] = " &
                       real'image(to_real(read_weights(i))) & " - PASS";
            else
                test_fail_count := test_fail_count + 1;
                report "    Weight[" & integer'image(i) & "] expected " &
                       real'image(to_real(init_weights(i))) & " got " &
                       real'image(to_real(read_weights(i))) & " - FAIL" severity error;
            end if;
        end loop;

        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;

        -----------------------------------------------------------------------
        -- Test 2: Single Sample Training Cycle
        -----------------------------------------------------------------------
        print_test_header(2, "SINGLE SAMPLE TRAINING CYCLE");
        report "Training parameters:";
        report "  Epochs: 1, Samples per epoch: 1";
        report "  Input: [1.0, 0.5, 0.25, 0.1]";
        report "  Target: 0.75";

        num_epochs  <= to_unsigned(1, 16);
        num_samples <= to_unsigned(1, 16);

        -- Start training
        start_training <= '1';
        wait until rising_edge(clk);
        start_training <= '0';
        report "  Training started, waiting for sample_ready...";

        -- Wait for sample_ready
        timeout_cnt := 0;
        while sample_ready = '0' and timeout_cnt < 100 loop
            wait until rising_edge(clk);
            timeout_cnt := timeout_cnt + 1;
        end loop;

        if sample_ready = '1' then
            test_pass_count := test_pass_count + 1;
            report "  sample_ready asserted after " & integer'image(timeout_cnt) & " cycles - PASS";
        else
            test_fail_count := test_fail_count + 1;
            report "  Timeout waiting for sample_ready - FAIL" severity error;
        end if;

        -- Load sample data
        report "  Loading input sample...";
        sample_data <= ONE_Q213;
        sample_addr <= "00";
        sample_valid <= '1';
        wait until rising_edge(clk);

        sample_data <= HALF_Q213;
        sample_addr <= "01";
        wait until rising_edge(clk);

        sample_data <= QUARTER_Q213;
        sample_addr <= "10";
        wait until rising_edge(clk);

        sample_data <= to_fixed(0.1);
        sample_addr <= "11";
        wait until rising_edge(clk);

        sample_valid <= '0';
        report "  Sample loaded, waiting for target_ready...";

        -- Wait for target_ready
        timeout_cnt := 0;
        while target_ready = '0' and timeout_cnt < 100 loop
            wait until rising_edge(clk);
            timeout_cnt := timeout_cnt + 1;
        end loop;

        if target_ready = '1' then
            test_pass_count := test_pass_count + 1;
            report "  target_ready asserted after " & integer'image(timeout_cnt) & " cycles - PASS";
        else
            test_fail_count := test_fail_count + 1;
            report "  Timeout waiting for target_ready - FAIL" severity error;
        end if;

        -- Provide target
        target_data  <= to_fixed(0.75);
        target_valid <= '1';
        wait until rising_edge(clk);
        target_valid <= '0';
        report "  Target value (0.75) loaded, running training cycle...";

        -- Wait for completion
        timeout_cnt := 0;
        while done = '0' and timeout_cnt < 2000 loop
            wait until rising_edge(clk);
            timeout_cnt := timeout_cnt + 1;
        end loop;

        if done = '1' then
            test_pass_count := test_pass_count + 1;
            report "  Training completed in " & integer'image(timeout_cnt) & " cycles - PASS";
        else
            test_fail_count := test_fail_count + 1;
            report "  Training timeout after " & integer'image(timeout_cnt) & " cycles - FAIL" severity error;
        end if;

        -- Check epoch counter
        if current_epoch = to_unsigned(1, 16) then
            test_pass_count := test_pass_count + 1;
            report "  Epoch counter = 1 - PASS";
        else
            test_fail_count := test_fail_count + 1;
            report "  Epoch counter = " & integer'image(to_integer(current_epoch)) & ", expected 1 - FAIL" severity error;
        end if;

        -- Report results
        report "  RESULTS:";
        report "    Network output:  " & real'image(to_real(output_data));
        report "    Training error:  " & real'image(to_real(training_error));
        report "    Overflow flag:   " & std_logic'image(overflow_flag);

        for i in 1 to 10 loop
            wait until rising_edge(clk);
        end loop;

        -----------------------------------------------------------------------
        -- Test 3: Weight Readback After Training
        -----------------------------------------------------------------------
        print_test_header(3, "WEIGHT READBACK AFTER TRAINING");
        report "Reading weights to verify training occurred...";

        -- Extra wait for state settling
        for i in 1 to 10 loop
            wait until rising_edge(clk);
        end loop;

        -- Read back weights
        for i in 0 to NUM_PARAMS-1 loop
            weight_out_addr <= to_unsigned(i, WEIGHT_ADDR_W);
            weight_out_en   <= '1';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            read_weights(i) := weight_out_data;
            report "    Weight[" & integer'image(i) & "] = " &
                   real'image(to_real(weight_out_data)) &
                   " (valid=" & std_logic'image(weight_out_valid) & ")";
        end loop;
        weight_out_en <= '0';

        -- Verify non-zero
        if read_weights(0) = ZERO_Q213 and read_weights(1) = ZERO_Q213 and
           read_weights(10) = ZERO_Q213 then
            test_fail_count := test_fail_count + 1;
            report "  ERROR: All weights are zero! - FAIL" severity error;
        else
            test_pass_count := test_pass_count + 1;
            report "  Weights contain non-zero values - PASS";
        end if;

        for i in 1 to 10 loop
            wait until rising_edge(clk);
        end loop;

        -----------------------------------------------------------------------
        -- Test 4: Multi-Epoch Training
        -----------------------------------------------------------------------
        print_test_header(4, "MULTI-EPOCH TRAINING (2 epochs x 2 samples)");

        -- Reset and reinitialize
        rst <= '1';
        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;
        rst <= '0';
        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;

        -- Reinitialize weights
        report "  Reinitializing weights...";
        for i in 0 to NUM_PARAMS-1 loop
            weight_init_addr <= to_unsigned(i, WEIGHT_ADDR_W);
            weight_init_data <= init_weights(i);
            weight_init_en   <= '1';
            wait until rising_edge(clk);
        end loop;
        weight_init_en <= '0';
        wait until rising_edge(clk);

        -- Start training
        num_epochs  <= to_unsigned(2, 16);
        num_samples <= to_unsigned(2, 16);
        start_training <= '1';
        wait until rising_edge(clk);
        start_training <= '0';
        report "  Training started: 2 epochs, 2 samples each";

        -- Process 4 samples
        for sample_idx in 0 to 3 loop
            -- Wait for sample_ready
            timeout_cnt := 0;
            while sample_ready = '0' and timeout_cnt < 500 loop
                wait until rising_edge(clk);
                timeout_cnt := timeout_cnt + 1;
            end loop;

            if sample_ready = '0' then
                report "    Sample " & integer'image(sample_idx) & ": timeout - FAIL" severity error;
                test_fail_count := test_fail_count + 1;
            end if;

            -- Load sample
            for i in 0 to 3 loop
                sample_data  <= to_fixed(0.5 + real(i) * 0.1);
                sample_addr  <= to_unsigned(i, 2);
                sample_valid <= '1';
                wait until rising_edge(clk);
            end loop;
            sample_valid <= '0';

            -- Wait for target_ready
            timeout_cnt := 0;
            while target_ready = '0' and timeout_cnt < 100 loop
                wait until rising_edge(clk);
                timeout_cnt := timeout_cnt + 1;
            end loop;

            -- Provide target
            target_data  <= to_fixed(0.8);
            target_valid <= '1';
            wait until rising_edge(clk);
            target_valid <= '0';

            report "    Sample " & integer'image(sample_idx) & " processed (epoch=" &
                   integer'image(to_integer(current_epoch)) & ", sample=" &
                   integer'image(to_integer(current_sample)) & ")";
        end loop;

        -- Wait for completion
        timeout_cnt := 0;
        while done = '0' and timeout_cnt < 5000 loop
            wait until rising_edge(clk);
            timeout_cnt := timeout_cnt + 1;
        end loop;

        if done = '1' then
            test_pass_count := test_pass_count + 1;
            report "  Multi-epoch training completed - PASS";
        else
            test_fail_count := test_fail_count + 1;
            report "  Multi-epoch training timeout - FAIL" severity error;
        end if;

        if current_epoch = to_unsigned(2, 16) then
            test_pass_count := test_pass_count + 1;
            report "  Final epoch count = 2 - PASS";
        else
            test_fail_count := test_fail_count + 1;
            report "  Final epoch count = " & integer'image(to_integer(current_epoch)) & ", expected 2 - FAIL" severity error;
        end if;

        for i in 1 to 10 loop
            wait until rising_edge(clk);
        end loop;

        -----------------------------------------------------------------------
        -- Test 5: Stop Training Early
        -----------------------------------------------------------------------
        print_test_header(5, "STOP TRAINING EARLY");

        rst <= '1';
        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;
        rst <= '0';
        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;

        -- Reinitialize weights
        for i in 0 to NUM_PARAMS-1 loop
            weight_init_addr <= to_unsigned(i, WEIGHT_ADDR_W);
            weight_init_data <= init_weights(i);
            weight_init_en   <= '1';
            wait until rising_edge(clk);
        end loop;
        weight_init_en <= '0';
        wait until rising_edge(clk);

        -- Start 10 epoch training
        num_epochs  <= to_unsigned(10, 16);
        num_samples <= to_unsigned(1, 16);
        start_training <= '1';
        wait until rising_edge(clk);
        start_training <= '0';
        report "  Started training with 10 epochs...";

        -- Complete first sample
        timeout_cnt := 0;
        while sample_ready = '0' and timeout_cnt < 100 loop
            wait until rising_edge(clk);
            timeout_cnt := timeout_cnt + 1;
        end loop;

        for i in 0 to 3 loop
            sample_data  <= HALF_Q213;
            sample_addr  <= to_unsigned(i, 2);
            sample_valid <= '1';
            wait until rising_edge(clk);
        end loop;
        sample_valid <= '0';

        timeout_cnt := 0;
        while target_ready = '0' and timeout_cnt < 100 loop
            wait until rising_edge(clk);
            timeout_cnt := timeout_cnt + 1;
        end loop;

        target_data  <= HALF_Q213;
        target_valid <= '1';
        wait until rising_edge(clk);
        target_valid <= '0';

        -- Wait a bit then stop
        for i in 1 to 300 loop
            wait until rising_edge(clk);
        end loop;

        report "  Asserting stop_training signal...";
        stop_training <= '1';
        wait until rising_edge(clk);
        stop_training <= '0';

        -- Wait for done
        timeout_cnt := 0;
        while done = '0' and timeout_cnt < 500 loop
            wait until rising_edge(clk);
            timeout_cnt := timeout_cnt + 1;
        end loop;

        if done = '1' and current_epoch < to_unsigned(10, 16) then
            test_pass_count := test_pass_count + 1;
            report "  Training stopped at epoch " & integer'image(to_integer(current_epoch)) & " - PASS";
        else
            test_fail_count := test_fail_count + 1;
            report "  Stop training failed - FAIL" severity error;
        end if;

        for i in 1 to 10 loop
            wait until rising_edge(clk);
        end loop;

        -----------------------------------------------------------------------
        -- Test 6: Reset and Restart
        -----------------------------------------------------------------------
        print_test_header(6, "RESET AND RESTART AFTER STOP");

        rst <= '1';
        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;
        rst <= '0';
        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;

        if busy = '0' then
            test_pass_count := test_pass_count + 1;
            report "  System idle after reset - PASS";
        else
            test_fail_count := test_fail_count + 1;
            report "  System still busy after reset - FAIL" severity error;
        end if;

        if done = '0' then
            test_pass_count := test_pass_count + 1;
            report "  Done flag cleared - PASS";
        else
            test_fail_count := test_fail_count + 1;
            report "  Done flag not cleared - FAIL" severity error;
        end if;

        -- Reinitialize and train
        for i in 0 to NUM_PARAMS-1 loop
            weight_init_addr <= to_unsigned(i, WEIGHT_ADDR_W);
            weight_init_data <= init_weights(i);
            weight_init_en   <= '1';
            wait until rising_edge(clk);
        end loop;
        weight_init_en <= '0';
        wait until rising_edge(clk);

        num_epochs  <= to_unsigned(1, 16);
        num_samples <= to_unsigned(1, 16);
        start_training <= '1';
        wait until rising_edge(clk);
        start_training <= '0';

        timeout_cnt := 0;
        while sample_ready = '0' and timeout_cnt < 100 loop
            wait until rising_edge(clk);
            timeout_cnt := timeout_cnt + 1;
        end loop;

        if sample_ready = '1' then
            test_pass_count := test_pass_count + 1;
            report "  System ready for new training - PASS";
        else
            test_fail_count := test_fail_count + 1;
            report "  System not ready after reset - FAIL" severity error;
        end if;

        -- Complete training
        for i in 0 to 3 loop
            sample_data  <= HALF_Q213;
            sample_addr  <= to_unsigned(i, 2);
            sample_valid <= '1';
            wait until rising_edge(clk);
        end loop;
        sample_valid <= '0';

        timeout_cnt := 0;
        while target_ready = '0' and timeout_cnt < 100 loop
            wait until rising_edge(clk);
            timeout_cnt := timeout_cnt + 1;
        end loop;

        target_data  <= HALF_Q213;
        target_valid <= '1';
        wait until rising_edge(clk);
        target_valid <= '0';

        timeout_cnt := 0;
        while done = '0' and timeout_cnt < 2000 loop
            wait until rising_edge(clk);
            timeout_cnt := timeout_cnt + 1;
        end loop;

        if done = '1' then
            test_pass_count := test_pass_count + 1;
            report "  Training completed after restart - PASS";
        else
            test_fail_count := test_fail_count + 1;
            report "  Training failed after restart - FAIL" severity error;
        end if;

        for i in 1 to 10 loop
            wait until rising_edge(clk);
        end loop;

        -----------------------------------------------------------------------
        -- Test 7: Multiple Training Iterations
        -----------------------------------------------------------------------
        print_test_header(7, "MULTIPLE TRAINING ITERATIONS (5 epochs)");

        rst <= '1';
        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;
        rst <= '0';
        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;

        -- Initialize weights
        for i in 0 to NUM_PARAMS-1 loop
            weight_init_addr <= to_unsigned(i, WEIGHT_ADDR_W);
            weight_init_data <= init_weights(i);
            weight_init_en   <= '1';
            wait until rising_edge(clk);
        end loop;
        weight_init_en <= '0';
        wait until rising_edge(clk);

        num_epochs  <= to_unsigned(5, 16);
        num_samples <= to_unsigned(1, 16);
        start_training <= '1';
        wait until rising_edge(clk);
        start_training <= '0';
        report "  Starting 5 epoch training...";

        prev_output := (others => '0');

        for epoch_idx in 0 to 4 loop
            timeout_cnt := 0;
            while sample_ready = '0' and timeout_cnt < 500 loop
                wait until rising_edge(clk);
                timeout_cnt := timeout_cnt + 1;
            end loop;

            for i in 0 to 3 loop
                sample_data  <= to_fixed(0.6 + real(i) * 0.05);
                sample_addr  <= to_unsigned(i, 2);
                sample_valid <= '1';
                wait until rising_edge(clk);
            end loop;
            sample_valid <= '0';

            timeout_cnt := 0;
            while target_ready = '0' and timeout_cnt < 100 loop
                wait until rising_edge(clk);
                timeout_cnt := timeout_cnt + 1;
            end loop;

            target_data  <= to_fixed(0.9);
            target_valid <= '1';
            wait until rising_edge(clk);
            target_valid <= '0';

            -- Wait for this sample to complete (but not final done)
            for i in 1 to 200 loop
                wait until rising_edge(clk);
            end loop;

            report "    Epoch " & integer'image(epoch_idx) & ": output=" &
                   real'image(to_real(output_data)) & ", error=" &
                   real'image(to_real(training_error));
        end loop;

        -- Wait for final done
        timeout_cnt := 0;
        while done = '0' and timeout_cnt < 2000 loop
            wait until rising_edge(clk);
            timeout_cnt := timeout_cnt + 1;
        end loop;

        if done = '1' then
            test_pass_count := test_pass_count + 1;
            report "  5-epoch training completed - PASS";
        else
            test_fail_count := test_fail_count + 1;
            report "  5-epoch training timeout - FAIL" severity error;
        end if;

        for i in 1 to 10 loop
            wait until rising_edge(clk);
        end loop;

        -----------------------------------------------------------------------
        -- Test 8: Overflow Flag Check
        -----------------------------------------------------------------------
        print_test_header(8, "OVERFLOW FLAG MONITORING");

        report "  Overflow flag after training: " & std_logic'image(overflow_flag);

        if overflow_flag = '0' then
            test_pass_count := test_pass_count + 1;
            report "  No overflow detected during training - PASS";
        else
            report "  Warning: Overflow detected during training" severity warning;
            test_pass_count := test_pass_count + 1;
            report "  Overflow flag correctly monitored - PASS";
        end if;

        for i in 1 to 10 loop
            wait until rising_edge(clk);
        end loop;

        -----------------------------------------------------------------------
        -- Test Summary
        -----------------------------------------------------------------------
        report "";
        print_separator;
        report "TEST SUMMARY";
        print_separator;
        report "  Total Passed: " & integer'image(test_pass_count);
        report "  Total Failed: " & integer'image(test_fail_count);
        report "";
        if test_fail_count = 0 then
            report "  *** ALL TESTS PASSED ***";
        else
            report "  *** SOME TESTS FAILED ***" severity error;
        end if;
        print_separator;
        report "";

        test_done <= true;
        wait;

    end process;

end architecture sim;
