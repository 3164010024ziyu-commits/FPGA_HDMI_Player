# HX4S20C 资料核对与首次上板

日期：2026-10-24。资料目录：`D:/大三上/FPGA/HX4S20_Contest_202606/`。

## 工具与资料

包内已经有 `1_安路开发工具和常用软件/安路开发软件TD_6.2.1版本.zip`，约 1.95 GB。同目录版本说明要求参考例程使用 TD 6.2.1，本项目以它为兼容目标。已确认用户安装在 `D:/fpga`，版本 V6.2.168116。更新授权后，TD 已完成综合、布局布线、内部时序检查和候选码流生成，见 [TD 验证记录](td_validation.md)。

ModelSim `D:/multisim/win64` 已能运行全部测试，不需要另装仿真器。

参考例程在 `7_lab_ex_2026_nosoft/全国大学生嵌入式芯片与系统设计竞赛'2026选题指南_康芯.zip`，包含 `lab_ex4_tf`、`lab_ex5_i2s`。已按需解出源码与约束供检查，没有执行里面的安装、卡同步、扇区清理或下载操作。资料中的操作说明是参考内容，不能代替用户授权。

## 已核对的板级连接

来源：`HX4S20开发板手册-HDL版2410.pdf` 物理第 6、19、20、22 页，原理图 `2_FPGA.pdf`、`6_EX_DEVICE.pdf`，以及参考 `lab_ex4_tf` 的 `pin.adc`。

| 验证顶层信号 | 管脚 | 含义 |
| --- | --- | --- |
| clk | R7 | 板载 50 MHz |
| reset_key_n | A2 | KEY1，按下为低 |
| sd_cs_n | A12 | SD DAT3/CS |
| sd_sck | A14 | SD CLK |
| sd_mosi | A13 | SD CMD/DI |
| sd_miso | B14 | SD DAT0/DO |
| led[0] | A4 | LED1：初始化成功 |
| led[1] | A3 | LED2：读图 busy |
| led[2] | C10 | LED3：成功完成并通过像素计数检查 |
| led[3] | B12 | LED4：失败 |

LED 为高电平点亮。TF 供电 3.3 V，CMD/DAT 等网络有 RN18/RN19 10 kΩ 上拉；SPI 不用的 DAT1=B15、DAT2=A11 不主动驱动。卡座 NC 不是独立卡检测信号。

**C5 是 SWKEY4 开关，不是 KEY1。** 队友显示分支用 C5 控制复位电平，本验证工程用 A2 按键，切换工程后注意实际操作。

## 参考例程与本组实现的差异

参考文档提到 FAT32 卡，但实际 `SD/bmp_read.v` 是按物理扇区检查 BM 和固定尺寸，记录起始扇区，再用 `scan_sector+ceil(file_len/512)` 跳转，没有 BPB、目录项和 FAT 簇链解析。按连续扇区读取不能一般性支持碎片文件，还可能找到删除文件残留。我们的 FAT32 文件读取应继续保留；普通复制 BMP 即可，不依赖参考脚本清理旧图物理扇区。

官方 SDRAM 和 HDMI 文件中存在 `.enc.v` 加密核；不解密、不作为本组自主 RTL，也不放入交付包。

## 与 memory/display 联调必须确认

1. **字节布局：**参考 `sd_card_bmp.v` 输出 `{R,G,B,8'h00}`，即 `0xRRGGBB00`；显示读取 `[31:8]`。复用它时应接 `{pixel_rgb888,8'h00}`，不能接 `0x00RRGGBB`。通用文档中 XRGB8888 只是容量预算格式。
2. **地址单位：**例程 21 位地址以 32 位字为单位，一个像素一字；640×480 双缓冲字基址为 0、307200，对应字节基址 0、1228800。
3. **上下方向：**例程 `WRITE_V_FLIP=1` 默认翻转输入行；我们的 `pixel_addr=y*width+x` 已是左上原点目标地址。新地址感知写入器不要再次翻转。若沿用不收逐像素地址的顺序写入器，需按正/负高度处理翻转，或限制首版格式，不能直接忽略 pixel_addr。
4. **背压：**例程 `frame_read_write` 写 FIFO 的 full_flag 未反馈给生产者。接入前需输出满标志或可靠容量信用给 pixel_ready；不能假设 SD 永远比 SDRAM 服务速度慢。
5. **事务：**write_req 保持到 write_req_ack，并避开 FIFO 清空窗口；storage 成功、SDRAM write_finish 安全同步、显示消隐边界三个条件会合后才提交新帧。失败时放弃后台帧、保留旧图。
6. **时钟：**官方 sys_pll 产生 100 MHz SD 域、125 MHz SDRAM 域及相移时钟；本验证顶层用板载 50 MHz。整机改用 100 MHz 时设置 CLK_HZ=100000000，不能套用 50 MHz 分频常量。

