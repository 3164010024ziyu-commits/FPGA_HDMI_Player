-----------------------------------------------------
-- HDMI 1.4a transmitter wrapper (Anlogic EG4).
--
-- The encrypted DVITransmitter/SerializerN_1_lvds/TMDSEncoder blocks that
-- used to live in src/enc_file have been replaced by the open, local
-- implementations in src/enc.  This entity keeps the original pin names so
-- the top level and the pin constraints stay unchanged.
-----------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity hdmi_tx is
    Generic (
        FAMILY   : STRING  := "EG4";
        AUDIO_EN : integer := 1;      -- 0: data islands without audio packets
        DVI_MODE : integer := 0;      -- 1: pure DVI output
        AUDIO_FS : integer := 48000   -- 44100 or 48000
    );
    Port (
        PXLCLK_I    : in  STD_LOGIC;
        PXLCLK_5X_I : in  STD_LOGIC;
        RST_N       : in  STD_LOGIC;

        -- Video timing / data (from read_RAM, 640x480p60)
        H_COUNT     : in  std_logic_vector(9 downto 0);
        V_COUNT     : in  std_logic_vector(9 downto 0);
        VGA_HS      : in  std_logic;
        VGA_VS      : in  std_logic;
        VGA_RGB     : in  std_logic_vector(23 downto 0);

        -- Audio (pixel-clock-domain side of the audio FIFO)
        AUDIO_I      : in  std_logic_vector(31 downto 0);
        AUDIO_VOL    : in  std_logic_vector(7 downto 0);
        AUDIO_EMPTY  : in  std_logic;
        AUDIO_OVF    : in  std_logic;
        AUDIO_POP    : out std_logic;
        AUDIO_STATUS : out std_logic_vector(1 downto 0);
        AUDIO_PKT    : out std_logic;

        -- HDMI pins (only the _P side is named; TD pairs the LVDS outputs)
        HDMI_CLK_P : out STD_LOGIC;
        HDMI_D2_P  : out STD_LOGIC;
        HDMI_D1_P  : out STD_LOGIC;
        HDMI_D0_P  : out STD_LOGIC
    );
end hdmi_tx;

architecture Behavioral of hdmi_tx is

    component hdmi_tx_core
        generic (
            AUDIO_EN   : integer;
            DVI_MODE   : integer;
            AUDIO_FS   : integer;
            IT_CONTENT : integer
        );
        port (
            clk_pixel       : in  std_logic;
            clk_pixel_x5    : in  std_logic;
            reset           : in  std_logic;
            hcnt            : in  std_logic_vector(9 downto 0);
            vcnt            : in  std_logic_vector(9 downto 0);
            rgb             : in  std_logic_vector(23 downto 0);
            hs              : in  std_logic;
            vs              : in  std_logic;
            audio_sample    : in  std_logic_vector(31 downto 0);
            audio_vol       : in  std_logic_vector(7 downto 0);
            audio_empty     : in  std_logic;
            audio_overflow  : in  std_logic;
            audio_pop       : out std_logic;
            audio_status    : out std_logic_vector(1 downto 0);
            audio_pkt       : out std_logic;
            HDMI_CLK_P      : out std_logic;
            HDMI_D0_P       : out std_logic;
            HDMI_D1_P       : out std_logic;
            HDMI_D2_P       : out std_logic
        );
    end component;

    signal reset_i : std_logic;

begin

    reset_i <= not RST_N;

    Inst_hdmi_tx_core : hdmi_tx_core
    generic map (
        AUDIO_EN   => AUDIO_EN,
        DVI_MODE   => DVI_MODE,
        AUDIO_FS   => AUDIO_FS,
        IT_CONTENT => 1
    )
    port map (
        clk_pixel      => PXLCLK_I,
        clk_pixel_x5   => PXLCLK_5X_I,
        reset          => reset_i,
        hcnt           => H_COUNT,
        vcnt           => V_COUNT,
        rgb            => VGA_RGB,
        hs             => VGA_HS,
        vs             => VGA_VS,
        audio_sample   => AUDIO_I,
        audio_vol      => AUDIO_VOL,
        audio_empty    => AUDIO_EMPTY,
        audio_overflow => AUDIO_OVF,
        audio_pop      => AUDIO_POP,
        audio_status   => AUDIO_STATUS,
        audio_pkt      => AUDIO_PKT,
        HDMI_CLK_P     => HDMI_CLK_P,
        HDMI_D0_P      => HDMI_D0_P,
        HDMI_D1_P      => HDMI_D1_P,
        HDMI_D2_P      => HDMI_D2_P
    );

end Behavioral;
