# SDRAM 参考 IP 接入说明

IP初次导入位于memory分支，基线为main的ae419c6检查点，当时用户模块保持原样。2026-10-24经用户授权修复计时宏，并给memory_top增加物理总线和SIP原语例化；FIFO、写控制器和用户测试台保持原样。

## 文件与配置

- 现有rtl/memory/sdram_write_ctrl.v已纳入TD工程，没有重新实现或复制第二份写控制器。
- rtl/ip/clk_pll/clk_pll.v与.ipc来自HX4S20C配套lab_ex4_tf的Anlogic生成文件，模块名sys_pll适配为clk_pll；原语配置保持不变。
- PLL输入50MHz，C0=100MHz/0°（当前local_clk未用）、C1=125MHz/0°（Clk）、C2=125MHz/180°（Clk_sft）。不混用APUG011旧25MHz输入仿真文件。
- include/global_def.v的SDR_CLK_PERIOD配置从150MHz同步为125MHz，其他位宽保持32/21/4/11/2。
- rtl/ip/sdram内三个.enc.v来自APUG011v1.2，逐字节原样复制。来源及哈希见rtl/ip/source_manifest.json。
- project/td/HDMI_Player.al把头文件设为全局包含，加入PLL、写控制器、参考IP和memory_top，顶层设为memory_top；移除同步FIFO旧的自动排除标记。

## 验证与用户下一步

ModelSim编译及保留层次的0ns加载通过，PLL外部输出周期和相位检查通过。日志与测试台见verification/ip_integration_20261023。当前保留的旧TD综合报告仍是async_fifo结果，不能用于新顶层。

用户已固定未用读输入，Check_ok已按用户选择表示PLL锁定且初始化完成。接下来明确上游时钟约定，再进行供数、器件模型逐字读回及刷新交叉测试。此次导入不代表完整存储功能或上板通过。

2026-10-24：memory_top已声明BA/ADDR/DM/DQ真实宽度并例化EG_PHY_SDRAM_2M_32，片选0、CKE1、DM逐位连接；Sdr_busy已显式声明。原语来自TD器件库，不把sim_release模型加入综合源清单。新一轮0ns层次加载确认原语已加载，四类物理总线位宽警告消除；完整存储功能仍待验证。

Check_ok仅为初始化状态，不代表存储数据校验；未加入刷新占用条件。Sdr_rd_en是IP输出，保持由IP唯一驱动。相关顶层初始化指示仿真及差异保存在FFF/check_ok_20261024。

2026-10-24功能回归：11场景4376字模型落存正确，当前125MHz/180°每组第四应用读返回Z共1094错。刷新请求延后到写流结束，连续4096字窗口98.232μs无实际刷新，最大间隔99.544μs。仅测试台270°诊断消除读错误，未修改工程相位；整体测试仍失败，详见FFF/sdram_functional_20261024/README.md。
