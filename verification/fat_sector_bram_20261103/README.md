# FAT同步扇区缓存回归

见 [实现、测量及验证边界](../../docs/FAT_SECTOR_BRAM.md)。

- `run.py --output <新目录>`：公共接口23场景，既可测新实现也可通过`--project <目录>`对照原版。
- `cache_tb.sv`：独立检查固定夹具的字节、元数据、last、背压稳定、连续吞吐、错误及复位恢复。没有force DUT信号。
- `audit_timing.py --build <TD输出目录>`：核对最终普通/例外路径端点、64项DQ输入/64项DQ输出和负余量。

完整板级构建沿用`verification/subtitles_20261103/rebuild_td.py`，所有日志输出到显式指定的新目录。ModelSim默认`D:/modelsim2020/win64`，TD默认`C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116`。
