# FPGA HDMI Player 项目进度

更新日期：2026-10-28（北京时间）

核对范围：本机工程、FFF验证记录和资料。2026-10-25先提交检查点6a6fc1c，再执行真实参考IP与SDRAM行为模型测试，按证据应用刷新仲裁修复。PLL、加密IP和FIFO保持不变；本次用户明确授权助手进行必要工程修改。当前完整读回仍未通过，下文分开报告刷新和读采样结果。

协作约定：用户负责主要模块代码；助手负责资料查阅、接口核对、验证和必要提示。助手默认不修改用户模块实现、不直接提供模块实现代码；用户明确授权的定点修改按指定范围执行并展示差异。

## 当前阶段

最新storage状态：MBR误识别已在fat32_bmp_reader中修复，121场景复测通过；此前快照中的0x34误判记录作为历史保留。memory尾包、FIFO最小深度和正式读采样问题仍独立跟踪。

存储部分已具备同步 FIFO、异步 FIFO 和四字预取写控制器；写控制器的历史单模块自动检查与真实同步 FIFO 连接测试通过。用户已新增 `memory_top.v` 和 `include/global_def.v`，完成 32 位、深度 16 的同步 FIFO 与写控制器之间的连接，以及上游写数据、写使能和满标志端口。复位极性、数据位宽、FIFO 深度和端口分隔符已在静态复核中纠正。

已在 `memory` 分支导入匹配板载 50 MHz 输入的 PLL，以及 APUG011 的 `sdr_as_ram`、`sdr_init_ref`、`sdr_wrrd`；现有 `sdram_write_ctrl` 复用用户文件。此前 TD 源文件清单与顶层调整为 `memory_top`；本轮接口对接后已增加 storage 与系统顶层，切换为 `hdmi_player_top`。PLL 使用配套例程的 100/125/125 MHz、0/0/180° 配置，刷新周期参数同步为 125 MHz。ModelSim 编译和零时层次加载通过，PLL 输出周期及相位测量通过；物理 SDRAM 总线与 SIP 原语已按参考例程接入并经零时层次检查；未用读请求已停用，LED已按用户选择指示PLL锁定且初始化完成，尚不表示数据校验通过。

当前已接入帧描述CDC、行列写地址、帧完成保持电平及50MHz返回同步。本轮已把外部Reset_n接入memory：两域异步进入、各自两级同步释放，FIFO内部按读写域释放，SDRAM重新初始化前关闭像素/描述接收和就绪状态。12组复位及回归通过；PLL保持锁定的WRITE中复位后，真实IP重新初始化并正确完成新8字；真实storage与memory在替身IP下的中途复位重读也通过。尾包、帧中止、整机单独失锁恢复及正式读采样继续独立处理；未宣称SDRAM物理内容/读回和实板时序验收。

2026-10-25新方案：15µs周期的应用侧刷新仲裁，pending暂停启动新四字组，等待在途写入与下游忙解除后发送单拍请求。三种512µs最终生产场景均34请求/34确认/34占用/34实际刷新；pending到实际刷新最长196ns，相邻刷新最长15.064µs。11场景4376字模型存储全部正确、刷新覆盖通过，但工程125MHz/180°仍每组第四字读回Z，共1094错。仅测试台270°诊断的11场景全部通过，未改工程PLL。帧缓存、显示、板级时序和实板运行尚未完成。详见 [刷新修复记录](SDRAM_REFRESH_VERIFICATION.md)。

## 2026-10-28 memory外部复位接入与验证

已按用户授权检查整个工程复位，并让外部Reset_n清除memory旧任务。仅修改memory_top、async_fifo两个RTL及原异步FIFO测试台：共同请求由外部复位或PLL失锁产生，50MHz/125MHz分别两级释放；FIFO端口不变但内部按写/读域释放；writer/refresh/IP使用125MHz复位，CDC两侧分别复位。初始化状态同步回50MHz，就绪和写入握手在复位及重新初始化期间关闭，PLL配置保持不变。原有顶层/storage复位无需改动。

12组检查通过：8种锁定PLL下的外部复位、7次新帧/56字无旧数据；6组FIFO矩阵共49152条目；原4字FIFO测试；完整TD层次；真实IP在WRITE中复位并两次初始化、新8字完成；原同高度两帧16字完成回归；真实storage和memory在替身IP下接收2像素后复位、改基址和颜色重读8像素正确。复位不清物理存储阵列，只使旧内容失效，不再消费旧FIFO和帧状态。

FIFO在复位/两拍释放阶段full=1、empty=1，表示暂不可读写；原测试台新增等待full解除。源码和记录见[MEMORY_RESET_VERIFICATION.md](MEMORY_RESET_VERIFICATION.md)、[测试结果](C:/Users/31640/Documents/ChatGPT/FFF/memory_reset_integration_20261028/verification_results.json)。真实IP验证使用受控时钟，不含物理内容/读回和板级时序；单独PLL失锁的整机自动重播仍未实现。未创建Git提交，保留此前未提交修复和用户注释。

## 2026-10-28 帧完成与50MHz同步最小修复

用户明确授权先保存Git、再尽量少改修复三个完成问题。已原样提交修复前检查点35b7335；后续修复代码保留在工作区供查看。修改4个RTL和TD清单：修正用户同步块的端口/复位及旧输出名连接；writer新增Sdr_busy、有效帧与4拍排空保护；新描述优先清done；顶层首次空闲可启动，任务等待本次done低后高并等storage空闲，保留头部失败且无描述时的重试；TD加入CDC为第16项。四字状态机和地址公式字节比对不变，FIFO/PLL/刷新/IP及storage哈希不变。

7组验证通过：writer无描述和同高度连续两帧/延迟busy/尾包保护、50MHz同步高低/共同复位、24字正反行序及刷新暂停、顶层5场景启动/旧done/错误重试、完整TD零时层次、真实IP两帧16字，以及真实storage配测试memory的3场景782像素接线。真实IP完成均在末次App提交后120ns、Sdr_busy解除后32ns，busy=0后才done。同步代码不再有ack重复驱动和done同步寄存器未复位问题。

