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



entity single_neuron is

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

end entity single_neuron;



architecture rtl of single_neuron is



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



    ---------------------------------------------------------------------------

    -- Weight and Bias Storage

    ---------------------------------------------------------------------------

    type weight_array_t is array (0 to NUM_INPUTS-1) of signed(DATA_WIDTH-1 downto 0);

    -- Small random-like initialization to break symmetry (using NEURON_ID for uniqueness)
    -- Values are small (~0.01 to 0.1) to prevent saturation and enable gradual learning
    -- Different per neuron (via NEURON_ID) to ensure neurons in same layer evolve differently
    signal weights : weight_array_t := (
        others => to_signed(200 + NEURON_ID * 73, DATA_WIDTH)  -- ~0.024 to 0.051 depending on NEURON_ID
    );

    signal bias    : signed(DATA_WIDTH-1 downto 0) := to_signed(100 + NEURON_ID * 37, DATA_WIDTH);  -- ~0.012 to 0.018



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

    

    function relu(x : signed(DATA_WIDTH-1 downto 0)) return signed is

    begin

        if x(DATA_WIDTH-1) = '1' then

            return to_signed(0, DATA_WIDTH);

        else

            return x;

        end if;

    end function;

    

    function relu_derivative(z : signed(DATA_WIDTH-1 downto 0)) return signed is

    begin

        if z > 0 then

            return ONE_Q213;

        else

            return to_signed(0, DATA_WIDTH);

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

            else

                case fwd_state is

                

                    when FWD_IDLE =>

                        if fwd_clear = '1' then

                            inputs_loaded <= (others => '0');

                            accumulator   <= (others => '0');

                            overflow_reg  <= '0';  -- Clear overflow flag

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

                            -- MAC: accumulator += weight × input

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

                            a_reg <= relu(z_reg);

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

                            -- δ = error × σ'(z)

                            deriv := relu_derivative(z_reg);

                            delta_product := error_in * deriv;



                            -- Saturate before extracting to Q2.13 format

                            if delta_product > shift_left(resize(SAT_MAX, 2*DATA_WIDTH), FRAC_BITS) then

                                delta_reg <= SAT_MAX;

                                overflow_reg <= '1';

                            elsif delta_product < shift_left(resize(SAT_MIN, 2*DATA_WIDTH), FRAC_BITS) then

                                delta_reg <= SAT_MIN;

                                overflow_reg <= '1';

                            else

                                delta_reg <= delta_product(DATA_WIDTH+FRAC_BITS-1 downto FRAC_BITS);

                            end if;



                            grad_index <= (others => '0');

                            bwd_state <= BWD_CALC_GRADIENTS;

                        end if;

                    

                    when BWD_CALC_GRADIENTS =>

                        if bwd_clear = '1' then

                            bwd_state <= BWD_IDLE;

                        elsif grad_index < NUM_INPUTS then

                            -- ∇W[i] = δ × input[i]

                            grad_product := delta_reg * input_buffer(to_integer(grad_index));

                            weight_gradients(to_integer(grad_index)) <= 

                                resize(grad_product, GRAD_WIDTH);

                            grad_index <= grad_index + 1;

                        else

                            -- Bias gradient = δ (shifted to gradient format)

                            bias_gradient <= shift_left(resize(delta_reg, GRAD_WIDTH), FRAC_BITS);

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

                            upd_index <= (others => '0');

                            upd_state <= UPD_UPDATE_WEIGHTS;

                        end if;

                    

                    when UPD_UPDATE_WEIGHTS =>

                        if upd_clear = '1' then

                            upd_state <= UPD_IDLE;

                        elsif upd_index < NUM_INPUTS then

                            -- Check if learning rate is zero - skip update
                            if learning_rate = to_signed(0, DATA_WIDTH) then
                                upd_index <= upd_index + 1;  -- Just advance, no update
                            else
                                -- W = W - η × ∇W

                                lr_times_grad := learning_rate * weight_gradients(to_integer(upd_index));

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

                        if upd_clear = '1' then

                            upd_state <= UPD_IDLE;

                        else

                            -- Check if learning rate is zero - skip update
                            if learning_rate = to_signed(0, DATA_WIDTH) then
                                upd_state <= UPD_DONE_ST;  -- Skip update, go directly to done
                            else
                                -- b = b - η × ∇b

                                lr_times_grad := learning_rate * bias_gradient;

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
                            end if;  -- End LR=0 check

                        end if;

                    

                    when UPD_DONE_ST =>

                        if upd_clear = '1' or upd_start = '1' then

                            if upd_start = '1' then

                                upd_index <= (others => '0');

                                upd_state <= UPD_UPDATE_WEIGHTS;

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

    upd_done    <= '1' when upd_state = UPD_DONE_ST else '0';

    upd_busy    <= '0' when upd_state = UPD_IDLE else '1';

    

    -- Status

    overflow    <= overflow_reg;



end architecture rtl;
