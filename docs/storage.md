# SD 卡与 BMP 读取

将 `rtl/storage/` 下四个 `.v` 文件加入主工程，实例化 `storage_pipeline`。数据链为 SD SPI → FAT32 文件 → BMP 解码 → 带地址的像素流；SPI 字节收发已包含在 `sd_spi_reader.v` 内。

| 文件 | 职责 |
| --- | --- |
| `storage_pipeline.v` | 总入口、模块连接、读图完成与错误处理 |
| `sd_spi_reader.v` | SD v2 初始化、CMD17、命令 CRC7 与数据 CRC16 |
| `fat32_bmp_reader.v` | FAT32 根目录查找与碎片簇链读取 |
| `bmp_stream_decoder.v` | BMP 校验、行补齐、RGB 与像素地址输出 |

## 接入

使用系统时钟，`CLK_HZ` 必须与实际频率一致。首次联调建议 50 MHz、`READ_HALF_PERIOD=2`，并设置 `MAX_WIDTH=640`、`MAX_HEIGHT=480`；复位低有效，在系统时钟域同步释放。引脚与时序约束由整机工程统一配置。

| 信号 | 约定 |
| --- | --- |
| `start / ready / file_index` | ready 为 1 时给一个周期 start；编号从 0 开始，按根目录物理顺序选择 BMP |
| `busy` | 本次加载进行中 |
| `meta_valid / width / height` | meta_valid 单周期，通知图像尺寸通过头部校验 |
| `pixel_valid / pixel_ready` | 同时为 1 的时钟沿传输一个像素；队列满时拉低 ready |
| `pixel_rgb888 / pixel_rgb565` | RGB888 为 `0xRRGGBB`，另提供 RGB565 |
| `pixel_x / pixel_y / pixel_addr` | 左上角原点，地址为 `y*width+x`，单位是像素 |
| `pixel_sof / pixel_eol / pixel_eof` | 输入流首像素、行末、末像素，仅在有效传输时使用 |
| `done / error / error_code` | done 仅成功时单周期；error 保持至下次启动，初始化失败需复位 |

```verilog
// 同域队列须同时保存地址与颜色；异步接收使用异步 FIFO。
assign pixel_ready = !pixel_fifo_full;
assign pixel_fifo_wr_en = pixel_valid && pixel_ready;
assign pixel_fifo_wr_data = {pixel_addr, pixel_rgb888}; // 56 bit
```

正高度 BMP 先输出最底行，地址已处理上下方向，写入器不要再次翻转。若 SDRAM 每像素存一个 32 位字且布局为 `0xRRGGBB00`，写入字地址为 `frame_base_word + pixel_addr`，数据为 `{pixel_rgb888,8'h00}`。

**done 不表示 SDRAM 已写完。** 锁存 done，等队列与 SDRAM 写事务完成后，在 VSYNC 边界换帧。失败时废弃后台帧、保留前台帧，排空旧事务后再重试；不能仅凭 pixel_eof 提交新帧。

## 范围与验证

支持 SD v2 SDSC/SDHC/SDXC 的 SPI 只读；512 字节扇区 FAT32、MBR 主分区或 superfloppy、活动 FAT 和碎片文件；24/32 位非压缩 BI_RGB BMP，含正负高度、行补齐与扩展像素偏移。32 位第 4 字节忽略。默认最大文件 16 MiB。

不支持 FAT16/exFAT、子目录递归、调色板/RLE/BITFIELDS BMP、写卡或热插拔自动恢复。坏簇、自环与读取预算有检查，未实现任意多节点簇链环检测。解析尺寸上限不代表整机输出分辨率。

精简版本已在本地通过 ModelSim 五组 92 个场景，以及 EG4S20BG256 的 TD 综合、布局布线和 50 MHz 内部时序检查。回归与独立板级验证环境保留在本地，测试和构建产物不加入本次提交。实卡、SD 外部时序及 SDRAM/HDMI 联调仍待验收。

2026-10-26兼容性修复：LBA0只作为候选卷，完整BPB或几何校验失败且有支持的MBR分区时回退读取分区VBR；回退只允许一次。修复后18项FAT专项、6项SPI专项、原92场景及5项背压全部通过。原TD时序记录属于原交付版本，本次尚未重新进行P&R或实卡验收。详见 [MBR修复记录](STORAGE_MBR_FIX.md)。
