# memory 分支 IP 接入验证

2026-10-23 使用本机ModelSim SE-64 2020.4及TD6.2的common/eg4仿真库验证。为保持用户模块实现不变，在FFF暂存副本编译；导入时逐文件核对SHA-256。

## 已验证

- elaboration：供应商库、三个受保护SDRAM模块、PLL及用户顶层编译退出0；保留内部访问的memory_top层次加载成功，运行0ns。它不验证实际数据传输。
- pll_smoke：50MHz输入；锁定后外部测得C0周期10ns，C1/C2周期8ns，相位间隔4ns。完成时周期检查16/20/20次、相位21次，1111.200ns输出PLL_SMOKE_PASS；批处理运行到50us，退出0。
- results.json记录实际使用的暂存路径、完整命令、输入哈希、退出码及源码未变检查。路径仍保留真实运行位置，不改写成尚未运行的路径。

## 重跑

在安装了对应ModelSim及安路仿真库的环境下，用Python运行本目录check_memory_elaboration.py，传入--project为工程根目录。默认执行编译与0ns加载；追加--testbench指向本目录pll_smoke_tb.v、--top pll_smoke_tb、--run-time "50 us"、--expect-marker PLL_SMOKE_PASS可执行时钟检查。首次编译库后可用--skip-libraries复用本目录run下的库。工具路径可通过--modelsim和--vendor-libs配置。

## 验证边界

层次检查仍有用户尚未声明物理总线导致的BA/ADDR/DM/DQ位宽警告；参考IP也有未定宽常量以及PLL load_reg连接宽度警告，均在日志中保留。没有改用户RTL来消除这些警告。

用户仍需固定未用读输入、完成物理总线声明与EG_PHY_SDRAM_2M_32连接、设计LED状态、明确上游时钟域。尚未完成SDRAM器件模型读回、刷新交叉写入、综合实现或上板验证。
