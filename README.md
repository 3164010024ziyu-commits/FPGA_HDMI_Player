# FPGA HDMI Multimedia Player

基于安路 FPGA 的 HDMI 多媒体播放系统。

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

## storage 实现与验证

新增 `rtl/storage/storage_pipeline.v` 及四个子模块，完成 SD v2 SPI 读卡、
CRC 校验、FAT32 根目录 BMP 枚举与碎片读取、24/32 位 BI_RGB BMP 解析。
像素接口带 ready/valid、坐标和像素地址；整图成功后再与 SDRAM 写入完成联动换帧。

- [给 memory/display 队友的接入约定](docs/storage_integration.md)
- [设计分析、接口与争奖路线](docs/storage_design.md)
- [仿真结果与尚未验证的范围](docs/storage_verification.md)
- [HX4S20C 板卡核对与首次上板](docs/hx4s20c_board_integration.md)
- 独立验证工程：`project/td/Storage_Bringup.al`（KEY1 复位、四个 LED 指示）
- 自动回归：`./tools/run_storage_tests.ps1`（Python 3 + ModelSim/Questa）

当前 storage 已通过 92 个自检查场景及独立顶层 TD 综合/布局布线，50 MHz 内部时序满足当前约束；HX4S20C 上板和 SD 外部时序尚未验证。
上述项目功能清单为整机目标，不表示音视频、SDRAM 和扩展功能都已实现。

TD 命令行验证：`./tools/run_td_storage.ps1 -TdRoot D:/fpga`。授权已生效，使用 `-Physical` 可生成候选码流，见 [TD 验证记录](docs/td_validation.md)。
