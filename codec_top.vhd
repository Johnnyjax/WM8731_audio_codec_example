library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity codec_top is
	generic(FIFO_SIZE: integer:= 3);
	port(
		clk, reset : in std_logic;
		-- to WM8731
		m_clk, b_clk, dac_lr_clk, adc_lr_clk : out std_logic;
		dacdat : out std_logic;
		adcdat : in std_logic;
		i2c_sclk : out std_logic;
		i2c_sdat : inout std_logic;
		--to main system
		wr_i2c : in std_logic;
		i2c_packet : in std_logic_vector(23 downto 0);
		i2c_idle : out std_logic;
		i2c_done_tick : out std_logic;
		rd_adc_fifo : in std_logic;
		adc_fifo_out : out std_logic_vector(31 downto 0);
		adc_fifo_empty : out std_logic;
		wr_dac_fifo : in std_logic;
		dac_fifo_in : in std_logic_vector(31 downto 0);
		dac_fifo_full : out std_logic;
		sample_tick :out std_logic
	);
end codec_top;

architecture arch of codec_top is
	signal dac_data_in : std_logic_vector(31 downto 0);
	signal adc_data_out : std_logic_vector(31 downto 0);
	signal dac_done_tick : std_logic;
begin
	sample_tick <= dac_done_tick;
	--instantiate i2c unit
	i2c_unit : entity work.i2c(arch)
		port map(clk => clk, reset => reset,
					wr_i2c => wr_i2c, din => i2c_packet,
					i2c_sclk => i2c_sclk, i2c_sdat => i2c_sdat,
					i2c_idle => i2c_idle,
					i2c_done_tick => i2c_done_tick, i2c_fail => open);
	--instantiate codec dac/adc
	dac_adc_unit : entity work.adc_dac(arch)
		port map(clk => clk, reset => reset,
					dac_data_in => dac_data_in,
					adc_data_out => adc_data_out,
					m_clk => m_clk, b_clk => b_clk,
					dac_lr_clk => dac_lr_clk, adc_lr_clk => adc_lr_clk,
					dacdat => dacdat, adcdat => adcdat,
					load_done_tick => dac_done_tick);
	-- instantiate adc fifO
	fifo_adc_unit : entity work.fifo(arch)
		generic map(B => 32, W => FIFO_SIZE)
		port map(clk => clk, reset => reset, rd => rd_adc_fifo,
					wr => dac_done_tick, w_data => adc_data_out,
					empty=> adc_fifo_empty, full => open,
					r_data => adc_fifo_out);
	fifo_dac_unit : entity work.fifo(arch)
		generic map(B => 32, W => FIFO_SIZE)
		port map(clk => clk, reset => reset, rd => dac_done_tick,
					wr => wr_dac_fifo, w_data => dac_fifo_in,
					empty => open, full => dac_fifo_full,
					r_data => dac_data_in);
end arch;