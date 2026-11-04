# SD 卡 UTF-8 中文字幕

> 2026-11-04 更新：当前固件按图片读取同名 TXT，不再统一读取 CAPTION.TXT。请按 [同名 TXT 使用说明](PAIRED_CAPTIONS.md) 准备 SD 卡；以下 CAPTION.TXT 交付说明记录的是早期版本。


2026-11-04版本记录：本功能源码、约束、测试与说明已随memory分支版本保存；下文“未提交/未推送”为实施结束时的历史状态，当前以项目进度最新版本记录与Git为准。

后续音画同步版：图片现会自动播放同名WAV，SW3已停用，两路静音改为暂停且左上音频时间停止推进；TXT字幕读取/移动/滚动保持。当前资源和新bit以[音画同步](AV_SYNC.md)与最新项目进度为准，以下验收数字属于前一版。

2026-11-03。实施前已将 FAT 扇区缓存优化保存到本地 `memory`，提交 `9604f4804a49587579636181a0140ea1bfbd3e65`（Use block RAM for FAT sector caches）。本次字幕改动在该提交之后，未自动推送 GitHub。

## 使用

1. 将交付包 `sd_card` 内的 **CAPTION.TXT 和 FONT16.BIN** 放到 FAT32 SD 卡根目录，和原有 BMP/WAV 共存。不要改字库文件名，也不要把 ZIP 直接放到卡上。
2. 用记事本编辑 CAPTION.TXT，保存为 **UTF-8**，带/不带 BOM 均可。支持中文、英文、数字和标点；不支持 ANSI/GBK 或 UTF-16 文件。
3. 每次加载图片前重新读同一个 CAPTION.TXT。修改文字不需要重新编译 FPGA。更换卡或字库时先复位/重新上电，不支持带电换卡。
4. SW2 仍控制底部字幕显示，SW1 仍控制左上角音频播放时间。移动按键和接线完全沿用当前 main 布局：J1-8/J13 左移、J1-9/K12 右移，外接低有效按键接 GND；短按松手移动一个字位，长按约 0.5 秒持续滚动，同时按下归位。首次字幕超过 38 字时自动左滚，后续切图保留当前滚动方向、暂停状态与位置。

字幕仍在原图片信息字幕区域：640×480 画面 x=16..623、y=452..467，16×16 白字、阴影、暗底。每次最多缓存 **64 个 Unicode 字符**，读取 TXT 前 512 字节；换行/制表转为空格，CRLF 合成一个空格，其他 C0 控制字符忽略。超过64字的内容截断，不是无限长文本阅读器。滚动重复间隔保留四个空字位。

CAPTION.TXT 不存在、为空或字库读取失败时，自动恢复原来的图片序号、8.3 文件名和尺寸字幕，不阻止 BMP/WAV 播放。无效 UTF-8 序列按 U+FFFD 替代。这里只扩展底部文字内容，未改音频计时为现实时间。

## 字库与“任意中文”的范围

字形不再限定为原来固化的少数字。字库采用 GNU Unifont 17.0.03，当前 FONT16.BIN 收录 126641 个上游字形，覆盖基本区及扩展 A 的简繁汉字，以及上游收录的部分扩展区字符；**没有承诺覆盖全部 Unicode 生僻字**。未收录字符显示方框，组合字形、异体选择序列与复杂文字排版未实现。

FONT16.BIN 为固定 Unicode 索引文件，共 `0x110000 × 32 = 35,651,584` 字节（34 MiB）。字符 U+XXXX 在 `codepoint × 32` 字节处占16行，每行一个大端16位字。8像素宽字形居中到16像素格。FPGA只读本段字幕需要的字形，不将整套字库放进 LUT 或 SDRAM 帧缓存。

官方来源：<https://unifoundry.com/unifont/>；上游 HEX：<https://ftp.gnu.org/gnu/unifont/unifont-17.0.03/unifont_all-17.0.03.hex.gz>。转换后的字库选择 SIL OFL 1.1，交付包及 `rtl/display/licenses` 中保留原作者版权和许可证。生成工具为 `rtl/display/tools/build_sd_font.py`，不需要第三方 Python 库：

```powershell
python rtl/display/tools/build_sd_font.py unifont_all-17.0.03.hex.gz --output sd_card
```

源码 HEX SHA-256：`dd9e15729a1450c4f5e7f634ffcade4c84ee3d172291c67d39f1d747ad1be1f6`。

FONT16.BIN SHA-256：`c974db9433a9f13c8c6599fdba12e0bdf4c3fd3e4082f835ae3d002d7d42bfd0`。

## 实现边界