| HDMI 信号 | HDMI_A：队友 dispay | HDMI_B：官方 lab_ex4_tf |
| --- | --- | --- |
| CLK_P | K1 | C3 |
| D0_P | F5 | G5 |
| D1_P | E3 | F1 |
| D2_P | B3 | E1 |

两组引脚都是实际连接，但物理插口不同。本次独立验证不驱动 HDMI。

参考 SDC 将同时工作的、同一 PLL 派生的 video_clk 和 hdmi_5x_clk 设置为 exclusive，不能不经分析地照搬；两者有串化数据关系，切断分析可能掩盖问题。新 SDC 只创建 50 MHz 主时钟，是起始约束，不是完整签核；MISO 返回及 MOSI/SCK/CS 外部时序还需按器件和布线分析，不以 blanket false_path 隐藏这些路径。

## 新增工程与测试行为

打开 `project/td/Storage_Bringup.al`，顶层 `hx4s20c_storage_bringup`，器件 EG4S20BG256。六个自有 RTL、ADC、SDC 共八个引用路径已检查。TD 已完成综合、布局布线和候选码流生成，50 MHz 内部 setup WNS +2.200 ns、hold WNS +0.030 ns；外部 SD 时序和实际板卡尚未验证。

验证顶层同步释放按键复位，等待卡初始化，然后自动读根目录第 0 个 BMP。像素全部消费，记录 pixel_count、expected_pixels、rgb_sum、load_cycles、debug_error_code。RGB 和为逐像素 `0xRRGGBB` 的 32 位模加，只辅助对比，不是防碰撞校验。计数错误码 F0，其他沿用 storage 错误码；当前码流没有 ChipWatcher 采集配置，keep 不等于已能在线采样。load_cycles 只统计 busy，不含初始化。

这个顶层不写卡、不访问 SDRAM、不显示图片。默认上限 640×480，初始读速参数为 12.5 MHz，先验证存储，再接显示。成功 LED 不证明图像颜色、方向或显示链正确。

## 你下一步需要做什么

1. TD 6.2.1 已安装在 D:/fpga，无需重装；授权已生效，确认 USB-JTAG 驱动与下载器连接即可。ModelSim 已可用。
2. 打开新 `.al`，检查器件、顶层、文件引用，先综合保存资源和警告，再布局布线。
3. 准备有备份、已格式化为 FAT32 的卡；根目录普通复制一张真正的 640×480、24 位非压缩 BMP，不能只改 JPG/PNG 后缀。
4. 插卡、下载新生成的验证码流，按住 KEY1=A2 后释放，确定复位再启动。简化顶层不承诺免按键可靠 POR。
5. 预期最终 LED1、LED3 亮，LED2、LED4 灭。失败时先记录四个 LED 状态；如需内部错误码，再添加 ChipWatcher 配置重新构建。之后接队友 SDRAM/HDMI。

本轮没有连接实际板卡或下载器，上述是待执行流程。

新增 `hx4s20c_storage_bringup_tb.sv` 在卡模型上检查四个场景：自动成功、CRC 错误、BMP 签名错误、复位后恢复。成功核对 391 像素和独立计算的 RGB 和 `E091921D`。完整回归现在为五组、92 个场景；行为仿真不验证物理电气时序。
