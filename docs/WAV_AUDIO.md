# SD 卡 WAV → HDMI 音频

2026-11-03最新：图片信息字幕和音频播放进度已接通；SW2控制底部图片序号/短文件名/尺寸，SW1控制左上角音频HH:MM:SS。J1-8/9短按左右步进、长按自动滚动，同时按回到起点。20档音量、轮播、频谱均保留。详见[字幕与播放进度](SUBTITLES.md)；尚未上板。以下记录按其日期与版本理解。


2026-11-02最新：已新增J1-13/M14常开频谱按键（另一端GND12/30），按一次开、再按关；播放WAV时在右下角显示512点FFT／16柱频谱，音量与两路静音反映到柱形，音频关闭时隐藏。保留main全部现有控制与J1-10轮播。最新bit及验证见[音频频谱](AUDIO_SPECTRUM.md)，尚未上板。以下旧记录按其版本理解。


2026-11-02合并main后最新接线：用户选择采用队友main布局。SW4(C5)复位、SW3(C6)音频开关、KEY1/2音量减/加、KEY3/4下一张/上一张；J1-1加载，J1-2..5对比度/亮度，J1-6与7静音，J1-10(L14)轮播。SW1/SW2字幕接口暂未启用。原先SW1复位、SW4静音、J1-1/2切图、J1-3轮播的说明均为旧版本。接线、含义、冲突处理与本次新bit见[main按键布局](MAIN_KEY_LAYOUT.md)。


2026-11-02最新补充：已增加J1-3/G12常开轮播按键（另一端GND），按一次开启每张完全显示后计时五秒的自动循环，再按停止；原J1-1/2手动切图保留。板级默认启用16帧淡出—黑场换缓存—16帧淡入，单侧约0.269秒。当前41源，新bit为`FFF/slideshow_transition_20261102/HDMI_Player_slideshow_fade_20261102.bit`，setup +0.288ns、hold +0.023ns，仿真及构建通过，尚未上板。接线、操作、变更与验证见[五秒轮播与淡入淡出](SLIDESHOW_FADE.md)。以下旧版本说明作为历史记录，以本段最新状态为准。


2026-11-02补充：已修复旧末图编号缓存导致的两图循环条件；最新40源工程bit及验证记录见 [IMAGE_SWITCH_FIX.md](IMAGE_SWITCH_FIX.md)。最新setup +0.192ns、HWNS +0.023ns，音频及原功能保留；尚待实板复测。以下保留此前版本的功能说明与构建记录。

更新：2026-11-01。基于 memory 分支 `d7f3204`，按用户授权增加背景音频，SW3 开关、SW4 静音，循环播放根目录中第一首兼容 WAV。功能仿真和 TD 编译、布线通过；尚未下载、试听实板。本轮代码、约束、测试及文档已保存到本地 memory 分支，未推送GitHub。

## 上板使用

1. SD 卡继续使用当前工程支持的 FAT32。把 BMP 和 WAV 一起放在**根目录**。
2. WAV 使用 **48 kHz、16 位、双声道、未压缩整数 PCM（格式标识 1）**。支持标准 RIFF/WAVE、额外 fmt 字段、JUNK/LIST 等未知块及奇数字节填充；不是固定跳过 44 字节。其他采样率、单声道、浮点、压缩和 WAVE_FORMAT_EXTENSIBLE 不支持。
3. 下载本轮 `HDMI_Player_WAV_audio_20261101.bit`。HDMI A 连接带音频播放能力的显示设备或 HDMI 音频接收设备；此功能通过 HDMI 输出，板上蜂鸣器及模拟音频插孔不使用。
4. SW1 向下复位、向上释放。SW3 向下开始播放，SW4 向上取消静音。通过现有 SW2 或 J1 外接按键加载/切换图片。

| 开关 | 管脚 | 向上（1） | 向下（0） |
| --- | --- | --- | --- |
| SW1 | C8 | 释放复位 | 系统复位 |
| SW2 | C7 | 释放加载控制 | 下降沿触发当前图片重载 |
| **SW3 / SW_AUDIO_N** | **C6** | 关闭音频，清空音频缓冲 | 开启，查找首首兼容 WAV 并循环 |
| **SW4 / SW_MUTE_N** | **C5** | 正常声音 | 静音，播放位置继续推进 |

