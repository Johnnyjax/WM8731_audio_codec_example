library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity codec_test is
	generic(FIFO_SIZE : integer := 3);
	port(
		CLOCK_50 : in std_logic;
		KEY      : in std_logic_vector(3 downto 0);
		LEDG     : out std_logic_vector(0 downto 0);
		SW       : in std_logic_vector(0 downto 0);
		AUD_XCK, AUD_BCLK, AUD_DACLRCK, AUD_ADCLRCK: out std_logic;
		AUD_DACDAT : out std_logic;
		AUD_ADCDAT : in std_logic;
		I2C_SCLK : out std_logic;
		I2C_SDAT : inout std_logic
	);
end codec_test;

architecture arch of codec_test is
	type statetype is(config, wait0, next_reg, sample_state, playback_state,
							wait1, wait2, wait3, config_done);
	signal state_reg, state_next : statetype;
	
	constant WM8731_ID : std_logic_vector(7 downto 0) := "00110100";
	signal wram_en : std_logic;
	signal ram_addr : std_logic_vector(11 downto 0);
	signal ram_data_in, ram_data_out : std_logic_vector(31 downto 0);
	signal ram_pos_reg, ram_pos_next : unsigned(11 downto 0);
	signal wr_i2c, i2c_idle, wr_sel : std_logic;
	signal i2c_done_tick : std_logic;
	signal i2c_packet_reg, i2c_packet_next : std_logic_vector(23 downto 0);
	signal conf_cnt_reg, conf_cnt_next : unsigned(3 downto 0);
	signal dbus_sel_reg : std_logic_vector(1 downto 0);
	signal dac_fifo_in : std_logic_vector(31 downto 0);
	signal adc_fifo_out : std_logic_vector(31 downto 0);
	signal dac_done_tick : std_logic;
	signal wr_dac_fifo : std_logic;
	signal rd_adc_fifo : std_logic;
	signal adc_fifo_empty, dac_fifo_full : std_logic;
	signal codec_sample_tick : std_logic;
	signal inc_vol, dec_vol, sample : std_logic;
	signal vol_reg, vol_next : unsigned(6 downto 0) := "1111001";
	signal led_reg, led_next : std_logic;
	
	type config_registers is array(0 to 10) of 
		  std_logic_vector(15 downto 0);
		  
	constant CONFIG_ROM : config_registers :=
		(	"0001111000000000", -- R15: dummy data to R15 to reset 
			"0000000000010111", -- R0 : left line in gain 0 dB
			"0000001000010111", -- R1 : right line in gain 0 dB
			"0000010001111001", -- R2 : left headphone out volume 0 dB
			"0000011001111001", -- R3 : right headphone out volume 0 dB
			"0000100000010000", -- R4 : analog path select: line in to line out
			"0000101000000000", -- R5 : digital audio : high-pass filter, no de-emphasis
			"0000110000000000", -- R6 : enable all power
			"0000111000000001", -- R7 : digital interface : left-adjust, 16-bit resolution
			"0001000000000000", -- R8 : 48K sampling rate with 12.228MHz master cloCK_50
			"0001001000000001"  -- R9 : activate
		);
	
