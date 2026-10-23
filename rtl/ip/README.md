# 存储参考 IP

这些文件按用户要求接入 memory 分支，保留原供应商版权和受保护代码。

- `clk_pll/clk_pll.v`：来自HX4S20C配套lab_ex4_tf的Anlogic IP Generator输出；输入50MHz，C0=100MHz/0°、C1=125MHz/0°、C2=125MHz/180°。仅将模块名sys_pll适配为现有顶层使用的clk_pll，原语参数未手调。
- `clk_pll/clk_pll.ipc`：配套配置副本，目标EG4S20BG256，文件名与Verilog输出对应。
- `sdram/*.enc.v`：APUG011 v1.2原样复制的sdr_as_ram、sdr_init_ref、sdr_wrrd及其受保护逻辑。

旧APUG011的25MHz输入clk_pll_sim.v没有混入本工程。仿真也使用这里的50MHz配置及本机安路EG4行为模型。

刷新计时头文件已按125MHz配置。当前用户memory_top的物理SDRAM接线、未用读输入和LED状态仍待用户完成，导入IP不等于存储功能或上板验证通过。

来源和SHA-256见`source_manifest.json`。用户的FIFO、写控制器和memory_top实现未因本次导入改写。
