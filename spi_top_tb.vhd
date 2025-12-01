library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;  -- for stop (VHDL-2008)

entity spi_top_tb is
end entity spi_top_tb;

architecture sim of spi_top_tb is

    constant C_CLK_PERIOD    : time     := 20 ns;
    constant C_NBITS         : positive := 8;
    constant C_DIV           : positive := 5;
    constant C_CPOL          : std_logic := '0';
    constant C_CPHA          : std_logic := '0';

    -- !!! CHANGED VALUES HERE !!!
    -- I changed C3 to 12, and AB to 99. 
    -- You can type any 2-digit Hex code here (e.g., x"FF", x"0A", etc.)
    constant C_TX_DATA       : std_logic_vector(C_NBITS-1 downto 0) := x"12";
    constant C_RX_DATA       : std_logic_vector(C_NBITS-1 downto 0) := x"99";

    constant C_TIMEOUT_TX    : time := 10 us;
    constant C_TIMEOUT_SS    : time := 10 us;
    constant C_TIMEOUT_SCLK  : time := 10 us;
    constant C_TIMEOUT_RX    : time := 10 us;

    signal s_clk   : std_logic := '0';
    signal s_reset : std_logic := '1';

    -- TX
    signal s_tx_start : std_logic := '0';
    signal s_tx_sclk  : std_logic;
    signal s_tx_mosi  : std_logic;
    signal s_tx_ss_n  : std_logic;
    signal s_tx_busy  : std_logic;
    signal s_tx_done  : std_logic;

    -- RX
    signal s_rx_start    : std_logic := '0';
    signal s_rx_miso     : std_logic := '0';
    signal s_rx_sclk     : std_logic;
    signal s_rx_ss_n     : std_logic;
    signal s_rx_data_out : std_logic_vector(C_NBITS-1 downto 0);
    signal s_rx_busy     : std_logic;
    signal s_rx_done     : std_logic;

begin

    -------------------------------------------------------------------------
    -- CLK
    -------------------------------------------------------------------------
    p_clk : process
    begin
        wait for C_CLK_PERIOD / 2;
        s_clk <= not s_clk;
    end process;

    -------------------------------------------------------------------------
    -- TX
    -------------------------------------------------------------------------
    U_TX : entity work.spi_master_tx
        generic map (
            G_NBITS         => C_NBITS,
            G_CLK_DIV_RATIO => C_DIV,
            G_CPOL          => C_CPOL,
            G_CPHA          => C_CPHA
        )
        port map (
            i_clk   => s_clk,
            i_reset => s_reset,
            i_start => s_tx_start,
            i_data  => C_TX_DATA,
            o_sclk  => s_tx_sclk,
            o_mosi  => s_tx_mosi,
            o_ss_n  => s_tx_ss_n,
            o_busy  => s_tx_busy,
            o_done  => s_tx_done
        );

    -------------------------------------------------------------------------
    -- RX
    -------------------------------------------------------------------------
    U_RX : entity work.spi_master_rx
        generic map (
            G_NBITS         => C_NBITS,
            G_CLK_DIV_RATIO => C_DIV,
            G_CPOL          => C_CPOL,
            G_CPHA          => C_CPHA
        )
        port map (
            i_clk   => s_clk,
            i_reset => s_reset,
            i_start => s_rx_start,
            i_miso  => s_rx_miso,
            o_sclk  => s_rx_sclk,
            o_ss_n  => s_rx_ss_n,
            o_data  => s_rx_data_out,
            o_busy  => s_rx_busy,
            o_done  => s_rx_done
        );

    -------------------------------------------------------------------------
    -- Stimulus
    -------------------------------------------------------------------------
    p_stim : process
        variable L          : line;
        variable deadline   : time;
        variable last_sclk  : std_logic;
    begin
        report "--- Simulation Start ---";

        -- RESET
        s_reset <= '1';
        wait for 100 ns;
        s_reset <= '0';
        wait for 5 * C_CLK_PERIOD;

        ---------------------------------------------------------------------
        -- TX TEST
        ---------------------------------------------------------------------
        report "--- Starting TX Test (Sending " & to_hstring(C_TX_DATA) & ") ---";
        s_tx_start <= '1';
        wait for C_CLK_PERIOD;
        s_tx_start <= '0';

        -- wait TX done + timeout
        deadline := now + C_TIMEOUT_TX;
        while s_tx_done = '0' loop
            wait for 10 ns;
            if now >= deadline then
                report "Timeout: TX o_done not asserted" severity failure;
                stop;
            end if;
        end loop;

        report "--- TX Test Finished ---";
        wait for 200 ns;

        ---------------------------------------------------------------------
        -- RX TEST
        ---------------------------------------------------------------------
        report "--- Starting RX Test (Expecting " & to_hstring(C_RX_DATA) & ") ---";

        -- start RX
        s_rx_start <= '1';
        wait for C_CLK_PERIOD;
        s_rx_start <= '0';

        -- wait SS_n low
        report "--- Waiting for RX SS_n to go low... ---";
        deadline := now + C_TIMEOUT_SS;
        while s_rx_ss_n = '1' loop
            wait for 10 ns;
            if now >= deadline then
                report "Timeout: RX SS_n did not go low" severity failure;
                stop;
            end if;
        end loop;
        report "--- RX SS_n is low, proceeding... ---";

        -- drive bits on falling edges
        for idx in C_NBITS-1 downto 0 loop
            deadline  := now + C_TIMEOUT_SCLK;
            last_sclk := s_rx_sclk;

            loop
                wait for 10 ns;
                if (last_sclk = '1') and (s_rx_sclk = '0') then
                    exit;
                end if;
                last_sclk := s_rx_sclk;
                if now >= deadline then
                    report "Timeout: no falling edge on RX SCLK" severity failure;
                    stop;
                end if;
            end loop;

            s_rx_miso <= C_RX_DATA(idx);
        end loop;

        -- wait RX done
        deadline := now + C_TIMEOUT_RX;
        while s_rx_done = '0' loop
            wait for 10 ns;
            if now >= deadline then
                report "Timeout: RX o_done not asserted" severity failure;
                stop;
            end if;
        end loop;

        report "--- RX Test Finished ---";

        -- print result
        write(L, string'("RX received: ") & to_hstring(s_rx_data_out));
        writeline(output, L);

        -- check
        assert s_rx_data_out = C_RX_DATA
            report "!!! ERROR: RX data mismatch !!!" severity error;

        wait for 500 ns;
        report "--- Simulation Finished ---" severity note;

        stop; -- коректне завершення без "simulation failed"
        wait;
    end process;

end architecture sim;