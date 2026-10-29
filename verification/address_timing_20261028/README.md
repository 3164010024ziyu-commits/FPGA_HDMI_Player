# 写地址时序修复验证

从工程根目录运行：

```powershell
python verification/address_timing_20261028/run.py
```

需要 ModelSim，可用 `MODELSIM_BIN` 指定其可执行文件目录。默认结果写到系统临时目录 `hx4s20_writer_address`，也可用 `--output` 指定目录，不修改 RTL。

- 地址矩阵：84 帧、777752 字，覆盖不同宽高、正反向、变化基址、无复位连续帧、随机 FIFO 停顿及写组中的刷新等待；比较完整 21 位地址和每个数据字。
- 旧地址回归：3 组、24 字，使用此前保存的场景，期望零地址错误。
- 原有 Memory/显示/Storage 回归：沿用 `verification/display_memory_20261028/run.py`，本次修改后的版本已重新通过 unit / raster / system。真实 IP 当前180°仍复现原第四字Z；270°测试台对照零错。

本次 TD 使用原 ADC、SDC 和 PLL 配置完成 gate 综合、布局布线。全物理终点报告中，保留名称的写地址缓存终点 setup +6.656ns、hold +0.223ns；writer 内部终点 setup +0.019ns、hold +0.076ns。物理合并后的终点数与逻辑总线位数不同，完整地址位由功能矩阵校验。

整体 Routed 时序仍未通过：最差 setup -6.565ns 为 SDRAM DQ/PAD 路径，另有 FIFO 控制和复位 recovery 项。没有修改时钟或用时序例外消除报告，不把本次写地址修复等同于整机时序闭合。

详见 [ADDRESS_TIMING_FIX.md](../../docs/ADDRESS_TIMING_FIX.md)。原始快照、布线报告与仿真记录：`C:/Users/31640/Documents/ChatGPT/FFF/address_timing_fix_20261028/`。
