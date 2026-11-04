# 多图切换/旧末图上限回归

工程根目录执行：

```powershell
python verification/image_navigation_20261102/run.py --case 0 --output "$env:TEMP/image_navigation_six"
python verification/image_navigation_20261102/run.py --case 1 --output "$env:TEMP/image_navigation_growth"
```

默认ModelSim为D:/modelsim2020/win64，可用--simulator-bin指定。
case0使用6张不同BMP，经过实际板级按键/导航、SD SPI、FAT32跨根目录簇、应用核心和HDMI；Memory后端为应用模型。
case1先模拟目录末尾在两张，再恢复六张，检查下一张不受旧边界限制。两种模式均核对每个源像素、前台显示像素及两个缓冲槽的新图，并附带目录增长/缩短的导航单测。
本测试模拟目录可见内容变化，不模拟物理拔插或证明热插拔已实现。硬件/SDRAM物理时序仍需实板验证。

inspect_sd.ps1仅以FileAccess.Read打开根卷，按实际FAT顺序列出BMP并检查文件头；报告写在脚本目录。可在有卡的电脑以管理员PowerShell运行：
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File verification/image_navigation_20261102/inspect_sd.ps1 -Root E:\`
无卡时可用--ImagePath方式（PowerShell参数为-ImagePath）检查以FAT32卷引导扇区起始的测试镜像。

修复前后证据、新bit、实板验证包位置与限制见 [IMAGE_SWITCH_FIX.md](../../docs/IMAGE_SWITCH_FIX.md)。
