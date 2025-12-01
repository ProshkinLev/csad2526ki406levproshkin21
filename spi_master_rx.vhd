library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--=============================================================================
-- ENTITY: spi_master_rx
-- Description: SPI Master Module (Receiver)
--              Implements Master logic to receive N bits of data.
--              Generates SCLK clock pulses and controls SS_n.
--              Reads data from i_miso.
--=============================================================================
entity spi_master_rx is
    generic (
        G_NBITS             : positive := 8;
        G_CLK_DIV_RATIO     : positive := 5; 
        G_CPOL              : std_logic := '0';
        G_CPHA              : std_logic := '0'
    );
    port (
        -- === Control Inputs ===
        i_clk               : in  std_logic;
        i_reset             : in  std_logic;
        i_start             : in  std_logic;
        
        -- === Input Data ===
        -- i_miso: Master Input Slave Output
        i_miso              : in  std_logic;
        
        -- === SPI Outputs ===
        o_sclk              : out std_logic;
        o_ss_n              : out std_logic;
        
        -- === Output Data ===
        -- o_data: Received data
        o_data              : out std_logic_vector(G_NBITS-1 downto 0);
        
        -- === Status Outputs ===
        o_busy              : out std_logic;
        o_done              : out std_logic
    );
end entity spi_master_rx;

architecture rtl of spi_master_rx is

    -- FSM State Definitions
    type t_state is (
        IDLE,           -- Waiting / Idle
        LOAD,           -- (Just loading the counter)
        ASSERT_SS,      -- Activate Slave Select
        PREP_CPHA0,     -- (CPHA=0) Wait for 1st SCLK
        ALIGN_CPHA1,    -- (CPHA=1) Wait for 1st SCLK
        SHIFT,          -- Shift and receive bits
        DONE_FRAME      -- Completion, outputting data
    );
    
    -- === Internal Registers and Signals === 
    signal r_state      : t_state := IDLE;
    signal r_next_state : t_state := IDLE;
    
    -- r_shreg_rx: Shift register for data reception
    signal r_shreg_rx   : std_logic_vector(G_NBITS-1 downto 0);
    
    -- r_bitcnt: Bit counter (down-counting from Nbits to 0)
    signal r_bitcnt     : integer range 0 to G_NBITS;
    
    -- r_sclk: Internal register for SCLK generation
    signal r_sclk       : std_logic := G_CPOL;
    
    -- r_clk_div_cnt: Counter for SCLK frequency divider
    signal r_clk_div_cnt: integer range 0 to G_CLK_DIV_RATIO-1;
    
    -- r_done_pulse: Register for generating o_done pulse
    signal r_done_pulse : std_logic;

    -- s_sclk_tick: Internal pulse indicating SCLK change
    signal s_sclk_tick  : std_logic;
    
    -- s_sample_edge: Pulse indicating the SCLK "Sample" edge
    signal s_sample_edge: std_logic;
    
    -- r_data_out: Register for output data (o_data)
    signal r_data_out   : std_logic_vector(G_NBITS-1 downto 0);