测试边界：真实IP时序使用测试台受控时钟并绕过PLL模型启动，没有改工程PLL或检查SDRAM物理内容/读回；storage接线回归用memory替身，不等于391字尾包已修好。metadata后的部分帧错误/abort仍可能保持占用，外部复位和实板时序仍待处理。详见[FRAME_COMPLETION_FIX.md](FRAME_COMPLETION_FIX.md)，[完整命令/源码哈希/结果](C:/Users/31640/Documents/ChatGPT/FFF/completion_minimal_fix_20261028/verification_results.json)。

## 2026-10-28 CDC修正验证与开发前Git检查点

用户已自行修正frame_desc_cdc中ack_sync的声明顺序。本轮直接使用当前生产文件快照编译和测试，未修改模块代码：原文件编译通过，20/8ns、8/20ns、14/22ns及20/20ns错相四种时钟组合各512组帧描述、共2048组传输全部通过；共同复位并错开释放后恢复测试通过。结果不再依赖上轮仅调整声明顺序的诊断副本。

两侧独立复位的协议边界仍沿用上轮记录：目标侧独立复位可能重放旧描述，源侧独立复位可能产生全零伪描述；当前实现需协调两侧复位。数字仿真未替代器件CDC时序签核。

当前frame_desc_cdc尚未加入TD文件清单，也未在memory_top中例化；memory仍未消费帧基址、宽高与方向，外部Reset_n和frame_write_done的内部逻辑仍待用户实现。下一步先在memory_top中接入CDC并建立描述先于像素生效的控制，再由用户扩展sdram_write_ctrl的帧基址/行列地址处理及完成条件。四字尾包和正式读采样问题继续独立跟踪。

按用户要求，准备把当前已有的storage MBR修复及回归资料、storage/memory接口、系统顶层接线、TD文件清单、用户新增并修正的CDC及同步文档一并保存为memory分支的本地Git检查点。本轮不改PLL、写控制器或其他模块逻辑；本地保存范围不含FFF临时仿真库。

[本轮真实CDC测试结果](C:/Users/31640/Documents/ChatGPT/FFF/git_checkpoint_20261028/cdc_results.json)。上轮错误定位与复位边界见[检查记录](C:/Users/31640/Documents/ChatGPT/FFF/project_review_20261028/README.md)。

## 2026-10-26 storage / memory 接口与系统顶层对接

**接口和接线已更新，memory内部帧逻辑由用户继续完成。** 按用户授权仅改memory端口，并补全hdmi_player_top；storage端口无需增删，全部实现保留。删除未定义的frame_id，新增21位字地址frame_base_addr、16位宽高、frame_top_down、frame_abort、Reset_n和预留输出frame_write_done；保留像素valid/data/ready及frame_start/end。frame_start来自meta_valid，frame_end来自storage.done，frame_abort来自error。

顶层补全SD SPI、复位释放、读取启动/文件选择、请求基址锁存、图像元信息、像素握手和状态。初始化完成前不启动或传像素。load_done表示源端成功结束，memory_frame_write_done另行表示真实帧写完；目前后者没有驱动。load_ready仅表示storage空闲且memory已初始化；后续启动下一帧、复用缓冲区还必须等待memory完成并处理错误恢复。TD添加5个源文件条目、顶层设为hdmi_player_top；未执行板级管脚/布局布线/时序签核。

- 真实工程ModelSim编译、零时刻层次加载：通过，0错误；保留两项参考IP常量告警和一项PLL模型位宽告警。
- 顶层接线功能测试：真实storage + SPI卡模型 + 测试memory接收模型，3场景通过；两次成功帧各391像素，共782像素和2314次背压保持检查；错误BMP返回0x20/abort后恢复成功。覆盖基址锁存、元信息、过早启动门控、长背压和源完成/写完成区分。
- 本轮边界：memory从localparam开始的模块体与修改前逐字节相同；新端口尚未驱动内部地址/复位/完成逻辑。模型接线测试不等于真实SDRAM帧地址功能验证。391字尾部3字等待、正式180度读采样问题及异步FIFO深度2边界仍在，不因端口修改而解决。
- 用户下一步：先在SYS_CLK域按frame_start锁存帧基址、尺寸与方向，再设计与125MHz写侧的可靠跨时钟控制、行地址、尾包/取消/复位及排空完成。完整约定见[STORAGE_MEMORY_INTERFACE.md](STORAGE_MEMORY_INTERFACE.md)。

[本轮命令、快照和结果](C:/Users/31640/Documents/ChatGPT/FFF/storage_memory_interface_20261026/results.json)。本轮未提交Git，原有未提交修改保留。

## 2026-10-26 storage MBR识别修复

**已修复并复测通过。** 仅修改fat32_bmp_reader，新增单次MBR回退；18项FAT专项、6项SPI专项、原92场景及5项背压共121场景通过。有效MBR和superfloppy均可读取，坏分区仍按原规则报错；其他RTL哈希未变。详见 [STORAGE_MBR_FIX.md](STORAGE_MBR_FIX.md)，随工程保留24项专项重跑入口。

用户已授权修复FAT32/MBR识别问题；先用成功加载为预期复现错误，再修改单一storage模块并重跑回归。每步完成即记录，未涉及memory尾包或模块对接。

- **baseline/targeted_fat**：修复前按成功加载预期测试；已复现0x34错误，正常MBR对照通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/baseline/targeted_fat/results.json)。

- **baseline/targeted_spi**：修复前按成功加载预期测试；已复现0x34错误，正常MBR对照通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/baseline/targeted_spi/results.json)。

- **应用修复，等待回归**：仅修改fat32_bmp_reader，新增MBR回退状态与LBA0探测标志；扇区0的完整BPB或几何校验失败且存在支持的分区时，转读分区启动扇区；进入分区读取后关闭再次回退。未修改memory及其他RTL。[差异与哈希](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/applied.json)。

- **fixed/targeted_fat**：通过；# MBR_REGRESSION_PASS cases=18 [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/targeted_fat/results.json)。

- **fixed/targeted_spi**：通过；# MBR_PIN_REGRESSION_PASS cases=6 [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/targeted_spi/results.json)。

- **fixed/bmp_stream_decoder**：通过；# PASS bmp_stream_decoder: 49 cases, randomized stalls and bubbles [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/bmp_stream_decoder/results.json)。

- **fixed/fat32_bmp_reader**：通过；# PASS fat32_bmp_reader: 24 cases, fragmented files/root, stalls, corruption [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/fat32_bmp_reader/results.json)。

