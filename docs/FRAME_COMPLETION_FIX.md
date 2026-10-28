# 帧完成与返回同步最小修复（2026-10-28）

> 后续复位更新：外部Reset_n现已接入整个memory控制通路，50/125MHz分别同步释放；初始化前就绪关闭。当前行为及测试范围见[MEMORY_RESET_VERIFICATION.md](MEMORY_RESET_VERIFICATION.md)，以下保留此前阶段记录。

本轮用户明确授权助手：检查刚添加的50 MHz同步、先保存Git，再尽量少改代码修复同高度第二帧完成清不掉、无描述误报及早于下游排空三个问题。

修复前本地检查点：`35b73354582f20184b80e027fdffdb9ac7a5921a`，分支memory。该提交原样保存用户当时的4个文件，包含已记录的同步端口/复位编写问题。后续修复保留在工作区供查看差异。

## 实际修改范围

共改4个RTL文件和1个TD清单，修复相对检查点为69行新增、15行删除。原四字状态机、预取/写计数器、地址公式、FIFO、PLL、刷新仲裁和加密IP保留。

| 文件 | 修改 |
| --- | --- |
| rtl/memory/sdram_write_ctrl.v | 新增Sdr_busy输入、frame_active和3位排空计数；新描述优先清done；只有非零尺寸有效描述能够激活完成判断；整帧字数提交后连续4拍确认下游/FIFO输出空闲再置done并保持。行列初始化与正常推进改为互斥。 |
| rtl/memory/frame_desc_cdc.v | 保留用户写的两级50 MHz同步结构；修正端口分隔符和输出类型；复位清正确的done同步寄存器，移除误写ack同步寄存器造成的重复驱动。 |
| rtl/memory/memory_top.v | 将现有Sdr_busy连接到写控制器新增输入。 |
| rtl/top/hdmi_player_top.v | 使用正确的frame_write_done_sync端口名；初始空闲允许首帧；接受请求即占用帧任务，必须看到本帧done先低后高且storage空闲才释放，避免旧完成电平的同步延迟提前解锁；保留头部失败且尚未发出描述时的错误重试。 |
| project/td/HDMI_Player.al | 追加frame_desc_cdc文件，编译条目16；不重排原清单。 |

## 完成信号的约定

写控制器的frame_write_done属于125 MHz域，是保持电平：复位为0，每次新描述到来清0，只有该帧达到末字之后且下游确认排空，才置1并保持到下次描述。

排空判断同时检查：有效帧、已完成行列计数、SDRAM初始化完成、没有App写有效、Sdr_busy为0、没有初始化/刷新占用、FIFO为空且没有FIFO读回有效。这些条件连续成立4个125 MHz时钟后再置完成。4拍保护沿用当前刷新仲裁已有的管线静默策略，避免厂商busy稍晚出现时过早完成。

frame_desc_cdc把该保持电平经过两级同步返回50 MHz，memory_top对外输出为frame_write_done_sync；系统顶层memory_frame_write_done连接到这个已同步输出。

首次启动依赖初始空闲状态，不要求预先出现完成。任务启动后，系统记录本次done低电平，再等待其高电平与storage空闲。若头部就失败、尚无帧描述，则可以释放请求状态重试。storage的done与memory完成可先后到达，控制不要求两个脉冲同拍。

## 已运行的验证

| 组别 | 结果与范围 |
| --- | --- |
| writer_completion | 无描述height=0保持done0；同高度4×2两帧分别清零并完成；模拟末字后busy延迟出现及持续忙，解除后满4quiet拍才done；5字尾包仍只出4字，done0；共20字数据/地址检查。 |
| frame_sync | 完成电平上升、下降均经过两级50 MHz同步，复位无未知态；3组帧描述req/ack正确；奇数翻转状态下共同复位恢复。 |
| writer_addresses | 真实写控制器+同步FIFO，正行序、反行序、刷新暂停3场景，24字地址/数据正确。复用旧夹具未观察完成输出，因此其未连接输出提示不影响本组地址检查。 |
| system_gate | 真实系统顶层+受控memory/storage替身，首帧done0可启动；旧done高不得释放新帧；新低后高且storage空闲后释放；头部错误可重试；控制层复位恢复，共5场景。 |
| real_hierarchy | 当前完整16条TD清单与真实厂商原语编译、零时刻加载通过。保留厂商IP两项无尺寸常量告警和PLL模型load_reg宽度告警。 |
| real_ip_completion | 真实memory_top、异步FIFO、CDC、写控制器、刷新控制器和加密SDRAM IP，受控125 MHz/180°时钟；同高度两帧，第一帧正行序、第二帧反行序，16字应用地址/数据正确。两帧done均在末字App提交后120ns、Sdr_busy解除后32ns出现，done时busy=0；50 MHz完成正确返回。 |
| real_storage_wiring | 真实系统顶层+真实storage+SPI卡模型+测试memory接收模型：两次391像素成功，中间坏BMP报0x20并恢复；782像素、2314次背压保持检查通过。该组不使用真实写控制器，不能算391字尾包已修复。 |

七组验证全部通过。真实IP时序诊断在测试台控制时钟及lock释放，绕过PLL仿真启动；没有修改工程PLL，也没有验证SDRAM存储内容、读回、实板或布局布线。原样层次检查仅为零时刻加载。

## 保留的边界

- 四字尾包仍待实现，宽度/行边界非四字对齐的通用写入未完成；本轮不宣称任意BMP尺寸均可完成。
- 帧描述产生后发生部分帧错误，原有abort/丢弃流程仍未实现，任务可能保持占用；本轮只保留了尚无描述时的错误重试。
- memory外部Reset_n接入、两侧独立复位恢复、正式180°读采样及板级时序继续独立跟踪。控制层替身的复位测试不等于真实memory的外部复位验收。

工程源码快照、修改前备份、测试文件及日志位于 `C:/Users/31640/Documents/ChatGPT/FFF/completion_minimal_fix_20261028/`。汇总为verification_results.json，重跑入口verify_fix.py；原始同步编译失败证据位于baseline_compile。
