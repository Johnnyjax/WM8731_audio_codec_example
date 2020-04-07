library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity altera_one_port_ram is
	generic(
		ADDR_WIDTH : integer := 4;
		DATA_WIDTH : integer := 8
	);
	port(
		clk  : in std_logic;
		we   : in std_logic;
		addr : in std_logic_vector(ADDR_WIDTH-1 downto 0);
		d    : in std_logic_vector(DATA_WIDTH-1 downto 0);
		q    : out std_logic_vector(DATA_WIDTH-1 downto 0)
	);
end altera_one_port_ram;

architecture beh_arch1 of altera_one_port_ram is
	type mem_2d_type is array(0 to 2**ADDR_WIDTH-1) of
			std_logic_vector(DATA_WIDTH-1 downto 0);
	signal ram : mem_2d_type;
	signal addr_reg : std_logic_vector(ADDR_WIDTH-1 downto 0);
begin
	process(clk)
	begin
		if(clk'event and clk = '1') then
			if(we = '1') then
				ram(to_integer(unsigned(addr))) <= d;
			end if;
			addr_reg <= addr;
		end if;
	end process;
	q <= ram(to_integer(unsigned(addr_reg)));
end beh_arch1;

architecture beh_arch2 of altera_one_port_ram is
	type mem_2d_type is array(0 to 2**ADDR_WIDTH-1) of
			std_logic_vector(DATA_WIDTH-1 downto 0);
	signal ram : mem_2d_type;
	signal data_reg : std_logic_vector(DATA_WIDTH-1 downto 0);
begin
	process(clk)
	begin
		if(clk'event and clk = '1') then
			if(we = '1')then
				ram(to_integer(unsigned(addr))) <= d;
			end if;
			data_reg <= ram(to_integer(unsigned(addr)));
		end if;
	end process;
	q <= data_reg;
end beh_arch2;