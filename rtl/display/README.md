# 当前 Display 模块

当前系统唯一 TD 工程入口：[project/td/HDMI_Player.al](../../project/td/HDMI_Player.al)，板级顶层为 `hdmi_player_board_top`。主工程明确列出源文件，请按该清单编译，不要递归加入历史副本或仿真替代模块。

| 目录 | 用途 |
|---|---|
| `src/` | 当前显示 RTL、VHDL 包装和字库初始化文件 |
| `src/enc/` | HDMI/TMDS 编码、封包和串行输出 |
| `ipsrc/clock_ip/` | 显示 PLL 及生成配置，当前使用 `clk_wize.v` |
| `tb/` | 队友的单模块仿真与替代模型；不加入生产工程 |
| `tools/` | 字库生成工具；默认路径相对 `rtl/display/`，从该目录运行 |
| `docs/` | 原音频/字幕功能说明；其中旧 demo、引脚、时钟及烧录记录不代表当前集成配置 |

`src/hdmi_tx_display.v` 是 display 模块入口，`src/read_RAM.v` 生成显示时序并向 memory 请求像素。当前源码位置、内容、接口、字库相对路径及主工程清单均保持不变。`src/font_16x16_rom.v` 中原有电脑相关绝对路径未在本轮调整；当前顶层关闭 OSD，后续启用字库时需单独处理。

重复副本、旧独立工程、未使用的 SDRAM IP、历史构建目录、日志和旧 bitstream 已原样移至 [archive/display_legacy/](../../archive/display_legacy/README.md)。不恢复此前已删除的 `hdmi_demo_top.v`。

当前有效约束位于 [constraints/](../../constraints/)。集成验证见 [verification/display_memory_20261028/](../../verification/display_memory_20261028/README.md)，真实 PLL/SDRAM 验证见 [verification/sdram_timing_20261028/](../../verification/sdram_timing_20261028/README.md)。系统说明以 [PROJECT_STRUCTURE.md](../../docs/PROJECT_STRUCTURE.md) 和 [PROJECT_PROGRESS.md](../../docs/PROJECT_PROGRESS.md) 为准。
