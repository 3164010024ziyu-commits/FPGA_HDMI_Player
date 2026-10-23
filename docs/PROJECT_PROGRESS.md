# FPGA HDMI Player 项目进度

更新日期：2026-10-23（北京时间）

核对范围：本机工程 `C:\Users\31640\Desktop\FPGA_Projects\FPGA_HDMI_Player`、已保存的 TD 综合报告、HX4S20 资料包，以及 FFF 中的审核与验证记录。本轮在 `memory` 分支接入参考 IP，在暂存副本完成 ModelSim 编译、保留层次的零时加载和 PLL 时钟测量；未进行真实 SDRAM 写入读回。2026-10-22 的历史测试结论单独保留。用户的 `memory_top`、同步/异步 FIFO 和写控制器实现按 SHA-256 核对保持原样。

协作约定：用户负责主要模块代码；助手负责资料查阅、接口核对、验证和必要提示。助手不修改用户模块实现，也不直接提供模块实现代码。

## 当前阶段

存储部分已具备同步 FIFO、异步 FIFO 和四字预取写控制器；写控制器的历史单模块自动检查与真实同步 FIFO 连接测试通过。用户已新增 `memory_top.v` 和 `include/global_def.v`，完成 32 位、深度 16 的同步 FIFO 与写控制器之间的连接，以及上游写数据、写使能和满标志端口。复位极性、数据位宽、FIFO 深度和端口分隔符已在静态复核中纠正。

已在 `memory` 分支导入匹配板载 50 MHz 输入的 PLL，以及 APUG011 的 `sdr_as_ram`、`sdr_init_ref`、`sdr_wrrd`；现有 `sdram_write_ctrl` 复用用户文件。TD 源文件清单与顶层已调整为 `memory_top`。PLL 使用配套例程的 100/125/125 MHz、0/0/180° 配置，刷新周期参数同步为 125 MHz。ModelSim 编译和零时层次加载通过，PLL 输出周期及相位测量通过；物理 SDRAM 连接、未用读输入和 LED 状态仍待用户补齐。

目前的验证边界到 `App_wr_*` 输出。完整 SDRAM 存储链路、帧缓存读出、HDMI 输出和板级运行尚无本地完成证据。本文不使用整体完成百分比，避免将基础模块测试与系统完成混为一谈。

## 模块与工程状态

