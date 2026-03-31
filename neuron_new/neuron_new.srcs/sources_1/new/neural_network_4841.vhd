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
    -- Update Done Latching Signals (Fix for pulse alignment issue)
    ---------------------------------------------------------------------------
    signal l1_upd_done_latched : std_logic_vector(7 downto 0) := (others => '0');
    signal l2_upd_done_latched : std_logic_vector(3 downto 0) := (others => '0');
    signal l3_upd_done_latched : std_logic := '0';

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
    type l3_wr_state_t is (WR3_IDLE, WR3_READ, WR3_CAPTURE_LAST, WR3_DONE);
    signal l3_wr_state      : l3_wr_state_t;
    signal l3_wr_index      : unsigned(3 downto 0);

    ---------------------------------------------------------------------------
    -- L2 Weight Read FSM (reads L2 weights for L1 error calculation)
    ---------------------------------------------------------------------------
    type l2_wr_state_t is (WR2_IDLE, WR2_READ, WR2_CAPTURE_LAST, WR2_COMPUTE, WR2_DONE);
    signal l2_wr_state      : l2_wr_state_t;
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
            error_valid     => l3_fwd_done,  -- Only valid after forward pass completes
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

                        if l3_wr_index = 3 then
                            l3_wr_state <= WR3_CAPTURE_LAST;
                        else
                            l3_wr_index <= l3_wr_index + 1;
                        end if;

                    when WR3_CAPTURE_LAST =>
                        -- Capture final weight at index 3
                        l3_weights_captured(3) <= l3_weight_for_prop;
                        l3_wr_state <= WR3_DONE;

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
                l2_wr_weight_idx <= (others => '0');
                l2_weight_prop_en <= '0';
                l2_weights_matrix <= (others => (others => (others => '0')));
            else
                case l2_wr_state is
                        when WR2_IDLE =>
                        l2_weight_prop_en <= '0';
                        if l3_bwd_done = '1' then
                            l2_weight_prop_en <= '1';
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

                        if l2_wr_weight_idx = 7 then
                            l2_wr_state <= WR2_CAPTURE_LAST;
                        else
                            l2_wr_weight_idx <= l2_wr_weight_idx + 1;
                        end if;

                    when WR2_CAPTURE_LAST =>
                        -- Capture final weight at index 7 for all L2 neurons
                        for n in 0 to 3 loop
                            l2_weights_matrix(n, 7) <= l2_weight_for_prop(n);
                        end loop;
                        l2_wr_state <= WR2_COMPUTE;

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
    -- Update Done Latching Process (Fix for pulse alignment)
    -- Latches upd_done pulses from all neurons and generates combined done signal
    ---------------------------------------------------------------------------
    upd_done_latch_proc : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                l1_upd_done_latched <= (others => '0');
                l2_upd_done_latched <= (others => '0');
                l3_upd_done_latched <= '0';
            elsif start_update = '1' then
                -- Clear latches on new update cycle
                l1_upd_done_latched <= (others => '0');
                l2_upd_done_latched <= (others => '0');
                l3_upd_done_latched <= '0';
            else
                -- Latch each neuron's done pulse
                for i in 0 to 7 loop
                    if l1_upd_done(i) = '1' then
                        l1_upd_done_latched(i) <= '1';
                    end if;
                end loop;

                for i in 0 to 3 loop
                    if l2_upd_done(i) = '1' then
                        l2_upd_done_latched(i) <= '1';
                    end if;
                end loop;

                if l3_upd_done = '1' then
                    l3_upd_done_latched <= '1';
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    output_data  <= l3_a;
    output_valid <= l3_fwd_done;
    fwd_done     <= l3_fwd_done;
    bwd_done     <= l1_all_bwd_done;
    upd_done     <= '1' when (l1_upd_done_latched = "11111111" and
                              l2_upd_done_latched = "1111" and
                              l3_upd_done_latched = '1') else '0';

    ---------------------------------------------------------------------------
    -- Debug Monitoring Process
    ---------------------------------------------------------------------------
    debug_monitor : process(clk)
        variable fwd_done_prev : std_logic := '0';
        variable bwd_done_prev : std_logic := '0';
        variable upd_done_prev : std_logic := '0';
        variable sample_count : integer := 0;
    begin
        if rising_edge(clk) then
            -- Monitor forward pass completion
            if l3_fwd_done = '1' and fwd_done_prev = '0' then
                report "FWD: L1=[" &
                       integer'image(to_integer(l1_a(0))) & "," &
                       integer'image(to_integer(l1_a(1))) & "," &
                       integer'image(to_integer(l1_a(2))) & "," &
                       integer'image(to_integer(l1_a(3))) & "," &
                       integer'image(to_integer(l1_a(4))) & "," &
                       integer'image(to_integer(l1_a(5))) & "," &
                       integer'image(to_integer(l1_a(6))) & "," &
                       integer'image(to_integer(l1_a(7))) &
                       "] L2=[" &
                       integer'image(to_integer(l2_a(0))) & "," &
                       integer'image(to_integer(l2_a(1))) & "," &
                       integer'image(to_integer(l2_a(2))) & "," &
                       integer'image(to_integer(l2_a(3))) &
                       "] L3=" & integer'image(to_integer(l3_a));
            end if;

            -- Monitor backward pass completion
            if l1_all_bwd_done = '1' and bwd_done_prev = '0' then
                report "BWD: L3_delta=" & integer'image(to_integer(l3_delta)) &
                       " L2_delta=[" &
                       integer'image(to_integer(l2_delta(0))) & "," &
                       integer'image(to_integer(l2_delta(1))) & "," &
                       integer'image(to_integer(l2_delta(2))) & "," &
                       integer'image(to_integer(l2_delta(3))) &
                       "] L1_delta=[" &
                       integer'image(to_integer(l1_delta(0))) & "," &
                       integer'image(to_integer(l1_delta(1))) & "," &
                       integer'image(to_integer(l1_delta(2))) & "," &
                       integer'image(to_integer(l1_delta(3))) & "," &
                       integer'image(to_integer(l1_delta(4))) & "," &
                       integer'image(to_integer(l1_delta(5))) & "," &
                       integer'image(to_integer(l1_delta(6))) & "," &
                       integer'image(to_integer(l1_delta(7))) & "]";
            end if;

            -- Monitor update completion and print sample weight
            if (l1_upd_done_latched = "11111111" and
                l2_upd_done_latched = "1111" and
                l3_upd_done_latched = '1') and upd_done_prev = '0' then
                sample_count := sample_count + 1;
                if sample_count <= 5 or sample_count mod 100 = 0 then
                    report "UPD #" & integer'image(sample_count) & " completed";
                end if;
            end if;

            fwd_done_prev := l3_fwd_done;
            bwd_done_prev := l1_all_bwd_done;
            -- Use the internal signal instead of the output port
            if (l1_upd_done_latched = "11111111" and
                l2_upd_done_latched = "1111" and
                l3_upd_done_latched = '1') then
                upd_done_prev := '1';
            else
                upd_done_prev := '0';
            end if;
        end if;
    end process;

end architecture rtl;
