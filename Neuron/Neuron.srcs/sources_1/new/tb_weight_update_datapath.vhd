--------------------------------------------------------------------------------
-- Testbench: tb_weight_update_datapath
-- Description: Testbench for weight update datapath
--              Tests SGD weight updates for 4-2-1 network
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_weight_update_datapath is
end entity tb_weight_update_datapath;

architecture sim of tb_weight_update_datapath is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD    : time := 10 ns;
    constant DATA_WIDTH    : integer := 16;
    constant GRAD_WIDTH    : integer := 40;
    constant FRAC_BITS     : integer := 13;
    constant GRAD_FRAC_BITS: integer := 26;
    constant NUM_PARAMS    : integer := 13;
    constant ADDR_WIDTH    : integer := 4;

    ---------------------------------------------------------------------------
    -- DUT Signals
    ---------------------------------------------------------------------------
    signal clk              : std_logic := '0';
    signal rst              : std_logic := '1';
    signal start            : std_logic := '0';
    signal clear            : std_logic := '0';
    
    signal learning_rate    : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal use_default_lr   : std_logic := '1';
    
    signal weight_rd_data   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal weight_rd_addr   : unsigned(ADDR_WIDTH-1 downto 0);
    signal weight_rd_en     : std_logic;
    signal weight_wr_data   : signed(DATA_WIDTH-1 downto 0);
    signal weight_wr_addr   : unsigned(ADDR_WIDTH-1 downto 0);
    signal weight_wr_en     : std_logic;
    
    signal grad_rd_data     : signed(GRAD_WIDTH-1 downto 0) := (others => '0');
    signal grad_rd_addr     : unsigned(ADDR_WIDTH-1 downto 0);
    signal grad_rd_en       : std_logic;
    signal grad_clear       : std_logic;
    
    signal busy             : std_logic;
    signal done             : std_logic;
    signal param_count      : unsigned(ADDR_WIDTH-1 downto 0);
    signal overflow         : std_logic;

    ---------------------------------------------------------------------------
    -- Simulated Weight Register Bank
    ---------------------------------------------------------------------------
    type weight_mem_t is array (0 to NUM_PARAMS-1) of signed(DATA_WIDTH-1 downto 0);
    signal weight_mem : weight_mem_t := (
        -- Initial weights (all 0.5 for simplicity)
        to_signed(4096, DATA_WIDTH),   -- 0.5 * 8192
        to_signed(4096, DATA_WIDTH),
        to_signed(4096, DATA_WIDTH),
        to_signed(4096, DATA_WIDTH),
        to_signed(4096, DATA_WIDTH),
        to_signed(4096, DATA_WIDTH),
        to_signed(4096, DATA_WIDTH),
        to_signed(4096, DATA_WIDTH),
        to_signed(4096, DATA_WIDTH),   -- biases
        to_signed(4096, DATA_WIDTH),
        to_signed(4096, DATA_WIDTH),
        to_signed(4096, DATA_WIDTH),
        to_signed(4096, DATA_WIDTH)
    );
    
    -- Copy for verification
    signal weight_mem_before : weight_mem_t;

    ---------------------------------------------------------------------------
    -- Simulated Gradient Register Bank (Q10.26 format)
    ---------------------------------------------------------------------------
    type grad_mem_t is array (0 to NUM_PARAMS-1) of signed(GRAD_WIDTH-1 downto 0);
    signal grad_mem : grad_mem_t := (
        -- Gradients (various values, scaled to Q10.26)
        -- 0.1 in Q10.26 = 0.1 * 2^26 = 6710886
        to_signed(6710886, GRAD_WIDTH),    -- 0.1
        to_signed(3355443, GRAD_WIDTH),    -- 0.05
        to_signed(-3355443, GRAD_WIDTH),   -- -0.05
        to_signed(6710886, GRAD_WIDTH),    -- 0.1
        to_signed(-6710886, GRAD_WIDTH),   -- -0.1
        to_signed(1677722, GRAD_WIDTH),    -- 0.025
        to_signed(-1677722, GRAD_WIDTH),   -- -0.025
        to_signed(0, GRAD_WIDTH),          -- 0
        to_signed(3355443, GRAD_WIDTH),    -- 0.05 (bias grad)
        to_signed(-3355443, GRAD_WIDTH),   -- -0.05
        to_signed(6710886, GRAD_WIDTH),    -- 0.1
        to_signed(-6710886, GRAD_WIDTH),   -- -0.1
        to_signed(1677722, GRAD_WIDTH)     -- 0.025
    );

    ---------------------------------------------------------------------------
    -- Test Control
    ---------------------------------------------------------------------------
    signal test_done : boolean := false;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : entity work.weight_update_datapath
        generic map (
            DATA_WIDTH     => DATA_WIDTH,
            GRAD_WIDTH     => GRAD_WIDTH,
            FRAC_BITS      => FRAC_BITS,
            GRAD_FRAC_BITS => GRAD_FRAC_BITS,
            NUM_PARAMS     => NUM_PARAMS,
            ADDR_WIDTH     => ADDR_WIDTH
        )
        port map (
            clk              => clk,
            rst              => rst,
            start            => start,
            clear            => clear,
            learning_rate    => learning_rate,
            use_default_lr   => use_default_lr,
            weight_rd_data   => weight_rd_data,
            weight_rd_addr   => weight_rd_addr,
            weight_rd_en     => weight_rd_en,
            weight_wr_data   => weight_wr_data,
            weight_wr_addr   => weight_wr_addr,
            weight_wr_en     => weight_wr_en,
            grad_rd_data     => grad_rd_data,
            grad_rd_addr     => grad_rd_addr,
            grad_rd_en       => grad_rd_en,
            grad_clear       => grad_clear,
            busy             => busy,
            done             => done,
            param_count      => param_count,
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
    -- Weight Memory Read/Write Process
    ---------------------------------------------------------------------------
    weight_mem_proc : process(clk)
    begin
        if rising_edge(clk) then
            if weight_rd_en = '1' then
                weight_rd_data <= weight_mem(to_integer(weight_rd_addr));
            end if;
            
            if weight_wr_en = '1' then
                weight_mem(to_integer(weight_wr_addr)) <= weight_wr_data;
                report "Weight[" & integer'image(to_integer(weight_wr_addr)) & 
                       "] updated: " & integer'image(to_integer(weight_wr_data)) &
                       " (was " & integer'image(to_integer(weight_mem_before(to_integer(weight_wr_addr)))) & ")";
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Gradient Memory Read Process
    -- Note: grad_mem is driven only by stim_proc to avoid multiple drivers.
    --       grad_clear signal is monitored for reporting only.
    ---------------------------------------------------------------------------
    grad_mem_proc : process(clk)
    begin
        if rising_edge(clk) then
            if grad_rd_en = '1' then
                grad_rd_data <= grad_mem(to_integer(grad_rd_addr));
            end if;

            if grad_clear = '1' then
                report "Gradient clear signal asserted by DUT";
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Stimulus Process
    ---------------------------------------------------------------------------
    stim_proc : process
        variable expected_update : real;
        variable lr_real : real := 0.01;  -- Default learning rate
    begin
        -- Initial reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- Save initial weights for comparison
        weight_mem_before <= weight_mem;

        -- Test 1: Weight update with default learning rate (0.01)
        report "=== Test 1: Weight update with default LR (0.01) ===";
        report "Initial weights all = 0.5 (4096 in Q2.13)";
        
        use_default_lr <= '1';
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        -- Wait for completion
        wait until done = '1';
        wait for CLK_PERIOD * 2;

        -- Report results
        report "Weight update complete!";
        report "=== Updated Weights ===";
        
        for i in 0 to NUM_PARAMS-1 loop
            report "Weight[" & integer'image(i) & "]: " & 
                   integer'image(to_integer(weight_mem_before(i))) & " -> " &
                   integer'image(to_integer(weight_mem(i))) &
                   " (diff: " & integer'image(to_integer(weight_mem(i)) - to_integer(weight_mem_before(i))) & ")";
        end loop;
        
        if overflow = '1' then
            report "WARNING: Overflow occurred during weight update" severity warning;
        end if;

        -- Verify grad_clear was asserted
        if grad_clear = '0' then
            report "Note: Gradient clear signal should have been asserted";
        end if;

        -- Test 2: Weight update with custom learning rate (0.1)
        wait for CLK_PERIOD * 10;
        
        report "=== Test 2: Weight update with custom LR (0.1) ===";
        
        -- Reset gradients for second test
        grad_mem <= (
            to_signed(6710886, GRAD_WIDTH),    -- 0.1
            to_signed(3355443, GRAD_WIDTH),    -- 0.05
            to_signed(-3355443, GRAD_WIDTH),   -- -0.05
            to_signed(6710886, GRAD_WIDTH),    -- 0.1
            to_signed(-6710886, GRAD_WIDTH),   -- -0.1
            to_signed(1677722, GRAD_WIDTH),    -- 0.025
            to_signed(-1677722, GRAD_WIDTH),   -- -0.025
            to_signed(0, GRAD_WIDTH),          -- 0
            to_signed(3355443, GRAD_WIDTH),    -- 0.05
            to_signed(-3355443, GRAD_WIDTH),   -- -0.05
            to_signed(6710886, GRAD_WIDTH),    -- 0.1
            to_signed(-6710886, GRAD_WIDTH),   -- -0.1
            to_signed(1677722, GRAD_WIDTH)     -- 0.025
        );
        
        -- Save current weights
        weight_mem_before <= weight_mem;
        
        -- Set custom learning rate: 0.1 * 8192 = 819
        learning_rate <= to_signed(819, DATA_WIDTH);
        use_default_lr <= '0';
        
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait until done = '1';
        wait for CLK_PERIOD * 2;

        report "Second weight update complete (LR = 0.1)!";
        report "=== Updated Weights ===";
        
        for i in 0 to NUM_PARAMS-1 loop
            report "Weight[" & integer'image(i) & "]: " & 
                   integer'image(to_integer(weight_mem_before(i))) & " -> " &
                   integer'image(to_integer(weight_mem(i)));
        end loop;

        -- Test 3: Clear and verify reset
        wait for CLK_PERIOD * 5;
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD * 2;
        
        report "Datapath cleared";

        -- End simulation
        wait for CLK_PERIOD * 10;
        report "Weight update datapath testbench complete!";
        test_done <= true;
        wait;
    end process;

end architecture sim;