| 部分 | 当前已完成或已确认 | 尚需完成或核实 |
| --- | --- | --- |
| 同步 FIFO `sync_fifo` | 参数化 RTL；现有短用例自动复核通过，读出 11、22、33；另以 32 位、深度 16 接入写控制器，20 个字传递正确 | 满写阻止、空读阻止、并发读写、指针回绕等完整自动回归；旧 ModelSim 验证记录需补可复现证据 |
| 异步 FIFO `async_fifo` | RTL 包含 Gray 指针与两级同步；现有短用例读出 11、22、33、44；当前 TD 综合报告对应此模块 | 双时钟压力、满空边界、复位和参数回归；CDC 与实际时钟约束检查 |
| 写控制器 `sdram_write_ctrl` | IDLE/PREFETCH/WRITE/DONE；预取四字、连续输出四拍、基址加 4；11 项历史自动测试通过；已列入 TD 源清单 | 实际接收和刷新边界、器件模型读回验证 |
| FIFO → 写控制器 | 历史真实 `sync_fifo` 集成测试通过，20 字、五组四拍、地址 0–19；新顶层连接已核对 | 新顶层至真实 IP 的供数功能、异步 FIFO 接入及器件读回尚未验证 |
| 存储顶层 `memory_top` | 32 位×16 条目 FIFO、上游写端口与应用写控制器连接；复位极性已核对；暂存副本在 ModelSim 编译及零时层次加载通过 | 有物理总线位宽警告；完整功能、实际 SDRAM 写入读回、未用读输入及 LED 状态待完善 |
| 公共参数 `include/global_def.v` | 数据 32 位、地址 21 位、DM 4 位、行 11 位、BANK 2 位；刷新周期表达式已同步为 125 MHz | 实际刷新预算与器件行为仍需模型及板级验证 |
| PLL `clk_pll` | 导入配套 Anlogic 生成配置，输入 50 MHz，输出 100/125/125 MHz，后两路相差 180°；行为模型测量通过；`local_clk` 当前未使用 | FPGA 实际时钟和板级时序仍需实现与上板验证 |
| SDRAM 控制器与器件模型 | 三份 APUG011 控制器文件已导入 `rtl/ip/sdram` 并经 ModelSim 编译；模型仍为参考资源 | 初始化、刷新协调、接收条件、器件命令与数据读回联合验证；SIP 物理原语尚待用户连接 |
| SDRAM 读通路与帧缓存管理 | 当前目录中未发现实现 | 读请求、显示供数、帧地址管理与读写协调 |
| 存储与显示接口 | `docs/.gitkeep` 中有像素接口草稿，包括 pix_clk、pix_req、frame_sync、pix_rgb、pix_valid、frame_ready、pix_underflow | 整理为正式接口文档，明确时钟、复位、请求与返回时序，并落实到 RTL |
| SD 卡与 BMP 解析 | 当前本地 `rtl/storage` 仅有占位文件 | 若其他成员已有代码，需同步后重新核对；本地尚无功能验证记录 |
| HDMI 显示与音频 | 本地 `display.v` 为空模块 | 有效实现、显示通路集成与测试；其他成员的外部进度不在本次核对范围内 |
| TD 综合与约束 | `memory` 分支源清单包含参数头文件、PLL、FIFO、写控制器、三个 IP 文件及 `memory_top`，顶层设为 `memory_top`；目标 EG4S20BG256 | 仅完成工程配置，尚未运行新顶层综合；旧报告仍对应 `async_fifo`；约束、布局布线、时序与上板待完成 |

## 2026-10-23 新增顶层与检查结果

用户在原工程新增 `rtl/memory/memory_top.v` 和 `include/global_def.v`。当前静态核对通过的连接包括：

- 上游 `wr_en`、32 位 `wr_data` 和 `full` 接到同步 FIFO 写端；FIFO 的独立地址宽度为 4，深度 16，不与 SDRAM 的 21 位地址宏混用。
- FIFO 读数据为 32 位，读使能、读有效和空标志与写控制器连接，FIFO 和写控制器共用 `Clk`。
- PLL 未锁定时 FIFO、写控制器和 SDRAM IP 都复位；锁定后两种复位极性分别释放。此处只确认逻辑电平关系，未验证实际复位释放时序。
- 写控制器的 `App_wr_*` 输出送入 IP，初始化和刷新状态从 IP 返回。

接入前编译诊断见 `memory_top_review_20261023/write_ports_recheck.log`：当时端口分隔符和宏未定义错误已消除，但缺少 `clk_pll`、`sdr_as_ram`。这是历史失败记录；本轮导入后已经解决缺失模块引用。普通沙箱中的工具 DLL 重定位/异常退出通过沙箱外运行 ModelSim 验证处理，不能把启动异常当作 RTL 通过或失败的依据。

### memory 分支的 IP 接入验证

- `main` 保留检查点 `ae419c6`，后续本轮修改在 `memory` 分支进行。
- PLL 来自 HX4S20C 配套 `lab_ex4_tf` 的 `sys_pll.v/.ipc`。导入副本仅适配模块名和生成文件名；PLL 原语参数保持供应商配置。原 APUG011 的旧 25 MHz PLL 未混入。
- APUG011 三份加密控制器文件原样导入，现有用户模块实现未改写。只有计时配置头文件从 150 MHz 同步为 125 MHz。
- ModelSim SE-64 2020.4 编译供应商库、IP 和当前层次均退出 0；保留内部访问的 `memory_top` 加载并运行 0 ns 成功。这个检查证明依赖可解析，不代表存储功能通过。
- 层次加载仍报告 SDR_BA、SDR_ADDR、SDR_DM、SDR_DQ 的位宽警告，以及原厂参考代码中未定宽常量与 PLL load_reg 端口的警告；未通过隐藏这些警告获取结果。
- PLL 测试以 50 MHz 驱动原厂行为模型，检查锁定后 C0 周期 10 ns、C1/C2 周期 8 ns、相位间隔 4 ns。PASS 时已检查 16/20/20 个周期及 21 次相位，时间 1111.200 ns；批处理运行到 50 us 退出 0。它不是板级时序结果。
- 记录、测试台和重跑入口随工程保存于 `verification/ip_integration_20261023`。验证在 FFF 暂存副本执行；导入时核对文件 SHA-256 一致。

