# storage / memory 接口约定（2026-10-26）

本轮按用户选择，采用 **memory 根据帧信息自行计算地址** 的方案。storage 保留现有端口和全部逻辑；memory 只改模块端口声明与说明，`localparam ADDR_WIDTH = 4;` 起至文件结束的内容与本轮修改前逐字节一致。系统顶层补全接线、请求配置锁存、复位释放和初始化状态同步。新增 memory 端口的功能由用户继续实现。

## storage 顶层检查

`rtl/storage/storage_pipeline.v` 现有接口满足需要，本轮没有增删端口。

| 接口 | 本方案的用途 |
| --- | --- |
| `pixel_valid / pixel_rgb888[23:0] / pixel_ready` | 50 MHz 像素流；valid 和 ready 同拍为 1 才完成一次传输 |
| `meta_valid / width[15:0] / height[15:0] / top_down` | 帧描述；meta_valid 为单拍，尺寸、方向必须同时采样 |
| `done` | 文件读取和图像解码成功结束，并且最后一个像素已交给下游；不表示 SDRAM 排空 |
| `error / error_code` | 失败与诊断；error 是保持至下次启动的电平，不是单拍 |
| `start / file_index / ready / busy` | 选择并启动文件读取，以及任务状态 |
| `pixel_addr / pixel_x / pixel_y / pixel_sof / pixel_eol / pixel_eof` | 保留兼容，但本次系统顶层不使用；memory 根据尺寸和方向维护自己的计数 |
| `sd_cs_n / sd_sck / sd_mosi / sd_miso` | 顶层透传到 SD 卡 SPI 引脚 |

`top_down=1` 时文件第一行就是图像最上面一行；`top_down=0` 时文件第一行是图像最下面一行。`pixel_addr` 是像素序号，当前方案不把它传入 memory。

## memory 顶层端口变更

| 端口 | 变化 | 约定 |
| --- | --- | --- |
| `SYS_CLK` | 保留 | 当前工程为 50 MHz；像素和帧接口均属于这个时钟域 |
| `Reset_n` | 新增输入 | 外部低有效复位；本轮只接到端口，内部原有 lock 复位逻辑未改 |
| `pixel_valid / pixel_data[23:0] / pixel_ready` | 保留，规范声明 | 一个像素对应一个 32 位存储字，当前内部填充为 `00_RR_GG_BB` |
| `frame_id` | 删除 | 当前没有已定义的帧编号/缓冲区选择规则，用明确的帧基址替代 |
| `frame_base_addr[20:0]` | 新增输入 | 图像左上角在 SDRAM 中的 **32 位字地址**，不是字节地址，也不是每拍输入的像素地址 |
| `frame_start` | 保留，明确含义 | 与帧基址、宽、高、方向同时有效的单拍；顶层来自 storage.meta_valid |
| `frame_width[15:0] / frame_height[15:0]` | 新增输入 | 图像像素宽、高；由 storage 的 BMP 元信息提供 |
| `frame_top_down` | 新增输入 | 文件像素行的输入顺序；由 storage.top_down 提供 |
| `frame_end` | 保留，明确含义 | 源端成功结束单拍；来自 storage.done，不能直接当作写完成 |
| `frame_abort` | 新增输入 | 源端失败取消电平；来自 storage.error，失败帧不得交付显示 |
| `frame_write_done` | 新增输出，仅预留 | 用户完成实现后：全部有效像素真正写完时，在 SYS_CLK 域给出一个完成脉冲；当前没有驱动 |
| `LED` | 保留 | 现有 `PLL lock && Sdr_init_done` 就绪指示，不代表读回校验成功 |

原来的三个帧端口 `frame_start / frame_end / frame_id` 因此调整为：**开始时提供一份帧描述，结束时报告成功或取消，memory 单独报告写入完成**。像素通道原有的三个信号不需要合并或增加逐像素地址。

地址关系是 `帧基址 + 图像中的行号 × 宽度 + 列号`，这里的行号以图像左上角为原点。底朝上的 BMP 输入第一行对应 `height-1` 行，顶朝下则对应第 0 行。地址计算在 memory 内完成，不要求 storage 每拍再送地址。21 位字地址覆盖 2^21 个 32 位字，即 8 MiB；计算尺寸和边界时需要足够位宽，检查整帧不越界。本轮没有实现这些运算或检查。

当前写控制器按四字处理。后续帧基址需要考虑四字对齐；底朝上的逐行地址切换还必须考虑行边界，宽度不是 4 的倍数时，不能简单让四字组跨到下一条反向行。现有 391 像素只输出 388 字、尾部 3 字等待的问题仍未处理。建议先用宽度可被 4 整除的单帧完成验证，再设计尾包。

