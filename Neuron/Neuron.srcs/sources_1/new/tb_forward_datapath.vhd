--------------------------------------------------------------------------------
-- Testbench: tb_forward_datapath
-- Description: Testbench for forward propagation datapath
--              Tests complete forward pass through 4-2-1 network
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_forward_datapath is
end entity tb_forward_datapath;

architecture sim of tb_forward_datapath is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD  : time := 10 ns;
    constant DATA_WIDTH  : integer := 16;
    constant ACCUM_WIDTH : integer := 40;
    constant FRAC_BITS   : integer := 13;
    constant NUM_INPUTS  : integer := 4;
    constant NUM_HIDDEN  : integer := 2;
    constant NUM_OUTPUTS : integer := 1;
    constant NUM_WEIGHTS : integer := 13;

    ---------------------------------------------------------------------------
    -- DUT Signals
    ---------------------------------------------------------------------------
    signal clk              : std_logic := '0';
    signal rst              : std_logic := '1';
    signal start            : std_logic := '0';
    signal clear            : std_logic := '0';
    
    signal input_data       : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal input_addr       : unsigned(1 downto 0) := (others => '0');
    signal input_valid      : std_logic := '0';
    signal input_ready      : std_logic;
    
    signal weight_rd_data   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal weight_rd_addr   : unsigned(3 downto 0);
    signal weight_rd_en     : std_logic;
    
    signal cache_z_wr_en    : std_logic;
    signal cache_z_wr_addr  : unsigned(1 downto 0);
    signal cache_z_wr_data  : signed(DATA_WIDTH-1 downto 0);
    signal cache_a_wr_en    : std_logic;
    signal cache_a_wr_addr  : unsigned(2 downto 0);
    signal cache_a_wr_data  : signed(DATA_WIDTH-1 downto 0);
    
    signal output_data      : signed(DATA_WIDTH-1 downto 0);
    signal output_valid     : std_logic;
    
    signal busy             : std_logic;
    signal done             : std_logic;
    signal layer_complete   : std_logic;
    signal current_layer    : unsigned(1 downto 0);
    signal overflow         : std_logic;

    ---------------------------------------------------------------------------
    -- Weight Memory (simulated)
    -- Memory Map:
    --   0-3:   Layer 1, Neuron 0 weights
    --   4-7:   Layer 1, Neuron 1 weights
    --   8-9:   Layer 1 biases
    --   10-11: Layer 2 weights
    --   12:    Layer 2 bias
    ---------------------------------------------------------------------------
    type weight_mem_t is array (0 to NUM_WEIGHTS-1) of signed(DATA_WIDTH-1 downto 0);
    signal weight_mem : weight_mem_t := (
        -- Layer 1, Neuron 0 weights (0.1, 0.2, 0.3, 0.4)
        to_signed(819, DATA_WIDTH),   -- 0.1 * 8192
        to_signed(1638, DATA_WIDTH),  -- 0.2 * 8192
        to_signed(2458, DATA_WIDTH),  -- 0.3 * 8192
        to_signed(3277, DATA_WIDTH),  -- 0.4 * 8192
        -- Layer 1, Neuron 1 weights (0.5, 0.4, 0.3, 0.2)
        to_signed(4096, DATA_WIDTH),  -- 0.5 * 8192
        to_signed(3277, DATA_WIDTH),  -- 0.4 * 8192
        to_signed(2458, DATA_WIDTH),  -- 0.3 * 8192
        to_signed(1638, DATA_WIDTH),  -- 0.2 * 8192
        -- Layer 1 biases (0.1, 0.1)
        to_signed(819, DATA_WIDTH),   -- 0.1 * 8192
        to_signed(819, DATA_WIDTH),   -- 0.1 * 8192
        -- Layer 2 weights (0.6, 0.7)
        to_signed(4915, DATA_WIDTH),  -- 0.6 * 8192
        to_signed(5734, DATA_WIDTH),  -- 0.7 * 8192
        -- Layer 2 bias (0.1)
        to_signed(819, DATA_WIDTH)    -- 0.1 * 8192
    );

    ---------------------------------------------------------------------------
    -- Test Input Values (1.0, 0.5, 0.25, 0.125)
    ---------------------------------------------------------------------------
    type input_array_t is array (0 to NUM_INPUTS-1) of signed(DATA_WIDTH-1 downto 0);
    signal test_inputs : input_array_t := (
        to_signed(8192, DATA_WIDTH),  -- 1.0 * 8192
        to_signed(4096, DATA_WIDTH),  -- 0.5 * 8192
        to_signed(2048, DATA_WIDTH),  -- 0.25 * 8192
        to_signed(1024, DATA_WIDTH)   -- 0.125 * 8192
    );

    ---------------------------------------------------------------------------
    -- Test Control
    ---------------------------------------------------------------------------
    signal test_done : boolean := false;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : entity work.forward_datapath
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
            start            => start,
            clear            => clear,
            input_data       => input_data,
            input_addr       => input_addr,
            input_valid      => input_valid,
            input_ready      => input_ready,
            weight_rd_data   => weight_rd_data,
            weight_rd_addr   => weight_rd_addr,
            weight_rd_en     => weight_rd_en,
            cache_z_wr_en    => cache_z_wr_en,
            cache_z_wr_addr  => cache_z_wr_addr,
            cache_z_wr_data  => cache_z_wr_data,
            cache_a_wr_en    => cache_a_wr_en,
            cache_a_wr_addr  => cache_a_wr_addr,
            cache_a_wr_data  => cache_a_wr_data,
            output_data      => output_data,
            output_valid     => output_valid,
            busy             => busy,
            done             => done,
            layer_complete   => layer_complete,
            current_layer    => current_layer,
            overflow         => overflow
        );

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk_proc : process
    begin
        while not test_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    ---------------------------------------------------------------------------
    -- Weight Memory Read Process
    ---------------------------------------------------------------------------
    weight_read_proc : process(clk)
    begin
        if rising_edge(clk) then
            if weight_rd_en = '1' then
                weight_rd_data <= weight_mem(to_integer(weight_rd_addr));
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Stimulus Process
    ---------------------------------------------------------------------------
    stim_proc : process
        variable expected_output : real;
    begin
        -- Initial reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- Start forward pass
        report "Starting forward pass test...";
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        -- Wait for input_ready (may already be high if state transitioned)
        if input_ready /= '1' then
            wait until input_ready = '1';
        end if;
        wait for CLK_PERIOD;  -- Ensure we're aligned to clock edge

        for i in 0 to NUM_INPUTS-1 loop
            input_data  <= test_inputs(i);
            input_addr  <= to_unsigned(i, 2);
            input_valid <= '1';
            wait for CLK_PERIOD;
        end loop;
        input_valid <= '0';

        -- Wait for completion
        wait until done = '1';
        wait for CLK_PERIOD;

        -- Report results
        report "Forward pass complete!";
        report "Output value: " & integer'image(to_integer(output_data));
        report "Output (Q2.13): " & real'image(real(to_integer(output_data)) / 8192.0);
        
        if overflow = '1' then
            report "WARNING: Overflow occurred during forward pass" severity warning;
        end if;

        -- Manual calculation for verification:
        -- Input: [1.0, 0.5, 0.25, 0.125]
        -- Layer 1, N0: z = 0.1*1 + 0.2*0.5 + 0.3*0.25 + 0.4*0.125 + 0.1 = 0.425
        --              a = ReLU(0.425) = 0.425
        -- Layer 1, N1: z = 0.5*1 + 0.4*0.5 + 0.3*0.25 + 0.2*0.125 + 0.1 = 0.9
        --              a = ReLU(0.9) = 0.9
        -- Layer 2:     z = 0.6*0.425 + 0.7*0.9 + 0.1 = 0.985
        --              a = ReLU(0.985) = 0.985
        -- Expected output ≈ 0.985 ≈ 8069 in Q2.13
        
        report "Expected output approximately: 0.985 (8069 in Q2.13)";

        -- Test 2: Clear and restart
        wait for CLK_PERIOD * 5;
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD * 2;

        report "Test 2: Second forward pass with same inputs...";
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        if input_ready /= '1' then
            wait until input_ready = '1';
        end if;
        wait for CLK_PERIOD;

        for i in 0 to NUM_INPUTS-1 loop
            input_data  <= test_inputs(i);
            input_addr  <= to_unsigned(i, 2);
            input_valid <= '1';
            wait for CLK_PERIOD;
        end loop;
        input_valid <= '0';

        wait until done = '1';
        wait for CLK_PERIOD;

        report "Second forward pass complete!";
        report "Output value: " & integer'image(to_integer(output_data));

        -- End simulation
        wait for CLK_PERIOD * 10;
        report "Forward datapath testbench complete!";
        test_done <= true;
        wait;
    end process;

end architecture sim;
