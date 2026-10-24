# TD 构建验证结果

日期：2026-10-24。Tang Dynasty V6.2.168116（TD 6.2.1），EG4S20BG256，速度等级 NA，顶层 `hx4s20c_storage_bringup`。完成综合、布局、布线、内部时序检查和 bitgen。

## 布线后结果

| 指标 | 结果 |
| --- | --- |
| 系统时钟约束 | 50 MHz / 20.000 ns |
| Setup WNS / TNS | +2.200 ns / 0.000 ns |
| Hold WNS / TNS | +0.030 ns / 0.000 ns |
| 内部路径最小周期 / 报告 Fmax | 17.800 ns / 56.180 MHz |
| LUT | 4849 / 19600，24.74% |
| 寄存器 | 1872 / 19600，9.55% |
| DSP | 2 / 29，6.90% |
| BRAM9K / BRAM32K | 0 / 0，缓存采用逻辑 RAM |
| 全局时钟 / PLL | 1 / 0 |
| STA coverage | 99.85% |
| 检查角 | Slow 与 Fast |

这些资源包含独立板级计数/调试逻辑，也受未使用输出被裁剪影响。整机接入全部像素地址和控制输出后，需要重新测量资源和时序。56.180 MHz 是当前内部路径报告值，不能用作整机保证频率。

SD MISO 输入和 MOSI/SCK/CS 外部器件时序尚未完整约束；实际 I/O、卡片兼容性、上板及 HDMI/SDRAM 联调尚未验收。STA coverage 高不表示这些接口已被完整验证。

## 优化及代价

BMP 格式检查、尺寸乘法、长度加法/比较分拍，按配置尺寸限制算术位宽。FAT 仅接受一或两份副本，用移位/选择代替副本数乘法；数据扇区数、簇数、范围检查分拍。顶层使用 EG_LOGIC_BUFG；其理想仿真模型只加入测试工程。

最后将 FAT32 的 BPB/MBR 小字段在扇区接收时捕获，目录项逐字节提取，FAT 链值分四拍提取；三种用途与文件流共享一个扇区字节读口，使大缓存可映射为逻辑 RAM。相较重构前同一独立顶层，LUT 从 11148 降为 4849（减少 56.5%），寄存器从 5621 降为 1872，setup WNS 从 +0.160 ns 提高至 +2.200 ns。没有降低时钟约束，也没有添加 false_path/multicycle。

代价为每个目录项额外 32 个系统周期、每次 FAT 链提取额外 4 个周期。50 MHz 下分别为 0.64 μs 和 0.08 μs；文件像素流仍支持背压，单扇区 SPI 读取方式保持不变。

最终 RTL 已通过五组 **92 个自检查场景**：BMP 49、FAT32 24、SD SPI 9、端到端 6、板级封装 4。新增检查覆盖目录末项、跨扇区快照更新、四个 MBR 主分区槽、FAT 扇区最后四字节和保留高四位，详见 [功能验证](storage_verification.md)。

最终综合仍有两条 HDL-5001 匿名实例/网络命名警告；本次日志未再出现早期版本的 SYN-5025 未驱动网络警告。不能宣传零警告。候选码流未插入 ChipWatcher 采集核；`keep` 只保留调试网络，板上当前通过 LED 查看状态。

## 复现与记录

```powershell
./tools/run_storage_tests.ps1 -SimulatorBin 'D:/multisim/win64'
./tools/run_td_storage.ps1 -TdRoot 'D:/fpga' -Physical
python tools/export_storage_delivery.py
```

按本机安装路径修改参数。构建脚本记录输入 SHA-256 并拒绝构建期间源文件变化；仅在 setup/hold 非负时生成候选码流，不连接下载器。

导出工具核对源码与仿真/TD 输入记录、五组 PASS 标记和最终时序，再写出构建清单与交付压缩包。白名单打包源码、测试、文档、报告、候选码流和测试 BMP，不包含授权文件。仓库内保存 [构建清单](reports/storage/storage_build_manifest.json) 及原始资源/时序报告，二进制不进入 Git 源码历史。

构建日志与码流分别在 `build/storage/`、`build/td/`；导出包默认在仓库同级 `output/`。上板流程见 [板卡核对与首次上板](hx4s20c_board_integration.md)。独立顶层只读图计数，不驱动 HDMI 或 SDRAM。
