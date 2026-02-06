--------------------------------------------------------------------------------

-- Module: neural_network_421

-- Description: 4-2-1 Neural Network using single_neuron modules

--------------------------------------------------------------------------------



library IEEE;

use IEEE.std_logic_1164.all;

use IEEE.numeric_std.all;



entity neural_network_421_sigmoid is

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

        

        -- Input data (4 values)

        input_data      : in  signed(DATA_WIDTH-1 downto 0);

        input_index     : in  unsigned(1 downto 0);

        input_valid     : in  std_logic;

        

        -- Target for training

        target          : in  signed(DATA_WIDTH-1 downto 0);

        

        -- Learning rate

        learning_rate   : in  signed(DATA_WIDTH-1 downto 0);

        

        -- Network output

        output_data     : out signed(DATA_WIDTH-1 downto 0);

        output_valid    : out std_logic;

        

        -- Status

        fwd_done        : out std_logic;

        bwd_done        : out std_logic;

        upd_done        : out std_logic

    );

end entity neural_network_421_sigmoid;



architecture rtl of neural_network_421_sigmoid is



    -- Layer 1 signals (2 neurons, 4 inputs each)

    signal l1_n0_a, l1_n1_a : signed(DATA_WIDTH-1 downto 0);

    signal l1_n0_delta, l1_n1_delta : signed(DATA_WIDTH-1 downto 0);

    signal l1_n0_fwd_done, l1_n1_fwd_done : std_logic;

    signal l1_n0_bwd_done, l1_n1_bwd_done : std_logic;

    

    -- Layer 2 signals (1 neuron, 2 inputs)

    signal l2_a : signed(DATA_WIDTH-1 downto 0);

    signal l2_delta : signed(DATA_WIDTH-1 downto 0);

    signal l2_fwd_done, l2_bwd_done : std_logic;

    

    -- Error propagation

    signal output_error : signed(DATA_WIDTH-1 downto 0);

    signal l1_n0_error, l1_n1_error : signed(DATA_WIDTH-1 downto 0);

    

    -- Layer 2 weights for error propagation (initialized to avoid metavalues)

    signal l2_weight_0 : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal l2_weight_1 : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    -- Resized input_index for neuron port maps (2-bit to 4-bit)
    signal input_index_4bit : unsigned(3 downto 0);



    ---------------------------------------------------------------------------

    -- Fix #1: L2 Input Sequencing FSM Signals

    ---------------------------------------------------------------------------

    type l2_input_state_t is (L2_IDLE, L2_FEED_INPUT0, L2_FEED_INPUT1, L2_WAIT_DONE);

    signal l2_input_state : l2_input_state_t;

    signal l2_input_data : signed(DATA_WIDTH-1 downto 0);

    signal l2_input_index : unsigned(3 downto 0);

    signal l2_input_valid : std_logic;

    signal l2_fwd_start_internal : std_logic;



    ---------------------------------------------------------------------------

    -- Fix #2: L2 Weight Read FSM Signals

    ---------------------------------------------------------------------------

    type l2_weight_read_state_t is (WR_IDLE, WR_READ_W0, WR_READ_W1, WR_DONE);

    signal l2_weight_read_state : l2_weight_read_state_t;

    signal l2_weight_prop_idx : unsigned(3 downto 0);

    signal l2_weight_prop_en : std_logic;

    signal l2_weight_1_reg : signed(DATA_WIDTH-1 downto 0);

    signal l2_weight_for_prop : signed(DATA_WIDTH-1 downto 0);



    ---------------------------------------------------------------------------

    -- Fix #3: Registered L2 Start Signals

    ---------------------------------------------------------------------------

    signal l1_both_done : std_logic;

    signal l1_both_done_prev : std_logic;

    signal l2_start_pulse : std_logic;



    ---------------------------------------------------------------------------

    -- Fix #6: Update Done Internal Signals

    ---------------------------------------------------------------------------

    signal l1_n0_upd_done_internal : std_logic;

    signal l1_n1_upd_done_internal : std_logic;

    signal l2_upd_done_internal : std_logic;

    ---------------------------------------------------------------------------

    -- Fix #10: Update Done Completion Tracker

    -- Captures when each neuron completes, pulses upd_done when all done

    ---------------------------------------------------------------------------

    signal l1_n0_upd_complete : std_logic := '0';
    signal l1_n1_upd_complete : std_logic := '0';
    signal l2_upd_complete : std_logic := '0';
    signal upd_done_prev : std_logic := '0';  -- For edge detection



    ---------------------------------------------------------------------------

    -- Fix #4: Saturation Helper Function

    ---------------------------------------------------------------------------

    function saturate_multiply(

        a : signed(DATA_WIDTH-1 downto 0);

        b : signed(DATA_WIDTH-1 downto 0)

    ) return signed is

        variable product : signed(2*DATA_WIDTH-1 downto 0);

        variable scaled : signed(DATA_WIDTH downto 0);

        constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);

        constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH);

        constant FRAC_BITS : integer := 13;

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



