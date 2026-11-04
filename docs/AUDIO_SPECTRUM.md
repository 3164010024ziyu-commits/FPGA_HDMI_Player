# WAV 音频频谱与按键叠加

2026-11-03最新：图片信息字幕和音频播放进度已接通；SW2控制底部图片序号/短文件名/尺寸，SW1控制左上角音频HH:MM:SS。J1-8/9短按左右步进、长按自动滚动，同时按回到起点。20档音量、轮播、频谱均保留。详见[字幕与播放进度](SUBTITLES.md)；尚未上板。以下记录按其日期与版本理解。


2026-11-02，基于 memory `b995975`。用户要求新增按键，在播放音频时显示频谱，并从GitHub寻找可参考实现。当前方案采用512点定点FFT、Hann窗、16个近似对数频段及右下角半透明柱形面板；按用户决定不开发FPGA图片缩放。

## 接线和使用

新增常开按键：一端接 **J1第13脚，GPIOA_10／FPGA M14**，另一端接 **J1第12或30脚GND**。内部上拉，LVCMOS33，无需外接电源；依据HX4S20手册PDF第13页，已核对未占用main的J1-1..10控制。

- 上电或SW4复位后，频谱默认关闭。按一次开启，再按一次关闭；两级同步、约10.49ms消抖，长按只触发一次。
- SW3向下开启WAV。找到符合48kHz／16位／双声道整数PCM格式的文件，完成预缓冲后，频谱面板自动出现；音频关闭、没有兼容WAV或播放进入故障/重缓冲时隐藏。
- 在音频关闭时也可切换频谱开关；选择会保留，后续开始播放时自动显示。不需要先加载图片。
- KEY1/KEY2音量、J1-6源静音及J1-7HDMI静音都会反映到频谱。静音后采样能量归零，柱形按每帧2像素衰减；不是立即硬清屏。取消静音后恢复随音乐跳动。
- 音频开关关闭后面板在下一次垂直消隐隐藏，最多约一帧延迟；频谱选中状态保留。关闭频谱只停止分析/叠加，不停止WAV、不暂停音频，也不修改图片或缓存。
- 当前接线仍是SW4复位、SW3音频、KEY3/KEY4下一张/上一张、J1-10自动轮播。SW1/SW2字幕接口仍未启用，详见[完整按键布局](MAIN_KEY_LAYOUT.md)。

## 屏幕位置和频率含义

面板位于640×480画面的 **x=304..591、y=328..443**，大小288×116。背景为原图亮度的一半，16根彩色柱形从低频到高频排列，最大高度72像素，快速上升、缓慢回落。与右侧参数条的y=160..319区域分开，未新增像素流水延迟。

512点FFT在48kHz下频点间隔为 **93.75Hz**。DC零频点不参与柱形聚合，使用正频点1..255；16段采用区间最大幅度，不是16个孤立单频谐振器，正频范围内每个频点均归属一个柱形。

| 柱号 | 频点范围 | 对应频率范围 Hz |
| --- | --- | --- |
| 1 | 1 | 93.75 |
| 2 | 2 | 187.5 |
| 3 | 3 | 281.25 |
| 4 | 4 | 375 |
| 5 | 5–6 | 468.75–562.5 |
| 6 | 7–9 | 656.25–843.75 |
| 7 | 10–13 | 937.5–1218.75 |
| 8 | 14–19 | 1312.5–1781.25 |
| 9 | 20–27 | 1875–2531.25 |
| 10 | 28–39 | 2625–3656.25 |
| 11 | 40–56 | 3750–5250 |
| 12 | 57–79 | 5343.75–7406.25 |
| 13 | 80–112 | 7500–10500 |
| 14 | 113–159 | 10593.75–14906.25 |
| 15 | 160–207 | 15000–19406.25 |
| 16 | 208–255 | 19500–23906.25 |

面板100／1k／10k／24k为概略刻度，不是等间隔线性坐标或校准仪器刻度。幅度使用`max(abs(re),abs(im))+min(abs(re),abs(im))/4`的近似，再转近似log2柱高；不是校准dBFS测量。Hann窗减轻频谱泄漏，每级FFT缩小1/2，共1/512归一化；低于93.75Hz的细节不能独立分辨。