begin
	codec_unit : entity work.codec_top(arch)
		generic map(FIFO_SIZE => FIFO_SIZE)
		port map(clk => CLOCK_50, reset => not(KEY(0)),
					i2c_sclk => I2C_SCLK, i2c_sdat => I2C_SDAT,
					m_clk => AUD_XCK, b_clk => AUD_BCLK,
					dac_lr_clk => AUD_DACLRCK, adc_lr_clk => AUD_ADCLRCK,
					dacdat => AUD_DACDAT, adcdat => AUD_ADCDAT,
					wr_i2c => wr_i2c, i2c_idle => i2c_idle,
					i2c_done_tick => i2c_done_tick,
					i2c_packet => i2c_packet_next, rd_adc_fifo => rd_adc_fifo,
					adc_fifo_empty => adc_fifo_empty, 
					adc_fifo_out => adc_fifo_out, 
					wr_dac_fifo => wr_dac_fifo,
					dac_fifo_full => dac_fifo_full,
					dac_fifo_in => dac_fifo_in,
					sample_tick => codec_sample_tick);
	debounce_unit0 : entity work.debounce
		port map(clk => CLOCK_50, reset => not(KEY(0)), 
					sw => not(KEY(1)), db_tick => dec_vol,
					db_level => open);
	debounce_unit1 : entity work.debounce
		port map(clk => CLOCK_50, reset => not(KEY(0)), 
					sw => not(KEY(2)), db_tick => inc_vol,
					db_level => open);
	debounce_unit2 : entity work.debounce
		port map(clk => CLOCK_50, reset => not(KEY(0)), 
					sw => not(KEY(3)), db_tick => sample,
					db_level => open);
					
	ram_unit : entity work.altera_one_port_ram
		port map(clk => CLOCK_50, we => wram_en, 
					addr => std_logic_vector(ram_pos_next), d => adc_fifo_out,
					q => dac_fifo_in);
	
	
	process(CLOCK_50, KEY(0))
	begin
		if KEY(0) = '0' then
			state_reg <= config;
			conf_cnt_reg <= (others => '0');
			led_reg <= '0';
			i2c_packet_reg <= (others => '0');
			ram_pos_reg <= (others => '0');
			vol_reg <= "1111001";
		elsif(CLOCK_50'event and CLOCK_50 = '1') then
			state_reg <= state_next;
			conf_cnt_reg <= conf_cnt_next;
			led_reg <= led_next;
			i2c_packet_reg <= i2c_packet_next;
			ram_pos_reg <= ram_pos_next;
			vol_reg <= vol_next;
		end if;
	end process;
	
	process(state_reg, sample, SW, led_reg, i2c_packet_reg, vol_reg, vol_next, inc_vol,
				dec_vol, conf_cnt_reg, i2c_done_tick, ram_pos_reg, adc_fifo_empty, dac_fifo_full)
	begin
		state_next <= state_reg;
		conf_cnt_next <= conf_cnt_reg;
		i2c_packet_next <= i2c_packet_reg;
		led_next <= led_reg;
		vol_next <= vol_reg;
		ram_pos_next <= ram_pos_reg;
		wr_i2c <= '0';
		rd_adc_fifo <= '0';
		wram_en <= '0';
		wr_dac_fifo <= '0';
		case state_reg is
			when config =>
				i2c_packet_next <= WM8731_ID & CONFIG_ROM(to_integer(conf_cnt_reg)); 
				wr_i2c <= '1';
				state_next <= wait0;
			when wait0 =>
				if (i2c_done_tick = '1') then
					state_next <= next_reg;
				end if;
			when next_reg =>
				if(conf_cnt_reg = 10) then	
					state_next <= config_done;
				else
					conf_cnt_next <= conf_cnt_reg + 1;
					state_next <= config;
				end if;
			when config_done =>
				if SW(0) = '1' then
					vol_next <= vol_reg + 1;
					i2c_packet_next <= (WM8731_ID & "000001010" & std_logic_vector(vol_next));
					wr_i2c <= '1';
					state_next <= wait1;
				elsif(dec_vol = '1') then
					vol_next <= vol_reg - 1;
					i2c_packet_next <= (WM8731_ID & "000001010" & std_logic_vector(vol_next));
					wr_i2c <= '1';
					state_next <= wait1;
				elsif(sample = '1') then
					state_next <= sample_state;
				elsif inc_vol = '1' then
					state_next <= playback_state;
				end if;
			when wait1 =>
				if (i2c_done_tick = '1') then
					state_next <= config_done;
				end if;
			when sample_state =>
				if adc_fifo_empty /= '1' then
					rd_adc_fifo <= '1';
					wram_en <= '1';
					state_next <= wait2;
				end if;
			when wait2 =>
				if(ram_pos_reg = 4095) then
					state_next <= config_done;
					ram_pos_next <= (others => '0');
					led_next <= '1';
				else
					ram_pos_next <= ram_pos_reg + 1;
				   state_next <= sample_state;
				end if;
			when playback_state =>
				if dac_fifo_full /= '1' then
					wr_dac_fifo <= '1';
					state_next <= wait3;
				end if;
			when wait3 =>
				if(ram_pos_reg = 4095) then
					state_next <= config_done;
					ram_pos_next <= (others => '0');
				else
					ram_pos_next <= ram_pos_reg + 1;
				   state_next <= playback_state;
				end if;
		end case;
	end process;
	LEDG(0) <= led_reg;
end arch;