当前仍需由用户处理的内容：

1. PLL 与控制器依赖已导入；后续修改时钟配置时，需继续保持刷新参数一致，并验证实际器件时序。
2. `App_rd_en`、`App_rd_addr` 尚无驱动。只验证写入阶段需要明确停用读请求并给地址确定值。
3. 声明 SDRAM 物理信号的真实位宽并接入 SIP 原语；当前多位信号名称会形成隐式一位网络，尚未连接到器件。
4. `Sdr_busy` 尚未显式声明；`Check_ok` 没有驱动，当前 LED 不能代表测试成功。
5. 确定上游写信号所在时钟域。当前同步 FIFO 要求写数据与内部 `Clk` 的采样时序匹配；若后续上游使用其他时钟域，需要重新设计跨域连接。
6. TD 文件清单与顶层已更新；后续在补齐物理连接和约束后运行综合与实现。上游时钟域和接口采样约定仍需明确。

## 历史已通过仿真（2026-10-22）

### 写控制器自动测试

2026-10-22 使用本机 **Icarus Verilog** 编译和运行：`iverilog -g2012 -Wall`、`vvp -n`。独立测试台放在本工作目录，原工程的 `tb/memory/sdram_write_ctrl_tb.v` 仍为 0 字节。

11 项测试全部通过，仿真时间 12,700 ns，逐次检查 306 次写入的数据、地址和字节掩码。覆盖复位与空闲、四字连续输出、多组地址递增、初始化前等待、刷新前等待、FIFO 缺数与恢复、返回延迟，以及预取和写入中的共同复位；另完成间歇供数下的 64 组、256 字测试。

306 次中包含复位打断前已输出的 2 次写入。复位测试采用 FIFO 模型与控制器共同复位，没有验证控制器单独复位后仍收到外部旧响应的情形。

### 真实同步 FIFO 集成

原 `sync_fifo` 配置为 32 位、深度 16，连接原 `sdram_write_ctrl`。测试中 20 个字经过 FIFO 后正确输出，地址为 0–19；五组写入均恰好连续四拍。初始化等待、刷新信号已有效时禁止启动、两字断流等待与恢复均通过。仿真时间为 1,560 ns。

### 波形检查状态

两套测试均生成了 VCD。通过结论来自测试台自动检查和日志；**尚未在 ModelSim 或其他波形查看器中查看这些 VCD，也未直接解析其信号变化**。ModelSim 并未用于上述两套新增测试。

原 `docs/sync_fifo.md` 记录了历史 ModelSim 验证。该历史记录保留，但当前启用的 FIFO 测试激励与本次日志不足以复现文档列出的全部边界场景，应另行补充用例或历史记录。

## 已核实的硬件与参考接口

资料来自 `C:\Users\31640\Desktop\FPGA_Projects\HX4S20_Contest_202606`；详细出处和页码见 FFF 的 `reference_audit_20261023/资料提取摘要.md`。

