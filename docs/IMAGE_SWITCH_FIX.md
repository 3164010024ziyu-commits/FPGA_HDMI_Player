# 多图切换与旧末图上限修复

日期：2026-11-02。基于 memory `2f6b342`。用户反馈在队友的SD卡E盘根目录放多张图片，按下一张却出现 A→B→A；卡与硬件不在当前电脑，尚未读取实际E盘、确认文件格式或复测硬件。本记录区分已证实的代码缺陷与尚未确认的实板原因。

## 发现及修复

当前双帧缓存允许依次加载任意编号图片。未修改的原版本使用六张有效BMP，已通过完整GPIO→导航→SD SPI→FAT32→Memory应用模型→HDMI仿真：`0→1→2→3→4→5→0→5→0`。因此并不存在固定“最多两张”的正常设计限制。

但原导航有一个可稳定复现同样循环的缺陷：

1. 第一次访问编号2时，Storage若报目录结束 `0x36`，导航记录 `last_known=1,last_index=1`。
2. 之后即使Storage当前能枚举到编号2及后续图片，导航仍把编号1当作永久末图。
3. 在编号1再次按下一张时，直接请求编号0，根本不再请求编号2；从第一张按上一张也沿用旧末图。

这一条件在导航单测及实际板级/SD SPI/双帧缓存/HDMI完整仿真中均已复现：目录起初可见两张，后来恢复六张，旧版仍为 `0→1→0`，断言“期望编号2、实际编号0”失败。测试模拟的是目录可见条目变化，不模拟物理拔插，也不能证明队友的卡发生过相同条件。

**本轮只修改 `rtl/top/image_navigation_ctrl.v` 的导航实现：**

- 移除 `last_known/last_index` 的永久缓存。
- 下一张始终实际请求 `current_index+1`；本次查询确实到目录末尾，才回到编号0。16位索引到65535时仍正常回零。
- 从第一张按上一张，每次都让Storage重新查询当前末图。
- 原按键排队、成功后更新当前编号、失败保留前台帧、正常越界不亮LED4等规则保留。

每次跨首尾会多一次实际目录查询，是有意的正确性取舍；不增加SDRAM帧缓存。Storage/FAT实现、Memory、PLL、SDRAM IP、Display及音频逻辑未修改。原导航测试去掉了对已删除缓存寄存器的依赖，并增加独立多图回归。

## 验证结果

| 项目 | 修复前 | 修复后 |
| --- | --- | --- |
| 六张有效图的完整系统导航 | 通过 | 通过：9次加载、1152源像素、2457600显示像素 |
| 曾观察两张后目录可见六张 | 错误回零，不能到编号2 | 通过：11次加载、1408源像素、3072000显示像素 |
| 目录从六张缩为两张，再从两张增为六张 | 缓存可能指向不存在编号/限制旧范围 | 导航单测通过，两方向均使用当前查询结果 |
| GPIO消抖、忙时排队、循环、单图/空目录、坏图恢复 | 原测试 | 本轮通过 |
| 末图FAT 28场景、末图SPI 6场景、原系统集成 | 原测试 | 本轮通过 |
| WAV/SPI→HDMI、静音、并发图像、错误恢复 | 原测试 | 本轮通过：5000播放采样；独立HDMI4796采样；实际核心两图/1820音频CDC样本 |
| 40源文件及真实厂商IP层次编译 | 原测试 | 本轮通过 |
| TD综合/布局布线/bitgen | 音频版 +0.191/+0.010ns | **setup +0.192ns，HWNS +0.023ns** |

16975项已导出终点检查无负余量，包含64项SDRAM DQ输入检查。未更改SDC、PLL、物理引脚或放宽时序。新bit保留SW3/SW4音频、原亮度/对比度及J1图片切换功能；仍有已记录的厂商SIP布局/本地时钟路由告警。

本次无需再次泛化整个工程回归；已覆盖改变的导航行为及相关音频/图像集成。当前工程代码与本次构建输入逐字节核对。

## 队友上板验证

新bit：`C:/Users/31640/Documents/ChatGPT/FFF/image_switch_fix_20261102/HDMI_Player_image_navigation_fixed_20261102.bit`。
SHA-256：`37cb4a00cc7cb1d28d252aedab9840a83235417326ed3e3a983d092c07014b12`。

可直接转交 `FFF/image_switch_fix_20261102/image_switch_verification_20261102.zip`，包含新bit、六张640×480/24位未压缩BMP、说明及只读检查脚本。六张图片的颜色、大数字和文件名不同，便于确定是否确实遍历六张。

下载新bit后，SW1复位再释放，SW3先向上关闭音频；按同一个下一张按钮。若使用六张验证图，请先把原卡BMP备份到电脑，测试时卡根目录只保留六张验证BMP，避免文件类型和目录顺序影响判读；WAV可保留。图片顺序仍按FAT根目录条目，而非文件名排序。GPIO接线沿用J1-1上一张、J1-2下一张、常开按键到GND。

**没有实际E盘报告前，不能认定此次代码缺陷就是实板唯一原因，也不能排除卡上只被枚举到两个BMP、其余格式不支持或所下载bit版本不一致。**

若仍只有两张，由持卡队友以管理员PowerShell运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "解压目录\inspect_sd.ps1" -Root E:\
```

脚本显式以 `FileAccess.Read` 打开SD卡卷，读取FAT32根目录和BMP文件头，按硬件枚举顺序报告图片编号、短文件名、尺寸、位深、压缩字段及可接受性。它不写卡，JSON报告写在脚本目录；读卷可能需要管理员权限。还应提供LED4是否亮及下载的完整bit名称。脚本只检查文件头，不承诺整条文件簇链或所有像素内容正确。

只读检查脚本已用测试FAT32卷验证：正常报告六张可用图；第三张改成compression=3后，准确指出编号2不支持、预期错误0x21，其余五张仍通过。

## 可重复测试与证据

工程内：

```powershell
python verification/image_navigation_20261102/run.py --case 0 --output "$env:TEMP/image_navigation_six"
python verification/image_navigation_20261102/run.py --case 1 --output "$env:TEMP/image_navigation_growth"
```

默认ModelSim为D:/modelsim2020/win64，可用--simulator-bin指定；每种模式均附带旧上限/目录增减单测。Memory使用应用模型，真实厂商IP仅做层次编译及TD时序检查，本次并未下载硬件。

FFF原始证据：`cached_before.log`、`cached_after.log`、`full_cache_before/simulation.log`、`full_six_after/results.json`、`full_cache_after/results.json`、`packaged_growth/results.json`、`final_timing_audit.json`。之前音频版本已在本地Git `2f6b342` 保存；本轮修复、回归测试及文档已纳入2026-11-02本地memory分支Git保存，未推送GitHub。
