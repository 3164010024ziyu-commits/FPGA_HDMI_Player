# SDRAM 时序与生产时钟读回验证（2026-10-28）

当前生产配置为 memory 100 MHz / SDRAM 转发 100 MHz、306°，display 保持 125 / 25 MHz。
本目录测试使用实际 `clk_pll`、加密 SDRAM IP、未修改的 APUG011 `IS42s32200.v` 参考模型和厂商原语库；不强制覆盖 DUT 的 PLL 时钟、锁定信号或刷新确认。

```powershell
$env:TD_MODEL_LIBS = '已编译 Anlogic al、eg 库的父目录'
$env:FPGA_PLAYER_SIM_OUTPUT = '独立的结果目录'
python verification/sdram_timing_20261028/run.py readback refresh --model 'APUG011/source_code/model/IS42s32200.v'
python verification/sdram_timing_20261028/run.py full --model 'APUG011/source_code/model/IS42s32200.v'
```

需要 ModelSim，默认路径 `D:/modelsim2020/win64`，可用 MODELSIM_BIN 设置；TD_SIM_ROOT 可指定 TD 的 sim_release。测试不写工程源文件，结果默认存于临时目录。参考模型与实际合封器件不能等同，结果不替代硬件测量。

- readback：100 次实际 PLL 周期/306° 相位断言，6 帧/768 像素，对比正反行序、换槽、外部复位及重新初始化。记录 DQ 输出与被控制器标记有效的采样时刻。PLL 仅在 FPGA 配置后启动复位，普通外部复位不断 SDRAM 时钟。
- refresh：各观察 512 µs，空闲、持续输入、4096 字后暂停；保存请求、确认、占用标志和实际 AUTO REFRESH 的 events.csv，每例均 34 次。
- full：实际 read_RAM 的 640×480/25 MHz 时序，实际 PLL/IP，满速源写后台，逐像素检查前台、禁止前台覆盖，检查欠载和刷新。此次通过 7 帧/2,150,400 像素、8,865 次刷新；第二张完整图写完并在消隐提交后结束。新前台的像素内容另由 readback 换槽测试覆盖；full 不宣称逐像素读过第二张全尺寸图。该长测试本机约 21 分钟。

应用层替代模型的回归另见 `verification/display_memory_20261028`，其时钟模型已同步到 100 MHz。旧的 180°/270° 强制时钟实验保留为历史诊断，不能当作当前生产时钟测试。

本轮汇总与生产源 SHA-256 见 RESULTS.json；完整原始报告、日志和失败候选保留于 FFF/sdram_timing_closure_20261028。未生成或下载 bitstream，未提交 Git。
