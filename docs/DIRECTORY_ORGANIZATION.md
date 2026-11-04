# Display 目录整理记录

日期：2026-10-29。范围：整理当前工程目录，不修改 RTL 逻辑、模块端口、模块连接、PLL 配置或约束。

## 当前目录

```text
rtl/display/
├─ src/                 当前 RTL、VHDL、enc 编码模块与字库
├─ ipsrc/clock_ip/      当前显示 PLL 及生成配置
├─ tb/                  原显示单模块仿真与替代模型
├─ tools/               字库生成脚本
├─ docs/                原音频/字幕功能说明
└─ README.md            当前工程入口及维护导航

archive/display_legacy/
├─ puresrc/             原参考副本
├─ ipsrc/al_ip/         未被当前系统采用的旧 SDRAM IP
├─ HDMI_display.al      原独立工程及同目录旧约束
├─ HDMI_display_Runs/   原综合、布局布线结果
├─ log/                 原日志；其他散落日志、bit、dump 亦保留
├─ MANIFEST.json        274 个文件的新旧路径、字节数、SHA-256
└─ README.md            历史资料适用范围
```

274 个文件共 28,362,795 字节原样搬迁，没有丢弃旧源码、日志、工程、字库或 bitstream。旧独立工程按历史资料保存，不保证在新位置直接运行；原有绝对路径及已经缺失的 demo 顶层没有改写或恢复。

当前系统继续打开 `project/td/HDMI_Player.al`，顶层继续为 `hdmi_player_board_top`。34 个源文件清单及所有当前源码路径保持不变，因此现有构建与验证脚本不需要修改路径。字库暂留 `src/`，避免改变其路径依赖。原音频/字幕文档中的旧引脚、时钟和 demo 烧录说明不代表集成工程状态；当前状态以项目进度和约束说明为准。

更新了根 README、工程结构、项目进度、display 导航和归档说明。`.gitignore` 增加 display 本地新日志、构建目录、旧独立工程生成的 bit/dump/状态文件过滤；归档目录未忽略，搬迁资料仍可纳入版本管理。

## 本轮检查

- 274 个搬迁文件逐一 SHA-256 核对通过，原位置均已搬离。
- 70 个保留的 RTL/字库/IP 配置/仿真/说明/工具/include/约束/主工程文件逐一字节校验通过。
- 主工程 34 个 Verilog/VHDL 源文件及约束引用均存在。
- 使用 ModelSim 和真实厂商库完成生产源文件编译、VHDL 编译及 `hdmi_player_board_top` 层次展开，`REAL_HIERARCHY_PASS`。
- 本轮是目录整理，没有重新执行功能长仿真或布局布线；先前时序与功能记录仍是上一轮测试结果。

检查复现：从项目根目录执行 `python verification/display_memory_20261028/run.py hierarchy`。需已配置 ModelSim 与厂商库；脚本默认输出到系统临时目录。本次详细日志保存在 FFF 工作区的 `display_cleanup_20261029/validation/`。

原有未提交的源码修改、已经删除的 `hdmi_demo_top.v` 均保持原状态。本轮没有提交或推送 Git，没有生成或下载新的 bitstream。

相关入口：[当前工程结构](PROJECT_STRUCTURE.md)、[Display 导航](../rtl/display/README.md)、[归档清单](../archive/display_legacy/MANIFEST.json)。
