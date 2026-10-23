# FPGA HDMI Player 项目进度

更新日期：2026-10-23（北京时间）

核对范围：本机工程 `C:\Users\31640\Desktop\FPGA_Projects\FPGA_HDMI_Player`、已保存的 TD 综合报告、HX4S20 资料包，以及 FFF 中的 FIFO 审核、SDRAM 写控制器仿真和 `memory_top` 检查记录。本轮按用户已保存的源码更新进度并准备 Git 检查点，未重新运行功能仿真；下列通过结果来自 2026-10-22 的历史记录。当前写控制器、同步 FIFO 源码与当时保存的 SHA-256 一致。

协作约定：用户负责主要模块代码；助手负责资料查阅、接口核对、验证和必要提示。助手不修改用户模块实现，也不直接提供模块实现代码。

## 当前阶段

存储部分已具备同步 FIFO、异步 FIFO 和四字预取写控制器；写控制器的历史单模块自动检查与真实同步 FIFO 连接测试通过。用户已新增 `memory_top.v` 和 `include/global_def.v`，完成 32 位、深度 16 的同步 FIFO 与写控制器之间的连接，以及上游写数据、写使能和满标志端口。复位极性、数据位宽、FIFO 深度和端口分隔符已在静态复核中纠正。

已从资料包确认 SDRAM 硬件和 APUG011 参考接口。当前处于真实 IP 接入准备阶段：顶层只例化了 `clk_pll`、`sdr_as_ram`，工程内仍缺这些模块的实现与依赖，物理 SDRAM 连接和部分未用输入也未补齐。下一步优先生成匹配板载 50 MHz 输入的 PLL、确定实际存储时钟与刷新参数，再完善 IP 和器件模型接入。

目前的验证边界到 `App_wr_*` 输出。完整 SDRAM 存储链路、帧缓存读出、HDMI 输出和板级运行尚无本地完成证据。本文不使用整体完成百分比，避免将基础模块测试与系统完成混为一谈。

## 模块与工程状态

| 部分 | 当前已完成或已确认 | 尚需完成或核实 |
| --- | --- | --- |
| 同步 FIFO `sync_fifo` | 参数化 RTL；现有短用例自动复核通过，读出 11、22、33；另以 32 位、深度 16 接入写控制器，20 个字传递正确 | 满写阻止、空读阻止、并发读写、指针回绕等完整自动回归；旧 ModelSim 验证记录需补可复现证据 |
| 异步 FIFO `async_fifo` | RTL 包含 Gray 指针与两级同步；现有短用例读出 11、22、33、44；当前 TD 综合报告对应此模块 | 双时钟压力、满空边界、复位和参数回归；CDC 与实际时钟约束检查 |
| 写控制器 `sdram_write_ctrl` | IDLE/PREFETCH/WRITE/DONE；预取四字、连续输出四拍、基址加 4；11 项历史自动测试通过；APUG011 字地址与四字分组已有依据 | 实际接收和刷新边界、器件模型读回验证；纳入 TD 工程 |
| FIFO → 写控制器 | 使用真实 `sync_fifo` 的集成测试通过，20 字、五组四拍写入，地址 0–19 | 尚未验证异步 FIFO 与此写控制器连接；尚未连接真正的 SDRAM 控制器 |
| 存储顶层 `memory_top` | 已有上游写端口；同步 FIFO 为 32 位×16 条目，读侧连接写控制器；写接口与初始化/刷新状态回连，逻辑复位极性正确 | 尚无编译展开或功能仿真通过记录；PLL/IP 实现、物理连接、未用读输入及 LED 状态还需完善 |
| 公共参数 `include/global_def.v` | 数据 32 位、地址 21 位、DM 4 位、行 11 位、BANK 2 位；已建立头文件引用 | 刷新周期表达式暂按 150 MHz；必须与最终 PLL 配置核对 |
| PLL `clk_pll` | 已核对参考端口与锁定/复位关系；当前 `local_clk` 未使用 | 项目只有例化，无实现文件；按板载 50 MHz 配置输出频率与相位并验证 |
| SDRAM 控制器与器件模型 | FFF 已保存 APUG011 参考 IP、器件模型及脚本；`memory_top` 已例化 `sdr_as_ram`，但项目内没有实现文件 | 初始化、刷新协调、接收条件、器件命令与数据读回联合验证；相容仿真库和工具环境 |
| SDRAM 读通路与帧缓存管理 | 当前目录中未发现实现 | 读请求、显示供数、帧地址管理与读写协调 |
| 存储与显示接口 | `docs/.gitkeep` 中有像素接口草稿，包括 pix_clk、pix_req、frame_sync、pix_rgb、pix_valid、frame_ready、pix_underflow | 整理为正式接口文档，明确时钟、复位、请求与返回时序，并落实到 RTL |
| SD 卡与 BMP 解析 | 当前本地 `rtl/storage` 仅有占位文件 | 若其他成员已有代码，需同步后重新核对；本地尚无功能验证记录 |
| HDMI 显示与音频 | 本地 `display.v` 为空模块 | 有效实现、显示通路集成与测试；其他成员的外部进度不在本次核对范围内 |
| TD 综合与约束 | 当前工程顶层为 `async_fifo`，目标 EG4S20BG256，有综合阶段报告 | 当前工程未列入写控制器；引脚和实际时钟约束、布局布线、完整时序检查与上板验证 |

## 2026-10-23 新增顶层与检查结果

用户在原工程新增 `rtl/memory/memory_top.v` 和 `include/global_def.v`。当前静态核对通过的连接包括：

