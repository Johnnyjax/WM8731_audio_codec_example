library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c is
	port(
		clk, reset 			 : in std_logic;
		din 					 : in std_logic_vector(23 downto 0);
		wr_i2c				 : in std_logic;
		i2c_sclk 			 : out std_logic;
		i2c_sdat 			 : inout std_logic;
		i2c_idle, i2c_fail : out std_logic;
		i2c_done_tick 		 : out std_logic
	);
end i2c;

architecture arch of  i2c is
	constant HALF : integer := 249;
	constant QUTR : integer := 125;
	constant C_WIDTH : integer := 8;
	type statetype is (
		idle, start, scl_begin, data1, data2, data3,
		ack1, ack2, ack3, scl_end, stop, turn);
	signal state_reg, state_next : statetype;
	signal c_reg, c_next : unsigned(C_WIDTH-1 downto 0);
	signal data_reg, data_next : std_logic_vector(23 downto 0);
	signal bit_reg, bit_next : unsigned(2 downto 0);
	signal byte_reg, byte_next : unsigned(1 downto 0);
	signal sdat_out, sclk_out : std_logic;
	signal sdat_reg, sclk_reg : std_logic;
	signal ack_reg, ack_next : std_logic;
begin
	process(clk, reset)
	begin	
		if reset = '1' then
			sdat_reg <= '1';
			sclk_reg <= '1';
		elsif(clk'event and clk = '1') then
			sdat_reg <= sdat_out;
			sclk_reg <= sclk_out;
		end if;
	end process;
	i2c_sclk <= sclk_reg;
	i2c_sdat <= 'Z' when sdat_reg = '1' else '0';
	i2c_fail <= '1' when ack_reg = '1' else '0';
	
	process(clk, reset)
	begin
		if reset = '1' then
			state_reg <= idle;
			c_reg <= (others => '0');
			bit_reg <= (others => '0');
			byte_reg <= (others => '0');
			data_reg <= (others => '0');
			ack_reg <= '1';
		elsif(clk'event and clk = '1') then
			state_reg <= state_next;
			c_reg <= c_next;
			bit_reg <= bit_next;
			byte_reg <= byte_next;
			data_reg <= data_next;
			ack_reg <= ack_next;
		end if;
	end process;
	
	process(state_reg, bit_reg, byte_reg, data_reg, c_reg, 
			  din, wr_i2c, i2c_sdat, ack_reg)
	begin
		state_next <= state_reg;
		sclk_out <= '1';
		sdat_out <= '1';
		c_next <= c_reg + 1;
		bit_next <= bit_reg;
		byte_next <= byte_reg;
		data_next <= data_reg;
		ack_next <= ack_reg;
		i2c_done_tick <= '0';
		i2c_idle <= '0';
		
		case state_reg is
			when idle =>
				i2c_idle <= '1';
				if(wr_i2c = '1') then
					data_next <= din;
					bit_next <= "000";
					byte_next <= "00";
					c_next <= (others => '0');
					state_next <= start;
				end if;
			when start =>
				sdat_out <= '0';
				if c_reg = HALF then
					c_next <= (others => '0');
					state_next <= scl_begin;
				end if;
			when scl_begin =>
				sclk_out <= '0';
				if c_reg = QUTR then
					c_next <= (others => '0');
					state_next <= data1;
				end if;
			when data1 =>
				sdat_out <= data_reg(23);
				sclk_out <= '0';
				if c_reg = QUTR then
					c_next <= (others => '0');
					state_next <= data2;
				end if;
			when data2 =>
				sdat_out <= data_reg(23);
				if c_reg = HALF then
					c_next <= (others => '0');
					state_next <= data3;
				end if;
			when data3 =>
				sdat_out <= data_reg(23);
				sclk_out <= '0';
				if c_reg = QUTR then
					c_next <= (others => '0');
					if bit_reg = 7 then
						state_next <= ack1;
					else
						data_next <= data_reg(22 downto 0) & '0';
						bit_next <= bit_reg + 1;
						state_next <= data1;
					end if;
				end if;
				when ack1 =>
					sclk_out <= '0';
					if c_reg = QUTR then
						c_next <= (others => '0');
						state_next <= ack2;
					end if;
				when ack2 =>
					if c_reg = HALF then
						c_next <= (others => '0');
						state_next <= ack3;
						ack_next <= i2c_sdat;
					end if;
				when ack3 =>
					sclk_out <= '0';
					if c_reg = QUTR then
						c_next <= (others => '0');
						if ack_reg = '1' then
							state_next <= scl_end;
						else
							if byte_reg = 2 then
								state_next <= scl_end;
							else
								bit_next <= "000";
								byte_next <= byte_reg + 1;
								data_next <= data_reg(22 downto 0) & '0';
								state_next <= data1;
							end if;
						end if;
					end if;
				when scl_end =>
					sclk_out <= '0';
					sdat_out <= '0';
					if c_reg = QUTR then
						c_next <= (others => '0');
						state_next <= stop;
					end if;
				when stop =>
					sdat_out <= '0';
					if c_reg = HALF then
						c_next <= (others => '0');
						state_next <= turn;
					end if;
				when turn =>
					if c_reg = HALF then
						state_next <= idle;
						i2c_done_tick <= '1';
					end if;
			end case;
		end process;
end arch;