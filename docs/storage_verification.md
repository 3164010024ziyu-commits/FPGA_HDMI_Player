# storage 功能验证记录

更新：2026-10-24（北京时间）。工具：本机 ModelSim SE-64 2020.4；RTL 为 Verilog，测试平台为 SystemVerilog。人工生成稀疏 FAT32 卡镜像，未访问物理卡。

复现命令：

```powershell
./tools/run_storage_tests.ps1 -SimulatorBin 'D:/multisim/win64'
```

## 回归矩阵

| 测试平台 | 场景数 | 覆盖内容 |
| --- | ---: | --- |
| `bmp_stream_decoder_tb` | 49 | 宽 1..8 的全部补齐余数；正负高度；24/32 位；54/70/1024/138 像素偏移；合法扩展 DIB；尾随数据；零声明长度；错误签名/planes/格式/尺寸/长度/偏移；提前 EOF；错误后重启；完整 640×480 BGR24 与 BGRX32 |
| `fat32_bmp_reader_tb` | 24 | 两个 BMP 目录索引与缺失索引；末目录项快照及跨扇区更新；全部四个 MBR 槽；FAT 扇区末链值及保留高位；碎片文件和跨簇根目录；1/2 扇区每簇；MBR/superfloppy；活动 FAT #1；单 FAT 副本合法卷与越界活动 FAT 拒绝；跳过删除项/LFN/子目录/卷标/其他扩展名；非法 BPB、EOC 过早、坏簇、自环；扇区错误、提前 last；错误后恢复 |
| `sd_spi_reader_tb` | 9 | 两次正常读取；CRC16 错误时零字节发布；错误后成功读取；令牌超时/错误；SDHC 扇区地址；SDSC 字节地址和 CMD16；CMD8 错误；R1 超时；模型独立检查命令 CRC7 |
| `storage_pipeline_tb` | 6 | SD 引脚→FAT32→BMP→像素的完整成功链；缺失文件；BMP 签名错误后排空；首扇区 CRC 错误；已有像素后后续扇区 CRC 错误；无需复位即可重新加载 |
| `hx4s20c_storage_bringup_tb` | 4 | 自动读图成功状态、像素数及 RGB 和；CRC/BMP 错误状态与错误码；按键复位后恢复 |

合计 **92 个场景**。每组包含时钟周期 watchdog。数据源与下游施加可复现伪随机空隙/背压；像素/字节流停顿期间检查字段稳定；比对数据、坐标、线性像素地址和首/行末/帧末标志。端到端测试还制造 1000 个系统时钟的持续背压，并检查失败不产生成功 `done`。

这些是预先定义的场景计数，不是代码覆盖率或形式证明。故障注入发生在行为模型中，不等价于实际拔卡、接触不良或物理信号完整性测试。

## 性能记录

SD 单元卡模型在短响应、无下游停顿、50 MHz 系统时钟、25 MHz 字节内 SCK 条件下：

```text
SD no-stall CMD17 sector: 11033 clocks, 2.320 MB/s (model, 50 MHz)
```

该数值含单块命令/令牌/数据/CRC/输出等 FSM 开销，不包含 FAT 层与 BMP 层处理。不是实卡吞吐保证，不用于宣称最高可达分辨率或整机帧率。

端到端小图为 17×23、24 位 BMP，文件 1250 字节；故意采用每簇 1 扇区和碎片链，方便快速覆盖边界。最终回归中，索引 1 的成功事务为 113,344 个系统时钟，索引 0 为 90,708 个，均含模型及随机背压。小图固定开销占比很高，不能直接外推大图吞吐。

## 输出与失败判定

日志位置：

```text
build/storage/bmp_stream_decoder.log
build/storage/fat32_bmp_reader.log
build/storage/sd_spi_reader.log
build/storage/storage_pipeline.log
build/storage/hx4s20c_storage_bringup.log
```

脚本确认编译/仿真进程结果，逐个检查 `PASS <module>:` 标记，并拒绝 `** Fatal:`、`** Error:`。日志属于构建产物，被 `.gitignore` 排除；测试平台、向量生成器和人工测试向量可提交。

## 尚未验证的项目

- 板级 SPI 波形和外部时序；引脚、电压、上拉已于 2026-10-24 按原理图/手册交叉核对，见 hx4s20c_board_integration.md。
- 多品牌、多容量、不同格式化工具生成的实卡兼容性。
- 任意多节点簇链环的识别、完整文件系统一致性、文件内容级完整性校验。
- 外部 I/O 时序与整机 CDC；独立顶层的综合资源及 50 MHz 布线后内部时序已检查，详见 td_validation.md。
- 物理 SDRAM 写入器及 HDMI/音频输出；当前仓库 main 原工程尚未形成整机。
- 热插拔自动恢复、连续运行时间、实卡加载时间分布。

集成时必须继续验证后台帧写入完成与垂直消隐提交。`storage done` 仅保证最后一个像素已被下游接受，不能替代 SDRAM 写完成。

## TD 实际检查补充

2026-10-24 已使用 D:/fpga 的 V6.2.168116 完成工程读入、六个 RTL 分析/展开与 ADC/SDC 读取。授权更新后已完成综合、布局布线和候选码流生成；内部 setup/hold WNS 为 +2.200/+0.030 ns，外部 SD 时序与实卡仍待验证。详见 [TD 验证记录](td_validation.md)。

BMP 文件长度校验分拍、FAT 几何统计分拍并消除 FAT 副本数乘法，新增 FAT 元数据捕获与共享字节读口；最终 RTL 已重新通过全部 92 个场景。