- **fixed/sd_spi_reader**：通过；# PASS sd_spi_reader: 9 cases, SDHC/SDSC, CRC rejection, timeouts, recovery [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/sd_spi_reader/results.json)。

- **fixed/storage_pipeline**：通过；# PASS storage_pipeline: 6 pin-level end-to-end cases [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/storage_pipeline/results.json)。

- **fixed/hx4s20c_storage_bringup**：通过；# PASS hx4s20c_storage_bringup: 4 board-wrapper cases [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/hx4s20c_storage_bringup/results.json)。

- **fixed/backpressure**：通过；# STORAGE_BACKPRESSURE_PASS cases=5 pixels_per_case=391 normal_transaction=1 [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/backpressure/results.json)。

- **工程内重跑入口复核**：随工程保存的run_mbr_regression.py已在当前生产RTL上再次跑通18项FAT与6项SPI专项；这24项重复检查不另计入121场景。源码哈希与已测试修复一致。[入口](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/verification/storage_mbr_fix_20261026/README.md)。

## 2026-10-26 当前底层模块全面回归

以下为MBR修复前的历史快照；其中MBR失败已由上面的修复及新回归解决，其余问题状态不变。

**本轮已完成：30项验证任务，24项通过、1项仅诊断通过、3项既有功能失败复现、1项最小深度参数不支持、1项尾包限制确认。** 两项MBR复现属于同一缺陷。底层常用配置未见新的功能回归；当前顶层按用户要求作为未完成草稿隔离。新增问题为async_fifo的ADDR_WIDTH=1不能展开，当前深度16不受影响。正式读回1094个末字Z和MBR识别错误仍未修复；各任务证据如下。

本轮按用户要求冻结当前工作区，独立测试底层模块；memory_top与hdmi_player_top正在编写的接口/连接不作为底层失败项。验证夹具只存在FFF，实例化本轮当前底层RTL；不修改用户模块，不把历史测试结果直接当作本轮通过。每项完成即同步本节。

[完整回归记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/README.md)。

- **sync_w8_d2_10_10**：同步FIFO，宽8/深2，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/sync_w8_d2_10_10/results.json)。

- **sync_w8_d4_10_10**：同步FIFO，宽8/深4，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/sync_w8_d4_10_10/results.json)。

- **sync_w32_d16_10_10**：同步FIFO，宽32/深16，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/sync_w32_d16_10_10/results.json)。

- **sync_w56_d16_10_10**：同步FIFO，宽56/深16，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/sync_w56_d16_10_10/results.json)。

- **async_w8_d4_10_4**：异步FIFO，宽8/深4，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_w8_d4_10_4/results.json)。

- **async_w32_d16_10_4**：异步FIFO，宽32/深16，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_w32_d16_10_4/results.json)。

- **async_w56_d16_10_4**：异步FIFO，宽56/深16，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_w56_d16_10_4/results.json)。

- **async_w32_d16_4_10**：异步FIFO，宽32/深16，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_w32_d16_4_10/results.json)。

- **async_w8_d4_4_10**：异步FIFO，宽8/深4，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_w8_d4_4_10/results.json)。

- **async_w56_d4_10_4**：异步FIFO，宽56/深4，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_w56_d4_10_4/results.json)。

- **async_depth2_boundary**：异步FIFO深度2参数边界（ADDR_WIDTH=1）；未通过；见展开/仿真错误，不影响默认ADDR_WIDTH=4的独立结果 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_depth2_boundary/results.json)。

- **writer_unit_11**：写控制器历史11项自检查，当前新增pending输入在本组绑0；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/writer_unit_11/results.json)。

- **writer_sync_fifo**：实际同步FIFO到当前写控制器20字；其中占用标志中途注入仅验证输出行为；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/writer_sync_fifo/results.json)。

- **writer_pending**：pending禁止新组、已开始四拍完成、下一组等待后恢复；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/writer_pending/results.json)。

- **writer_tail**：四字尾包限制：391字只输出388字、缓存3字；392字对照全部输出，尚无尾包协议 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/writer_tail/results.json)。

- **refresh_unit_7**：刷新仲裁7项，包括手动/周期相邻、排空、超时锁存与复位；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/refresh_unit_7/results.json)。

- **pll**：实际PLL行为模型50MHz输入、100/125/125MHz输出及180度相位；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/pll/results.json)。

- **storage_bmp_stream_decoder**：storage历史回归49场景，生产模块为当前快照；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/storage_bmp_stream_decoder/results.json)。

- **storage_fat32_bmp_reader**：storage历史回归24场景，生产模块为当前快照；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/storage_fat32_bmp_reader/results.json)。

- **storage_sd_spi_reader**：storage历史回归9场景，生产模块为当前快照；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/storage_sd_spi_reader/results.json)。

- **storage_storage_pipeline**：storage历史回归6场景，生产模块为当前快照；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/storage_storage_pipeline/results.json)。

- **storage_hx4s20c_storage_bringup**：storage历史回归4场景，该组独立包装层来自历史提交，仅作补充；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/storage_hx4s20c_storage_bringup/results.json)。

- **storage_backpressure**：storage首/行末/中/末及随机背压5项，最长200微秒、每项391像素；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/storage_backpressure/results.json)。

- **mbr_fat_probe**：既有MBR识别缺陷：仅改引导代码3字节，合法分区卡只读LBA0即0x34，扇区接口层复现 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/mbr_fat_probe/results.json)。

- **mbr_pin_probe**：既有MBR识别缺陷在SPI引脚完整链路复现；不是新增回归通过项 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/mbr_pin_probe/results.json)。

- **refresh_idle**：512微秒真实IP刷新场景：idle；50MHz异步写入、125MHz后端；通过；请求/确认/占用/命令=34/34/34/34；最长pending→命令=92.0ns，命令间隔=15000.0ns [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/refresh_idle/results.json)。

- **refresh_continuous**：512微秒真实IP刷新场景：continuous；50MHz异步写入、125MHz后端；通过；请求/确认/占用/命令=34/34/34/34；最长pending→命令=212.0ns，命令间隔=15064.0ns [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/refresh_continuous/results.json)。

- **refresh_pause**：512微秒真实IP刷新场景：pause；50MHz异步写入、125MHz后端；通过；请求/确认/占用/命令=34/34/34/34；最长pending→命令=212.0ns，命令间隔=15064.0ns [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/refresh_pause/results.json)。