左右声道分别计算一块内的绝对值能量，下一块选用能量较大的一个声道做FFT，并在整块内保持该选择。这样右声道单独播放或反相立体声不会因左右平均而消失；显示不是两声道独立双排频谱，首次右声道选择最多延后一块。

分析捕获512个连续采样后进行计算，计算期间的观察采样会略过，随后再捕获下一块。音频播放始终连续，不受FFT busy影响；它是分块音乐可视化，非无间隙测量采集。显示仅在垂直消隐快照完整柱高，活动帧不会混用两批分析结果。

## 数据通路和代码

WAV播放器新增一个注册`playing`状态，表示开启、预缓冲完成、无致命故障且显示接收端就绪。这个状态不参与原音频数据控制。经Storage/Core送入Display，并两级同步到像素域。

FFT直接观察已有音频FIFO在HDMI消费时的采样，使用同一音量系数做定点缩放，再加窗；源静音已经在WAV采样中体现，HDMI静音通过音量系数体现。FFT、频段聚合、面板均在原25MHz像素域，不另跨PCM总线，不改音频FIFO ready/pop，不增加SDRAM读写、PLL或图像帧缓存。

| 文件 | 本次作用 |
| --- | --- |
| `rtl/display/src/audio_fft512.v` | 从MIT许可参考核适配512点、注册乘法、内嵌系数ROM、线性幅度输出 |
| `rtl/display/src/audio_spectrum.v` | 声道选择、音量缩放、Hann窗、FFT旁路观察、16段聚合与对数柱高 |
| `rtl/display/src/spectrum_overlay.v` | 半透明面板、彩色柱形、刻度、逐帧平滑/启停 |
| `rtl/display/src/hdmi_tx_display.v` | 频谱按键消抖、播放状态同步、分析与HDMI像素叠加 |
| `rtl/top/hdmi_player_board_top.v`、`hdmi_player_top.v` | M14输入接入和频谱参数启用 |
| `rtl/storage/wav_audio_player.v`、`storage_pipeline.v` | 只增加注册播放状态及其接口，不改变音频播放逻辑 |
| `constraints/`、`project/td/HDMI_Player.al` | 新GPIO、状态CDC及完整44个Verilog/VHDL源清单 |

通用Core/Display的`ENABLE_SPECTRUM`默认0，板级封装默认1；按键运行时仍默认关闭。ROM系数直接初始化在源码内，不依赖额外hex文件或绝对路径。字幕字体ROM不参与本面板绘制。

## GitHub参考与许可

已实际搜索并读取以下项目；未执行外部仓库脚本或安装其工具链。

