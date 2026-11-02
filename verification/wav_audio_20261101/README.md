# WAV / HDMI 音频回归

在工程根目录运行 `python verification/wav_audio_20261101/run.py`。默认使用 D:/modelsim2020/win64，可用 --simulator-bin 指定 ModelSim、--output 指定日志目录；默认输出到系统临时目录。

包含 WAV 解析10场景、真实SPI共享读卡与HDMI逐样本包验证、独立HDMI音频打包、SW3/SW4消抖及状态灯、真实hdmi_player_top/VHDL/音频FIFO与双帧缓存并发集成。集成测试的Memory后端使用应用模型；真实40源文件/厂商IP层次编译和TD布线结果见工程文档及FFF原始日志，不代表上板已通过。

fixtures/card.hex 是稀疏映射的FAT32测试卡，包含BMP、故意不兼容的单声道WAV和带奇数JUNK块的48k/16bit/双声道WAV，音频跨碎片簇。core_card.hex 将BMP替换为16×8，适配四字Memory写通路。所有音频为生成的测试数据。

完整用法、文件格式、错误码和本轮bit见 [WAV_AUDIO.md](../../docs/WAV_AUDIO.md)。