- **sdram_formal_180**：正式125MHz/180度的11场景写入、模型存储与读回；独立夹具隔离未完成顶层；统计={"cases": 11, "accepted": 4376, "app_writes": 4376, "reads": 4376, "physical_writes": 1094, "physical_reads": 1094, "physical_refreshes": 57, "write_refresh_overlap": 0, "data_errors": 1094, "storage_checks": 4376, "storage_errors": 0, "coverage_errors": 0}；模型时序错误=0 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/sdram_formal_180/results.json)。

- **sdram_diagnostic_270**：仅测试台270度采样诊断；未改工程PLL，不能计入正式读回通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/sdram_diagnostic_270/results.json)。

## 2026-10-26 异步FIFO接线与storage背压验证

- 用户已将memory_top内同步FIFO换为async_fifo，wr_clk接SYS_CLK（50MHz），rd_clk接Clk（125MHz），32位、深度16；助手只检查和验证，未改模块实现。用户同时整理的sdram_refresh_ctrl注释经去注释比较无逻辑变化。
- 当前顶层真实IP/器件模型写入测试通过：上游50MHz域接受1024字，应用写1024拍、物理WRITE256组，模型存储1024字全部正确，覆盖初始化等待、FIFO满背压及1次自然刷新。尚未验证读回或硬件复位释放时序。
- storage背压5场景通过：首像素、行末、最后像素分别停顿1000个50MHz周期（20µs），中途停顿10000拍（200µs），以及随机背压。每场景391像素地址/颜色/坐标/标志正确；有效像素等待时所有载荷及valid保持，恢复后不丢不重，最后像素握手前不done。
- pixel_ready低表示没有交付，已有待传像素应保持valid为1。空输出寄存器可以先缓存一个像素，SD已发起读取也可完成并缓存；不等于所有内部活动立即停止。复位/abort/读卡错误中止另按帧作废处理。
- 接口后续约定：按50MHz侧full及memory可用状态形成pixel_ready，FIFO写使能以pixel_valid与pixel_ready同拍成立为准；复位时full为0不能单独作为可用依据。当前FIFO仍仅32位数据，像素地址/帧协议以及两域同步释放复位仍待用户完善。
- [完整报告、当前源码快照与命令日志](C:/Users/31640/Documents/ChatGPT/FFF/async_fifo_storage_ready_20261026/README.md)。本轮未改PLL、模块代码，也未将storage实际接入memory；原有读采样及MBR识别问题继续跟踪。

## 2026-10-26 storage与memory对接前检查点

- 用户要求再次检查并保存当前Git版本，后续由用户自行连接两个模块；继续使用memory分支，保存基线为0e5c450之后的当前工作区。
- 本次两个RTL文件的差异均为用户新增注释：sdram_refresh_ctrl的interval_count说明，以及sdram_write_ctrl中Sdr_refresh_pending启动条件说明。去除注释与空白后和原提交逐项相同，逻辑未变；原样保存用户注释，没有代写连接代码。
- 注释精度提示：interval_count实际为0到INTERVAL_CYCLES-1，默认0～1874，1875拍为15µs；用户新增注释写到INTERVAL_CYCLES，尚未替用户改动。
- 对接状态仍为：storage输出尚未连接memory_top，现有TD顶层和清单仍为memory部分；50/125MHz跨域、像素地址/颜色、四字分组和帧排空完成由用户后续实现。
- 本日对接前独立测试已验证56位、深度16的async_fifo在50MHz写/125MHz读下，复位前后各4096条地址与颜色正确，覆盖满空、随机背压、回绕和有数据时共同复位；尚非硬件CDC时序签核。391字尾部检查为388字输出、3字留在预取缓存且FIFO空；392字对照全部输出。详见 [对接检查和独立测试记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_memory_readiness_20261026/README.md)。
- 本次检查未重跑功能仿真：两处变化只涉及注释，历史通过及已知失败按原测试配置保留。1094次正式180°读回错误、MBR识别兼容性问题及整机联调仍未解决。
- [本次保存前核对及源码快照](C:/Users/31640/Documents/ChatGPT/FFF/checkpoint_storage_memory_20261026/checks.json)。

## 2026-10-26 GitHub工程同步

- 已获取GitHub `origin/main` 的 `74ebebc`（合并storage PR #2），合入本地 `memory` 分支。合并前本地检查点为 `2690162`，已有PLL、FIFO、SDRAM及刷新修复提交保留，无合并冲突。
- 本轮接收4个storage RTL：`storage_pipeline`、`sd_spi_reader`、`fat32_bmp_reader`、`bmp_stream_decoder`，以及 `docs/storage.md`。每个新文件的Git对象与远端main一致；除本进度文档外，原有受版本控制文件内容未改变。
- Icarus以Verilog-2005模式编译 `storage_pipeline` 及三个子模块通过。这里只确认新文件语法和模块依赖，本轮没有重新运行功能仿真，没有把storage接入memory_top或修改TD源文件清单。
- 2026-10-25审核中原有92个场景已通过（其中4项属于恢复的历史独立包装层）；新增MBR识别测试复现的0x34错误仍在当前同步版本中，本轮没有修改队友实现。审核证据见 [storage审核记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_review_20261025/REVIEW.md)。
- 后续联调仍需处理像素地址、50/125MHz时钟域、四字组对齐及末尾不足4字、写事务排空后换帧。同步不代表这些接口已接通，也不改变正式180°配置1094次末字读回错误的状态。
- [本轮文件一致性和编译记录](C:/Users/31640/Documents/ChatGPT/FFF/github_sync_20261026/verification.json)。

## 2026-10-25 迭代修复与逐步验证

用户授权：先提交当前版本，再按测试证据修改工程；每步测试完成即同步本节。检查点为 `6a6fc1c`，保留原始故障供对照。

- **busy_gate/continuous**：执行失败。来源：`candidate_busy`。这是隔离候选副本，尚未应用到工程的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/busy_gate/continuous/results.json)。

- **explicit_refresh/continuous**：通过执行。来源：`candidate_refresh`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是隔离候选副本，尚未应用到工程的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/explicit_refresh/continuous/results.json)。

