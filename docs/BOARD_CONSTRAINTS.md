# HX4S20 板级封装与约束

2026-11-02合并main后最新接线：用户选择采用队友main布局。SW4(C5)复位、SW3(C6)音频开关、KEY1/2音量减/加、KEY3/4下一张/上一张；J1-1加载，J1-2..5对比度/亮度，J1-6与7静音，J1-10(L14)轮播。SW1/SW2字幕接口暂未启用。原先SW1复位、SW4静音、J1-1/2切图、J1-3轮播的说明均为旧版本。接线、含义、冲突处理与本次新bit见[main按键布局](MAIN_KEY_LAYOUT.md)。


2026-11-02最新补充：已增加J1-3/G12常开轮播按键（另一端GND），按一次开启每张完全显示后计时五秒的自动循环，再按停止；原J1-1/2手动切图保留。板级默认启用16帧淡出—黑场换缓存—16帧淡入，单侧约0.269秒。当前41源，新bit为`FFF/slideshow_transition_20261102/HDMI_Player_slideshow_fade_20261102.bit`，setup +0.288ns、hold +0.023ns，仿真及构建通过，尚未上板。接线、操作、变更与验证见[五秒轮播与淡入淡出](SLIDESHOW_FADE.md)。以下旧版本说明作为历史记录，以本段最新状态为准。


2026-11-02补充：已修复旧末图编号缓存导致的两图循环条件；最新40源工程bit及验证记录见 [IMAGE_SWITCH_FIX.md](IMAGE_SWITCH_FIX.md)。最新setup +0.192ns、HWNS +0.023ns，音频及原功能保留；尚待实板复测。以下保留此前版本的功能说明与构建记录。

## 当前音频版本（2026-11-01）

在 d7f3204 外接切图版本上增加WAV背景音频，当前40个源文件，SW3(C6)向下开音频/向上关，SW4(C5)向下静音/向上正常；原SW1复位、SW2重载、四个KEY调图像和J1外接切图保留。音频错误也计入LED4锁存。格式、接线及全部结果见 [WAV_AUDIO.md](WAV_AUDIO.md)。

最新bit为 `C:/Users/31640/Documents/ChatGPT/FFF/audio_wav_20261101/HDMI_Player_WAV_audio_20261101.bit`，setup +0.191ns、HWNS +0.010ns；本轮音频尚未上板试听。以下保留GPIO版和更早的历史记录，其中源文件数、旧bit、音频关闭状态均以本段为准。


## 当前控制与构建（2026-11-01）

当前板级顶层为 `hdmi_player_board_top`，TD 清单为36个源文件。SW1(C8)复位、SW2(C7)重载当前图片；KEY1(A2)/KEY2(B2)调对比度，KEY3(B1)/KEY4(C1)调亮度。新增 J1-1(D14)上一张、J1-2(G11)下一张，常开按键分别接 GND，内部上拉，首尾循环。接线、电平、行为及完整测试见 [GPIO_NAVIGATION.md](GPIO_NAVIGATION.md)。

本轮 bit 为 `C:/Users/31640/Documents/ChatGPT/FFF/gpio_navigation_20261101/HDMI_Player_GPIO_navigation_20261101.bit`；本轮布局布线 setup +0.145ns、HWNS +0.030ns、终点检查15004项无负余量，尚未上板。原PLL 100MHz/306°配置保留。以下是此前检查的历史记录，其中旧 KEY1复位/KEY2加载、固定索引0、34源文件、旧bit的说明均以本段当前配置为准。

## 历史记录

2026-10-29 上板准备复核：已重新构建并生成独立的新 bit；主工程 Runs 中原 bit 仍是旧版本，请使用[上板准备记录](BOARD_READINESS.md)指定的新文件。以下保留历史约束过程，当前结论以上板准备记录和时序修复记录为准。


最新说明（2026-10-28）：管脚与板级封装保持不变。memory已改100 MHz/306°，最新布线setup +0.104 ns、min +0.031 ns，第四字Z已在生产PLL/IP模型测试中解决。SDC使用跨域源网络及目标时钟、复位同步链SR和有波形证明的32位读输入边沿关系；新增memory捕获预算。下文首次约束核对中的-6.566/-6.565及180°为历史记录，最新结果见[SDRAM_TIMING_CLOSURE.md](SDRAM_TIMING_CLOSURE.md)。


