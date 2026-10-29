# Display 历史资料（2026-10-29 归档）

这些资料从 `rtl/display/` 原样搬迁，保留原来的相对层次和文件内容，不参与当前主工程编译。

- `puresrc/`：导入时的参考副本，含重复模块和字库。
- `ipsrc/al_ip/`：未被当前主工程使用的旧 SDRAM IP；当前 memory 使用 `rtl/ip/sdram/`。
- `HDMI_display.al`、`constraints.adc`、`test_cons.adc`：旧独立显示工程及约束。
- `HDMI_display_Runs/`、`log/`、`td_*.log*`：旧综合、布局布线结果和日志。
- `*.bit`：旧独立显示演示的烧录文件；不是当前 storage/memory/display 集成工程的输出。
- `*.dmp`、隐藏状态文件：旧崩溃记录和工具状态。

此处是历史参考，不是可直接运行的独立工程。旧工程保留原路径，部分路径依赖原电脑，且 `hdmi_demo_top.v` 在本轮整理前已被本地删除。本轮未恢复该文件，也没有改写历史工程或历史日志中的路径。

请打开 [当前 TD 工程](../../project/td/HDMI_Player.al)，维护 [当前 display 源码](../../rtl/display/README.md)。搬迁清单及 SHA-256 见 [MANIFEST.json](MANIFEST.json)。
