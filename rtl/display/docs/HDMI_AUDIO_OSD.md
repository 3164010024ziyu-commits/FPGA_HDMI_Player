# HDMI 音频 + 中文字幕（display 组）

## 1. 结果概述

- `src/enc_file` 中的加密 DVI 模块已全部删除，替换为 `src/enc` 下的明文实现。
- 视频：640x480p60（CEA VIC 1），8-bit RGB；像素时钟 25.175 MHz，5x 串化时钟 125.875 MHz。
- 音频：HDMI 数据岛（data island）传输 LPCM，44.1 kHz / 48 kHz 可选，16-bit 立体声。
- 字幕：两槽并存，16x16 中文字形，1 行最多 15 字；槽 0 为普通字幕（位置可调），槽 1 为时间戳（默认左下角 8,448）。
- 顶层验证工程：`src/hdmi_demo_top.v`（渐变图案 + 1 kHz 正弦测试音 + 示例字幕）。

## 2. 目录

```
src/
  hdmi_demo_top.v       硬件验证顶层（图案/测试音/默认文字）
  hdmi_tx_display.v     display 组件：视频 + 音频 FIFO + OSD + HDMI TX
  hdmi_tx.vhd           HDMI 发送封装（原端口名保留，新增音频/计时接口）
  read_RAM.v            640x480 时序，输出 HDMI_X/Y
  osd_overlay.v         双槽中文字幕叠加
  font_16x16_rom.v      16 x 32Kb BRAM 字形 ROM
  font_bank_XX.dath     字库初始化数据（每块 2048 x 16 bit）
  font_gb2312.hex       字库可读源数据（仿真/检查用）
  audio_fifo.v          音频采样跨时钟域缓冲
  enc/
    tmds_encoder.v      TMDS 视频/控制/TERC4/guard band 编码
    packet_assembler.v  数据岛 9-bit 流 + BCH ECC
    packet_picker.v     音频包/ACR/AVI/Audio InfoFrame 调度
    tmds_serializer.v   10:1 串化（EG_LOGIC_ODDR）
    eg_oddr.v           ODDR 封装（仿真用 SIM_ODDR 行为模型）
    hdmi_tx_core.v      三数据通道 + 时钟通道总装
tools/gen_font_rom.ps1  字库生成脚本
```

## 3. 接口

### 音频（`hdmi_tx_display`）

| 信号 | 方向 | 说明 |
|---|---|---|
| `audio_clk` | in | 音频源时钟域 |
| `audio_sample[31:0]` | in | `{L[15:0], R[15:0]}` 有符号 PCM |
| `audio_valid` | in | 写入一组采样 |
| `audio_ready` | out | 可接收下一组采样（反压） |
| `audio_status[1:0]` | out | `{overflow, underflow}` |
| `audio_pkt` | out | 正在发送 Audio Sample Packet 时为高，可用于活动指示 |

参数：`AUDIO_FS=48000`（或 `44100`）、`HDMI_AUDIO_EN=1/0`、`DVI_MODE=1` 可输出纯 DVI。

### 字幕

| 信号 | 方向 | 说明 |
|---|---|---|
| `osd_slot` | in | 写入目标槽 |
| `osd_char_idx[3:0]` | in | 字符位置 0..14 |
| `osd_char_code[15:0]` | in | GB2312 区位码（高字节=区，低字节=位） |
| `osd_char_we` | in | 写入一个字符 |
| `osd_y[9:0]` | in | 普通字幕左上角 Y（左/右由按键控制） |
| `osd_fg[23:0]` | in | 前景色 |

时间戳槽位置由 `TS_X/TS_Y` 参数设置（默认 8,448），两槽可同时显示，时间戳优先。
普通字幕的 X 初值由 `SUB_X_INIT` 参数给出（默认 200），之后由左右按键移动。

### 按键控制（`hdmi_tx_display`，7 键）

