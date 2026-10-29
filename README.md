# FPGA HDMI Multimedia Player

基于安路 FPGA 的 HDMI 多媒体播放系统。

## 当前主工程与显示对接

打开 `project/td/HDMI_Player.al`，板级顶层为 `hdmi_player_board_top`，内部系统核心为 `hdmi_player_top`。现已连接 Storage、SDRAM 双帧缓存及 HDMI Display，使用写入和显示两条异步 FIFO。系统显示为 640×480，支持宽度四字对齐的小图补黑；当前顶层关闭音频和 OSD。

- [SDRAM 时序与第四字 Z 修复](docs/SDRAM_TIMING_CLOSURE.md)
- [写地址时序修复与剩余问题](docs/ADDRESS_TIMING_FIX.md)
- [板级管脚、约束和按键说明](docs/BOARD_CONSTRAINTS.md)
- [当前工程结构](docs/PROJECT_STRUCTURE.md)
- [Display 目录导航](rtl/display/README.md)
- [Display 历史资料归档](archive/display_legacy/README.md)
- [双帧缓存、接口和测试边界](docs/DISPLAY_MEMORY_INTEGRATION.md)
- [最新进度](docs/PROJECT_PROGRESS.md)
- [可重复集成测试](verification/display_memory_20261028/README.md)

当前 memory 生产配置为100 MHz、SDRAM转发306°，display仍125/25 MHz。DQ/FIFO/复位时序及第四字Z已修复：最终布线setup +0.104 ns、min/hold +0.031 ns；实际PLL/IP全尺寸7帧、2150400像素及后台写入通过，8865次刷新。尚未做板级验收，外部SPI/HDMI时序预算、四字尾包与运行中失锁自动重播仍需处理。完整证据及测试范围见最新修复记录。

## 项目功能
- SD/TF 卡读取 BMP 图片
- SDRAM 图像帧缓存
- HDMI 图像显示
- HDMI 音频输出
- 按键切换和自动轮播
- 图片转场与 OSD 扩展

## 项目分工
- storage：SD 卡读取与 BMP 解析
- memory：FIFO 与 SDRAM 控制
- display：HDMI 视频与音频输出

## 工程目录
- rtl：Verilog 设计源码
- tb：Testbench 仿真文件
- constraints：引脚与时序约束
- docs：项目文档
