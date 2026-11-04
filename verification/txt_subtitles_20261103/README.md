# TXT 字幕验证

运行 `run.py --output <工程外目录>`，检查 UTF-8、FAT 碎片范围读取、双时钟字形缓存和真实 SPI TXT/字体/BMP 顺序读取。

随后运行 `run_system.py --fixtures <上述目录> --output <另一目录>`，复用原有板级应用 SDRAM 模型和真实 SPI 字节/CRC/扇区交互，检查字幕与 BMP、WAV、HDMI、频谱、静音、复位并发。模拟卡为独立 FAT32 超级软盘模型，字库链刻意碎片化；字形测试字节由独立公式生成，避免依赖 DUT 内部状态。实际交付字库另外用 `verify_font.py` 与上游 HEX 全量逐行核查。

可用 `CAPTION.TXT` 为43字 UTF-8 示例。物理资源/构建命令、测试数据和硬件边界见 `docs/TXT_SUBTITLES.md`。整机仿真不是上板验收，不包含本轮物理 SDRAM 模型长回归；SDRAM/PLL/IP RTL 未改。

输出日志、ModelSim work 库及 TD 产物应位于工程外，避免提交大型生成文件。