- 赛题平台为 HX4S20C，较早手册称 HX4S20；核心 EG4S20BG256，与 EM638325 SDRAM 合封，容量 2M×32 bit，即 8 MiB。板载输入晶振为 50 MHz。
- APUG011 v1.2 的 `sdr_as_ram` 接口与当前模块对应：数据 32 位、地址 21 位、DM 4 位。按参考配置每地址对应一个 32 位字，加 1 为 4 字节。
- 四字为一组，共 16 字节，组首低两位为 00，组内递增、组间可跳转。应用层读写必须互斥。
- 应用掩码每位对应一字节，1 为屏蔽；当前 0000 是整字写入。部分字节写入及物理 DM 的处理仍需实际 IP 验证。
- 初始化完成、初始化/刷新有效标志为低后开始读写；接口没有逐拍 ready/ack。明文部分表明 `Sdr_init_ref_vld` 是初始化或刷新占用标志，刷新请求另有信号。
- 默认参考顶层使用控制器定时刷新，手动请求为 0；本项目的当前例化延续该配置。部分内部协调逻辑加密，无法据资料确认中途刷新时剩余拍的接收保证。
- 手册对 `Sdr_busy` 存在“暂不使用”与“操作前检查”的不一致，保留为待核实项，不把它直接解释为 ready。

旧 APUG011 PLL 按 25 MHz 输入设计，参考测试台却使用 80 ns 输入周期，即 12.5 MHz，与其声明不一致。本轮已改用配套板卡例程的 50 MHz 输入 PLL，存储时钟为 125 MHz。`SDR_CLK_PERIOD` 只是计时参数，不会改变 PLL 输出频率。

参考包包含 ModelSim 脚本和器件模型 `IS42s32200.v`；该模型名称不代表实际合封器件型号。旧脚本和旧日志不作为本轮通过证据。本轮使用本机安路仿真库与新验证入口，未进行参考器件模型的存储读回测试。

## WRITE 期间出现刷新的待办

**已验证输出行为，尚未验证真实存储结果。**

集成测试在第四组首字（地址 12）输出后拉高 `Sdr_init_ref_vld`。当前 RTL 在标志有效时继续输出地址 13、14、15 的三个字，然后等待标志解除才启动下一组。

这项测试按当前 RTL 的“继续完成已启动的四字输出”设置预期，明确允许这三拍重叠。日志的 `INTEGRATION_PASS` 表示满足这套预期，不能用来证明刷新期间的数据最终写入正确。

待确认的问题：

1. 参考明文已确认该标志表示初始化或刷新占用；它与内部请求、应答和实际器件命令的完整时间关系仍需核实。
2. 下游是否保证一组四字输入一旦开始就连续接收？若下游不能接收，内部缓冲如何处理？当前应用写接口没有逐拍接收确认输入。
3. 参考 IP 内部存在读写/刷新握手，但主体加密；应用层应配合启动门控与读写互斥。先确认真实接收行为，再决定是否修改当前写控制器。
4. 接入实际 SDRAM 控制器与器件模型后，覆盖写入前、首拍附近和四拍中途出现刷新，写入后逐字读回比较，确认地址、数量、顺序及数据均正确。

当前尚无真实 SDRAM 的写入、刷新执行或读回结果，不能据此认定“必然丢数据”，也不能认定“刷新冲突已解决”。

## 综合记录的使用范围

本轮 `memory` 分支将 `project/td/HDMI_Player.al` 的顶层改为 `memory_top`；保留的旧 `syn_1` 报告仍标注 `async_fifo`，不能解释为新顶层综合结果。旧 `docs/sync_fifo.md` 中 LUT 37、REG 10、OREG 9、BRAM 0 是同步 FIFO 的历史文档记录；未找到与其对应的保留报告，不将其作为本次重新确认的结果。

当前异步 FIFO 的 `HDMI_Player_gate.area` 在 Utilization Statistics 栏记载 LUT 41、REG 40、OREG 11、BRAM 0。该报告另有不同口径的 LUT Statistics，记录资源时需同时注明模块、参数和报告栏目。

现存正时序裕量属于综合阶段报告，不能作为布局布线后或板级时序通过的结论。`constraints` 目录仅有占位文件，尚未看到实际约束和实现阶段完成产物。

## 下一步顺序与完成条件

