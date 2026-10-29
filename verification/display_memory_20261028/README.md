# display / memory 集成验证

RTL 设计和限制见 [DISPLAY_MEMORY_INTEGRATION.md](../../docs/DISPLAY_MEMORY_INTEGRATION.md)。测试文件使用真实项目 RTL，只有 `application_models.sv` 中的 PLL / SDRAM 应用接口替身属于测试模型，不能加入 TD 主工程。

## 快速复现

安装 Python 3 和 ModelSim 后，在工程根目录执行：

```powershell
$env:MODELSIM_BIN = 'D:\modelsim2020\win64'
python verification/display_memory_20261028/run.py unit raster system
```

默认输出位于系统临时目录下的 `fpga_display_memory_20261028`，不写入 RTL。可用 `FPGA_PLAYER_SIM_OUTPUT` 指定结果目录，`FPGA_PLAYER_PROJECT` 指定其他待测工程。每步生成日志和 `verification_results.json`，匹配 PASS 标志并检查 Error / Fatal，工具运行超时会单独记录，不当作通过。

| 场景 | 检查内容 | 本次结果 |
| --- | --- | --- |
| `unit` | 16×8 测试光栅，实际 memory/FIFO/CDC/writer/reader/仲裁器；双缓冲、补黑、方向、取消、非法宽度、复位、欠载和读超时恢复 | 14 帧、1792 像素通过 |
| `raster` | 640×480 实际 read_RAM 时序，后台无间断输入第二张图，逐像素核对并检查前台未被写入 | 3 帧、921600 像素、4383 次刷新通过 |
| `system` | 实际 hdmi_player_top + storage + HDMI 核及 VHDL 包装，SPI 卡、PLL/SDRAM 应用模型；非法宽度 E1 后重试 | 源 168 像素、显示 922245 像素通过 |

`raster` 的后台持续输入比实际 SPI 卡更快，必须观察到写入反压和同时进行的读取。`system` 使用本目录卡镜像和项目已有 SPI 卡模型，修改 BMP 内容产生多张小图；显示输出完整光栅并核对补黑。

## 厂商库与真实 SDRAM IP

这几项需要 TD 仿真源、已编译的 `al` / `eg` 库和参考 SDRAM 器件模型。器件模型不随本目录复制；按自己安装位置配置：

```powershell
$env:TD_SIM_ROOT = 'C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\sim_release'
$env:TD_MODEL_LIBS = 'C:\path\to\compiled_vendor_libraries'
$env:SDRAM_MODEL = 'C:\path\to\IS42s32200.v'
python verification/display_memory_20261028/run.py hierarchy real real_lines
```

`TD_MODEL_LIBS` 下必须有已编译的 `al`、`eg` 两个库；可按项目已有 `verification/ip_integration_20261023/check_memory_elaboration.py` 生成库。`hierarchy` 按 TD 清单编译全部 33 个混合语言文件并展开，零时长检查不代表功能通过。

`real` 使用实际 memory、加密 SDRAM IP 和器件模型，两次运行的预期不同：

- 当前 180°：512 显示像素中 32 个 Z，复现已知第四字问题；这是**问题复现通过**，不是数据测试通过。
- 测试台 270°：相同 512 像素，零错误。工程 PLL 没有修改。

`real_lines` 使用 640 像素宽、16 行的测试帧，检查真实 IP 在诊断相位下的连续长行读写竞争、地址推进和刷新。它保留 25 MHz 像素、125 MHz memory，缩短有效行数来降低器件模型运行时间。本次 3 帧、30720 像素、10240 拍并发读取、424 次刷新全部通过。

可选 `real_raster` 为真实 IP 下完整 640×480 三帧长跑。此次该长跑在 600 秒前核对了两帧、614400 像素，未见错误，随后达到工具时限，**没有最终 PASS**。不要将此项或 270° 诊断记为正式相位已验收。

## TD 综合

本次已用 TD 6.2.168116 对 `hdmi_player_top` 执行 elaborate / optimize_rtl / optimize_gate：LUT 6363/19600（32.46%）、寄存器 3203/19600（16.34%）、BRAM9K 6、DSP 4、PLL 2。显示 FIFO 成功映射为 BRAM；0 latch。

原始日志中仍保留厂商模板警告。读采样寄存器的时钟警告经最终网表核查，32 个 SDRAM DQ 输入 PAD 寄存器的 `ipclk` 都连接 memory `Clk`。这不是布局布线和时序签核；板级管脚、SDRAM 采样相位、跨域路径约束及 HDMI 实测仍待完成。

本次原始结果：`C:/Users/31640/Documents/ChatGPT/FFF/display_memory_integration_20261028/`，含修改前快照、仿真日志、指纹、TD 报告及长跑超时记录。