- **explicit_refresh/idle**：通过执行。来源：`candidate_refresh`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是隔离候选副本，尚未应用到工程的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/explicit_refresh/idle/results.json)。

- **explicit_refresh/pause**：通过执行。来源：`candidate_refresh`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是隔离候选副本，尚未应用到工程的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/explicit_refresh/pause/results.json)。

- **refresh_matrix_180**：完整11场景回归未全部通过；统计={"cases": 11, "accepted": 4376, "app_writes": 4376, "reads": 4376, "physical_writes": 1094, "physical_reads": 1094, "physical_refreshes": 60, "write_refresh_overlap": 0, "data_errors": 1094, "storage_checks": 4376, "storage_errors": 0, "coverage_errors": 0}；模型时序错误=0。使用工程125MHz/180° PLL；已知末字读采样故障单独统计，不以存储检查替代读回通过。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/refresh_matrix_180/results.json)。

- **refresh_matrix_phase270_diagnostic**：完整11场景回归通过；统计={"cases": 11, "accepted": 4376, "app_writes": 4376, "reads": 4376, "physical_writes": 1094, "physical_reads": 1094, "physical_refreshes": 60, "write_refresh_overlap": 0, "data_errors": 0, "storage_checks": 4376, "storage_errors": 0, "coverage_errors": 0}；模型时序错误=0。仅测试台将SDRAM时钟移到270°进行读采样诊断，工程PLL未改。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/refresh_matrix_phase270_diagnostic/results.json)。

- **refresh_unit**：刷新仲裁器6项单元测试失败：初始化前抑制、精确周期、手动请求保持高仅触发一次、写/读/下游忙排空与静默保护、确认超时锁存、故障及忙中复位。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/refresh_unit/results.json)。

- **refresh_unit_harness_fixed**：刷新仲裁器6项单元测试通过：初始化前抑制、精确周期、手动请求保持高仅触发一次、写/读/下游忙排空与静默保护、确认超时锁存、故障及忙中复位。前次测试的6项断言实际均通过，但测试台$finish被onbreak按退出码1处理；已修复测试结束方式，未更改RTL。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/refresh_unit_harness_fixed/results.json)。

- **apply_verified_refresh**：已应用通过的刷新仲裁候选：新增调度器、写启动pending门控、顶层单一请求来源、TD源清单和旧测试台端口绑0。PLL、加密IP、FIFO哈希与检查点相同；准备生产文件复测。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/applied.json)。

- **production_refresh/continuous**：通过执行。来源：`production`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是工程源码的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/production_refresh/continuous/results.json)。

- **refresh_unit_deadline_overlap**：刷新仲裁器7项单元测试失败：原6项外增加手动请求紧邻周期到期，要求该请求满足本次刷新而不误报超时；完整仿真日志保留。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/refresh_unit_deadline_overlap/results.json)。

- **refresh_unit_deadline_fixed**：刷新仲裁器7项单元测试通过：原6项外增加手动请求紧邻周期到期，要求该请求满足本次刷新而不误报超时；完整仿真日志保留。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/refresh_unit_deadline_fixed/results.json)。

- **apply_deadline_fix**：手动请求紧邻周期到期会误置refresh_error，已复现并修复：接收新的手动请求时重新开始周期计时；忙中额外手动边沿仍合并。新增第7项单元测试修复前失败、修复后通过，已应用工程，准备最终复测。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/applied_final.json)。

- **production_final/idle**：通过执行。来源：`production`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是工程源码的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/production_final/idle/results.json)。

- **production_final/continuous**：通过执行。来源：`production`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是工程源码的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/production_final/continuous/results.json)。

- **production_final/pause**：通过执行。来源：`production`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是工程源码的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/production_final/pause/results.json)。

- **production_matrix_180**：完整11场景回归未全部通过；统计={"cases": 11, "accepted": 4376, "app_writes": 4376, "reads": 4376, "physical_writes": 1094, "physical_reads": 1094, "physical_refreshes": 57, "write_refresh_overlap": 0, "data_errors": 1094, "storage_checks": 4376, "storage_errors": 0, "coverage_errors": 0}；模型时序错误=0。使用工程125MHz/180° PLL；已知末字读采样故障单独统计，不以存储检查替代读回通过。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/production_matrix_180/results.json)。

- **production_matrix_phase270_diagnostic**：完整11场景回归通过；统计={"cases": 11, "accepted": 4376, "app_writes": 4376, "reads": 4376, "physical_writes": 1094, "physical_reads": 1094, "physical_refreshes": 57, "write_refresh_overlap": 0, "data_errors": 0, "storage_checks": 4376, "storage_errors": 0, "coverage_errors": 0}；模型时序错误=0。仅测试台将SDRAM时钟移到270°进行读采样诊断，工程PLL未改。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/production_matrix_phase270_diagnostic/results.json)。

- **final_source_and_results_audit**：最终生产RTL哈希与测试输入一致；PLL/IP/FIFO哈希与检查点相同，TD的10项源文件存在且编译顺序连续。三场景请求/确认/占用/命令逐项匹配，最长16ns/24ns/60ns，pending到刷新最长196ns，实际刷新间隔最长15.064µs。7项单元通过；正式配置4376字存储正确但1094读回错，270°诊断全通过。此检查不等于TD综合或时序签核。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/final_summary.json)。

- **saved_rerun_entrypoint**：随工程保存的run_refresh.py重跑入口编译及1µs观察器绑定检查通过，源码未改变；只是入口复核，完整功能结论以production_final和production_matrix记录为准。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/final_summary.json)。

## 当前重点问题（2026-10-26）

读采样、刷新调度、文件系统识别和FIFO参数边界分别跟踪。四字写数据已正确进入参考模型，不把读回Z统称为写入失败；未完成的系统连接不计底层失败。

| 编号 | 问题 | 当前状态 |
| --- | --- | --- |
| 1 | 1094次每组第四字返回Z | 已定位参考模型下的读捕获窗口不匹配；未修复，原125MHz/180°配置读回仍失败 |
| 2 | 连续供数时实际刷新延后 | 15µs仲裁已修复，本轮异步夹具三场景及逐拍测试通过；实板及长期保持未验证 |
| 3 | MBR卡被误判superfloppy | 已修复单次回退路径，18项FAT及6项SPI专项通过，原storage回归及背压通过；实卡待验证 |
| 4 | async_fifo最小深度 | 新发现ADDR_WIDTH=1展开失败；当前ADDR_WIDTH=4以及2均通过 |

