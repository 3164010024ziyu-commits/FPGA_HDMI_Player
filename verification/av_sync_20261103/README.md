# 音画同步验证

`run.py`：配对WAV的7场景、轮播截止计时、音频暂停进度测试，同时生成独立FAT32超级软盘卡数据及SPI模型。

`run_system.py --fixtures <上一步目录>`：当前生产board + 真SPI/CRC + 应用层SDRAM模型 + Display/HDMI消费，包含TXT和字库，检查切图首采样一帧内、旧epoch隔离、配音首采样、两路暂停不推进时间、暂停中循环轮播。

`probe_media.py --media <英文短名WAV目录>`：四段用户实际WAV文件头和各64个采样与标准wave参考核对。

所有命令带 `--output <工程外目录>`；默认使用本机ModelSim `D:/modelsim2020/win64`。完整原理、资源、时序及测试限制见 `docs/AV_SYNC.md`。原board依赖SW3的测试属于历史背景音乐接口，由新的板级测试覆盖；保留的背景模式通过 `verification/wav_audio_20261101/run.py --units-only` 单独回归。
