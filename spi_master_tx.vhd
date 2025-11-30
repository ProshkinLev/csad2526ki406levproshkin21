-- Connection of standard IEEE libraries
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--=============================================================================
-- ENTITY: spi_master_tx
-- Description: SPI Master Module (Transmitter)
--              Implements Master logic for transmitting N bits of data.
--              Generates SCLK clock pulses and controls SS_n.
--              FSM is based on the provided diagram.
--=============================================================================
entity spi_master_tx is
    generic (
        -- Number of bits in the frame (from diagram "Nbits")
        G_NBITS             : positive := 8;
        -- Divider ratio for SCLK
        -- SCLK_freq = CLK_freq / (2 * G_CLK_DIV_RATIO)
        G_CLK_DIV_RATIO     : positive := 5; 
        -- CPOL: Clock signal polarity (0 = idle low, 1 = idle high)
        G_CPOL              : std_logic := '0';
        -- CPHA: Clock signal phase (0 = sample 1st edge, 1 = sample 2nd edge)
        G_CPHA              : std_logic := '0'
    );
    port (
        -- === Control Inputs ===
        -- i_clk:   System clock signal (fast)
        i_clk               : in  std_logic;
        -- i_reset: Asynchronous reset signal (active high)
        i_reset             : in  std_logic;
        -- i_start: Transmission start signal (one pulse)
        i_start             : in  std_logic;
        
        -- === Input Data ===
        -- i_data:  Data to be transmitted (MSB goes out first)
        i_data              : in  std_logic_vector(G_NBITS-1 downto 0);
        
        -- === SPI Outputs ===
        -- o_sclk:  Generated SPI clock signal (Master Clock)
        o_sclk              : out std_logic;
        -- o_mosi:  Master output data (Master Out Slave In)
        o_mosi              : out std_logic;
        -- o_ss_n:  Slave Select (active low)
        o_ss_n              : out std_logic;
        
        -- === Status Outputs ===
        -- o_busy:  High when FSM is executing transmission
        o_busy              : out std_logic;
        -- o_done:  One clock cycle pulse when transmission is complete
        o_done              : out std_logic
    );
end entity spi_master_tx;

architecture rtl of spi_master_tx is

    -- 1. FSM State Definitions (from your diagram)
    type t_state is (
        IDLE,           -- Idle / Waiting
        LOAD,           -- Load data
        ASSERT_SS,      -- Activate Slave Select
        PREP_CPHA0,     -- (CPHA=0) Set up 1st bit before SCLK
        ALIGN_CPHA1,    -- (CPHA=1) Wait for 1st SCLK edge
        SHIFT,          -- Shift and transmit bits
        DONE_FRAME      -- Completion, deactivate SS
    );
    
    -- === Internal Registers and Signals === 
    -- r_state, r_next_state: Current and next FSM state
    signal r_state      : t_state := IDLE;
    signal r_next_state : t_state := IDLE;
    
    -- r_shreg: Shift register for data transmission
    signal r_shreg      : std_logic_vector(G_NBITS-1 downto 0);
    
    -- r_bitcnt: Bit counter (down-counting, from Nbits to 0)
    signal r_bitcnt     : integer range 0 to G_NBITS;
    
    -- r_sclk: Internal register for SCLK generation
    signal r_sclk       : std_logic := G_CPOL;
    
    -- r_clk_div_cnt: Counter for SCLK frequency divider
    signal r_clk_div_cnt: integer range 0 to G_CLK_DIV_RATIO-1;
    
    -- r_done_pulse: Register for generating o_done pulse
    signal r_done_pulse : std_logic;

    -- sclk_tick: Internal pulse indicating SCLK change
    signal s_sclk_tick  : std_logic;
    
    -- s_sample_edge: Pulse indicating "Sample" edge of SCLK
    signal s_sample_edge: std_logic;
    