### 问题1：第四字读回Z（读采样问题）

- 2026-10-24共4376字、1094组测试：应用写拍和模型存储内容全部正确，物理DQ也输出第四字；应用返回每组第四字为Z，共1094错。这批错误不是第四字漏写的证据。
- 当前125MHz周期为8ns，逻辑与SDRAM时钟相差180°。以最后字的SDRAM发数沿为0，参考模型的末字有效窗为5.5～10.5ns，两个相邻逻辑采样沿为4ns、12ns，均不在窗口内。控制器先捕获Z，测试台随后才消费该Z；单纯延后比较不能修复。
- 2026-10-25新版本单组四字复现相同窗口。上轮仅在测试台覆盖移相输入为270°时，4376字读回0错；没有把270°写入工程，该历史诊断因刷新覆盖不足未整体通过；本轮刷新修复后的270°诊断11场景已全通过，但仍未改工程PLL。
- 结论适用于IS42s32200 -7参考模型与当前配置组合；不能据此宣称实物EM638325必然失败。模型无输入时序ERROR，也不等于FPGA端读捕获满足时序。
- 下一步：结合EM638325速度档参数、FPGA输入建立/保持及TD时序核定PLL相位与读捕获安排；确认方案后再修改，并对正式配置执行正常及刷新交叉读回回归。
- 证据：[根因复核及当前版本复现](C:/Users/31640/Documents/ChatGPT/FFF/sdram_read_z_root_cause_20261025/README.md)、[4376字正式回归与相位诊断](C:/Users/31640/Documents/ChatGPT/FFF/sdram_functional_20261024/README.md)。

### 问题2：连续四字组供数时的刷新执行等待

- 原逻辑仍为四字一组，组间有间隙；`Sdr_init_ref_vld` 只表示初始化/刷新实际占用，不表示待处理请求。基线512µs连续写入16请求、0确认、0实际刷新，最早等待至少480.828µs；暂停后才刷新，不能指望PREFETCH的占用检查自行终止内部持续忙。
- Etron EM638325 Rev1.4要求4096次刷新/64ms，均摊15.625µs；不能将2048行直接当成刷新次数。新调度器每15µs置pending，完成当前四拍后阻止新组，等待应用和下游空闲连续4拍，再单拍请求；占用拉高、解除且下游空闲后释放pending。内部周期发生器关闭，避免双重调度。
- 2026-10-25的三个512µs生产测试均34/34/34/34、最长pending→命令196ns；2026-10-26采用50MHz异步输入独立夹具重跑，三个场景仍各34/34/34/34，最长pending→命令212ns、IP请求→命令60ns、命令间隔15.064µs。本轮11场景4376字落存0错，刷新覆盖/写占用重叠均0，4096字连续写阶段刷新6次；当前接口草稿未参与该夹具。
- 仅加Sdr_busy启动门控的候选出现间隔8ns的两条刷新及tRC错误，已拒绝，不加入工程。
- 7项仲裁单元测试通过，包含修复后的手动/定时交界；超时将锁存内部refresh_error并保持禁止启动；当前LED仍仅指示初始化。后续读控制器也须遵守pending禁止新组并与写互斥。
- 本次已按用户授权修改RTL及工程源清单；逐步候选结果和生产复测分开保留。没有更改PLL、加密IP、FIFO；正式读回错误尚存，无板级与长期数据保持通过证据。完整记录见 [SDRAM_REFRESH_VERIFICATION.md](SDRAM_REFRESH_VERIFICATION.md)。

## 模块与工程状态

| 部分 | 当前已完成或已确认 | 尚需完成或核实 |
| --- | --- | --- |
| 同步 FIFO `sync_fifo` | 本轮4组参数回归通过：8/32/56位、深度2/4/16的选定组合；满空、并发、回绕、非空复位；32位FIFO到writer的20字也通过 | 其他参数、综合推断和实际时序需按使用配置验证 |
| 异步 FIFO `async_fifo` | 本轮6组参数回归通过：8/32/56位、深度4/16、50→125MHz及125→50MHz；满空、回绕、背压和共同复位通过 | ADDR_WIDTH=1（深度2）位选越界无法展开；实际CDC、复位释放及Gray总线约束待检查 |
| 写控制器 `sdram_write_ctrl` | 本轮11项单元/306次写拍通过，pending启动/中途交界检查通过；四拍连续、地址/数据/DM正确 | 仍要求四字成组；391字只出388，尾部/帧地址与排空协议待后续扩展 |
| FIFO → 写控制器 | 当前同步FIFO20字检查通过；异步FIFO→当前写入/刷新/IP独立夹具4376字应用写及模型落存正确 | 系统顶层连接由用户继续处理；正式读回仍失败，尾包和帧协议待完善 |
| 存储顶层 `memory_top` | 已有FIFO/写入/刷新/SIP连接基础，历史1024字接线检查通过；当前正在重构像素/帧接口 | 本轮隔离该接口草稿，未宣称它当前编译或整机通过；上游接口/复位/地址仍由用户完善 |
| 公共参数 `include/global_def.v` | 数据 32 位、地址 21 位、DM 4 位、行 11 位、BANK 2 位；125 MHz 计时宏已修复分组，常量及两次自动请求检查通过 | 旧内部周期发生器已关闭，该宏当前不控制实际刷新；新仲裁器按1875拍周期运行 |
| PLL `clk_pll` | 本轮真实行为模型周期及相位检查通过：50MHz输入，100/125/125MHz输出，后两路180度 | 正式180度读捕获仍不匹配参考模型；硬件冷启动、板级时序尚未验证 |
| SDRAM 控制器与器件模型 | 本轮原样参考IP和IS42s32200模型完成11场景4376字回归，写入存储0错；三种刷新场景通过 | 正式180度读回1094错；270度仅测试台诊断通过，实板/时序签核待完成 |
| SDRAM 读通路与帧缓存管理 | 当前目录中未发现实现 | 读请求、显示供数、帧地址管理与读写协调 |
| 存储与显示接口 | `docs/.gitkeep` 中有像素接口草稿，包括 pix_clk、pix_req、frame_sync、pix_rgb、pix_valid、frame_ready、pix_underflow | 整理为正式接口文档，明确时钟、复位、请求与返回时序，并落实到 RTL |
| SD 卡与 BMP 解析 | MBR误识别已修复；18项FAT和6项SPI专项通过；原88项直接测试、4项历史包装层及5项背压全部通过 | 真实卡、外部时序和整机接口留待后续；修复后TD时序需重新核定 |
| HDMI 显示与音频 | 本地 `display.v` 为空模块 | 有效实现、显示通路集成与测试；其他成员的外部进度不在本次核对范围内 |
| TD 综合与约束 | `memory` 分支源清单包含参数头文件、PLL、FIFO、写控制器、三个 IP 文件及 `memory_top`，顶层设为 `memory_top`；目标 EG4S20BG256 | 仅完成工程配置，尚未运行新顶层综合；旧报告仍对应 `async_fifo`；约束、布局布线、时序与上板待完成 |