| 位 | 引脚 | 功能 | 类型 | 行为 |
|---|---|---|---|---|
| `key_in[0]` | C1 | VOL+ | 点动，按下=0 | 音量 +1 挡，4 挡封顶 |
| `key_in[1]` | B1 | VOL− | 点动 | 音量 −1 挡，0 挡封底 |
| `key_in[2]` | C8 | MUTE | 乒乓开关，ON=0 | 静音开/关，挡位保留 |
| `key_in[3]` | C7 | SUB ON/OFF | 乒乓开关，ON=0 | 普通字幕开关（`osd_en[0]`） |
| `key_in[4]` | C6 | TS ON/OFF | 乒乓开关，ON=0 | 时间戳开关（`osd_en[1]`），与普通字幕独立 |
| `key_in[5]` | B2 | SUB ← | 点动 | 左移 1 字符（16 px），最小 x=8 |
| `key_in[6]` | A2 | SUB → | 点动 | 右移 1 字符（16 px），最大 x=392 |

复位键 `sys_rst_n` 在 **C5**（低有效，内部上拉）。

- 点动按键：2 级同步 + 每键 ~10 ms 消抖 + 单周期“按下”脉冲，按住不连发。
- 乒乓开关：消抖后直接取电平作为状态（不是边沿），`SWITCH_ON_LOW=1` 表示“ON 位置接地”。
  如果板上开关方向相反，把该参数改为 0。
- `KEY_ACTIVE_LOW=0` 可适配高有效点动按键。

音量 5 挡（0..4）对应 `0 / 64 / 128 / 192 / 255`，线性 `sample * volume / 256`：

- `255` ≈ 0 dB，`192` ≈ -2.5 dB，`128` ≈ -6 dB，`64` ≈ -12 dB，`0` 数字静音。
- MUTE 开关只把输出置 0，不清除挡位，关掉静音后恢复原挡位。

### 音频波形显示（demo 顶层）

`hdmi_demo_top` 在画面右上角 **(512, 8) – (639, 39)** 放了一个 **128 x 32** 的音频波形框：

- 每一列 1 像素宽；**每 `WAVE_ZOOM` 个采样写入一列**，时间轴按该比例压缩；
- 每列从中心行（第 16 行）向采样值画一根竖条，正采样向上、负采样向下；
- 采样在 `sys_clk` 域用 toggle 信箱把 5-bit 幅值送到像素域，抽取后写入 128 深循环缓冲；
- **上升过零触发**：抽取后的采样由负变非负时，把“以该过零点结尾”的最近 128 列
  快照到显示缓冲，波形相位固定（右端总在过零点），不再每帧跳动；
- 无过零（静音或直流）时不刷新，画面保持一条中心绿线；
- 颜色：柱体亮绿 `00FF00`，背景黑。

压缩比由 **`WAVE_ZOOM`** 参数选择（1、2、4、8、16，默认 4），改 `hdmi_demo_top`
的参数后重新综合即可：

| `WAVE_ZOOM` | 一屏采样数 | 时间窗 (48 kHz) | 1 kHz 周期数 |
|---|---|---|---|
| 1 | 128 | 2.7 ms | 2.7 |
| 2 | 256 | 5.3 ms | 5.3 |
| **4（默认）** | **512** | **10.7 ms** | **10.7** |
| 8 | 1024 | 21.3 ms | 21.3 |
| 16 | 2048 | 42.7 ms | 42.7 |

仿真（`tb/tb_wave.v`，ASCII 打印，`WAVE_ZOOM=4`）中 128 列正好 10.7 个周期，
相邻周期 12 列，右端收在过零点。

> 若希望柱子之间有空隙（更像离散柱状图），把列步进改为 2 像素即可，
> 代价是同样宽度内只显示 64 列。
> 若需要运行中切换压缩比，需要一个按键/拨码开关引脚（当前 7 个按键已占用），
> 给出引脚后可以加。

## 4. 字库与容量说明

器件 EG4S20BG256 可用存储为 64 x 9Kb + 16 x 32Kb BRAM。
当前字库使用 16 个 `EG_LOGIC_BRAM`（2048 x 16 bit，`IMPLEMENT="32K"`），TD 打包后占用 8/16 个 32Kb 块，提供 **2000 个 16x16 字形**：

- index 0：空白（未实现/非法码）
- index 1..94：GB2312 区 3（全角 ASCII/标点）
- index 95..1999：GB2312 一级字前 1905 字

