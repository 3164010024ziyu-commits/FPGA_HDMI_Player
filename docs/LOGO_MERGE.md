# Logo 合并与验证（2026-11-04）

将 `origin/main` 的 logo 提交 `ed9ac4f` 合入 `memory`，第一父版本为 `c4a925a`（UTF-8 字幕与同名图片配音）。

## 冲突处理

- `hdmi_tx_display.v` 参数区同时保留 `HDMI_LOGO_EN`、`IMAGE_FADE_EN`、`ENABLE_AV_SYNC`。logo 作为最后一层送给 HDMI，原音画同步 epoch、暂停与 TXT 字幕连接得到保留。
- TD 清单删除队友电脑的 `D:/...` 项目根路径，继续使用可移植的相对路径。
- logo 两个源文件的编译序号改为 53/54，避免与 TXT 模块的 49/50 重复。
- 保留队友补充的参数条测试时钟和等待周期。

## 画面行为

默认启用右上角 64×64 logo，坐标 x=568..631、y=8..71，距右侧和顶部均为 8 像素。logo 在亮度、对比度、淡入淡出、字幕和频谱之后叠加，所以切图时仍保持原亮度。`HDMI_LOGO_EN=0` 可在 display 模块禁用。

图片为 `rtl/display/my_logo.bmp`，已固化到 `logo_rom.v`。更换图案后需重新生成 ROM 和 bit；无需在 SD 卡另放该 BMP。当前透明色 FDFEF8，生成时使用每通道容差 12：

```powershell
python rtl/display/tools/gen_logo_rom.py --bmp rtl/display/my_logo.bmp --tolerance 12 rtl/display/src/logo_rom.v
```

## 验证结果

- ROM 的 4096 像素与 BMP 按透明色容差 12 处理后逐像素一致。
- 两帧完整 800×525 扫描：840000 像素通过，含 6324 个不透明 logo 像素、1868 个透明像素；边界和区域外背景均通过。
- 音画同步单元：7 个配音场景、轮播计时、暂停进度通过。
- 全工程仿真：9 次切图、8 次首采样检查、23599 个采样、66 次循环、手动/自动切图、双暂停路径、暂停时轮播、旧 epoch 屏蔽通过；首采样最大偏移 19240ns。仿真将轮播周期缩短，单元另核对生产配置的 5 秒计数。
- 原字幕、参数条和时间字幕回归通过，独立 golden RGB 比对 4608000 像素。
- TD seed=7 综合、布局布线、hold 修复、bitgen 通过。布局布线后 LUT 17114/19600、BRAM9K 52/64；最大延迟/恢复时间汇总 SWNS +0.150ns，最小延迟/hold 汇总 HWNS +0.030ns。
- 全端点审计 25005 项，负裕量 0；包含 SDRAM DQ 读/写各 64 项。

首次 seed4 出现 -0.165ns recovery（复位释放恢复时间）违例，主要为布线延迟；seed2 另有 -0.059ns setup 违例，均未生成可交付 bit。随后使用同一综合网表更换布局种子验证，所有失败日志保留；未修改时钟与约束来隐藏违例。seed7 通过后停止了不再需要的 seed1 备用布线进程，该中止记录不计作通过。

仿真仍有原有 FIFO 输出 `wr_used` 未连接的两条提示；这是同一未使用输出对应的两条诊断。TD 保留基线中已记录的 SDRAM SIP 位置/局部时钟提示，构建脚本拒绝其他严重警告。本轮未上板，整机回归使用 SDRAM 应用接口模型。

## 复现与记录

```powershell
python verification/logo_merge_20261104/run.py --output <输出目录>
python verification/av_sync_20261103/run.py --output <单元输出目录>
python verification/av_sync_20261103/run_system.py --fixtures <单元输出目录> --output <整机输出目录>
python verification/subtitles_20261103/run.py --output <字幕输出目录>
python verification/subtitles_20261103/rebuild_td.py --seed 7 --output <TD输出目录>
python verification/fat_sector_bram_20261103/audit_timing.py --build <TD输出目录>
```

logo 测试需要 Icarus Verilog；其他仿真使用现有 ModelSim，构建使用现有 TD。完整日志位于本机 `C:/Users/31640/Documents/ChatGPT/FFF/logo_merge_20261104/`。

本轮 bit：`td_seed7/HDMI_Player_subtitles.bit`（另存为 `HDMI_Player_Logo_20261104.bit`），SHA-256 `6f20a92adf538ecdb28c04483331c3d94234d26532e05d5763e3eca47dd72390`。这是合入 logo 的新 bit，旧音画同步 bit 不包含 logo。