## 2026-10-24 SDRAM模型写读回与刷新交叉回归

**当前125MHz/180°配置整体测试失败。** 本轮仅新增独立测试台、模型副本及验证记录，没有修改工程模块、PLL、计时参数或用户现有测试台。

- 11场景共4376个上游字、1094组四拍；4376应用写拍及物理模型存储逐字检查正确。应用接口返回4376字，其中每组第四字为Z，共1094错，不能认定完整读回通过。
- 四拍各消费位置分别请求刷新，真实IP均把占用和AUTO REFRESH延后；无App写拍与真实刷新占用重叠。真实刷新已有效时供数，新组等待解除后启动的检查通过。这不等于验证了人为强制刷新有效时仍续写三拍安全。
- 连续4096字写窗口98.232μs内没有实际AUTO REFRESH，前后命令最大间隔99.544μs；预期至少两次实际刷新的覆盖未达成。模型不模拟长期缺刷新数据衰减，刷新预算仍未解决。
- 第四字确实正确写入并从物理DQ输出，但当前控制器捕获比模型最后数据有效窗晚1.5ns。仅测试台改为270°的诊断可使4376字全部读回正确；该诊断仍存在刷新覆盖问题，不等于工程或实板通过，未把270°写入PLL。
- 正式回归使用原样IS42s32200 -7参考行为模型，未放宽模型参数，未强制刷新状态、ACK或返回数据；模型没有报告内置时序ERROR。PLL模型启动仍使用200ns测试台复位，原硬件冷启动未验证。
- 详细矩阵、波形、日志、输入哈希、失败和诊断记录见 [功能回归报告](C:/Users/31640/Documents/ChatGPT/FFF/sdram_functional_20261024/README.md)。当前优先项改为读捕获时序及连续写刷新等待预算。

## 2026-10-24 初始化状态指示 Check_ok

- 用户选择让LED暂时表示“PLL锁定且SDRAM初始化完成”。新增组合赋值 `Check_ok = lock && Sdr_init_done`，保持现有LED连接；无锁定或初始化未完成时为0，两者成立时为1。周期刷新不使初始化失效，因此不把刷新占用标志加入这个条件。
- 这只是初始化状态，既不是写入接收握手，也不是存储数据校验通过；LED实际亮灭还取决于板卡极性。
- 保留用户新增的两个 `App_rd_*` 赋零。移除 `assign Sdr_rd_en = 0`：该信号是IP输出，额外驱动会与IP冲突。
- 真实PLL与SDRAM控制器连接的独立测试台先对PLL模型注入200ns复位，再检查锁定前LED为0、初始化完成后LED为1，随后5000个125MHz周期保持为1；强制锁定状态为0后LED立即为0。ModelSim运行1.2ms，输出 `MEMORY_READY_PASS`。测试不涉及存储数据读回。
- 原顶层PLL复位固定0时，本次仿真在1.19ms仍未锁定；失败记录保留在验证目录的without_pll_reset中。带测试台复位的通过不能证明原硬件顶层的冷启动或失锁恢复设计已验证，相关复位策略仍待后续核实。
- 差异、测试台、完整命令和日志见 [Check_ok验证记录](C:/Users/31640/Documents/ChatGPT/FFF/check_ok_20261024/README.md)。FIFO、写控制器、供应商IP、计时头文件及用户测试台保持原样，未创建新Git提交。

## 2026-10-24 物理 SDRAM 原语接入

- 经用户明确授权，在 `memory_top` 新增内部物理信号：时钟及 RAS/CAS/WE 各1位、BA 2位、ADDR 11位、DM 4位、双向DQ 32位；显式声明 `Sdr_busy`。
- 新增 `EG_PHY_SDRAM_2M_32 u_sdram_phy`，连接控制器的物理接口，片选接0、时钟使能接1，DM按四个独立字节端口连接。接线对照 APUG011 原始 `top.v` 与本机 TD6.2 器件模板。
- 该原语由 EG4S20 器件库提供；TD 工程无需加入供应商仿真模型源码，也无需把这些合封器件内部连接添加为外部板级引脚。
- ModelSim 编译及0ns层次加载通过，并加载 `eg.EG_PHY_SDRAM_2M_32`；原BA/ADDR/DM/DQ四类宽度警告消除，保留供应商常量及PLL端口的3条警告。检查不推进数据传输，不能据此认为SDRAM读写或刷新执行已经通过。
- 修改差异和验证凭据见 [SIP接入记录](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sip_integration_20261024/README.md)。本次未修改 FIFO、写控制器或用户现有测试台，未新增Git提交。

## 2026-10-24 刷新计时宏修复