SW3/SW4 均为两级同步、约 20 ms 消抖的电平开关。关闭再开启 SW3 会重新扫描并从第一首兼容 WAV 开头播放，不是暂停/续播。SW4 只把输出采样置零，不停止读卡或改变曲目位置。静音解除恢复当前播放位置。无需增加其他按钮；本轮不实现选曲、暂停或板上音量调节，显示设备可以调节音量。

枚举顺序沿用 FAT32 根目录目录项顺序，不按文件名排序。起始不兼容 WAV 会跳过，再尝试下一首，最多尝试 256 个 WAV 条目；找到兼容文件后固定循环该首。每个 WAV 上限 512 MiB。目录不存在兼容文件时报告音频错误，BMP 仍可读取。

提供了生成的 440 Hz、48k/16bit/双声道测试文件：`C:/Users/31640/Documents/ChatGPT/FFF/audio_wav_20261101/fixtures/TEST48K.WAV`。可复制到卡根目录测试；若卡上已有其他兼容 WAV，会先播放目录顺序靠前的文件。

SW3 关闭、启动预缓冲、出错或重新缓冲期间，HDMI 继续发送以 48 kHz 节奏提交的数字静音，保持音频时钟连续。

## 实现与接口

| 文件 | 作用 |
| --- | --- |
| rtl/storage/sd_sector_arbiter.v | 两个独立文件读取上下文共用原 SD SPI 主机，逐扇区轮询；完整 512 字节响应归属单一客户，取消音频时排空已接受的扇区 |
| rtl/storage/wav_audio_player.v | 查找首首兼容 WAV、循环/错误恢复、48k 分数累加节拍、静音、预缓冲和欠载检测；FAT 输出增加一字节弹性流水以满足时序 |
| rtl/storage/wav_stream_decoder.v | 解析 RIFF/fmt/data，检查文件及块边界、格式和对齐，按小端字节组成 `{L[15:0],R[15:0]}` |
| rtl/storage/pcm_sample_fifo.v | 同步 BRAM 缓冲，4096 个 RAM 位置加输出寄存器；启动预填充 1024 个立体声采样帧，约 21.3 ms；约 16 KiB 缓冲 |
| rtl/storage/fat32_bmp_reader.v | 增加文件扩展名及最小文件大小参数；默认 BMP 行为保留，另一个实例读取 WAV，不复制 FAT 实现 |
| rtl/storage/storage_pipeline.v | 共用原物理 SD 主机，接入扇区仲裁、WAV 上下文和音频输出；BMP ready/busy/done 不被 WAV 占用 |
| rtl/top/hdmi_player_top.v | 连接 PCM 到 Display，新增音频控制/状态，显式选择是否启用音频 |
| rtl/top/hdmi_player_board_top.v | SW3/SW4 同步消抖，板级显式启用音频，音频错误计入 LED4 |
| rtl/display/src/hdmi_tx_display.v | 音频 FIFO 写侧复位改为在 audio_clk 域同步释放 |
| rtl/display/src/enc/packet_picker.v | 修复音频包使用上一组四样本：发送当前 staging 样本，消除首包错误零数据和四样本延迟 |
| constraints / project/td/HDMI_Player.al | C6/C5 约束、音频/状态 CDC 路径约束、增加四个源文件，当前40个 Verilog/VHDL 文件 |

通用 `hdmi_player_top` 和 `storage_pipeline` 的 `ENABLE_AUDIO` 默认 0，以兼容原图像测试及独立使用；实际板级封装显式设置 `ENABLE_AUDIO=1`。独立例化应用核心时，需开启参数并连接 `audio_enable`、`audio_mute`。音频输出为 `audio_sample[31:0]`、`audio_valid`、`audio_ready`，每组为左右各16位有符号采样，按48k提交，而不是突发灌入HDMI。

Memory 模块、PLL 参数、厂商 SDRAM IP、图片像素地址和双帧缓存逻辑未修改。音频不占 SDRAM 图片帧缓存。已有 GPIO 图片切换、亮度和对比度按键保留。

## 自检与时序结果