全量 3855 个 16x16 字形需要约 120 个 9Kb 块，超出器件容量；若要收全字库，需要外挂 SDRAM 或进一步压缩/分 bank。重新生成：

```
powershell -ExecutionPolicy Bypass -File tools/gen_font_rom.ps1 `
  -FontName SimHei -PixelSize 15 -MaxGlyphs 2000
```

脚本同时输出 `font_gb2312.hex` 与 16 个 `font_bank_XX.dath`。

## 5. 验证记录

- TMDS 编码器与 hdl-util/hdmi 参考实现（MIT/Apache-2.0）对 256 个像素值、控制码、TERC4、guard band 逐位比对通过。
- 数据岛包组装器与参考实现 6 组随机包逐拍比对通过。
- 串化器：每像素 10 bit、bit0 先出，装载点距像素沿约 16 ns。
- 核心级仿真：每行 640 视频 + 128 数据岛 + 4 保护带 + 26/27 控制；音频 200 包/帧（48 kHz）、ACR 约 16.5 包/帧、AVI/AI 各 1 帧。
- OSD 仿真：字符映射、位置、预取时序通过。
- TD 6.2 综合/布局/布线/bitgen 通过：setup WNS +5.883 ns，hold +0.129 ns，LUT 1655/19600，BRAM32K 8/16。

## 6. 已知限制

- 字幕字库为 2000 字，非 GB2312 全量。
- 按键控制已实现（音量 5 挡 + 静音、双槽字幕开关、普通字幕左右移动）；左右移动步进固定为
  1 个字符（16 像素），不支持按住连发；时间戳槽位置仍由 `TS_X/TS_Y` 固定。
- `DVI_MODE=1` 时无数据岛，音频自然不可用（兼容老显示器）。

## 7. 无声问题定位与修复（2026-10-22）

### 现象
- 640x480p60 视频、OSD 正常，但 HDMI 无声。

### 已核对（均正常）
- 用 `tb/tb_audio_pipe.v` 跑 `audio_fifo + hdmi_tx_core`：48 kHz 音源下每帧约 205 个
  Audio Sample Packet、约 17 个 ACR 包，包内采样值与写入序列一致。
- 数据岛 9-bit 流、BCH ECC、TERC4、guard band、前导码位置均与 hdl-util/hdmi 参考实现逐位一致。
- ASP 头（0x02 / 0x0F / 块起始位）、AVI（0x0D0282，PB0=0xE6）、
  Audio InfoFrame（0x0A0184，PB0=0x70）、SPD（0x190183，PB0=0xFB）内容正确。

### 已修复缺陷
1. **IEC 60958 通道状态块长度错误**（`packet_picker.v`）
   - `frame_counter` 原来按 8 bit 自然回绕（0..255），但通道状态块固定为 **192** 帧。
   - 结果：上电约 4 ms 后 `CS_L[fc]`/`CS_R[fc]` 索引越界（192..255），
     块起始标志 B 变成每 256 帧一次，接收端无法正确解析采样率/字长等通道状态位。
   - 修复：`frame_counter` 在 188 → 0 回绕。仿真验证块起始间隔由 64 个音频包变为 48 个
     （48 x 4 = 192 帧），且不再出现越界索引。
2. **左右声道写反**（`packet_picker.v`）
   - `audio_sample = {L, R}`，但子包 bits[23:0] 放的是 R、bits[47:24] 放的是 L。
   - 修复：`l0..l3` 取 `[31:16]`，`r0..r3` 取 `[15:0]`，奇偶校验同步按新定义计算。
     演示音左右相同，所以此前听不出差别，但接真实立体声源会左右颠倒。
3. **ACR CTS 抖动**（`packet_picker.v`）
   - 原 CTS 在“音频包发送时刻”测量，受数据岛 32 像素槽位量化影响，
     实测在 24799..25599 之间跳变（±1.6%），会让依赖 ACR 恢复音频时钟的接收端抖动/失锁。
   - 修复：对连续 8 个 ACR 周期的测量值求和后右移 3 位（平均），
     仿真中稳定在 24999..25001（首次上电那一包仍为原始测量值，属正常启动瞬态）。

4. **测试音频率错误**（`hdmi_demo_top.v`）
   - `localparam integer PHASE_INC = (67_108_864 * 1000) / AUDIO_FS;` 的乘法在 32 位
     整数里溢出（67,108,864,000 → 负数），实际得到 -33554，相位步进只有设计值的 2.4%，
     测试音变成约 24 Hz 的近乎直流信号——即使音频协议修好也基本听不到。
   - 修复：改为 64 位常量 `(64'd67_108_864 * 64'd1000) / AUDIO_FS`（=1,398,101），
     仿真中相邻采样按 48 采样/周期递增，恢复 1 kHz。

5. **OSD 字符写入的跨时钟竞争（“家”丢失）**（`hdmi_demo_top.v`）
   - 初始化字幕时 `osd_char_we` 与 `char_idx/char_code` 在同一个 `sys_clk` 沿变化，
     像素域（25 MHz）异步采样时可能采到“新 strobe + 旧数据”或反之，
     于是某个字符被写成 0（空白）——现象就是“大 好”，中间字丢失。
   - 修复：把 `osd_char_we` 推迟到数据稳定 2 个 `sys_clk` 之后（`init_div` 2..5 有效），
     数据至少提前 40 ns 稳定，写选通仍保持 80 ns。
   - 用真实字库数据对 `osd_overlay` 做的仿真（`tb/tb_osd.v` + `tb/font_rom_model.v`）确认
     `大/家/好` 三个字形都能正确渲染，字体 index 1272 的数据也正常（`7FFC/4004/…`）。

6. **波形显示改为过零触发**（`hdmi_demo_top.v`）
   - 原来每帧快照一次，1 kHz 信号相对 59.5 Hz 帧率会使波形相位每帧跳变，看起来“速度太快”。
   - 改为上升过零触发：每次负→正过零时快照“以过零点结尾”的 64 个采样，
     波形相位固定、视觉上稳定（示波器 auto trigger）。

### 仍建议后续处理（未改动，避免影响已验证的视频链路）
- **像素时钟未过全局缓冲**：布局布线报 `PHY-5079`，`clk_pixel`（约 400 扇出）
  有 2 段走本地布线。建议给 PLL 的 C1 输出加 `EG_LOGIC_BUFG` 后重新布局布线。
- **缺少 SDC**：`SDCList` 为空，STA 只按 50 MHz 单时钟分析，125 MHz 串化域未被约束；
  建议补 `create_clock`/`create_generated_clock`（50M、25M、125M）与异步时钟组。
- 文档写的 25.175 MHz / 125.875 MHz 与实际 PLL IP（25.000 / 125.000 MHz）不一致；
  当前 25.000 MHz 对应 59.52 Hz 刷新率，如需严格 59.94 Hz 需重新生成 PLL。

### 重建结果
- 音频修复版：setup WNS +6.278 ns、hold WNS +0.136 ns，LUT 1722/19600，BRAM32K 8/16，DSP 1；
  码流 `HDMI_display_audiofix.bit`。
- 加上按键控制的版本（包含上面的音频修复）：setup WNS **+6.416 ns**、hold WNS +0.259 ns，
  LUT 1997/19600、寄存器 939；码流 **`HDMI_display_keys.bit`**（工程根目录），可直接下载。
- 波形显示版（包含音频修复、按键、1 kHz 修正、64x32 波形）：
  setup WNS **+4.520 ns**、hold WNS +0.242 ns，LUT 3259/19600、寄存器 1578。
- 波形触发 + OSD 写时序修复版：setup WNS **+4.797 ns**、hold WNS +0.237 ns，
  LUT 3241/19600、寄存器 1579。
- 128x32 时间轴压缩版（`WAVE_ZOOM=4`）：setup WNS **+4.475 ns**、hold WNS +0.237 ns，
  LUT 4583/19600、寄存器 2256；码流 **`HDMI_display_wave.bit`**（工程根目录，覆盖旧版）。
- 原 `HDMI_display_Runs/best_result/HDMI_display.bit` 未被覆盖，可随时回退。


