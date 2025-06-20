library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_cmd is
  generic (
    CLK_FREQ  : integer := 100_000_000;
    BAUD_RATE : integer := 115200
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    uart_rx      : in  std_logic;
    uart_tx      : out std_logic;
    -- MIG interface
    app_addr         : out std_logic_vector(26 downto 0);
    app_cmd          : out std_logic_vector(2 downto 0);
    app_en           : out std_logic;
    app_wdf_data     : out std_logic_vector(63 downto 0);
    app_wdf_end      : out std_logic;
    app_wdf_mask     : out std_logic_vector(7 downto 0);
    app_wdf_wren     : out std_logic;
    app_rd_data      : in  std_logic_vector(63 downto 0);
    app_rd_data_valid: in  std_logic;
    app_rdy          : in  std_logic;
    app_wdf_rdy      : in  std_logic;
    -- Debug
    led              : out std_logic_vector(3 downto 0)
  );
end entity;

architecture RTL of uart_cmd is

  -- UART instance interface signals
  signal rx_data    : std_logic_vector(7 downto 0);
  signal rx_valid   : std_logic;
  signal tx_start   : std_logic := '0';
  signal tx_data    : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_busy    : std_logic;

  -- FSM states
  type state_type is (
    WAIT_CMD, GET_ADDR1, GET_ADDR2, GET_ADDR3,
    GET_WDATA, WRITE_WAIT, WRITE_DONE,
    READ_REQ, READ_WAIT, SEND_RDATA, SEND_DONE
  );
  signal state        : state_type := WAIT_CMD;
  signal cmd_byte     : std_logic_vector(7 downto 0) := (others => '0');
  signal addr_bytes   : std_logic_vector(23 downto 0) := (others => '0');
  signal burst_data   : std_logic_vector(63 downto 0) := (others => '0');
  signal rdata        : std_logic_vector(63 downto 0) := (others => '0');
  signal data_count   : integer range 0 to 7 := 0;

  -- Default assignments
  signal app_en_i         : std_logic := '0';
  signal app_cmd_i        : std_logic_vector(2 downto 0) := (others => '0');
  signal app_addr_i       : std_logic_vector(26 downto 0) := (others => '0');
  signal app_wdf_data_i   : std_logic_vector(63 downto 0) := (others => '0');
  signal app_wdf_end_i    : std_logic := '0';
  signal app_wdf_mask_i   : std_logic_vector(7 downto 0) := (others => '0');
  signal app_wdf_wren_i   : std_logic := '0';

begin

  -- UART instantiation (connect to your UART IP here)
  uart_inst: entity work.uart
    generic map (
      CLK_FREQ  => CLK_FREQ,
      BAUD_RATE => BAUD_RATE
    )
    port map (
      clk        => clk,
      rst        => rst,
      rx         => uart_rx,
      tx         => uart_tx,
      data_out   => rx_data,
      data_valid => rx_valid,
      tx_start   => tx_start,
      data_in    => tx_data,
      tx_busy    => tx_busy
    );

  -- Actual connection to top-level
  app_en      <= app_en_i;
  app_cmd     <= app_cmd_i;
  app_addr    <= app_addr_i;
  app_wdf_data<= app_wdf_data_i;
  app_wdf_end <= app_wdf_end_i;
  app_wdf_mask<= app_wdf_mask_i;
  app_wdf_wren<= app_wdf_wren_i;

  -- Main FSM
  process(clk)
  begin
    if rising_edge(clk) then
      -- Default assignments
      app_en_i      <= '0';
      app_wdf_wren_i<= '0';
      tx_start      <= '0';
      led           <= (others => '0');

      if rst = '1' then
        state        <= WAIT_CMD;
        data_count   <= 0;
        burst_data   <= (others => '0');
        rdata        <= (others => '0');
      else
        case state is
          -- ==== CMD ====
          when WAIT_CMD =>
            if rx_valid = '1' then
              cmd_byte <= rx_data;
              data_count <= 0;
              if rx_data = x"02" then   -- WRITE
                state <= GET_ADDR1;
                led(0) <= '1';
              elsif rx_data = x"01" then -- READ
                state <= GET_ADDR1;
                led(1) <= '1';
              end if;
            end if;

          -- ==== ADDR ====
          when GET_ADDR1 =>
            if rx_valid = '1' then
              addr_bytes(23 downto 16) <= rx_data;
              state <= GET_ADDR2;
            end if;
          when GET_ADDR2 =>
            if rx_valid = '1' then
              addr_bytes(15 downto 8) <= rx_data;
              state <= GET_ADDR3;
            end if;
          when GET_ADDR3 =>
            if rx_valid = '1' then
              addr_bytes(7 downto 0) <= rx_data;
              data_count <= 0;
              if cmd_byte = x"02" then  -- WRITE
                state <= GET_WDATA;
                led(2) <= '1';
              else                      -- READ
                state <= READ_REQ;
                led(3) <= '1';
              end if;
            end if;

          -- ==== WRITE ====
          when GET_WDATA =>
            if rx_valid = '1' then
              burst_data(63 - data_count*8 downto 56 - data_count*8) <= rx_data;
              if data_count = 7 then
                state <= WRITE_WAIT;
              else
                data_count <= data_count + 1;
              end if;
            end if;
          when WRITE_WAIT =>
            -- Wait for MIG ready
            if app_rdy = '1' and app_wdf_rdy = '1' then
              app_en_i      <= '1';
              app_cmd_i     <= "000"; -- WRITE
              app_addr_i    <= (others => '0');
              app_addr_i(23 downto 0) <= addr_bytes;
              app_wdf_data_i<= burst_data;
              app_wdf_end_i <= '1';
              app_wdf_mask_i<= (others => '0');
              app_wdf_wren_i<= '1';
              state <= WRITE_DONE;
            end if;
          when WRITE_DONE =>
            -- Wait for MIG to accept, then ACK over UART
            if (app_rdy = '1' and app_wdf_rdy = '1') = false then
              tx_data <= x"AA"; -- ACK
              tx_start <= '1';
              state <= SEND_DONE;
            end if;

          -- ==== READ ====
          when READ_REQ =>
            if app_rdy = '1' then
              app_en_i   <= '1';
              app_cmd_i  <= "001"; -- READ
              app_addr_i <= (others => '0');
              app_addr_i(23 downto 0) <= addr_bytes;
              state <= READ_WAIT;
            end if;
          when READ_WAIT =>
            if app_rd_data_valid = '1' then
              rdata <= app_rd_data;
              data_count <= 0;
              state <= SEND_RDATA;
            end if;
          when SEND_RDATA =>
            if tx_busy = '0' then
              tx_data <= rdata(63 - data_count*8 downto 56 - data_count*8);
              tx_start <= '1';
              if data_count = 7 then
                state <= SEND_DONE;
              else
                data_count <= data_count + 1;
              end if;
            end if;
          when SEND_DONE =>
            if tx_busy = '0' then
              state <= WAIT_CMD;
            end if;
          when others =>
            state <= WAIT_CMD;
        end case;
      end if;
    end if;
  end process;

end architecture;