- WAV 解析：10 个用例通过，包括 2048 个逐帧左右声道比对、背压稳定性、奇数 JUNK 填充、非法声道/位宽/采样率、RIFF/chunk 越界及错误后重试。
- 真实 SD SPI → WAV → 音频 FIFO → HDMI 包：5000 个播放采样帧准确，含跨碎片簇、跳过单声道文件、循环、静音推进287帧、同时读取BMP、关闭时排空、CRC错误隔离/恢复、无WAV时保留BMP；核对6148个HDMI输出采样、1537个音频包、128个ACR包。
- 独立 HDMI 音频：4796 个样本逐值核对，1199个音频包、99个ACR、25个IEC60958块起始。修复前第一个样本预期 `0063ff9c`、实际 `00000000`，修复后通过。
- SW3/SW4：映射、短抖动过滤、静音/开关、LED4错误锁存、复位通过；原外接GPIO切图测试通过。
- 实际应用顶层 + VHDL HDMI 封装 + SD SPI + 音频 CDC + Memory 应用模型：两次图片加载、256源像素、1820音频CDC采样、静音115帧通过，前台帧有效、所有错误标志为0。
- 原回归：40源文件/厂商IP真实层次、Memory/Display14帧1792像素、Storage/SPI/HDMI图像系统、GPIO首尾循环/末图、FAT 28场景/末图SPI6场景及原MBR18+6场景通过。
- TD综合/布局布线/bitgen：**setup +0.191 ns，HWNS +0.010 ns**。17002项已导出终点检查无负余量，含64项SDRAM DQ输入检查；SW_AUDIO_N=C6、SW_MUTE_N=C5、均为LVCMOS33/PULLUP。资源：12691 LUT（64.75%）、21/64 BRAM9k、9/29 DSP、2/4 PLL。

首轮时序发现音频写域复位跨域释放、音频mailbox与原帧缓存状态同步路径缺少明确CDC约束；现已同步释放复位，并对实际跨域源网施加8ns数据路径限制，保留后续同步器级及内部数据通路计时。对WAV解析的真实建立违例增加了弹性字节寄存器。未放宽PLL或SDRAM数据时序。仍有原厂SIP初始位置调整和本地时钟路由等已有工具告警。

可重复测试：

```powershell
python verification/wav_audio_20261101/run.py --output "$env:TEMP/fpga_wav_audio"
```

默认 ModelSim 路径 `D:/modelsim2020/win64`，可用 `--simulator-bin` 指定。日志、`results.json` 保存在输出目录；核心集成的 Memory 使用行为模型，功能仿真和STA不替代实板音质验证。构建、原始测试日志、源码快照和测试音源保留在 `FFF/audio_wav_20261101/`。

## 错误与边界

普通模式 LED4 增加音频错误锁存，复位清除；关再开 SW3 清除播放器内部错误并重试，但不能清除已经锁存的 LED4。音频错误与 BMP 的 `load_error` 分离。

| audio_error_code | 含义 |
| --- | --- |
| B6 | 没有找到兼容WAV（枚举到末尾） |
| B7 | WAV解析失败或超过候选搜索上限 |
| B8 | 启动后音频缓冲欠载，输出静音并重新预填充 |
| B9 | 音频发送时HDMI侧未就绪，未丢弃FIFO队首样本 |
| 其他 | 原SD/FAT错误码，如CRC或目录链错误 |

512字节轮询仲裁保证双方有机会读卡；SD卡长时间无响应仍可能超过约85ms缓冲，触发B8。极短WAV每圈重扫目录会增大开销，不能承诺无缝循环；秒级或更长的测试文件更适合首次试听。未实现热插拔、44.1k、格式转换、压缩解码、随机选曲或暂停续播。原四字尾包限制不变。

格式核对依据：[Microsoft WAVEFORMATEX](https://learn.microsoft.com/en-us/windows/win32/api/mmreg/ns-mmreg-waveformatex)。开关电平及引脚依据用户《HX4S20开发板手册-HDL版2410》PDF第18页，已渲染核对并由最终TD物理报告确认。

bit：`C:/Users/31640/Documents/ChatGPT/FFF/audio_wav_20261101/HDMI_Player_WAV_audio_20261101.bit`。
SHA-256：`6e75833233f07b36de1a400143fecbf11091a01e96e5faeb0604111e9977b8ed`。

下一步：复制测试WAV到卡根目录，确认HDMI接收端可播放声音，下载新bit，SW1复位后SW3向下、SW4向上试听，再验证静音、关/开重播及播放中切图；记录画面、声音和LED4。尚无本轮实板结果。
