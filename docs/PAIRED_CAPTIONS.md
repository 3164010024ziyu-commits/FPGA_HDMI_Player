# 图片同名 TXT 字幕（2026-11-04）

## SD 卡准备

在 FAT32 卡根目录按相同 8.3 基本文件名放置图片、字幕和可选配音，例如：

```text
FIRST.BMP     FIRST.TXT     FIRST.WAV
SECOND.BMP    SECOND.TXT    SECOND.WAV
FONT16.BIN
```

TXT 保存为 UTF-8，带/不带 BOM 均可；继续共用原来的 FONT16.BIN。每次加载图片时重新读取同名 TXT，修改文字无需重新编译。当前按 FAT 短文件名匹配，推荐英文/数字基本文件名不超过 8 字符，避免长文件名生成的 ~1/~2 别名不一致。统一 CAPTION.TXT 已不再作为全局字幕；仅名为 CAPTION.BMP 的图片才匹配它。

找不到同名 TXT、内容为空或字库缺失时，显示原来的图片序号、短文件名和尺寸信息，不沿用上一张的文字。图片不存在或 BMP 无法解码时保留原图与原字幕，回收未发布字幕，允许后续重试。字库继续保留原有限制：每段最多 64 字符，只读取 TXT 开头 512 字节，换行/制表符转空格；无效 UTF-8 用替代字符表示。

字幕开关、移动、长按滚动及音频时间字幕的操作沿用原有方式。字幕在图片预加载期间保持旧内容，收到实际显示图片更换通知后，于下一个视频帧边界更新；最多有一帧的边界等待。

## 修改

- fat32_bmp_reader：增加可选同名字幕模式和 BMP 目录探测任务，先按图片序号/最后一张规则查出真实基本文件名，再以它匹配 TXT；复用既有 FAT/扇区 BRAM。未开启该参数的独立 FAT 实例保留原有行为。
- text_caption_loader / storage_pipeline：按“BMP 名称探测 → 同名 TXT → 字形 → BMP”的流程启动；上一张/下一张及首尾循环使用相同的图片选择规则。
- text_glyph_cache：增加等待显示切图发布、加载失败取消和取消后的缓存复用，避免预加载时提前换字幕；源域锁存取消请求直到确认，防止首尾循环快速重试清掉错误电平造成死锁。
- hdmi_tx_display / hdmi_player_top：连接实际图片更换事件及加载失败通知。
- SDC：为新 bank 状态和保持到确认的取消信号补充与既有工程一致的 8ns 跨域数据路径预算；后级同步寄存器及其他逻辑继续计时，未增加全时钟异步分组。
- verification：新增同名字幕 SPI 与缓存发布测试，更新旧字幕/音画同步夹具。

## 验证

- 独立真实 SPI 卡模型：9 个场景通过；三张图片、TXT 目录乱序、全局 CAPTION.TXT 干扰项、缺失同名 TXT、最后一张选择、损坏/缺失 BMP 后恢复、重复加载。
- 独立双时钟缓存：预加载不提前发布、旧字幕保留、失败取消、缓存复用、缺失 TXT 清空与再加载通过。
- 原字幕回归：UTF-8 解析、FAT 范围读取、2520000 像素缓存/滚动验证、SPI 六场景通过。
- 原音画同步单元通过；整机 9 次切图、8 次首采样检查、23599 个音频采样、66 次音频循环、暂停/轮播通过。
- TD seed4 综合、布局布线、hold 修复和 bitgen 通过：LUT 17472/19600，BRAM9K 52/64，SWNS +0.146ns，HWNS +0.021ns；全端点 25034 项无负裕量，SDRAM DQ 读写各 64 项通过。

完整测试日志：`C:/Users/31640/Documents/ChatGPT/FFF/paired_captions_20261104/`。验证仍包含原有未使用输出端口与厂商 SIP/局部时钟提示。整机仿真使用 SDRAM 应用接口模型；尚未上板，需下载新 bit 并验证实际 SD 卡文件名与字幕。

早期版本的整机回归在越过图片目录末尾后卡住，定位为取消通知在缓存确认前被清除，现以源域锁存修复并加入短脉冲取消测试；失败日志保留在 av_system。早期 seed7 构建同时出现时序负裕量，未生成交付 bit。最终 seed4 首次报告的新 bank 跨域 hold 路径尚未覆盖跨域预算，补齐两条真正经过双级同步的控制源网约束后，在同一布线数据库重新读取 SDC、修复 hold、完整重导出时序并生成 bit；记录位于 finalize_constraints.tcl/console.log。新约束以源网限定且只针对目标时钟，原有级间、复位与 SDRAM 时序检查继续保留。

## 复现

```powershell
python verification/paired_captions_20261104/run.py --output <同名字幕测试目录>
python verification/txt_subtitles_20261103/run.py --output <原字幕测试目录>
python verification/av_sync_20261103/run.py --output <音频单元目录>
python verification/av_sync_20261103/run_system.py --fixtures <音频单元目录> --output <整机测试目录>
python verification/subtitles_20261103/rebuild_td.py --seed 4 --output <TD目录>
python verification/fat_sector_bram_20261103/audit_timing.py --build <TD目录>
```

新 bit：`HDMI_Player_Paired_Captions_20261104.bit`，SHA-256 `f4a8951cae4b503d764bf95562ab1217f61232522c9345278e444e6ec30683d2`。
同名 TXT 字幕的源码、测试和使用说明随本次 Git 提交保存，板上验证待完成。
