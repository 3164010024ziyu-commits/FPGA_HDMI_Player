# memory外部复位接入与整机复位检查（2026-10-28）

用户授权：检查整个工程复位逻辑，使外部Reset_n真正复位整个memory通路。修改前已保存所有RTL、头文件、TD清单和文档快照，保留此前尚未提交的帧完成修复及用户注释。本轮未创建Git提交。

## 检查结论与复位分配

修改前，顶层和storage使用外部Reset_n生成的50 MHz复位，memory虽然有Reset_n输入，内部却只跟随PLL的lock。外部复位时可能保留FIFO数据、帧描述和在途写入状态。本轮将其接入统一请求，并在两个时钟域分别释放。

| 模块/状态 | 复位来源与结果 |
| --- | --- |
| hdmi_player_top | 原有reset_release保持不变：外部低有效Reset_n异步断言、50 MHz两级释放；清启动控制、帧任务、基址和就绪同步。 |
| storage_pipeline、SD SPI、FAT32、BMP解码 | 沿用sys_reset_n，清协议/文件/解码状态；SPI退出当前事务，随后重新初始化。真实链路测试已覆盖读像素中途复位。 |
| memory共同请求 | reset_request由外部Reset_n或PLL失锁触发；不依赖memory自身LED，避免初始化反馈死锁。 |
| memory的50 MHz侧 | sys_reset_n经过SYS_CLK两级释放；复位源侧CDC、完成同步和初始化状态同步。 |
| memory的125 MHz侧 | mem_reset_n经过Clk两级释放；复位目标侧CDC、writer全部有效状态、帧计数/完成、刷新调度。 |
| 厂商SDRAM控制器 | Rst为mem_reset_n的反相，高有效；复位后重新执行初始化。 |
| 异步FIFO | 单一Reset_n端口保留，接共同请求；内部wr_reset_n/rd_reset_n各自两级释放，指针、Gray同步、标志及读有效按所在域复位。 |
| PLL | 继续供钟，配置和模块代码不改；外部复位不重启PLL。 |
| display / 同步FIFO | 本地display为空模块；同步FIFO不在当前memory实例中，本轮未改。 |

异步断言不依赖时钟继续运行。某一域时钟停止时，该域保持复位，恢复后才按自己的时钟释放。两侧共同进入复位，不支持随意只清FIFO/描述CDC的一侧。

## 本轮修改的文件

1. `rtl/memory/memory_top.v`：增加共同请求及50/125 MHz两级释放；将FIFO、CDC、writer、refresh和IP接到对应复位。把mem_reset_n和Sdr_init_done一起同步到50 MHz，作为就绪条件。复位/重新初始化期间pixel_ready、LED和完成保持为0；FIFO写使能使用实际valid/ready握手，描述也在重新就绪之前被阻止。
2. `rtl/memory/async_fifo.v`：增加读写两侧的复位释放链，其他数据通路、Gray算法和端口保留。未释放时full=1、empty=1，明确表示暂不能写/读；避免接口虚假接受但内部尚在复位。
3. `tb/memory/async_fifo_tb.v`：仅在复位解除后等待full释放，再发送原有11/22/33/44四字，匹配新的复位忙语义。

writer、frame_desc_cdc、刷新模块、storage、PLL和加密IP源码均未修改。本轮也没有修改写状态机、地址公式或帧完成算法。

复位清除的是控制状态、FIFO指针/有效性和帧归属；不清除FIFO存储阵列或SDRAM物理内容。被中途打断的帧应丢弃，重新初始化后从新帧开始。

## 验证结果

共12组检查全部通过，生产源码在测试期间保持不变。

| 组别 | 覆盖与结果 |
| --- | --- |
| memory_reset | 实际memory/FIFO/CDC/writer/refresh，PLL/IP替身；PLL一直锁定，8次外部复位覆盖初始化、FIFO非空、3字预取、WRITE、下游排空、done保持及两个时钟域分别停钟。7次新帧重载、56字地址/数据正确，无旧数据。 |
| 6组FIFO矩阵 | 实际异步FIFO，8/32/56位、深度4/16、正反及非整数/相同时钟比；满空、背压、回绕和非空复位。每组两轮各4096条目，共49152条目检查通过。测试先等待复位忙结束再做容量测试。 |
| existing_async_fifo_tb | 原工程FIFO测试加独立监视器，11/22/33/44四字全部正确。 |
| real_hierarchy | 当前完整16条TD清单及真实厂商原语，编译/零时刻加载通过。 |
| real_ip_external_reset | 实际memory/FIFO/CDC/writer及加密SDRAM IP，受控时钟、PLL lock保持1；提交旧帧第一字时外部复位，所有任务状态清除；IP初始化共出现两次。重新加载不同基址/数据的8字帧正确完成，未混入旧字。 |
| completion_regression | 前一轮真实IP完成回归继续通过：同高度正/反行序两帧、16字，完成仍在下游busy解除后32ns返回。 |
| system_external_reset | 实际系统顶层+实际storage+实际memory/FIFO/CDC/writer，SPI卡模型与PLL/IP替身；4×2图像接收2像素后外部复位，检查storage和memory共同清状态；复位期间改颜色及基址，随后重读8像素，应用地址512+n、数据0x00660000+n全部正确，源完成、memory完成及ready恢复。 |

快层和系统层中的PLL/IP为测试替身，用于制造停钟、在途事务和短初始化场景；真实IP层使用测试台控制50/125 MHz及180度移相和lock，绕过PLL模型的启动。未改工程PLL，没有验证板级时序或SDRAM物理内容/读回。真实厂商层仍保留两项加密IP无尺寸常量和一项PLL模型端口位宽告警，其他测试无告警。

## 保留的边界与后续

- 本轮完整处理的是外部Reset_n请求。单独PLL失锁也会清memory，但当前顶层/storage没有自动取消旧半帧；整机失锁自动重播尚未实现，应由上层重新发起完整帧或执行外部复位，不能将memory单独复位解释为失锁自动恢复已验收。
- 尾包、metadata后abort恢复、正式180度读采样与HDMI读侧继续独立处理。
- 下一步可以使用四字对齐的小图，进一步验收实际SDRAM行为模型中的整帧存储内容；本轮已验证真实storage到真实memory的应用写入重启，但厂商IP时序与storage整链路分别在不同夹具中覆盖。

完整命令、测试范围、源码哈希和标记见 `C:/Users/31640/Documents/ChatGPT/FFF/memory_reset_integration_20261028/verification_results.json`；源码快照在snapshot，修改前备份在before，重跑入口为verify_reset.py。
