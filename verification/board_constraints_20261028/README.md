# 板级封装与约束验证

从工程根目录执行：

```powershell
python verification/board_constraints_20261028/run.py
```

需要 Icarus Verilog；可用 `IVERILOG_BIN` 指定包含 `iverilog.exe`、`vvp.exe` 的目录。输出默认为系统临时目录的 `hx4s20_board_wrapper`，可用 `--output` 覆盖。

`board_wrapper_tb.sv` 使用真实 `hdmi_player_board_top` 和受控系统核心替身，检查无按键复位时的上电启动、按键抖动、长按只请求一次、忙时保留一个请求、外部复位、LED跨域同步/错误保持以及文件序号和缓存基址固定为0。该替身不能加入TD源码清单。

本次测试通过；另已用真实厂商库展开主工程全部34个Verilog/VHDL文件，并在TD 6.2.168116中加载ADC/SDC执行gate综合。

约束核对：15个逻辑顶层信号全部绑定，HDMI自动配对负端后共19个PAD；6个时钟频率分别为50/100/125/125/125/25MHz。FIFO写、读Gray首级分别17位，标量握手/完成首级3位，优化后的描述目的寄存器19位，四组8ns限制均生效，无Shadowed或Ignored。

**当前时序未收敛**：综合估计最差setup slack为-6.566ns，最差写地址组合路径约14.450ns，125MHz预算8ns。未进行布局布线验收，没有因综合成功而将时序记为通过。没有修改原业务模块、降低实际时钟、添加未经证明的多周期例外或生成下载文件。

管脚来源、按键和LED含义及外部I/O预算边界见 [BOARD_CONSTRAINTS.md](../../docs/BOARD_CONSTRAINTS.md)。原始记录在 `C:/Users/31640/Documents/ChatGPT/FFF/board_constraints_20261028`。
