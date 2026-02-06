--------------------------------------------------------------------------------
-- Testbench: tb_backward_datapath
-- Description: Testbench for backward propagation datapath
--              Tests complete backprop through 4-2-1 network
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_backward_datapath is
end entity tb_backward_datapath;

architecture sim of tb_backward_datapath is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD  : time := 10 ns;
    constant DATA_WIDTH  : integer := 16;
    constant GRAD_WIDTH  : integer := 32;
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
    
    signal target_in        : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal target_valid     : std_logic := '0';
    signal actual_in        : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    signal weight_rd_data   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal weight_rd_addr   : unsigned(3 downto 0);
    signal weight_rd_en     : std_logic;
    
    signal cache_z_rd_data  : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal cache_z_rd_addr  : unsigned(1 downto 0);
    signal cache_z_rd_en    : std_logic;
    signal cache_a_rd_data  : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal cache_a_rd_addr  : unsigned(2 downto 0);
    signal cache_a_rd_en    : std_logic;
    
    signal grad_out         : signed(GRAD_WIDTH-1 downto 0);
    signal grad_addr        : unsigned(3 downto 0);
    signal grad_valid       : std_logic;
    signal grad_ready       : std_logic := '1';
    
    signal busy             : std_logic;
    signal done             : std_logic;
    signal current_layer    : unsigned(1 downto 0);
    signal overflow         : std_logic;

    ---------------------------------------------------------------------------
    -- Simulated Weight Memory (for error propagation)
    ---------------------------------------------------------------------------
    type weight_mem_t is array (0 to NUM_WEIGHTS-1) of signed(DATA_WIDTH-1 downto 0);
    signal weight_mem : weight_mem_t := (
        -- Layer 1 weights (not used for propagation)
        0 => to_signed(819, DATA_WIDTH),
        1 => to_signed(819, DATA_WIDTH),
        2 => to_signed(819, DATA_WIDTH),
        3 => to_signed(819, DATA_WIDTH),
        4 => to_signed(819, DATA_WIDTH),
        5 => to_signed(819, DATA_WIDTH),
        6 => to_signed(819, DATA_WIDTH),
        7 => to_signed(819, DATA_WIDTH),
        8 => to_signed(819, DATA_WIDTH),
        9 => to_signed(819, DATA_WIDTH),
        -- Layer 2 weights (used for error propagation)
        10 => to_signed(4915, DATA_WIDTH),  -- 0.6 * 8192
        11 => to_signed(5734, DATA_WIDTH),  -- 0.7 * 8192
        12 => to_signed(819, DATA_WIDTH)
    );

    ---------------------------------------------------------------------------
    -- Simulated Forward Cache
    -- Z values: z_hidden[0], z_hidden[1], z_output
    -- A values: x[0-3], a_hidden[0-1], a_output
    ---------------------------------------------------------------------------
    type z_cache_t is array (0 to 2) of signed(DATA_WIDTH-1 downto 0);
    signal z_cache : z_cache_t := (
        to_signed(3482, DATA_WIDTH),   -- z_hidden[0] = 0.425 * 8192
        to_signed(7373, DATA_WIDTH),   -- z_hidden[1] = 0.9 * 8192
        to_signed(8069, DATA_WIDTH)    -- z_output = 0.985 * 8192
    );

    type a_cache_t is array (0 to 6) of signed(DATA_WIDTH-1 downto 0);
    signal a_cache : a_cache_t := (
        to_signed(8192, DATA_WIDTH),   -- x[0] = 1.0
        to_signed(4096, DATA_WIDTH),   -- x[1] = 0.5
        to_signed(2048, DATA_WIDTH),   -- x[2] = 0.25
        to_signed(1024, DATA_WIDTH),   -- x[3] = 0.125
        to_signed(3482, DATA_WIDTH),   -- a_hidden[0] = 0.425
        to_signed(7373, DATA_WIDTH),   -- a_hidden[1] = 0.9
        to_signed(8069, DATA_WIDTH)    -- a_output = 0.985
    );

    ---------------------------------------------------------------------------
    -- Gradient Collection
    ---------------------------------------------------------------------------
    type grad_mem_t is array (0 to NUM_WEIGHTS-1) of signed(GRAD_WIDTH-1 downto 0);
    signal grad_mem : grad_mem_t := (others => (others => '0'));

    ---------------------------------------------------------------------------
    -- Test Control
    ---------------------------------------------------------------------------
    signal test_done : boolean := false;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : entity work.backward_datapath
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
            start            => start,
            clear            => clear,
            target_in        => target_in,
            target_valid     => target_valid,
            actual_in        => actual_in,
            weight_rd_data   => weight_rd_data,
            weight_rd_addr   => weight_rd_addr,
            weight_rd_en     => weight_rd_en,
            cache_z_rd_data  => cache_z_rd_data,
            cache_z_rd_addr  => cache_z_rd_addr,
            cache_z_rd_en    => cache_z_rd_en,
            cache_a_rd_data  => cache_a_rd_data,
            cache_a_rd_addr  => cache_a_rd_addr,
            cache_a_rd_en    => cache_a_rd_en,
            grad_out         => grad_out,
            grad_addr        => grad_addr,
            grad_valid       => grad_valid,
            grad_ready       => grad_ready,
            busy             => busy,
            done             => done,
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
    -- Z Cache Read Process
    ---------------------------------------------------------------------------
    z_cache_read_proc : process(clk)
    begin
        if rising_edge(clk) then
            if cache_z_rd_en = '1' then
                cache_z_rd_data <= z_cache(to_integer(cache_z_rd_addr));
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- A Cache Read Process
    ---------------------------------------------------------------------------
    a_cache_read_proc : process(clk)
    begin
        if rising_edge(clk) then
            if cache_a_rd_en = '1' then
                cache_a_rd_data <= a_cache(to_integer(cache_a_rd_addr));
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Gradient Collection Process
    ---------------------------------------------------------------------------
    grad_collect_proc : process(clk)
    begin
        if rising_edge(clk) then
            if grad_valid = '1' and grad_ready = '1' then
                grad_mem(to_integer(grad_addr)) <= grad_out;
                report "Gradient[" & integer'image(to_integer(grad_addr)) & 
                       "] = " & integer'image(to_integer(grad_out));
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Stimulus Process
    ---------------------------------------------------------------------------
    stim_proc : process
    begin
        -- Initial reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- Test 1: Backward pass with target = 1.0, actual = 0.985
        -- Error = 1.0 - 0.985 = 0.015
        report "Starting backward pass test...";
        report "Target: 1.0, Actual: 0.985, Error: 0.015";
        
        actual_in <= to_signed(8069, DATA_WIDTH);  -- 0.985 * 8192
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        -- Provide target value
        wait for CLK_PERIOD * 2;
        target_in <= to_signed(8192, DATA_WIDTH);  -- 1.0 * 8192
        target_valid <= '1';
        wait for CLK_PERIOD;
        target_valid <= '0';

        -- Wait for completion
        wait until done = '1';
        wait for CLK_PERIOD * 2;

        -- Report results
        report "Backward pass complete!";
        report "=== Computed Gradients ===";
        
        -- Display all gradients
        for i in 0 to NUM_WEIGHTS-1 loop
            report "Gradient[" & integer'image(i) & "] = " & 
                   integer'image(to_integer(grad_mem(i)));
        end loop;
        
        if overflow = '1' then
            report "WARNING: Overflow occurred during backward pass" severity warning;
        end if;

        -- Test 2: Different target (larger error)
        wait for CLK_PERIOD * 5;
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD * 2;

        report "Test 2: Backward pass with target = 0.0 (larger error)";
        
        actual_in <= to_signed(8069, DATA_WIDTH);  -- 0.985
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait for CLK_PERIOD * 2;
        target_in <= to_signed(0, DATA_WIDTH);  -- 0.0
        target_valid <= '1';
        wait for CLK_PERIOD;
        target_valid <= '0';

        wait until done = '1';
        wait for CLK_PERIOD * 2;

        report "Test 2 complete!";
        report "Error: -0.985 (target 0.0 - actual 0.985)";

        -- End simulation
        wait for CLK_PERIOD * 10;
        report "Backward datapath testbench complete!";
        test_done <= true;
        wait;
    end process;

end architecture sim;