后续更新：原写地址 -6.566 ns 长路径已修复，布线后该输出路径建立裕量 +6.656 ns。整机另有 SDRAM DQ、FIFO 和复位时序项，整体 Routed 最差 -6.565 ns，仍未完整收敛。下文原写地址分析是首次加入约束时的历史证据，最新结果见 [ADDRESS_TIMING_FIX.md](ADDRESS_TIMING_FIX.md)。

更新：2026-10-28。用户选择首次上板固定图片序号和缓存池基址为 0，增加薄板级封装，并用按键启动。

## 打开哪个工程

打开 `project/td/HDMI_Player.al`。TD 顶层现在是 **`hdmi_player_board_top`**，内部例化原来的 `hdmi_player_top`。原 Storage、Memory、Display 业务模块、两组 PLL 参数均未改动。系统核心仍保留完整配置接口，板级封装只固定 `file_index=0`、`frame_base_addr=0` 并处理按键和指示灯。

工程清单已经加入：

- `constraints/hx4s20_hdmi_player.adc`：物理管脚与电气标准。
- `constraints/hx4s20_hdmi_player.sdc`：50 MHz 输入时钟、真实 PLL 派生时钟、复位/按键输入例外、FIFO Gray 总线和帧描述跨域延迟限制。
- `rtl/top/hdmi_player_board_top.v`：板级控制封装。

两个约束文件都属于 `constraint_1`，在 Synthesis / PhysicalDesign 中启用；源码清单共 34 个 Verilog/VHDL 文件。不需要把旧的 `rtl/display/constraints.adc`、`test_cons.adc` 或独立 demo 约束再加入主工程。

## 使用方式

上电后封装先保持约 20 ms 复位，再同步释放。**KEY1 复位，KEY2 加载**，两者按下都是低电平。KEY2 带两级同步与约 20 ms 消抖；长按只产生一次请求。系统尚未就绪或正在加载时，可以保留一个请求，等 `load_ready` 后执行；不会把长按转换为重复加载。

第 0 张图遵循 Storage 的 `file_index=0` 枚举规则，不是指定某个固定文件名。缓存池位于 SDRAM 字地址 0，另一个槽位由 Memory 自动选择。仍支持宽度为 4 的倍数、尺寸不超过 640×480 的 BMP，小图补黑。

四个独立绿色 LED 均为高电平点亮：

| 板上标识 | 顶层端口 | 含义 |
| --- | --- | --- |
| LED1 | `LED[0]` | Memory PLL 锁定且 SDRAM 初始化完成 |
| LED2 | `LED[1]` | SD 卡初始化完成 |
| LED3 | `LED[2]` | 已有有效前台帧，不表示显示内容逐像素正确 |
| LED4 | `LED[3]` | 加载错误或显示欠载曾发生，保持到复位 |

显示状态经过两级同步进入 SYS_CLK。LED4 保持便于观察短暂错误，下一次正常显示不自动清除。

## 管脚表

当前约束选择 **HDMI A**，首次连接显示器请插 HDMI A。

| 顶层信号 | FPGA 管脚 | 标准 / 来源 |
| --- | --- | --- |
| `SYS_CLK` | R7 | 50 MHz 有源晶振，LVCMOS33 |
| `Reset_n` | A2 | KEY1，LVCMOS33，上拉 |
| `KEY_LOAD_N` | B2 | KEY2，LVCMOS33，上拉 |
| `LED[0]` | A4 | 独立 LED1，LVCMOS33 |
| `LED[1]` | A3 | 独立 LED2，LVCMOS33 |
| `LED[2]` | C10 | 独立 LED3，LVCMOS33 |
| `LED[3]` | B12 | 独立 LED4，LVCMOS33 |
| `sd_cs_n` | A12 | TF DAT3 / CS，LVCMOS33 |
| `sd_sck` | A14 | TF CLK，LVCMOS33 |
| `sd_mosi` | A13 | TF CMD / DI，LVCMOS33 |
| `sd_miso` | B14 | TF DAT0 / DO，LVCMOS33，上拉 |
| `HDMI_CLK_P` | K1 | HDMI A CLK，LVDS33；配对 N 为 J1 |
| `HDMI_D0_P` | F5 | HDMI A D0，LVDS33；配对 N 为 F4 |
| `HDMI_D1_P` | E3 | HDMI A D1，LVDS33；配对 N 为 E4 |
| `HDMI_D2_P` | B3 | HDMI A D2，LVDS33；配对 N 为 D3 |