begin

    --=========================================================================
    -- PROCESS 1: Synchronous Logic (FSM Registers and SCLK Divider)
    -- Description: This process is responsible for all changes occurring
    --              on the rising edge of the system clock (i_clk).
    --=========================================================================
    p_sync : process(i_clk, i_reset)
    begin
        if i_reset = '1' then
            -- Reset FSM and all registers
            r_state       <= IDLE;
            r_shreg       <= (others => '0');
            r_bitcnt      <= 0;
            r_clk_div_cnt <= 0;
            r_sclk        <= G_CPOL; -- SCLK in 'idle' state
            r_done_pulse  <= '0';
            
        elsif rising_edge(i_clk) then
            
            -- FSM state register
            r_state <= r_next_state;
            
            -- o_done pulse generation
            r_done_pulse <= '0'; -- Reset by default
            if (r_next_state = DONE_FRAME) and (r_state /= DONE_FRAME) then
                r_done_pulse <= '1'; -- Set for 1 clock cycle
            end if;

            -- === SCLK Divider Logic ===
            -- Divider active only in SHIFT state
            if (r_state = SHIFT) then
                if r_clk_div_cnt = G_CLK_DIV_RATIO-1 then
                    r_clk_div_cnt <= 0;
                    r_sclk        <= not r_sclk; -- Toggle SCLK state
                else
                    r_clk_div_cnt <= r_clk_div_cnt + 1;
                end if;
            else
                r_clk_div_cnt <= 0; -- Reset divider
                r_sclk        <= G_CPOL; -- SCLK in idle
            end if;

            -- === Register Logic (dependent on state) ===
            case r_state is
                when LOAD =>
                    r_shreg  <= i_data;  -- Load data into shift register
                    r_bitcnt <= G_NBITS; -- Set counter (from diagram)
                
                when SHIFT =>
                    -- Shift and bit counting occur on the "Sample" edge of SCLK
                    if s_sample_edge = '1' then
                        r_shreg  <= r_shreg(G_NBITS-2 downto 0) & '0'; -- Shift MSB
                        r_bitcnt <= r_bitcnt - 1;
                    end if;
                    
                when others =>
                    -- (IDLE, ASSERT_SS, PREP, ALIGN, DONE_FRAME)
                    -- No register changes (except SCLK divider reset above)
            end case;
            
        end if;
    end process p_sync;
    
    
    -- Definition of "Tick" and "Sample Edge"
    -- s_sclk_tick: pulse when SCLK must change
    s_sclk_tick <= '1' when (r_clk_div_cnt = G_CLK_DIV_RATIO-1) and (r_state = SHIFT) else '0';
    
    -- s_sample_edge: pulse on "Sample" edge of SCLK
    -- For CPHA=0: Sample on 1st edge (r_sclk = not G_CPOL)
    -- For CPHA=1: Sample on 2nd edge (r_sclk = G_CPOL)
    s_sample_edge <= '1' when (s_sclk_tick = '1') and ((G_CPHA = '0' and r_sclk = G_CPOL) or (G_CPHA = '1' and r_sclk /= G_CPOL)) else '0';

    
    --=========================================================================
    -- PROCESS 2: Combinational Logic (Outputs and Next State)
    -- Description: This process determines output logic (o_mosi, o_ss_n)
    --              and FSM state transitions (r_next_state).
    --=========================================================================
    p_comb : process(r_state, i_start, r_shreg, r_bitcnt, r_done_pulse)
    begin
        -- === Default Values ===
        r_next_state <= r_state;
        o_busy       <= '1'; -- Busy in all states except IDLE
        o_mosi       <= '0'; -- Default
        o_ss_n       <= '1'; -- Inactive
        o_done       <= r_done_pulse;
        
        -- === FSM Logic (from diagram) ===
        case r_state is
        
            when IDLE =>
                o_busy <= '0';
                if i_start = '1' and r_done_pulse = '0' then
                    r_next_state <= LOAD;
                end if;

            when LOAD =>
                -- (busy=1, done=0 from diagram)
                r_next_state <= ASSERT_SS;

            when ASSERT_SS =>
                o_ss_n <= '0'; -- Activate SS_n (active low)
                if G_CPHA = '1' then
                    r_next_state <= ALIGN_CPHA1;
                else
                    r_next_state <= PREP_CPHA0;
                end if;

            when PREP_CPHA0 => -- (CPHA=0)
                o_ss_n <= '0';
                o_mosi <= r_shreg(G_NBITS-1); -- Set MSB *before* 1st SCLK
                r_next_state <= SHIFT;
            
            when ALIGN_CPHA1 => -- (CPHA=1)
                o_ss_n <= '0';
                -- MOSI is not set yet
                r_next_state <= SHIFT;

            when SHIFT =>
                o_ss_n <= '0';
                -- MOSI is set according to shift register MSB
                o_mosi <= r_shreg(G_NBITS-1);
                
                -- Completion check
                if r_bitcnt = 0 then
                    r_next_state <= DONE_FRAME;
                end if;

            when DONE_FRAME =>
                o_busy <= '0';
                o_ss_n <= '1'; -- Deactivate SS_n
                if i_start = '1' then
                    r_next_state <= LOAD; -- Ready for next transmission
                else
                    r_next_state <= IDLE;
                end if;
                
        end case;
    end process p_comb;
    
    -- === Output Assignments ===
    o_sclk <= r_sclk; -- Connecting internal SCLK to output

end architecture rtl;