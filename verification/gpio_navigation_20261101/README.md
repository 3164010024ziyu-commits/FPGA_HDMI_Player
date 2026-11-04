# GPIO 循环切图回归

在工程根目录运行 `python verification/gpio_navigation_20261101/run.py`。
默认 ModelSim 路径 D:/modelsim2020/win64；可用 --simulator-bin 和 --output 指定工具及输出。

覆盖导航状态机、GPIO 同步消抖、首尾循环/单图/空目录/失败回退、末图FAT目录扫描28场景、实际SPI6场景，以及末图查询至双帧缓存/HDMI系统集成。系统夹具使用应用模型，不代表实板SDRAM测试。日志与 results.json 默认写入系统临时目录，不污染工程。

原 MBR 回归可单独运行 `python verification/storage_mbr_fix_20261026/run_mbr_regression.py --output "$env:TEMP/mbr_regression"`。

接线、实现文件和本次时序/bit结果见 [GPIO_NAVIGATION.md](../../docs/GPIO_NAVIGATION.md)。