begin

    --=========================================================================
    -- PROCESS 1: Synchronous Logic (FSM Registers and SCLK Divider)
    --=========================================================================
    p_sync : process(i_clk, i_reset)
    begin
        if i_reset = '1' then
            -- Reset FSM and all registers
            r_state       <= IDLE;
            r_shreg_rx    <= (others => '0');
            r_data_out    <= (others => '0');
            r_bitcnt      <= 0;
            r_clk_div_cnt <= 0;
            r_sclk        <= G_CPOL; -- SCLK in 'idle' state
            r_done_pulse  <= '0';
            
        elsif rising_edge(i_clk) then
            
            r_state <= r_next_state;
            
            -- Generate o_done pulse
            r_done_pulse <= '0'; 
            if (r_next_state = DONE_FRAME) and (r_state /= DONE_FRAME) then
                r_done_pulse <= '1';
            end if;

            -- === SCLK Divider Logic ===
            if (r_state = SHIFT) then
                if r_clk_div_cnt = G_CLK_DIV_RATIO-1 then
                    r_clk_div_cnt <= 0;
                    r_sclk        <= not r_sclk; -- Toggle SCLK state
                else
                    r_clk_div_cnt <= r_clk_div_cnt + 1;
                end if;
            else
                r_clk_div_cnt <= 0; 
                r_sclk        <= G_CPOL;
            end if;

            -- === Register Logic (dependent on state) ===
            case r_state is
                when LOAD =>
                    r_bitcnt   <= G_NBITS; -- Set counter
                    r_shreg_rx <= (others => '0'); -- Clear receive register
                
                when SHIFT =>
                    -- Reception and shift occur on the SCLK "Sample" edge
                    if s_sample_edge = '1' then
                        -- Shift and receive i_miso into LSB (or MSB, depending on implementation)
                        -- This implementation receives MSB first.
                        r_shreg_rx <= r_shreg_rx(G_NBITS-2 downto 0) & i_miso;
                        r_bitcnt   <= r_bitcnt - 1;
                    end if;
                
                when DONE_FRAME =>
                    -- Latch received data to output
                    r_data_out <= r_shreg_rx;
                    
                when others =>
                    -- (IDLE, ASSERT_SS, PREP, ALIGN)
                    -- No register changes
            end case;
            
        end if;
    end process p_sync;
    
    
    -- Definition of "Tick" and "Sample Edge"
    s_sclk_tick <= '1' when (r_clk_div_cnt = G_CLK_DIV_RATIO-1) and (r_state = SHIFT) else '0';
    
    -- For reception (Rx), CPHA determines on which edge we *read*
    -- CPHA=0: Sample on 1st edge (r_sclk = not G_CPOL)
    -- CPHA=1: Sample on 2nd edge (r_sclk = G_CPOL)
    s_sample_edge <= '1' when (s_sclk_tick = '1') and ((G_CPHA = '0' and r_sclk = G_CPOL) or (G_CPHA = '1' and r_sclk /= G_CPOL)) else '0';

    
    --=========================================================================
    -- PROCESS 2: Combinational Logic (Outputs and Next State)
    --=========================================================================
    p_comb : process(r_state, i_start, r_bitcnt, r_done_pulse, r_data_out)
    begin
        -- === Default Values ===
        r_next_state <= r_state;
        o_busy       <= '1'; 
        o_ss_n       <= '1'; 
        o_done       <= r_done_pulse;
        o_data       <= r_data_out; -- Register output
        
        -- === FSM Logic (from diagram) ===
        case r_state is
            when IDLE =>
                o_busy <= '0';
                if i_start = '1' and r_done_pulse = '0' then
                    r_next_state <= LOAD;
                end if;

            when LOAD =>
                r_next_state <= ASSERT_SS;

            when ASSERT_SS =>
                o_ss_n <= '0'; -- Activate SS_n (active low)
                -- For Rx it doesn't matter when to start, but we follow the FSM
                if G_CPHA = '1' then
                    r_next_state <= ALIGN_CPHA1;
                else
                    r_next_state <= PREP_CPHA0;
                end if;

            when PREP_CPHA0 | ALIGN_CPHA1 =>
                o_ss_n <= '0';
                r_next_state <= SHIFT;

            when SHIFT =>
                o_ss_n <= '0';
                if r_bitcnt = 0 then
                    r_next_state <= DONE_FRAME;
                end if;

            when DONE_FRAME =>
                o_busy <= '0';
                o_ss_n <= '1'; -- Deactivate SS_n
                if i_start = '1' then
                    r_next_state <= LOAD;
                else
                    r_next_state <= IDLE;
                end if;
                
        end case;
    end process p_comb;
    
    -- === Output Assignments ===
    o_sclk <= r_sclk;

end architecture rtl;