## 系统顶层已补全的接线

`rtl/top/hdmi_player_top.v` 现在提供 SYS_CLK、外部复位、读取启动、文件索引、帧基址、SD SPI 和状态端口。

1. 外部 Reset_n 异步拉低、在 SYS_CLK 中两拍释放，接到 storage 和新 memory 复位端口。memory 的内部复位仍由用户接入。
2. 现有 memory.LED 表示 PLL/SDRAM 初始化完成；顶层将其两拍同步到 SYS_CLK 后才允许启动和传像素。
3. 当 `start && load_ready` 同拍为 1，storage 接受请求，顶层锁存本次 frame_base_addr。文件索引由 storage 在启动时采样。请求配置随后变化不会改变本次已锁存的帧基址。
4. storage.meta_valid、width、height、top_down 接到 memory 的帧开始和描述端口；storage.done/error 接到 frame_end/frame_abort。
5. storage 的 RGB888 接到 memory.pixel_data；memory.pixel_ready 返回 storage。顶层仅把通过初始化门控且握手成功的像素变为 memory.pixel_valid，适配当前 FIFO 以 pixel_valid 为 wr_en 的实现。
6. load_done、load_error、load_error_code、load_busy、card_initialized 向外提供 storage 状态；memory_frame_write_done 单独透传新 memory 完成端口。

**启动约定：** `start` 是 SYS_CLK 域的单拍请求，配置信号在接受请求的上升沿稳定。`load_ready` 当前仅表示 storage 空闲且 memory 已初始化，不表示上一帧在 SDRAM 中已经排空。当前阶段仅按单帧集成使用；后续控制器启动下一帧或复用缓冲区之前，必须先等 memory_frame_write_done（由用户实现）。错误帧的排空、丢弃和恢复也需在 memory 中实现，不能把 storage.error 清零直接等同于 memory 已恢复。

TD 工程增加 storage 的四个源文件和 hdmi_player_top，顶层切换为 hdmi_player_top，共 15 个 Verilog 文件条目（包含全局头文件）。本轮没有添加板级管脚约束、按键启动控制器或 HDMI 显示逻辑，也没有执行布局布线或板级时序签核。

## 留给用户实现的内容

所有新 memory 输入目前都只存在于接口中，尚未被内部消费；frame_write_done 当前无驱动，仿真可能呈 Z。原有写控制器仍从自身复位地址开始连续累加，不会使用 frame_base_addr。外部 Reset_n 也尚不能重置其内部 FIFO/写控制器。**接线完成不等于帧写入功能已完成。**

用户下一步先在 SYS_CLK 域按 frame_start 锁存帧描述并维护帧状态，再设计描述/控制与 125 MHz 写侧之间的跨时钟传递，保证描述先于所属像素生效。之后处理行地址、四字组、尾包、取消、外部复位和写入排空完成条件。不要把 SYS_CLK 的单拍帧事件直接当成 125 MHz 域的单拍使用。

## 验证结果与边界

- 真实工程全部源文件及厂商 PLL/SDRAM 原语：ModelSim 编译与零时刻层次加载通过，0 错误。仍有参考加密 IP 的两项无尺寸常量告警，以及 PLL 模型 load_reg 端口位宽告警；本轮未修改厂商文件。
- 实际 hdmi_player_top + 实际 storage 四模块 + SPI 卡模型 + **仅供测试的 memory 接收模型**：3 个场景通过。两次成功读取各 391 像素，累计检查 782 像素；错误 BMP 经顶层返回 0x20/abort，随后不重置卡恢复成功。
- 接线测试覆盖：复位与过早启动门控、基址锁存、图像元信息、像素顺序、1000 拍长背压和随机背压、2314 次待传像素保持检查、源完成与模型延迟写完成分开。
- memory 模型只用于验证接口接线；以上结果 **不验证真实 SDRAM 的帧地址计算、行方向处理、尾包、帧排空或新外部复位逻辑**。真实 memory 对这些端口尚无实现。
- 修改前后比对：memory 模块体逐字节相同，storage 四模块、FIFO、PLL、写控制器、刷新控制器和加密 IP 与本轮开始时完全一致。本轮没有提交 Git。

实验源快照、修改前备份、命令与日志位于 `C:/Users/31640/Documents/ChatGPT/FFF/storage_memory_interface_20261026/`，入口为 `run_checks.py`，汇总为 `results.json`。
