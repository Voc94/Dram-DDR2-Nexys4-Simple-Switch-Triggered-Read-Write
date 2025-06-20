library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fifo64x8 is
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    wr_en   : in  std_logic;
    wr_data : in  std_logic_vector(63 downto 0);
    rd_en   : in  std_logic;
    rd_data : out std_logic_vector(63 downto 0);
    empty   : out std_logic;
    full    : out std_logic
  );
end entity;

architecture RTL of fifo64x8 is
  type mem_type is array(0 to 7) of std_logic_vector(63 downto 0);
  signal mem : mem_type := (others => (others => '0'));
  signal wr_ptr, rd_ptr : integer range 0 to 7 := 0;
  signal cnt : integer range 0 to 8 := 0;
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        wr_ptr <= 0; rd_ptr <= 0; cnt <= 0;
      else
        -- Write
        if wr_en = '1' and cnt < 8 then
          mem(wr_ptr) <= wr_data;
          wr_ptr <= (wr_ptr + 1) mod 8;
          cnt <= cnt + 1;
        end if;
        -- Read
        if rd_en = '1' and cnt > 0 then
          rd_ptr <= (rd_ptr + 1) mod 8;
          cnt <= cnt - 1;
        end if;
      end if;
    end if;
  end process;

  rd_data <= mem(rd_ptr);
  empty <= '1' when cnt = 0 else '0';
  full <= '1' when cnt = 8 else '0';
end architecture;