| 顺序 | 工作 | 完成条件 |
| --- | --- | --- |
| 1 | 完善接口与刷新约定 | PLL/125 MHz 参数和依赖已接入；继续核实 busy/中途刷新边界及实际器件时序 |
| 2 | 补齐顶层并进行器件读回验证 | 由用户处理未用输入、物理信号和 SIP 原语，消除相关位宽警告；正常及刷新交叉写入均能逐字读回 |
| 3 | 按接口结果完善写通路 | 需要修改时补充相应断言并回归；异步 FIFO 接入和 FIFO 边界用例有可复现记录 |
| 4 | 补齐读通路与显示供数 | 写入的数据能经读通路按帧输出，frame_ready、pix_valid 与缺数处理有明确行为 |
| 5 | 完善工程并推进上板 | 相关 RTL 纳入工程，约束完整，布局布线与时序检查完成，板级读写及显示验证有记录 |

当前优先项是第 1、2 项。用户下一步先固定未使用的读输入，再声明并连接物理 SDRAM 总线与 SIP 原语；未确认接收行为前，不把“WRITE 中途遇到刷新就立即停拍”直接定为修改方案。

## 证据与重跑入口

| 内容 | 位置 |
| --- | --- |
| 原项目概述 | [README.md](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/README.md) |
| 同步 FIFO 历史说明 | [sync_fifo.md](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/docs/sync_fifo.md) |
| 当前 TD 综合工程 | [HDMI_Player.al](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/project/td/HDMI_Player.al) |
| 当前综合资源报告 | [HDMI_Player_gate.area](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/project/td/HDMI_Player_Runs/syn_1/HDMI_Player_gate.area) |
| FIFO 基础用例复核 | [审核记录](C:/Users/31640/Documents/ChatGPT/FFF/hdmi_audit_20261022/README.md) |
| 写控制器详细仿真报告 | [仿真报告](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/README.md) |
| 单模块结果 | [sdram_write_ctrl.log](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/sdram_write_ctrl.log) |
| 刷新中途拉高的测试与结果 | [集成测试台](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/sdram_fifo_integration_tb.v:181)、[integration.log](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/integration.log:17) |
| 运行命令、退出码与源码 SHA-256 | [results.json](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/results.json) |
| 自动重跑入口 | [run_sim.py](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/run_sim.py) |
| 导出的波形 | [单模块 VCD](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/sdram_write_ctrl.vcd)、[集成 VCD](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/integration.vcd) |
| 当前存储顶层 | [memory_top.v](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/rtl/memory/memory_top.v) |
| 当前参数头文件 | [global_def.v](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/include/global_def.v) |
| 接入前历史编译诊断（未通过） | [write_ports_recheck.log](C:/Users/31640/Documents/ChatGPT/FFF/memory_top_review_20261023/write_ports_recheck.log) |
| 硬件与接口资料摘要 | [资料提取摘要](C:/Users/31640/Documents/ChatGPT/FFF/reference_audit_20261023/资料提取摘要.md) |
| SDRAM 参考接口详细核查 | [SDRAM_reference_findings.md](C:/Users/31640/Documents/ChatGPT/FFF/reference_audit_20261023/controller/SDRAM_reference_findings.md) |
| 随 Git 保存的验证记录 | [verification/README.md](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/verification/README.md) |
| IP 接入编译与零时层次加载 | [elaboration/results.json](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/verification/ip_integration_20261023/elaboration/results.json) |
| PLL 周期与相位验证 | [pll_smoke/results.json](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/verification/ip_integration_20261023/pll_smoke/results.json) |
| Git 内同步的进度总表 | [PROJECT_PROGRESS.md](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/docs/PROJECT_PROGRESS.md) |

本文件作为截至 2026-10-23 的进度总表，与原工程 `docs/PROJECT_PROGRESS.md` 同步保存。Git 保存用户模块、参考 IP、工程配置和验证证据，不表示完整存储功能通过。助手本轮导入已有 IP、同步计时及工程配置并更新文档，保留用户模块实现。后续每次更新记录“具体改动、验证方法、证据位置、剩余问题”，历史测试数量不自动代表新版本已经验证。