1. **采用：[mebner86/icesugar-pro_sound2fft](https://github.com/mebner86/icesugar-pro_sound2fft)**，原始[fft256.v](https://github.com/mebner86/icesugar-pro_sound2fft/blob/main/rtl/fft256.v)。共享内存蝶形、逐级缩放和HDMI可视化结构适合本器件。适配后的核心保留Martin Ebner版权和MIT许可，完整许可位于`rtl/display/licenses/sound2fft-MIT.txt`。本地改为512点、额外乘法寄存、内嵌系数、输出线性幅度；窗函数、声道选择、频段聚合、面板与接口为本项目新增实现。输入来自SD卡PCM，未移植其I2S麦克风、PLL、HDMI驱动或板卡约束。
2. [mattvenn/fpga-sdft](https://github.com/mattvenn/fpga-sdft)：滑动DFT，作者说明了缩放及模型核对；未移植，避免改变当前分块FFT选择。
3. [ZakriyaParacha46/fpga-audio-spectrum-analyzer](https://github.com/ZakriyaParacha46/fpga-audio-spectrum-analyzer)：Goertzel频段、对数压缩及柱形展示参考，未复制代码；其XADC/VGA通路与本项目不同。
4. [ZipCPU/dblclockfft](https://github.com/ZipCPU/dblclockfft)：可配置流水FFT生成器，考虑到本项目只需音频速率及现有资源，未移植该生成器。

## 验证与最终构建

验证、物理保持修复和bitgen均已完成。本轮代码、约束、MIT许可、回归测试及文档已纳入2026-11-02本地memory分支Git保存，未推送GitHub、未上板。本次保存未重复编译。

| 检查 | 结果 |
| --- | --- |
| 512点FFT | 16组输入、8192个输出幅度与独立定点参考逐值一致；浮点NumPy复数参考最大误差6个量化单位；含静音、DC、满幅、脉冲、低/中/高频、双音、随机输入、忙时输入忽略、未满块禁用重启 |
| 频谱处理 | 12组、16柱逐值一致，含Hann、右声道独播、反相立体声、两声道能量选择、双音、音量、静音和关闭清空 |
| 叠加 | 33408像素面板区域、区域外与消隐原样输出、帧边界启停/快照、每帧2像素回落、零像素延迟通过；已查看RTL生成的640×480预览 |
| 实际板级/SD/WAV/HDMI | 两次图片加载256源像素，15262音频CDC采样逐值正确，25次频谱更新，80922实际叠加像素；源静音、HDMI静音、音频关闭隐藏、重启恢复、按键抖动/长按、隐藏后继续出声及复位通过，错误0 |
| 原有功能 | 音频解析10场景、SPI/音频5000播放采样、独立HDMI4796采样、导航/FAT28/SPI6、六图五秒缩参轮播/淡入淡出及主按键回归通过 |
| 真PLL/厂商SDRAM/未改参考模型 | 768像素、6帧读回通过，Z字0、错误0、刷新5次，PLL启动检查100次通过 |
| 最终时序 | **setup +0.120ns，hold +0.030ns**；20939项已导出检查无负余量，64项DQ输入检查 |
| 最终资源 | 16415/19600 LUT，28/64 BRAM9k，16/29 DSP，2/4 PLL；44个Verilog/VHDL源文件 |

新bit：`C:/Users/31640/Documents/ChatGPT/FFF/audio_spectrum_20261102/HDMI_Player_audio_spectrum_20261102.bit`。
SHA-256：`a1cc81444cb0b9006b10518323980a9a25cbd8cd5cf55940eca1d990f7d43923`。

上板验证包：`FFF/audio_spectrum_20261102/HDMI_Player_audio_spectrum_package_20261102.zip`，含新bit、MIT许可、接线操作说明、RTL预览及13秒分段测试音SPECTRUM.WAV。临时只保留这一首兼容WAV更容易确认选中了测试音（先备份原文件）；图片可保留。该测试音按低频→高频→右声道单独→反相立体声→静音排列，格式48kHz/16位/双声道整数PCM。

本轮资源增加暴露了旧显示状态同步入口的普通hold检查：补充frame_ready、underflow及read_error_sync到SYS域首级的8ns数据路径约束，后续同步级仍正常计时。新增playing状态使用相同的首级路径限制。使用TD官方`fix_hold`物理修复其余短路径，包括既有复位/PCM RAM地址路径；**最终没有修改memory复位逻辑、PLL或SDRAM读写RTL，没有保留试验性的下降沿释放，也没有放宽SDRAM约束。** 第三轮试验的额外最小延迟选项未保留，最终SDC已清理并重新加载后审计，无约束解析错误。前期中间报告存于initial_timing、second_timing、pre_hold_fix，不是最终验收结果。

重建时需要包含保持修复步骤；TD官方DefaultFlow本身提供fix_hold。工程内还提供可查看的完整命令脚本：`python verification/audio_spectrum_20261102/rebuild_td.py --output "$env:TEMP/fpga_spectrum_td"`，默认本机TD6.2.1路径，可用--td-root指定。脚本先综合，再place/route/fix_hold，检查余量后才bitgen。通过的STA覆盖已建立约束，原外部SPI/HDMI电气预算和厂商SIP告警边界保留。

下一步按新接线下载本次bit、SW4复位释放、SW3开启音频，按J1-13观察频谱；验证两路静音、音量、关频谱后声音连续、切图/轮播并发及长时间运行。以上不是实板照片或实板试听结果。


工程根目录可重复运行：

```powershell
python verification/audio_spectrum_20261102/run.py --output "$env:TEMP/fpga_audio_spectrum"
```

`--units-only`只运行短算法与叠加测试；默认还运行实际板级、SD SPI、WAV、音频CDC、双缓存及HDMI集成，SDRAM应用端使用模型。ModelSim默认D:/modelsim2020/win64，可用`--simulator-bin`覆盖。真实厂商库层次、SDRAM模型读回和物理时序另行验证，不能把行为模型仿真当作上板验收。
