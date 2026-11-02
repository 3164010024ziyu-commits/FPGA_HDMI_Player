# 音频频谱验证
+
+工程根目录运行 `python verification/audio_spectrum_20261102/run.py --output "$env:TEMP/fpga_audio_spectrum"`。
+
+默认运行四项：512点FFT定点逐值比较、12种声道/频率/音量情形、叠加像素与帧边界、真实板级/SD SPI/WAV/双缓存/HDMI集成。`--units-only`只运行前三项。ModelSim默认D:/modelsim2020/win64，可用--simulator-bin指定。
+
+已有hex为固定测试向量。需要重建时运行 `python verification/audio_spectrum_20261102/generate_vectors.py`，该脚本需要NumPy，并与其FFT作独立复数误差检查。generate_vectors会重建测试向量和测试台。
+
+测试输出的overlay_pixels.hex是RTL画面，可转换为640×480 RGB图像进行目视检查。顶层集成测试的SDRAM应用端采用模型；真实厂商库及SDRAM读回另外验证。新功能及许可、接线、最终bit见[频谱说明](../../docs/AUDIO_SPECTRUM.md)。
+