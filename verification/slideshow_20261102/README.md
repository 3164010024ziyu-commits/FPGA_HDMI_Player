# 轮播与转场回归

从工程根目录运行：

```powershell
python verification/slideshow_20261102/run.py --output "$env:TEMP/fpga_slideshow"
python verification/slideshow_20261102/run_audio_fade.py --output "$env:TEMP/fpga_audio_fade"
```

五项测试分别检查：计时间隔/忙时不排队/失败重试、生产16级帧控制、RGB全部通道值及系数、真实SD SPI/双缓存/HDMI六图轮播与渐变、板级按键消抖启停。第二条运行实际应用核心的WAV与转场并发检查。SDRAM使用应用模型，厂商层次和物理时序另外验证。整机加速定时和转场步长，生产bit使用5秒/16级。

详见[实现与结果](../../docs/SLIDESHOW_FADE.md)。