- 经用户明确授权，仅给 `SDR_CLK_PERIOD` 与 `SELF_REFRESH_INTERVAL` 增加表达式分组括号，避免文本宏展开改变除法结合顺序；用户模块、测试台和供应商 IP 均未改写。
- 修复前 ModelSim 对照检查复现 `period=8 interval=0`，测试按预期失败。修复后为 `period=8 interval=3906`，提前请求比较值为 3896；另检查了宏作为除数时的分组效果。
- 以真实 `sdr_init_ref.enc.v` 在 125 MHz 下运行至初始化完成及两次自动请求：首请求在初始化完成后 3897 拍，两次请求间隔 3907 拍（31.256 μs），请求宽度各一拍。运行至 1.2 ms，退出 0，保留一条供应商未定宽常量警告。
- 本次固定手动刷新请求、刷新确认和读写活动输入为 0，仅验证自动请求调度；没有验证刷新确认、物理刷新命令或 SDRAM 数据保持。现有计数为 0 到 3906，含端点；若按 2048 次估算约 64.012288 ms，刷新预算及等待余量仍需单独核对，不能宣称器件 64 ms 要求已满足。
- 完整命令、源码哈希、修复前后头文件、测试台和日志保存在 [刷新宏验证记录](C:/Users/31640/Documents/ChatGPT/FFF/refresh_macro_fix_20261024/README.md)。修复应用时核对工程头文件与已测试副本逐字节一致。

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
2. 用户已将 `App_rd_en`、`App_rd_addr` 固定为0，停用读请求；助手移除对IP输出 `Sdr_rd_en` 的额外赋零，保持输出由IP驱动。
3. SDRAM 物理信号位宽及 SIP 原语例化已于2026-10-24补齐；继续验证器件命令、刷新执行与数据读回。
4. `Sdr_busy` 已声明；`Check_ok` 已按用户选择驱动为PLL锁定且初始化完成，LED不表示写入、读回或数据校验通过。
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
- 参考顶层原用控制器定时刷新；本项目2026-10-25已切换到应用侧15µs调度，关闭内部周期发生器，App_ref_req由仲裁器驱动。部分内部协调逻辑加密，无法据资料确认中途刷新时剩余拍的接收保证。
- 手册对 `Sdr_busy` 存在“暂不使用”与“操作前检查”的不一致，保留为待核实项，不把它直接解释为 ready。

旧 APUG011 PLL 按 25 MHz 输入设计，参考测试台却使用 80 ns 输入周期，即 12.5 MHz，与其声明不一致。本轮已改用配套板卡例程的 50 MHz 输入 PLL，存储时钟为 125 MHz。`SDR_CLK_PERIOD` 只是计时参数，不会改变 PLL 输出频率。

参考包包含 ModelSim 脚本和器件模型 `IS42s32200.v`；该模型名称不代表实际合封器件型号。旧脚本和旧日志不作为本轮通过证据。2026-10-24已使用本机安路库及原样参考器件模型执行写读回，当前配置失败，详见本轮功能回归记录。

## WRITE 期间出现刷新的待办

**已验证输出行为，尚未验证真实存储结果。**

集成测试在第四组首字（地址 12）输出后拉高 `Sdr_init_ref_vld`。当前 RTL 在标志有效时继续输出地址 13、14、15 的三个字，然后等待标志解除才启动下一组。

这项测试按当前 RTL 的“继续完成已启动的四字输出”设置预期，明确允许这三拍重叠。日志的 `INTEGRATION_PASS` 表示满足这套预期，不能用来证明刷新期间的数据最终写入正确。

待确认的问题：

1. 参考明文已确认该标志表示初始化或刷新占用；它与内部请求、应答和实际器件命令的完整时间关系仍需核实。
2. 下游是否保证一组四字输入一旦开始就连续接收？若下游不能接收，内部缓冲如何处理？当前应用写接口没有逐拍接收确认输入。
3. 参考 IP 内部存在读写/刷新握手，但主体加密；应用层应配合启动门控与读写互斥。先确认真实接收行为，再决定是否修改当前写控制器。
4. 接入实际 SDRAM 控制器与器件模型后，覆盖写入前、首拍附近和四拍中途出现刷新，写入后逐字读回比较，确认地址、数量、顺序及数据均正确。

2026-10-24已补充真实控制器加行为模型的测试：合法请求触发的实际刷新延后，无四拍重叠；4376字模型落存正确，应用读回与连续写刷新预算仍有问题。真实器件上板尚未验证，不能认定刷新协调已完全解决。

## 综合记录的使用范围

本轮 `memory` 分支将 `project/td/HDMI_Player.al` 的顶层改为 `memory_top`；保留的旧 `syn_1` 报告仍标注 `async_fifo`，不能解释为新顶层综合结果。旧 `docs/sync_fifo.md` 中 LUT 37、REG 10、OREG 9、BRAM 0 是同步 FIFO 的历史文档记录；未找到与其对应的保留报告，不将其作为本次重新确认的结果。

当前异步 FIFO 的 `HDMI_Player_gate.area` 在 Utilization Statistics 栏记载 LUT 41、REG 40、OREG 11、BRAM 0。该报告另有不同口径的 LUT Statistics，记录资源时需同时注明模块、参数和报告栏目。

现存正时序裕量属于综合阶段报告，不能作为布局布线后或板级时序通过的结论。`constraints` 目录仅有占位文件，尚未看到实际约束和实现阶段完成产物。

## 下一步顺序与完成条件

| 顺序 | 工作 | 完成条件 |
| --- | --- | --- |
| 1 | 处理问题1：读捕获时序 | 依据器件和FPGA时序核定相位/采样安排；正式配置正常及刷新交叉读回无末字Z，不以测试台相位覆盖冒充工程修复 |
| 2 | 扩展刷新修复验证 | 模型短窗三场景和逐拍测试已完成；进一步核对实物速度/温度档、长期调度与板级运行，未来读控制器也遵守pending约定 |
| 3 | 按接口结果完善写通路 | 需要修改时补充相应断言并回归；异步 FIFO 接入和 FIFO 边界用例有可复现记录 |
| 4 | 补齐读通路与显示供数 | 写入的数据能经读通路按帧输出，frame_ready、pix_valid 与缺数处理有明确行为 |
| 5 | 完善工程并推进上板 | 相关 RTL 纳入工程，约束完整，布局布线与时序检查完成，板级读写及显示验证有记录 |

当前优先项是正式读捕获时序与上游时钟域。刷新仲裁已有模型通过证据，后续补实板与长期验证；不得将270°测试台诊断当作正式PLL配置或完整工程通过。

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

本文件作为截至 2026-10-26 的进度总表，与原工程 `docs/PROJECT_PROGRESS.md` 同步保存。Git 保存用户模块、参考 IP、工程配置和验证证据，不表示完整存储功能通过。助手已导入IP、修复计时宏，并按用户明确授权给顶层增加物理原语连接；2026-10-25按新增授权修改刷新启动门控、顶层仲裁及测试台新端口，PLL/IP/FIFO未改。后续每次更新记录“具体改动、验证方法、证据位置、剩余问题”，历史测试数量不自动代表新版本已经验证。
