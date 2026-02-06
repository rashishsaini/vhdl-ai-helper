--------------------------------------------------------------------------------

-- Module: single_neuron

-- Description: Complete self-contained neuron with forward/backward capability

--              Parameterized for any layer position in the network

--

-- Generics:

--   NUM_INPUTS      - Number of input connections (4 for L1, 2 for L2)

--   IS_OUTPUT_LAYER - True for output layer (uses direct error)

--   NEURON_ID       - Unique identifier for debugging

--

-- Author: FPGA Neural Network Project

--------------------------------------------------------------------------------



library IEEE;

use IEEE.std_logic_1164.all;

use IEEE.numeric_std.all;



entity single_neuron_tanh is

    generic (

        DATA_WIDTH      : integer := 16;    -- Q2.13 format

        ACCUM_WIDTH     : integer := 40;    -- Q10.26 accumulator

        GRAD_WIDTH      : integer := 32;    -- Q4.26 gradient

        FRAC_BITS       : integer := 13;

        NUM_INPUTS      : integer := 4;     -- Number of inputs to this neuron

        IS_OUTPUT_LAYER : boolean := false; -- Output layer uses direct error

        NEURON_ID       : integer := 0;     -- For debugging

        DEFAULT_LR      : integer := 82     -- Learning rate 0.01 in Q2.13

    );

    port (

        -- Clock and Reset

        clk             : in  std_logic;

        rst             : in  std_logic;

        

        -- ===================== FORWARD PATH =====================

        -- Control

        fwd_start       : in  std_logic;

        fwd_clear       : in  std_logic;

        

        -- Input activations (from previous layer or external)

        input_data      : in  signed(DATA_WIDTH-1 downto 0);

        input_index     : in  unsigned(3 downto 0);  -- Which input (0 to NUM_INPUTS-1)

        input_valid     : in  std_logic;

        input_ready     : out std_logic;

        

        -- Forward outputs

        z_out           : out signed(DATA_WIDTH-1 downto 0);  -- Pre-activation

        a_out           : out signed(DATA_WIDTH-1 downto 0);  -- Post-activation (output)

        fwd_done        : out std_logic;

        fwd_busy        : out std_logic;

        

        -- ===================== BACKWARD PATH =====================

        -- Control

        bwd_start       : in  std_logic;

        bwd_clear       : in  std_logic;

        

        -- Error input

        -- For output layer: error = target - actual

        -- For hidden layer: error = weighted sum of downstream deltas

        error_in        : in  signed(DATA_WIDTH-1 downto 0);

        error_valid     : in  std_logic;

        

        -- Delta output (for error propagation to previous layer)

        delta_out       : out signed(DATA_WIDTH-1 downto 0);

        delta_valid     : out std_logic;

        

        -- Weight output (for error propagation calculation by previous layer)

        weight_for_prop : out signed(DATA_WIDTH-1 downto 0);

        weight_prop_idx : in  unsigned(3 downto 0);

        weight_prop_en  : in  std_logic;

        

        -- Backward status

        bwd_done        : out std_logic;

        bwd_busy        : out std_logic;

        

        -- ===================== WEIGHT UPDATE =====================

        upd_start       : in  std_logic;

        upd_clear       : in  std_logic;

        learning_rate   : in  signed(DATA_WIDTH-1 downto 0);

        upd_done        : out std_logic;

        upd_busy        : out std_logic;

        

        -- ===================== WEIGHT INIT/READ =====================

        weight_init_en  : in  std_logic;

        weight_init_idx : in  unsigned(3 downto 0);  -- 0 to NUM_INPUTS-1 = weights, NUM_INPUTS = bias

        weight_init_data: in  signed(DATA_WIDTH-1 downto 0);

        

        weight_read_en  : in  std_logic;

        weight_read_idx : in  unsigned(3 downto 0);

        weight_read_data: out signed(DATA_WIDTH-1 downto 0);

        

        -- ===================== STATUS =====================

        overflow        : out std_logic

    );

end entity single_neuron_tanh;