- 上游 `wr_en`、32 位 `wr_data` 和 `full` 接到同步 FIFO 写端；FIFO 的独立地址宽度为 4，深度 16，不与 SDRAM 的 21 位地址宏混用。
- FIFO 读数据为 32 位，读使能、读有效和空标志与写控制器连接，FIFO 和写控制器共用 `Clk`。
- PLL 未锁定时 FIFO、写控制器和 SDRAM IP 都复位；锁定后两种复位极性分别释放。此处只确认逻辑电平关系，未验证实际复位释放时序。
- 写控制器的 `App_wr_*` 输出送入 IP，初始化和刷新状态从 IP 返回。

最新编译诊断见 `memory_top_review_20261023/write_ports_recheck.log`：此前的端口分隔符和宏未定义错误已消除，当前报 `Unknown module type: clk_pll`、`Unknown module type: sdr_as_ram`，另有隐式线网警告。本机 Icarus 在输出诊断后异常退出（退出码 -1073741819）；未生成顶层通过结果，也未进行顶层功能仿真。

当前仍需由用户处理的内容：

1. 生成 PLL、加入真实控制器及依赖；现有工程只有实例名，不会自动生成 IP。
2. `App_rd_en`、`App_rd_addr` 尚无驱动。只验证写入阶段需要明确停用读请求并给地址确定值。
3. 声明 SDRAM 物理信号的真实位宽并接入 SIP 原语；当前多位信号名称会形成隐式一位网络，尚未连接到器件。
4. `Sdr_busy` 尚未显式声明；`Check_ok` 没有驱动，当前 LED 不能代表测试成功。
5. 确定上游写信号所在时钟域。当前同步 FIFO 要求写数据与内部 `Clk` 的采样时序匹配；若后续上游使用其他时钟域，需要重新设计跨域连接。
6. 将相关文件列入 TD 工程。当前保存的工程仍只有两个 FIFO，顶层仍为 `async_fifo`。

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

参考 PLL 按 25 MHz 输入设计，源码计算的两路存储时钟意图为 150 MHz、相差 180°，不是当前工程已生成或验证的时钟。参考测试台却使用 80 ns 输入周期，即 12.5 MHz，与其声明不一致，不能直接照搬。`SDR_CLK_PERIOD` 只是计时参数，不会改变 PLL 输出频率。

参考包包含 ModelSim 脚本和器件模型 `IS42s32200.v`；该模型名称不代表实际合封器件型号。脚本含旧路径，IP 有受保护代码，需要相容仿真环境。包内旧日志不是干净通过记录；本轮未运行参考工程。

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

当前 `project/td/HDMI_Player.al` 的顶层是 `async_fifo`，保留的 `syn_1` 报告也标注 `async_fifo`。旧 `docs/sync_fifo.md` 中 LUT 37、REG 10、OREG 9、BRAM 0 是同步 FIFO 的历史文档记录；本次未找到与其对应的保留报告，不将其作为本次重新确认的结果。

当前异步 FIFO 的 `HDMI_Player_gate.area` 在 Utilization Statistics 栏记载 LUT 41、REG 40、OREG 11、BRAM 0。该报告另有不同口径的 LUT Statistics，记录资源时需同时注明模块、参数和报告栏目。

现存正时序裕量属于综合阶段报告，不能作为布局布线后或板级时序通过的结论。`constraints` 目录仅有占位文件，尚未看到实际约束和实现阶段完成产物。

## 下一步顺序与完成条件

| 顺序 | 工作 | 完成条件 |
| --- | --- | --- |
| 1 | 落实 PLL、接口与刷新配置 | 硬件与 APUG011 接口已有依据；继续确定实际存储时钟、相位、刷新参数以及 busy/中途刷新边界，形成完整约定 |
| 2 | 完成顶层并接入控制器与器件模型 | 先处理未用输入、物理信号、IP 依赖和工程文件；编译展开通过后，正常写入和刷新交叉场景均能读回比对 |
| 3 | 按接口结果完善写通路 | 需要修改时补充相应断言并回归；异步 FIFO 接入和 FIFO 边界用例有可复现记录 |
| 4 | 补齐读通路与显示供数 | 写入的数据能经读通路按帧输出，frame_ready、pix_valid 与缺数处理有明确行为 |
| 5 | 完善工程并推进上板 | 相关 RTL 纳入工程，约束完整，布局布线与时序检查完成，板级读写及显示验证有记录 |

当前优先项是第 1、2 项。最近一个提示是先固定未使用的读输入，然后完善物理连接和真实 IP/PLL；未确认接收行为前，不把“WRITE 中途遇到刷新就立即停拍”直接定为修改方案。

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
| 最新顶层编译诊断（未通过） | [write_ports_recheck.log](C:/Users/31640/Documents/ChatGPT/FFF/memory_top_review_20261023/write_ports_recheck.log) |
| 硬件与接口资料摘要 | [资料提取摘要](C:/Users/31640/Documents/ChatGPT/FFF/reference_audit_20261023/资料提取摘要.md) |
| SDRAM 参考接口详细核查 | [SDRAM_reference_findings.md](C:/Users/31640/Documents/ChatGPT/FFF/reference_audit_20261023/controller/SDRAM_reference_findings.md) |
| 随 Git 保存的验证记录 | [verification/README.md](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/verification/README.md) |
| Git 内同步的进度总表 | [PROJECT_PROGRESS.md](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/docs/PROJECT_PROGRESS.md) |

本文件作为截至 2026-10-23 的进度总表，与原工程 `docs/PROJECT_PROGRESS.md` 同步保存。当前 Git 检查点用于保存用户已完成的模块和集成框架，不表示完整顶层已通过。助手本轮更新文档和版本管理辅助文件，不修改用户模块实现。后续每次更新记录“具体改动、验证方法、证据位置、剩余问题”，历史测试数量不自动代表新版本已经验证。