HDMI 负端由 TD 按 LVDS33 自动占用，不增加虚假的 N 端 RTL 端口。四个独立 LED 与数码管/双色 LED 阵列不同，不能使用 C15/C16 等数码管段选管脚替代。C5 是 SW4 拨动开关，不是本次使用的复位按键。

SDRAM 是 FPGA 封装内 SIP 器件，通过 `EG_PHY_SDRAM_2M_32` 接入，没有再给它分配外部 GPIO。TF 的 DAT1、DAT2 本次 SPI 通路不使用，不额外驱动。

## 时序约束及验证

`SYS_CLK` 周期 20 ns；`derive_clocks` 根据两组真实 PLL 参数推导时钟，已核对：

- Memory：100 MHz、100 MHz、100 MHz / 306°（当前配置）。
- Display：125 MHz 与 25 MHz。

没有用旧说明中的 25.175 MHz 覆盖实际 PLL；没有修改 SDRAM 相位。像素域与其 5 倍频串行域的时序关系保留，不作整组 false path。

外部复位和 KEY2 输入属于异步输入。KEY2 只进入第一级同步寄存器；从外部端口开始的 false path 不会切掉第一级到第二级的寄存器路径。两个异步 FIFO 的 Gray 指针到首级同步器数据输入都限制为 8 ns；后续同步级保持正常时序分析。保持型帧描述总线及其请求/确认首级同步也有 8 ns 的数据路径限制。

TD 最终网表确认：写 Gray 首级 17 位，读 Gray 首级 17 位，标量请求/确认/完成首级 3 位，优化后的有效帧描述目的寄存器 19 位；四组约束均生效，没有 Shadowed 或 Ignored。没有添加跨时钟全局 false path 掩盖 CDC 物理路径。

已验证：板级封装功能测试、包含真实厂商库的完整 34 文件层级展开、TD ADC/SDC 加载和 gate 综合。15 个逻辑管脚均分配，TD 使用 19 个实际 PAD，含 4 个 HDMI 自动配对负端。当前资源约 LUT 31.49%、寄存器 15.83%、BRAM9K 6、PLL 2。

**约束被正确加载，不等于时序已通过。** 首次约束核对的综合报告最差建立时间裕量 **-6.566 ns**。最差路径从帧高度描述寄存器到厂商 IP 的写地址寄存器，经过写地址乘法和多级加法，组合数据路径约 14.450 ns，而 125 MHz 单周期预算是 8 ns。需进一步检查该路径的数据有效条件和逐行地址实现；当次没有修改 writer，也没有用未经证明的 multicycle/false path 把它隐藏。后续已完成 writer 修复及一次布局布线，详细结果以最新修复文档为准。

SD 卡外部输入/输出延迟、HDMI 板级偏斜/电气时序、PLL 抖动预算尚需单独核定，本次没有填入猜测的 I/O delay 数值。报告中的 STA coverage 不能代替这些接口的签核。此前 180° 配置与 SDRAM 参考器件模型的第四字 Z 问题仍单独保留。

因此本次完成的是可加载的板级约束与控制封装，当前下一步处理剩余的 SDRAM 采样、FIFO 控制和复位时序，补齐接口预算后重新验收布局布线，再生成下载文件和分阶段上板。

## 资料依据

在用户提供的 `HX4S20_Contest_202606` 中核对并渲染检查：

- `9_康芯开发板使用手册及实验平台/HX4S20开发板手册-HDL版2410.pdf`：PDF 第 6 页 LED、第 8 页 HDMI A、第 18–19 页拨动开关及按键、第 20 页 TF、第 21–22 页晶振。
- `3_原理图/开发板原理图/2_FPGA.pdf` 第 1 页：FPGA 球位、时钟及信号网络。
- `3_原理图/开发板原理图/6_EX_DEVICE.pdf` 第 1 页：LED 极性、按键上拉、TF SPI 连接。
- `2_Example/DEMO_TD版本6.2.1.zip` 中的呼吸灯、按键、SD 和 HDMI 示例约束交叉核对；未运行归档脚本或下载旧 bit。

原始证据、快照、约束目标数量和 TD 报告保存在 `C:/Users/31640/Documents/ChatGPT/FFF/board_constraints_20261028/`。