architecture rtl of single_neuron_tanh is



    ---------------------------------------------------------------------------

    -- FSM States

    ---------------------------------------------------------------------------

    type fwd_state_t is (FWD_IDLE, FWD_LOAD_INPUTS, FWD_DOT_PRODUCT, 

                         FWD_ADD_BIAS, FWD_ACTIVATE, FWD_DONE_ST);

    signal fwd_state : fwd_state_t;

    

    type bwd_state_t is (BWD_IDLE, BWD_CALC_DELTA, BWD_CALC_GRADIENTS, 

                         BWD_OUTPUT_DELTA, BWD_DONE_ST);

    signal bwd_state : bwd_state_t;

    

    type upd_state_t is (UPD_IDLE, UPD_UPDATE_WEIGHTS, UPD_UPDATE_BIAS, UPD_DONE_ST);

    signal upd_state : upd_state_t;
    signal upd_done_reg : std_logic := '0';  -- Register for pulse generation



    ---------------------------------------------------------------------------

    -- Weight and Bias Storage

    ---------------------------------------------------------------------------

    type weight_array_t is array (0 to NUM_INPUTS-1) of signed(DATA_WIDTH-1 downto 0);

    -- Small random-like initialization to break symmetry (using NEURON_ID for uniqueness)
    -- Values are small (~0.01 to 0.1) to prevent saturation and enable gradual learning
    -- Different per neuron (via NEURON_ID) to ensure neurons in same layer evolve differently
    -- Fix #11: Random weight initialization to break symmetry
    -- Each weight gets unique value using prime number sequence
    -- Range: approximately -0.3 to +0.3 in Q2.13 format
    function init_weight(neuron_id : integer; weight_idx : integer) return signed is
        variable seed : integer;
        variable val : integer;
    begin
        -- Use prime numbers to generate pseudo-random values
        seed := (neuron_id * 251 + weight_idx * 127) mod 4096;
        val := 2048 - seed;  -- Range: -2048 to +2048 (approx -0.25 to +0.25)
        return to_signed(val, DATA_WIDTH);
    end function;

    -- Function to initialize entire weight array
    function init_weights(neuron_id : integer; num_inputs : integer) return weight_array_t is
        variable result : weight_array_t;
    begin
        for i in 0 to num_inputs-1 loop
            result(i) := init_weight(neuron_id, i);
        end loop;
        return result;
    end function;

    signal weights : weight_array_t := init_weights(NEURON_ID, NUM_INPUTS);
    signal bias    : signed(DATA_WIDTH-1 downto 0) := init_weight(NEURON_ID, NUM_INPUTS);



    ---------------------------------------------------------------------------

    -- Gradient Storage

    ---------------------------------------------------------------------------

    type grad_array_t is array (0 to NUM_INPUTS-1) of signed(GRAD_WIDTH-1 downto 0);

    signal weight_gradients : grad_array_t := (others => (others => '0'));

    signal bias_gradient    : signed(GRAD_WIDTH-1 downto 0) := (others => '0');



    ---------------------------------------------------------------------------

    -- Input Buffer (stores inputs during forward pass for gradient calc)

    ---------------------------------------------------------------------------

    type input_buffer_t is array (0 to NUM_INPUTS-1) of signed(DATA_WIDTH-1 downto 0);

    signal input_buffer : input_buffer_t := (others => (others => '0'));

    signal inputs_loaded : unsigned(3 downto 0) := (others => '0');



    ---------------------------------------------------------------------------

    -- Forward Pass Registers

    ---------------------------------------------------------------------------

    signal accumulator : signed(ACCUM_WIDTH-1 downto 0) := (others => '0');

    signal dot_index   : unsigned(3 downto 0) := (others => '0');

    signal z_reg       : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    signal a_reg       : signed(DATA_WIDTH-1 downto 0) := (others => '0');



    ---------------------------------------------------------------------------

    -- Backward Pass Registers

    ---------------------------------------------------------------------------

    signal delta_reg   : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    signal grad_index  : unsigned(3 downto 0) := (others => '0');



    ---------------------------------------------------------------------------

    -- Weight Update Registers

    ---------------------------------------------------------------------------

    signal upd_index   : unsigned(3 downto 0) := (others => '0');

    signal learning_rate_latched : signed(DATA_WIDTH-1 downto 0) := (others => '0');



    ---------------------------------------------------------------------------

    -- Status

    ---------------------------------------------------------------------------

    signal overflow_reg : std_logic := '0';



    ---------------------------------------------------------------------------

    -- Constants

    ---------------------------------------------------------------------------

    constant SAT_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(32767, DATA_WIDTH);

    constant SAT_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-32768, DATA_WIDTH);

    constant ONE_Q213 : signed(DATA_WIDTH-1 downto 0) := to_signed(8192, DATA_WIDTH);



    ---------------------------------------------------------------------------

    -- Helper Functions

    ---------------------------------------------------------------------------

    function round_saturate(acc : signed(ACCUM_WIDTH-1 downto 0)) 

        return signed is

        variable rounded : signed(ACCUM_WIDTH-1 downto 0);

        variable shifted : signed(ACCUM_WIDTH-1 downto 0);

    begin

        -- Add 0.5 LSB for rounding (avoid integer overflow with shift_left)

        rounded := acc + shift_left(to_signed(1, ACCUM_WIDTH), FRAC_BITS-1);

        shifted := shift_right(rounded, FRAC_BITS);

        if shifted > resize(SAT_MAX, ACCUM_WIDTH) then

            return SAT_MAX;

        elsif shifted < resize(SAT_MIN, ACCUM_WIDTH) then

            return SAT_MIN;

        else

            return shifted(DATA_WIDTH-1 downto 0);

        end if;

    end function;

    

    -- Tanh activation function (piecewise linear approximation)
    -- tanh(x) ≈ { -1 for x < -3
    --           { x/2.5 for -3 ≤ x < 3  (simplified linear)
    --           { 1 for x ≥ 3
    -- More accurate piecewise segments:
    function tanh_approx(x : signed(DATA_WIDTH-1 downto 0)) return signed is
        constant NEG_THREE : signed(DATA_WIDTH-1 downto 0) := to_signed(-3 * 8192, DATA_WIDTH);  -- -3.0 in Q2.13
        constant NEG_TWO : signed(DATA_WIDTH-1 downto 0) := to_signed(-2 * 8192, DATA_WIDTH);    -- -2.0
        constant NEG_ONE : signed(DATA_WIDTH-1 downto 0) := to_signed(-1 * 8192, DATA_WIDTH);    -- -1.0
        constant POS_ONE : signed(DATA_WIDTH-1 downto 0) := to_signed(1 * 8192, DATA_WIDTH);     --  1.0
        constant POS_TWO : signed(DATA_WIDTH-1 downto 0) := to_signed(2 * 8192, DATA_WIDTH);     --  2.0
        constant POS_THREE : signed(DATA_WIDTH-1 downto 0) := to_signed(3 * 8192, DATA_WIDTH);   --  3.0
        constant TANH_MAX : signed(DATA_WIDTH-1 downto 0) := to_signed(8192, DATA_WIDTH);        --  1.0
        constant TANH_MIN : signed(DATA_WIDTH-1 downto 0) := to_signed(-8192, DATA_WIDTH);       -- -1.0
        variable result : signed(2*DATA_WIDTH-1 downto 0);
    begin
        if x < NEG_TWO then
            return TANH_MIN;  -- Saturate at -1.0
        elsif x < to_signed(0, DATA_WIDTH) then
            -- Linear approximation: result = 0.6*x
            result := x * to_signed(4915, DATA_WIDTH);  -- 0.6 in Q2.13
            return result(DATA_WIDTH+12 downto 13);  -- Scale back
        elsif x < POS_TWO then
            -- Linear approximation: result = 0.6*x
            result := x * to_signed(4915, DATA_WIDTH);  -- 0.6 in Q2.13
            return result(DATA_WIDTH+12 downto 13);  -- Scale back
        else
            return TANH_MAX;  -- Saturate at 1.0
        end if;
    end function;

    -- Tanh derivative: 1 - tanh^2(x)
    -- Approximation: For the linear region (-2 to 2), derivative ≈ 0.6
    function tanh_derivative(z : signed(DATA_WIDTH-1 downto 0)) return signed is
        constant NEG_TWO : signed(DATA_WIDTH-1 downto 0) := to_signed(-2 * 8192, DATA_WIDTH);
        constant POS_TWO : signed(DATA_WIDTH-1 downto 0) := to_signed(2 * 8192, DATA_WIDTH);
    begin
        if z >= NEG_TWO and z <= POS_TWO then
            return to_signed(4915, DATA_WIDTH);  -- 0.6 in Q2.13
        else
            return to_signed(410, DATA_WIDTH);  -- 0.05 in Q2.13 (small gradient at saturation)
        end if;
    end function;



begin



    ---------------------------------------------------------------------------

    -- FORWARD PASS FSM

    ---------------------------------------------------------------------------

    process(clk)

        variable product : signed(2*DATA_WIDTH-1 downto 0);

        variable product_ext : signed(ACCUM_WIDTH-1 downto 0);

        variable sum : signed(ACCUM_WIDTH downto 0);

        variable bias_ext : signed(ACCUM_WIDTH-1 downto 0);

        variable sat_val : signed(ACCUM_WIDTH-1 downto 0);

    begin

        if rising_edge(clk) then

            if rst = '1' then

                fwd_state     <= FWD_IDLE;

                input_buffer  <= (others => (others => '0'));

                inputs_loaded <= (others => '0');

                accumulator   <= (others => '0');

                dot_index     <= (others => '0');

                z_reg         <= (others => '0');

                a_reg         <= (others => '0');

                overflow_reg  <= '0';  -- Clear overflow on reset

            else

                case fwd_state is

                

                    when FWD_IDLE =>

                        if fwd_clear = '1' then

                            inputs_loaded <= (others => '0');

                            accumulator   <= (others => '0');

                            overflow_reg  <= '0';  -- Clear overflow flag

                            input_buffer  <= (others => (others => '0'));  -- Clear stale inputs

                        elsif fwd_start = '1' then

                            inputs_loaded <= (others => '0');

                            overflow_reg  <= '0';  -- Clear overflow flag on new forward pass

                            fwd_state <= FWD_LOAD_INPUTS;

                        end if;

                    

                    when FWD_LOAD_INPUTS =>

                        if fwd_clear = '1' then

                            fwd_state <= FWD_IDLE;

                        elsif input_valid = '1' then

                            if to_integer(input_index) < NUM_INPUTS then

                                input_buffer(to_integer(input_index)) <= input_data;

                            end if;

                            inputs_loaded <= inputs_loaded + 1;

                            

                            if inputs_loaded = to_unsigned(NUM_INPUTS-1, 4) then

                                -- All inputs loaded, start dot product

                                accumulator <= (others => '0');

                                dot_index   <= (others => '0');

                                fwd_state   <= FWD_DOT_PRODUCT;

                            end if;

                        end if;

                    

                    when FWD_DOT_PRODUCT =>

                        if fwd_clear = '1' then

                            fwd_state <= FWD_IDLE;

                        elsif dot_index < NUM_INPUTS then

                            -- MAC: accumulator += weight Ã- input

                            product := weights(to_integer(dot_index)) * 

                                      input_buffer(to_integer(dot_index));

                            product_ext := resize(product, ACCUM_WIDTH);

                            sum := resize(accumulator, ACCUM_WIDTH+1) +

                                   resize(product_ext, ACCUM_WIDTH+1);



                            -- Saturate accumulator on overflow

                            if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then

                                overflow_reg <= '1';

                                if sum(ACCUM_WIDTH) = '0' then

                                    -- Positive overflow (0x7FFFFF...)

                                    sat_val := (others => '1');
                                    sat_val(ACCUM_WIDTH-1) := '0';
                                    accumulator <= sat_val;

                                else

                                    -- Negative overflow (0x800000...)

                                    sat_val := (others => '0');
                                    sat_val(ACCUM_WIDTH-1) := '1';
                                    accumulator <= sat_val;

                                end if;

                            else

                                accumulator <= sum(ACCUM_WIDTH-1 downto 0);

                            end if;

                            dot_index <= dot_index + 1;

                        else

                            fwd_state <= FWD_ADD_BIAS;

                        end if;

                    

                    when FWD_ADD_BIAS =>

                        if fwd_clear = '1' then

                            fwd_state <= FWD_IDLE;

                        else

                            -- Add bias (scale from Q2.13 to Q4.26)

                            bias_ext := shift_left(resize(bias, ACCUM_WIDTH), FRAC_BITS);

                            sum := resize(accumulator, ACCUM_WIDTH+1) +

                                   resize(bias_ext, ACCUM_WIDTH+1);



                            -- Saturate on overflow before rounding

                            if sum(ACCUM_WIDTH) /= sum(ACCUM_WIDTH-1) then

                                overflow_reg <= '1';

                                if sum(ACCUM_WIDTH) = '0' then

                                    -- Positive overflow

                                    sat_val := (others => '1');
                                    sat_val(ACCUM_WIDTH-1) := '0';
                                    z_reg <= round_saturate(sat_val);

                                else

                                    -- Negative overflow

                                    sat_val := (others => '0');
                                    sat_val(ACCUM_WIDTH-1) := '1';
                                    z_reg <= round_saturate(sat_val);

                                end if;

                            else

                                -- Round and saturate to get z

                                z_reg <= round_saturate(sum(ACCUM_WIDTH-1 downto 0));

                            end if;



                            fwd_state <= FWD_ACTIVATE;

                        end if;

                    

                    when FWD_ACTIVATE =>

                        if fwd_clear = '1' then

                            fwd_state <= FWD_IDLE;

                        else

                            -- Apply ReLU

                            a_reg <= tanh_approx(z_reg);

                            fwd_state <= FWD_DONE_ST;

                        end if;

                    

                    when FWD_DONE_ST =>

                        if fwd_clear = '1' or fwd_start = '1' then

                            if fwd_start = '1' then

                                inputs_loaded <= (others => '0');

                                fwd_state <= FWD_LOAD_INPUTS;

                            else

                                fwd_state <= FWD_IDLE;

                            end if;

                        end if;

                    

                    when others =>

                        fwd_state <= FWD_IDLE;

                        

                end case;

            end if;

        end if;

    end process;



    ---------------------------------------------------------------------------

    -- BACKWARD PASS FSM

    ---------------------------------------------------------------------------

    process(clk)

        variable delta_product : signed(2*DATA_WIDTH-1 downto 0);

        variable grad_product  : signed(2*DATA_WIDTH-1 downto 0);

        variable deriv         : signed(DATA_WIDTH-1 downto 0);

    begin

        if rising_edge(clk) then

            if rst = '1' then

                bwd_state        <= BWD_IDLE;

                delta_reg        <= (others => '0');

                grad_index       <= (others => '0');

                weight_gradients <= (others => (others => '0'));

                bias_gradient    <= (others => '0');

            else

                case bwd_state is

                

                    when BWD_IDLE =>

                        if bwd_clear = '1' then

                            weight_gradients <= (others => (others => '0'));

                            bias_gradient    <= (others => '0');

                        elsif bwd_start = '1' then

                            bwd_state <= BWD_CALC_DELTA;

                        end if;

                    

                    when BWD_CALC_DELTA =>

                        if bwd_clear = '1' then

                            bwd_state <= BWD_IDLE;

                        elsif error_valid = '1' then

                            -- Î´ = error Ã- Ïƒ'(z)

                            deriv := tanh_derivative(z_reg);

                            delta_product := error_in * deriv;



                            -- Saturate before extracting to Q2.13 format

                            -- Check if result fits in Q2.13 after extraction

                            if delta_product(2*DATA_WIDTH-1) = '0' then

                                -- Positive: check if upper bits exceed Q2.13 max

                                if delta_product(2*DATA_WIDTH-2 downto DATA_WIDTH+FRAC_BITS) /=

                                   (2*DATA_WIDTH-2 downto DATA_WIDTH+FRAC_BITS => '0') then

                                    delta_reg <= SAT_MAX;

                                    overflow_reg <= '1';

                                else

                                    delta_reg <= delta_product(DATA_WIDTH+FRAC_BITS-1 downto FRAC_BITS);

                                end if;

                            else

                                -- Negative: check if upper bits exceed Q2.13 min

                                if delta_product(2*DATA_WIDTH-2 downto DATA_WIDTH+FRAC_BITS) /=

                                   (2*DATA_WIDTH-2 downto DATA_WIDTH+FRAC_BITS => '1') then

                                    delta_reg <= SAT_MIN;

                                    overflow_reg <= '1';

                                else

                                    delta_reg <= delta_product(DATA_WIDTH+FRAC_BITS-1 downto FRAC_BITS);

                                end if;

                            end if;



                            grad_index <= (others => '0');

                            bwd_state <= BWD_CALC_GRADIENTS;

                        end if;

                    

                    when BWD_CALC_GRADIENTS =>

                        if bwd_clear = '1' then

                            bwd_state <= BWD_IDLE;

                        elsif grad_index < NUM_INPUTS then

                            -- âˆ‡W[i] = Î´ Ã- input[i]

                            grad_product := delta_reg * input_buffer(to_integer(grad_index));

                            weight_gradients(to_integer(grad_index)) <= 

                                resize(grad_product, GRAD_WIDTH);

                            grad_index <= grad_index + 1;

                        else

                            -- Bias gradient = Î´ (shifted to gradient format)

                            bias_gradient <= resize(delta_reg, GRAD_WIDTH);

                            bwd_state <= BWD_OUTPUT_DELTA;

                        end if;

                    

                    when BWD_OUTPUT_DELTA =>

                        if bwd_clear = '1' then

                            bwd_state <= BWD_IDLE;

                        else

                            bwd_state <= BWD_DONE_ST;

                        end if;

                    

                    when BWD_DONE_ST =>

                        if bwd_clear = '1' or bwd_start = '1' then

                            if bwd_start = '1' then

                                bwd_state <= BWD_CALC_DELTA;

                            else

                                bwd_state <= BWD_IDLE;

                            end if;

                        end if;

                    

                    when others =>

                        bwd_state <= BWD_IDLE;

                        

                end case;

            end if;

        end if;

    end process;



    ---------------------------------------------------------------------------

    -- WEIGHT UPDATE FSM

    ---------------------------------------------------------------------------

    process(clk)

        variable lr_times_grad : signed(DATA_WIDTH + GRAD_WIDTH - 1 downto 0);

        variable scaled_update : signed(DATA_WIDTH-1 downto 0);

        variable new_weight    : signed(DATA_WIDTH downto 0);

    begin

        if rising_edge(clk) then

            if rst = '1' then

                upd_state <= UPD_IDLE;

                upd_index <= (others => '0');

            else

                case upd_state is

                

                    when UPD_IDLE =>
                        upd_done_reg <= '0';  -- Clear pulse at state entry

                        if weight_init_en = '1' then

                            -- Weight initialization (merged to avoid multiple drivers)

                            if to_integer(weight_init_idx) < NUM_INPUTS then

                                weights(to_integer(weight_init_idx)) <= weight_init_data;

                            elsif to_integer(weight_init_idx) = NUM_INPUTS then

                                bias <= weight_init_data;

                            end if;

                        elsif upd_clear = '1' then

                            -- Nothing to clear

                        elsif upd_start = '1' then

                            learning_rate_latched <= learning_rate;  -- Latch LR to prevent mid-update changes

                            -- If LR is zero, skip update entirely and go directly to DONE

                            if learning_rate = to_signed(0, DATA_WIDTH) then

                                upd_state <= UPD_DONE_ST;
                                upd_done_reg <= '1';  -- Pulse upd_done for completion

                            else

                                upd_index <= (others => '0');

                                upd_state <= UPD_UPDATE_WEIGHTS;

                            end if;

                        end if;

                    

                    when UPD_UPDATE_WEIGHTS =>
                        upd_done_reg <= '0';  -- Clear pulse at state entry

                        if upd_clear = '1' then

                            upd_state <= UPD_IDLE;

                        elsif upd_index < NUM_INPUTS then

                            -- Check if learning rate is zero - skip update
                            if learning_rate_latched = to_signed(0, DATA_WIDTH) then
                                upd_index <= upd_index + 1;  -- Just advance, no update
                            else
                                -- W = W - Î· Ã- âˆ‡W

                                lr_times_grad := learning_rate_latched * weight_gradients(to_integer(upd_index));

                            -- Scale from Q12.39 to Q2.13 (shift right by 26)

                            scaled_update := lr_times_grad(DATA_WIDTH + FRAC_BITS*2 - 1 downto FRAC_BITS*2);

                            

                            new_weight := resize(weights(to_integer(upd_index)), DATA_WIDTH+1) -

                                         resize(scaled_update, DATA_WIDTH+1);

                            

                            -- Saturate

                            if new_weight > resize(SAT_MAX, DATA_WIDTH+1) then

                                weights(to_integer(upd_index)) <= SAT_MAX;

                            elsif new_weight < resize(SAT_MIN, DATA_WIDTH+1) then

                                weights(to_integer(upd_index)) <= SAT_MIN;

                            else

                                weights(to_integer(upd_index)) <= new_weight(DATA_WIDTH-1 downto 0);

                            end if;

                                upd_index <= upd_index + 1;
                            end if;  -- End LR=0 check

                        else

                            upd_state <= UPD_UPDATE_BIAS;

                        end if;

                    

                    when UPD_UPDATE_BIAS =>
                        upd_done_reg <= '0';  -- Clear pulse at state entry

                        if upd_clear = '1' then

                            upd_state <= UPD_IDLE;

                        else

                            -- Check if learning rate is zero - skip update
                            if learning_rate_latched = to_signed(0, DATA_WIDTH) then
                                upd_state <= UPD_DONE_ST;  -- Skip update, go directly to done
                                upd_done_reg <= '1';  -- Pulse upd_done for completion
                            else
                                -- b = b - Î· Ã- âˆ‡b

                                lr_times_grad := learning_rate_latched * bias_gradient;

                                scaled_update := lr_times_grad(DATA_WIDTH + FRAC_BITS*2 - 1 downto FRAC_BITS*2);



                                new_weight := resize(bias, DATA_WIDTH+1) -

                                             resize(scaled_update, DATA_WIDTH+1);



                                if new_weight > resize(SAT_MAX, DATA_WIDTH+1) then

                                    bias <= SAT_MAX;

                                elsif new_weight < resize(SAT_MIN, DATA_WIDTH+1) then

                                    bias <= SAT_MIN;

                                else

                                    bias <= new_weight(DATA_WIDTH-1 downto 0);

                                end if;



                                upd_state <= UPD_DONE_ST;
                                upd_done_reg <= '1';  -- Pulse upd_done for completion
                            end if;  -- End LR=0 check

                        end if;

                    

                    when UPD_DONE_ST =>
                        upd_done_reg <= '0';  -- Clear pulse at state entry

                        if weight_init_en = '1' then

                            -- Weight initialization (allow in DONE state too)

                            if to_integer(weight_init_idx) < NUM_INPUTS then

                                weights(to_integer(weight_init_idx)) <= weight_init_data;

                            elsif to_integer(weight_init_idx) = NUM_INPUTS then

                                bias <= weight_init_data;

                            end if;

                        elsif upd_clear = '1' or upd_start = '1' then

                            if upd_start = '1' then

                                learning_rate_latched <= learning_rate;

                                -- If LR is zero, skip update entirely and stay in DONE

                                if learning_rate = to_signed(0, DATA_WIDTH) then

                                    upd_state <= UPD_DONE_ST;  -- Stay in same state
                                    upd_done_reg <= '1';  -- Pulse upd_done to signal completion

                                else

                                    upd_index <= (others => '0');

                                    upd_state <= UPD_UPDATE_WEIGHTS;

                                end if;

                            else

                                upd_state <= UPD_IDLE;

                            end if;

                        end if;

                    

                    when others =>

                        upd_state <= UPD_IDLE;

                        

                end case;

            end if;

        end if;

    end process;



    ---------------------------------------------------------------------------

    -- Weight Read (initialization now handled in weight update FSM)

    ---------------------------------------------------------------------------



    -- Weight read for initialization verification or error propagation

    weight_read_data <= weights(to_integer(weight_read_idx)) 

                        when to_integer(weight_read_idx) < NUM_INPUTS 

                        else bias;

    

    -- Weight output for error propagation to previous layer

    weight_for_prop <= weights(to_integer(weight_prop_idx))

                       when weight_prop_en = '1' and to_integer(weight_prop_idx) < NUM_INPUTS

                       else (others => '0');



    ---------------------------------------------------------------------------

    -- Output Assignments

    ---------------------------------------------------------------------------

    -- Forward path

    z_out       <= z_reg;

    a_out       <= a_reg;

    fwd_done    <= '1' when fwd_state = FWD_DONE_ST else '0';

    fwd_busy    <= '0' when fwd_state = FWD_IDLE else '1';

    input_ready <= '1' when fwd_state = FWD_LOAD_INPUTS else '0';

    

    -- Backward path

    delta_out   <= delta_reg;

    delta_valid <= '1' when bwd_state = BWD_OUTPUT_DELTA or bwd_state = BWD_DONE_ST else '0';

    bwd_done    <= '1' when bwd_state = BWD_DONE_ST else '0';

    bwd_busy    <= '0' when bwd_state = BWD_IDLE else '1';

    

    -- Weight update

    upd_done    <= upd_done_reg;  -- Pulse signal instead of level

    upd_busy    <= '0' when upd_state = UPD_IDLE else '1';

    

    -- Status

    overflow    <= overflow_reg;



end architecture rtl;