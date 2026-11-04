# 显示FIFO欠载：返回数据流水输出修复

日期：2026-10-29。用户使用专用诊断bit确认仅LED2亮，LED3/LED4灭，说明发生了显示FIFO欠载，未记录读超时、加载或刷新错误。原图和受控BMP解码完整。

## 原因和改动

此前 `sdram_read_ctrl.v` 必须收齐四字，才进入EMIT逐字写显示FIFO。四字返回时，已经收到的字仍在本地缓冲等候；这部分等待降低读显通路的吞吐和停顿余量。FIFO被耗空后，既有保护会把当前帧剩余像素屏蔽为黑色。

现在仍按四拍请求、保留四字本地缓冲，但收到的字可以在ISSUE/RECEIVE阶段送往显示FIFO；剩余字继续接收。只有第四字真正送出才复用缓冲或进入下一组。FIFO满时保留本地字，flush取消本帧后不送旧数据，超时和欠载保护继续有效。黑边填充组显式标记四个零像素均已就绪，防止补黑路径停住。

**功能修改仅在 `rtl/memory/sdram_read_ctrl.v`。** 没有改变PLL、SDC、引脚、刷新调度、FIFO容量或写控制器，也没有删除报错保护。保留上一轮的可选诊断接口和用户已有修改。

实板证据确认了欠载类型，但没有采集首次出错时的组时延/FIFO水位；下述额外4拍是受控压力条件，并非实测硬件延迟。修复已通过仿真及新布局布线，实际板卡的底部显示仍需用新bit复测。

## 前后对照及验证

| 检查 | 结果 |
|---|---|
| 实际BMP：640×480/24位BI_RGB，正高度、从底行输入 | 逐像素比较原图全部行 |
| 原版，每组读响应额外延迟4个100MHz周期 | 在x=616、y=337处欠载，复现上部正常后黑屏的同类故障 |
| 修改版，完全相同受控条件 | 3帧、921600像素通过，4383次刷新，无欠载或错像素 |
| 实际两组PLL、原厂加密IP、未修改IS42模型 | 实际BMP两帧、614400像素全部匹配，含底部最后一行；无欠载 |
| 实际memory PLL/IP小帧 | 6帧、768像素，100次相位检查，0错字/0 Z，外部复位恢复通过 |
| 应用模型回归 | 14帧1792像素；小图补黑、换图、abort、欠载/超时恢复及复位通过 |
| 不规则返回间隔、FIFO满、读事务取消 | 9个光栅1152像素、4次取消、701个读活动背压周期通过 |
| 真实生产文件与厂商库层次 | 34个Verilog/VHDL源文件编译及层次展开通过 |
| 新最终布局布线 | setup +0.161 ns，min +0.010 ns；13152项无负裕量，慢快角检查通过 |

数据路径保持原DQ约束，DQ输入最小+0.335ns、输出+1.374ns；异常约束无新增shadow/ignore。原有SIP初始位置调整与非时钟端分支局部布线提示仍在，未为消除提示放宽约束。最小裕量仍较小，后续修改必须重新布局布线。

## 本次下载文件

`C:\Users\31640\Documents\ChatGPT\FFF\display_underflow_fix_20261029\HDMI_Player_underflow_fixed_20261029.bit`

SHA-256：`03c4ddda80de1f9537c161d4882b698fccfbfd2bdc601446462e991f7f85c2aa`

**这是普通灯模式的新修复文件，不是上一轮错误分类bit。** 四灯恢复为：LED1=memory就绪，LED2=SD初始化，LED3=前台帧有效，LED4=错误锁存。期望加载后前三灯亮、第四灯灭。

下载后按KEY1复位，等待数秒再按KEY2加载同一张测试图，检查底部黑白区是否完整、LED4是否保持灭。尚未由助手连接或下载硬件，也未提交Git。

## 复现测试

```powershell
python verification/display_underflow_20261029/run.py stalls
python verification/display_underflow_20261029/run.py stress --bmp C:/Users/31640/Documents/ChatGPT/FFF/test_pattern_640x480_24bit.bmp
python verification/display_underflow_20261029/run.py stress --baseline --bmp C:/Users/31640/Documents/ChatGPT/FFF/test_pattern_640x480_24bit.bmp --output C:/Users/31640/Documents/ChatGPT/FFF/underflow_baseline_recheck
```

`--baseline`使用测试目录内的修复前reader参考文件，仅预期受控欠载；不会覆盖生产源码。测试依赖已安装的ModelSim/Icarus与此前验证所用厂商库，工具路径可通过环境变量调整。真实IP完整图测试使用`physical --bmp ... --model .../IS42s32200.v`，耗时较长。原图须为本次640×480、正高度、24位BI_RGB，测试不会修改它。

本轮日志与源码快照在FFF的`display_underflow_fix_20261029/`。剩余既有限制：外部SD/HDMI板级签核、四字尾包、运行中PLL失锁自动重播未完成。此次未更改这些范围。