- `storage/text_caption_loader.v`：UTF-8 1~4字节解码、64码点队列、逐字形读取、完成提交。等待 FAT 接受新任务并清掉上次粘滞错误后才检查结果，避免最后一图查找失败污染循环回第一图的 TXT 读取。
- `storage/fat32_bmp_reader.v`：复用原扇区 BRAM 和 FAT 链逻辑，新增 CAPTION.TXT 精确匹配及 FONT16.BIN 字节范围任务；缓存字体首簇/大小，逐簇寻址，支持碎片文件、跨扇区/簇和流控。普通 BMP 和 WAV 的枚举方式保持；BPB宽加法与校验分成两拍改善真实时序。
- `storage/storage_pipeline.v`：字幕读取与 BMP 顺序共用原图片 FAT 实例，不再增加一个 FAT 实例；音频仍通过原扇区仲裁器共享 SD，字幕加载不会独占整段音频数据传输。
- `display/src/text_glyph_cache.v`：两个64字、16行的 BRAM 银行；SYS 写后台，像素域在完整帧边界交换。请求/确认握手完成后才允许重用另一银行，不在活动视频中换字形。
- `subtitle_overlay.v` 复用原位置/按键/滚动/阴影和逐像素前瞻，音频时间和缺文件时的图片信息继续使用原小 ROM。
- `hdmi_tx_display.v`、`hdmi_player_top.v` 连接内部字幕通路；TD 工程加入两个新 RTL；SDC 只补缓存握手跨域路由限制，以及原有初始化同步首级约束的综合后名称匹配。未改 PLL、SDRAM IP、memory 模块实现、ADC 或按键分配。

全图共用一段字幕，字幕在字形准备好的下一个视频帧边界生效；未实现每图独立 TXT，也不保证字幕发布与图片切换在同一个帧边界。BMP 加载失败仍保留前台图，字幕是全局共享文本。

## 验证与复现

新增 `verification/txt_subtitles_20261103`：10项 UTF-8/边界/旧错误状态测试；11项独立碎片 FAT 范围测试（含 U+10FFFF、跨扇区、跨簇、截短、坏链和流控）；6帧252万时钟像素的独立字幕合成比对、银行原子切换、短按/回绕/归位；真实 SPI 下6次成功图片加载及一次缺图后的恢复；并发整机 TXT/BMP/WAV/HDMI/频谱测试。

```powershell
python verification/txt_subtitles_20261103/run.py --output <绝对输出目录>
python verification/txt_subtitles_20261103/run_system.py --fixtures <上一步输出目录> --output <另一绝对输出目录>
python verification/subtitles_20261103/rebuild_td.py --seed 4 --output <TD绝对输出目录>
python verification/fat_sector_bram_20261103/audit_timing.py --build <TD绝对输出目录>
```

测试默认本机 ModelSim `D:/modelsim2020/win64` 和 TD 6.2.168.116；输出目录放工程外。完整构建显式执行 `fix_hold`，TD 随机布局会影响时序，不能将只通过综合视为通过实现。验证保留原SDRAM读采样/不确定度/Gray路由限制，不降低时钟频率或放宽 memory 内部时序。原有封装SDRAM位置及两条局部时钟警告照常记录；外部SD/HDMI电气时延仍需实际板级验证，不能声称全部I/O签核完成。

整机仿真使用既有应用层 SDRAM 模型，未重跑物理 SDRAM 长回归；本次 memory/IP/PLL 均未修改，但布局后的物理 DQ 输入/输出约束另作时序核查。未上板、未烧写Flash。

最终实测资源、时序和回归结果见本页末尾“最终验收”及 `docs/PROJECT_PROGRESS.md` 最新一节。

## 最终验收（2026-11-03）

最终完整 TD 布局布线/保持修复/bitgen 通过，布局 seed=4。LUT **17055/19600（87.02%）**，对比已保存的 FAT BRAM 版16293增加 **762**，剩 **2545**；寄存器8673/19600，BRAM9K **40/64**（原34），BRAM32K0/16，DSP16/29、PLL2/4不变。资源可以完成当前64字按需缓存方案，不等于还有余量把整套中文字库改为组合ROM。

最终 setup **+0.177ns**，整体 min/hold **+0.023ns**。独立导出 **24971** 项唯一时序检查，无负裕量，包含64项SDRAM DQ输入（最小+0.335ns）、64项DQ输出（最小+1.374ns）及5296项复位恢复/移除检查；既有CDC首级路由例外保持可见，后级正常计时。

最终新增10项解码、11项FAT范围、6帧252万像素时钟的字幕独立参考比对、SPI缺图后恢复及6次图片加载均通过。原有MBR18+SD6、扇区缓存23、字幕4608000个可见像素比对通过。并发整机验证2次图像加载、19294个音频CDC采样、10次WAV循环、33次频谱更新、14964个字幕覆盖像素通过。六图轮播0→1→2→3→4→5→0、手动切换、7次黑场交换、8次图片信息绑定和10300805个转场像素通过。字体独立核对126641字形、2026256行点阵通过。

bit：`FFF/txt_subtitles_20261103/HDMI_Player_TXT_Subtitles_20261103.bit`。

SHA-256：`9875793f5a59165803610e2c21b3da01ad12f73baebd60bbc8bde899bf0a5709`。

交付 ZIP：`FFF/txt_subtitles_20261103/HDMI_Player_TXT_Subtitles_20261103.zip`，含bit、sd_card/CAPTION.TXT、sd_card/FONT16.BIN、字库许可证与使用说明。源码/测试/进度已同步实际工程，TXT实现留在工作区供审阅；未再次提交、未推送、未上板。下一步用包内bit与SD文件验证中文、长按滚动、换图/轮播和音频同时播放。
