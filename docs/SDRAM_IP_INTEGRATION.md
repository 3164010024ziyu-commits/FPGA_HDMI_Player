# SDRAM 参考 IP 接入说明

本轮修改位于memory分支，基线为main的ae419c6检查点。用户的memory_top、sdram_write_ctrl、sync_fifo、async_fifo实现保持原样。

## 文件与配置

- 现有rtl/memory/sdram_write_ctrl.v已纳入TD工程，没有重新实现或复制第二份写控制器。
- rtl/ip/clk_pll/clk_pll.v与.ipc来自HX4S20C配套lab_ex4_tf的Anlogic生成文件，模块名sys_pll适配为clk_pll；原语配置保持不变。
- PLL输入50MHz，C0=100MHz/0°（当前local_clk未用）、C1=125MHz/0°（Clk）、C2=125MHz/180°（Clk_sft）。不混用APUG011旧25MHz输入仿真文件。
- include/global_def.v的SDR_CLK_PERIOD配置从150MHz同步为125MHz，其他位宽保持32/21/4/11/2。
- rtl/ip/sdram内三个.enc.v来自APUG011v1.2，逐字节原样复制。来源及哈希见rtl/ip/source_manifest.json。
- project/td/HDMI_Player.al把头文件设为全局包含，加入PLL、写控制器、参考IP和memory_top，顶层设为memory_top；移除同步FIFO旧的自动排除标记。

## 验证与用户下一步

ModelSim编译及保留层次的0ns加载通过，PLL外部输出周期和相位检查通过。日志与测试台见verification/ip_integration_20261023。当前保留的旧TD综合报告仍是async_fifo结果，不能用于新顶层。

接下来由用户先明确停用未使用的读输入，再声明并连接真实宽度的物理SDRAM总线与SIP原语，处理LED状态和上游时钟约定。随后进行供数、器件模型逐字读回及刷新交叉测试。此次导入不代表完整存储功能或上板通过。