begin

    -- Resize input_index from 2-bit to 4-bit for neuron inputs
    input_index_4bit <= resize(input_index, 4);


    ---------------------------------------------------------------------------

    -- Layer 1: Two neurons with 4 inputs each

    ---------------------------------------------------------------------------

    layer1_neuron0 : entity work.single_neuron_sigmoid

        generic map (

            NUM_INPUTS      => 4,

            IS_OUTPUT_LAYER => false,

            NEURON_ID       => 0

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

            a_out           => l1_n0_a,

            fwd_done        => l1_n0_fwd_done,

            fwd_busy        => open,

            bwd_start       => start_backward,

            bwd_clear       => '0',

            error_in        => l1_n0_error,

            error_valid     => l2_bwd_done,  -- Error valid when L2 backward done

            delta_out       => l1_n0_delta,

            delta_valid     => open,

            weight_for_prop => open,

            weight_prop_idx => (others => '0'),

            weight_prop_en  => '0',

            bwd_done        => l1_n0_bwd_done,

            bwd_busy        => open,

            upd_start       => start_update,

            upd_clear       => '0',

            learning_rate   => learning_rate,

            upd_done        => l1_n0_upd_done_internal,

            upd_busy        => open,

            weight_init_en  => '0',

            weight_init_idx => (others => '0'),

            weight_init_data=> (others => '0'),

            weight_read_en  => '0',

            weight_read_idx => (others => '0'),

            weight_read_data=> open,

            overflow        => open

        );



    layer1_neuron1 : entity work.single_neuron_sigmoid

        generic map (

            NUM_INPUTS      => 4,

            IS_OUTPUT_LAYER => false,

            NEURON_ID       => 1

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

            a_out           => l1_n1_a,

            fwd_done        => l1_n1_fwd_done,

            fwd_busy        => open,

            bwd_start       => start_backward,

            bwd_clear       => '0',

            error_in        => l1_n1_error,

            error_valid     => l2_bwd_done,

            delta_out       => l1_n1_delta,

            delta_valid     => open,

            weight_for_prop => open,

            weight_prop_idx => (others => '0'),

            weight_prop_en  => '0',

            bwd_done        => l1_n1_bwd_done,

            bwd_busy        => open,

            upd_start       => start_update,

            upd_clear       => '0',

            learning_rate   => learning_rate,

            upd_done        => l1_n1_upd_done_internal,

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

    -- Layer 2: One output neuron with 2 inputs

    ---------------------------------------------------------------------------

    layer2_output : entity work.single_neuron_sigmoid

        generic map (

            NUM_INPUTS      => 2,

            IS_OUTPUT_LAYER => true,

            NEURON_ID       => 2

        )

        port map (

            clk             => clk,

            rst             => rst,

            fwd_start       => l2_fwd_start_internal,  -- From FSM

            fwd_clear       => '0',

            input_data      => l2_input_data,  -- From FSM

            input_index     => l2_input_index,  -- From FSM

            input_valid     => l2_input_valid,  -- From FSM

            input_ready     => open,

            z_out           => open,

            a_out           => l2_a,

            fwd_done        => l2_fwd_done,

            fwd_busy        => open,

            bwd_start       => start_backward,

            bwd_clear       => '0',

            error_in        => output_error,

            error_valid     => '1',

            delta_out       => l2_delta,

            delta_valid     => open,

            weight_for_prop => l2_weight_for_prop,  -- From FSM

            weight_prop_idx => l2_weight_prop_idx,  -- From FSM

            weight_prop_en  => l2_weight_prop_en,  -- From FSM

            bwd_done        => l2_bwd_done,

            bwd_busy        => open,

            upd_start       => start_update,

            upd_clear       => '0',

            learning_rate   => learning_rate,

            upd_done        => l2_upd_done_internal,

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

    -- Fix #1: L2 Input Sequencing FSM

    ---------------------------------------------------------------------------

    -- This FSM sequentially feeds L1 outputs to L2 neuron

    l2_input_fsm_proc : process(clk)

    begin

        if rising_edge(clk) then

            if rst = '1' then

                l2_input_state <= L2_IDLE;

                l2_input_data <= (others => '0');

                l2_input_index <= (others => '0');

                l2_input_valid <= '0';

                l2_fwd_start_internal <= '0';

            else

                case l2_input_state is

                    when L2_IDLE =>

                        l2_input_valid <= '0';

                        l2_fwd_start_internal <= '0';

                        -- FIX: Use edge detection to prevent multiple triggers
                        if l1_n0_fwd_done = '1' and l1_n1_fwd_done = '1' and l1_both_done_prev = '0' then

                            l2_fwd_start_internal <= '1';

                            l2_input_state <= L2_FEED_INPUT0;

                        end if;



                    when L2_FEED_INPUT0 =>

                        l2_fwd_start_internal <= '0';

                        l2_input_data <= l1_n0_a;

                        l2_input_index <= to_unsigned(0, 4);

                        l2_input_valid <= '1';

                        l2_input_state <= L2_FEED_INPUT1;



                    when L2_FEED_INPUT1 =>

                        l2_input_data <= l1_n1_a;

                        l2_input_index <= to_unsigned(1, 4);

                        l2_input_valid <= '1';

                        l2_input_state <= L2_WAIT_DONE;



                    when L2_WAIT_DONE =>

                        l2_input_valid <= '0';

                        if l2_fwd_done = '1' then

                            l2_input_state <= L2_IDLE;

                        end if;

                end case;

            end if;

        end if;

    end process l2_input_fsm_proc;


    ---------------------------------------------------------------------------

    -- Fix #2: L2 Weight Read FSM

    ---------------------------------------------------------------------------

    -- This FSM reads L2 weights for error propagation

    l2_weight_read_fsm_proc : process(clk)

    begin

        if rising_edge(clk) then

            if rst = '1' then

                l2_weight_read_state <= WR_IDLE;

                l2_weight_prop_idx <= (others => '0');

                l2_weight_prop_en <= '0';

                l2_weight_1_reg <= (others => '0');

                l2_weight_0 <= (others => '0');

                l2_weight_1 <= (others => '0');

            else

                case l2_weight_read_state is

                    when WR_IDLE =>

                        l2_weight_prop_en <= '0';

                        if start_backward = '1' then

                            l2_weight_prop_idx <= to_unsigned(0, 4);

                            l2_weight_prop_en <= '1';

                            l2_weight_read_state <= WR_READ_W0;

                        end if;



                    when WR_READ_W0 =>

                        -- Weight 0 arrives this cycle, capture it FROM neuron

                        l2_weight_0 <= l2_weight_for_prop;

                        l2_weight_prop_idx <= to_unsigned(1, 4);

                        l2_weight_read_state <= WR_READ_W1;



                    when WR_READ_W1 =>

                        -- Weight 1 arrives this cycle, capture it FROM neuron

                        l2_weight_1 <= l2_weight_for_prop;

                        l2_weight_read_state <= WR_DONE;



                    when WR_DONE =>

                        l2_weight_prop_en <= '0';

                        if l2_bwd_done = '1' then

                            l2_weight_read_state <= WR_IDLE;

                        end if;

                end case;

            end if;

        end if;

    end process l2_weight_read_fsm_proc;


    ---------------------------------------------------------------------------

    -- Fix #3: Registered L2 Start Signal

    ---------------------------------------------------------------------------

    -- Register L1 done signals to generate a clean pulse for L2

    l2_start_reg_proc : process(clk)

    begin

        if rising_edge(clk) then

            if rst = '1' then

                l1_both_done_prev <= '0';

            else

                l1_both_done_prev <= l1_both_done;

            end if;

        end if;

    end process l2_start_reg_proc;



    -- Combinational assignments for L2 start

    l1_both_done <= l1_n0_fwd_done and l1_n1_fwd_done;

    l2_start_pulse <= l1_both_done and not l1_both_done_prev;


    ---------------------------------------------------------------------------

    -- Error Computation

    ---------------------------------------------------------------------------

    -- Fix #5: Output error with saturation

    output_error_proc : process(target, l2_a)

        variable diff : signed(DATA_WIDTH downto 0);

        constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);

        constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH);

    begin

        -- Fix #12: Corrected sign - should be (output - target) not (target - output)
        -- ∂Loss/∂output = (output - target) for MSE gradient descent
        diff := resize(l2_a, DATA_WIDTH+1) - resize(target, DATA_WIDTH+1);



        if diff > resize(SAT_MAX, DATA_WIDTH+1) then

            output_error <= SAT_MAX;

        elsif diff < resize(SAT_MIN, DATA_WIDTH+1) then

            output_error <= SAT_MIN;

        else

            output_error <= diff(DATA_WIDTH-1 downto 0);

        end if;

    end process output_error_proc;



    -- Fix #4: Propagated error to Layer 1 with saturation

    -- l1_n0_error = W_L2[0] Ã— Î´_L2

    -- l1_n1_error = W_L2[1] Ã— Î´_L2

    l1_n0_error <= saturate_multiply(l2_weight_0, l2_delta);

    l1_n1_error <= saturate_multiply(l2_weight_1, l2_delta);



    ---------------------------------------------------------------------------

    -- Output Assignments

    ---------------------------------------------------------------------------

    output_data  <= l2_a;

    output_valid <= l2_fwd_done;

    fwd_done     <= l2_fwd_done;

    bwd_done     <= l1_n0_bwd_done and l1_n1_bwd_done;


    ---------------------------------------------------------------------------
    -- Fix #10: Update Done Completion Tracker Process
    -- Tracks when all neurons complete, generates pulse when all done
    ---------------------------------------------------------------------------
    upd_done_tracker : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                l1_n0_upd_complete <= '0';
                l1_n1_upd_complete <= '0';
                l2_upd_complete <= '0';
                upd_done_prev <= '0';
            else
                -- Clear completion flags on start_update
                if start_update = '1' then
                    l1_n0_upd_complete <= '0';
                    l1_n1_upd_complete <= '0';
                    l2_upd_complete <= '0';
                end if;

                -- Capture when each neuron completes
                if l1_n0_upd_done_internal = '1' then
                    l1_n0_upd_complete <= '1';
                end if;
                if l1_n1_upd_done_internal = '1' then
                    l1_n1_upd_complete <= '1';
                end if;
                if l2_upd_done_internal = '1' then
                    l2_upd_complete <= '1';
                end if;

                -- Store previous state for edge detection
                upd_done_prev <= l1_n0_upd_complete and l1_n1_upd_complete and l2_upd_complete;
            end if;
        end if;
    end process upd_done_tracker;

    -- Generate pulse when all neurons complete (rising edge)
    upd_done <= '1' when (l1_n0_upd_complete = '1' and
                          l1_n1_upd_complete = '1' and
                          l2_upd_complete = '1' and
                          upd_done_prev = '0') else '0';


end architecture rtl;
