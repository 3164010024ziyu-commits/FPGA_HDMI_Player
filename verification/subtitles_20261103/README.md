# 字幕与音频播放进度验证

2026-11-03。功能、接线和结果见`docs/SUBTITLES.md`。

- `run.py --output <目录>`：ModelSim专项；20档百分比精确值、48,000帧/秒、循环/欠载/复位和BCD进位，以及15帧4,608,000个RGB像素独立参考比较。生成PPM帧可直接查看。
- `run_system.py --output <目录>`：真实Storage/SPI/WAV/Memory/HDMI实例，SDRAM应用端口使用可控模型；检查PCM数据与标签同序、播放计数、图片字幕、开关及频谱并发。不将应用模型当作真实器件读回。
- `rebuild_td.py --output <目录>`：TD6.2实际综合、布局、布线、物理fix_hold，检查setup/hold后才生成bit。未知错误/严重警告终止；历史封装SDRAM位置及两条时钟布线提示单独留档。
- 多张图片信息绑定：`verification/slideshow_20261102/run.py`，检查六图及槽位复用，每次实际reader采用事件携带正确序号/文件名/尺寸；同时回归轮播/转场和20档音量。
- 真实PLL、厂商SDRAM IP和器件行为模型读回：沿用`verification/sdram_timing_20261028/run.py readback --model <原始IS42s32200.v>`，外部模型路径可配置。

默认模拟器`D:/modelsim2020/win64`，构建脚本默认TD路径可由`--td-root`覆盖。模型、工具安装和生成的测试输出不随Git收录。字体的HEX是参考输入数据，硬件使用同版本生成的内嵌ROM；字体生成工具为`rtl/display/tools/generate_subtitle_font.py`，固定字体源提交及许可证见文档。

板级接线和实际硬件结果仍需上板确认，不因软件测试通过标记为实机验收通过。
