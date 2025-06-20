library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
  port (
    -- DDR2 interface
    ddr2_dq       : inout std_logic_vector(15 downto 0);
    ddr2_dqs_p    : inout std_logic_vector(1 downto 0);
    ddr2_dqs_n    : inout std_logic_vector(1 downto 0);
    ddr2_addr     : out std_logic_vector(12 downto 0);
    ddr2_ba       : out std_logic_vector(2 downto 0);
    ddr2_ras_n    : out std_logic;
    ddr2_cas_n    : out std_logic;
    ddr2_we_n     : out std_logic;
    ddr2_ck_p     : out std_logic_vector(0 downto 0);
    ddr2_ck_n     : out std_logic_vector(0 downto 0);
    ddr2_cke      : out std_logic_vector(0 downto 0);
    ddr2_cs_n     : out std_logic_vector(0 downto 0);
    ddr2_dm       : out std_logic_vector(1 downto 0);
    ddr2_odt      : out std_logic_vector(0 downto 0);
    sys_clk_i     : in std_logic;
    sys_rst       : in std_logic;
    uart_rx  : in  std_logic;
    uart_tx  : out std_logic;
    led : out std_logic_vector(3 downto 0)
  );
end entity top;

architecture Behavioral of top is

  -- MIG user interface signals
  signal app_addr            : std_logic_vector(26 downto 0) := (others => '0');
  signal app_cmd             : std_logic_vector(2 downto 0) := (others => '0');
  signal app_en              : std_logic := '0';
  signal app_wdf_data        : std_logic_vector(63 downto 0) := (others => '0');
  signal app_wdf_end         : std_logic := '0';
  signal app_wdf_mask        : std_logic_vector(7 downto 0) := (others => '0');
  signal app_wdf_wren        : std_logic := '0';
  signal app_rd_data         : std_logic_vector(63 downto 0);
  signal app_rd_data_end     : std_logic;
  signal app_rd_data_valid   : std_logic;
  signal app_rdy             : std_logic;
  signal app_wdf_rdy         : std_logic;
  signal app_sr_req          : std_logic := '0';
  signal app_ref_req         : std_logic := '0';
  signal app_zq_req          : std_logic := '0';
  signal app_sr_active       : std_logic;
  signal app_ref_ack         : std_logic;
  signal app_zq_ack          : std_logic;
  signal ui_clk              : std_logic;
  signal ui_clk_sync_rst     : std_logic;
  signal init_calib_complete : std_logic;

  -- Clock Wizard
  signal clk_mem   : std_logic;
  signal clk_cpu   : std_logic;
  signal clk_locked: std_logic;
    signal mig_sys_clk : std_logic;
  -- Simple state for the write command
  signal sw_write_reg, sw_read_reg : std_logic := '0';
  signal read_data_latched         : std_logic_vector(11 downto 0) := (others => '0');
  signal sys_rst_temp: std_logic := '0';
  type state_type is (IDLE, WAIT_WRITE, WRITE_CMD, WRITE_DONE, WAIT_READ, READ_CMD, READ_WAIT, LED_ON);
  signal state : state_type := IDLE;
  signal uart_leds : std_logic_vector(3 downto 0);


begin

    u_clk_wiz: entity work.clk_wiz_0
      port map (
        clk_in  => sys_clk_i,    -- 100 MHz from board
        clk_mem => mig_sys_clk,  -- 200 MHz output for MIG
        clk_cpu => clk_cpu,      -- for user logic
        locked  => clk_locked,
        reset   => sys_rst
      );
    

u_mig: entity work.mig_7series_0
  port map (
    ddr2_dq            => ddr2_dq,
    ddr2_dqs_p         => ddr2_dqs_p,
    ddr2_dqs_n         => ddr2_dqs_n,
    ddr2_addr          => ddr2_addr,
    ddr2_ba            => ddr2_ba,
    ddr2_ras_n         => ddr2_ras_n,
    ddr2_cas_n         => ddr2_cas_n,
    ddr2_we_n          => ddr2_we_n,
    ddr2_ck_p          => ddr2_ck_p,
    ddr2_ck_n          => ddr2_ck_n,
    ddr2_cke           => ddr2_cke,
    ddr2_cs_n          => ddr2_cs_n,
    ddr2_dm            => ddr2_dm,
    ddr2_odt           => ddr2_odt,
    app_addr           => app_addr,
    app_cmd            => app_cmd,
    app_en             => app_en,
    app_wdf_data       => app_wdf_data,
    app_wdf_end        => app_wdf_end,
    app_wdf_mask       => app_wdf_mask,
    app_wdf_wren       => app_wdf_wren,
    app_rd_data        => app_rd_data,
    app_rd_data_end    => app_rd_data_end,
    app_rd_data_valid  => app_rd_data_valid,
    app_rdy            => app_rdy,
    app_wdf_rdy        => app_wdf_rdy,
    app_sr_req         => app_sr_req,
    app_ref_req        => app_ref_req,
    app_zq_req         => app_zq_req,
    app_sr_active      => app_sr_active,
    app_ref_ack        => app_ref_ack,
    app_zq_ack         => app_zq_ack,
    ui_clk             => ui_clk,
    ui_clk_sync_rst    => ui_clk_sync_rst,
    init_calib_complete=> init_calib_complete,
    sys_clk_i          => mig_sys_clk, -- *** FIX: use 200 MHz from clk_wiz ***
    sys_rst            => sys_rst_temp
  );


u_uart_cmd: entity work.uart_cmd
  generic map (
    CLK_FREQ  => 100_000_000,
    BAUD_RATE => 115200
  )
  port map (
    clk          => clk_cpu,
    rst          => sys_rst,
    uart_rx      => uart_rx,
    uart_tx      => uart_tx,
    -- MIG
    app_addr         => app_addr,
    app_cmd          => app_cmd,
    app_en           => app_en,
    app_wdf_data     => app_wdf_data,
    app_wdf_end      => app_wdf_end,
    app_wdf_mask     => app_wdf_mask,
    app_wdf_wren     => app_wdf_wren,
    app_rd_data      => app_rd_data,
    app_rd_data_valid=> app_rd_data_valid,
    app_rdy          => app_rdy,
    app_wdf_rdy      => app_wdf_rdy,
    -- Debug
    led              => led(3 downto 0)
  );



 sys_rst_temp <= not(sys_rst);
end architecture Behavioral;
