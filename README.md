# FPGA HDMI Multimedia Player

基于安路 FPGA 的 HDMI 多媒体播放系统。

## 当前主工程与显示对接

打开 `project/td/HDMI_Player.al`，板级顶层为 `hdmi_player_board_top`，内部系统核心为 `hdmi_player_top`。现已连接 Storage、SDRAM 双帧缓存及 HDMI Display，使用写入和显示两条异步 FIFO。系统显示为 640×480，支持宽度四字对齐的小图补黑；板级工程现已启用 WAV/HDMI 音频、频谱、图片轮播、淡入淡出和字幕。底部字幕优先从卡根目录 UTF-8 `CAPTION.TXT` 读取，并按需从 `FONT16.BIN` 读取字形；支持最多64字，原有移动/滚动按键保持。

- [SDRAM 时序与第四字 Z 修复](docs/SDRAM_TIMING_CLOSURE.md)
- [写地址时序修复与剩余问题](docs/ADDRESS_TIMING_FIX.md)
- [板级管脚、约束和按键说明](docs/BOARD_CONSTRAINTS.md)
- [当前工程结构](docs/PROJECT_STRUCTURE.md)
- [Display 目录导航](rtl/display/README.md)
- [Display 历史资料归档](archive/display_legacy/README.md)
- [双帧缓存、接口和测试边界](docs/DISPLAY_MEMORY_INTEGRATION.md)
- [最新进度](docs/PROJECT_PROGRESS.md)
- [SD 卡中文字幕、字库和验证说明](docs/TXT_SUBTITLES.md)
- [图片同名配音、暂停与五秒同步轮播](docs/AV_SYNC.md)
- [可重复集成测试](verification/display_memory_20261028/README.md)

当前 memory 生产配置为100 MHz、SDRAM转发306°，display仍125/25 MHz。DQ/FIFO/复位时序及第四字Z的历史修复见相应记录。2026-11-03已增加图片同名配音同步与无损暂停，SW3停用。当前完整布线资源、时序和测试结果见AV_SYNC.md与最新进度；前一TXT版的17055 LUT/40 BRAM是历史基线，尚未做本版板级验收。外部SPI/HDMI时序预算、四字尾包与运行中失锁自动重播仍需处理。完整证据及测试范围以最新进度为准。

## 项目功能
- SD/TF 卡读取 BMP 图片
- SDRAM 图像帧缓存
- HDMI 图像显示
- HDMI 音频输出
- 按键切换和自动轮播
- 图片转场与 OSD 扩展
- SD 卡 UTF-8 中文字幕、移动和滚动
- 图片同名WAV自动配音、切图同步重播、暂停音频/时间

## 项目分工
- storage：SD 卡读取与 BMP 解析
- memory：FIFO 与 SDRAM 控制
- display：HDMI 视频与音频输出

## 工程目录
- rtl：Verilog 设计源码
- tb：Testbench 仿真文件
- constraints：引脚与时序约束
- docs：项目文档
