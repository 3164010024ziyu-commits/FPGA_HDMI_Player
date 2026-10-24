# 接入整机：storage → memory → display

正式整机实例化 `rtl/storage/storage_pipeline.v` 和它的四个子模块。`hx4s20c_storage_bringup.v` 仅用于独立上板检查；不要把其像素计数接收端当成 SDRAM 写入器。当前 main 的 `HDMI_Player.al` 仍是原 FIFO 工程，新的 `Storage_Bringup.al` 是独立存储工程。

## 时钟、启动与队列

1. storage 使用系统时钟，并令 `CLK_HZ` 与真实频率一致。首次联调建议 50 MHz、`READ_HALF_PERIOD=2`，字节内 SCK 为 12.5 MHz。
2. 卡初始化后 `ready=1`。在一个时钟上升沿满足 `start && ready` 即启动；`file_index` 是根目录物理顺序中从 0 开始的 BMP 编号。`start` 应是单周期脉冲，持续拉高会在空闲后再次启动。
3. memory 队列满时拉低 `pixel_ready`，只在 `pixel_valid && pixel_ready` 时写入。RGB、地址和标志必须属于同一个队列项。禁止仅保存 RGB 后按输入顺序线性写内存：正高度 BMP 先发送最底行。
4. storage 与 memory 写入器不同时钟时使用异步 FIFO；原 `sync_fifo` 只适合同域，其读取结果在 `rd_valid` 有效时消费。

```verilog
// 同一时钟域的队列入口示意。queue_* 由 memory 模块提供。
assign pixel_ready = !queue_full;
assign queue_wr_en = pixel_valid && pixel_ready;
assign queue_wr_data = {pixel_addr, pixel_rgb888, pixel_sof, pixel_eol, pixel_eof};
// 数据宽度：32 + 24 + 3 = 59 bit。
```

`pixel_sof/eof` 指输入流的首/末像素；`pixel_y` 和 `pixel_addr` 已经转换为左上角原点。正高度 BMP 的首像素地址为 `(height-1)*width`，负高度 BMP 为 0。字段的完整定义与错误码见 [storage_design.md](storage_design.md)。

## 与参考 SDRAM 接口的映射

板卡参考 `frame_read_write.v` 使用 32 位字地址及 `0xRRGGBB00` 数据布局，显示读取 `[31:8]`。若队友沿用该布局：

```verilog
// frame_base_word 在一次加载期间保持不变；选择后台帧，不能覆盖前台。
assign write_word_addr = frame_base_word + queued_pixel_addr;
assign write_word_data = {queued_rgb888, 8'h00};
// write_word_valid / write_word_ready 的握手由 memory 写入器实现。
```

640×480 时每帧 307200 个 32 位字；可选帧槽 0 和 307200，总计 2457600 字节。写地址加法先保留足够位宽并检查整幅图不越过帧槽与 8 MiB 容量，再截取控制器地址位。上述字地址不能套用到按字节寻址或 RGB565 打包的控制器。

已经使用 `pixel_addr` 定位时，关闭参考写入器的再次垂直翻转。若写入器只接受逐行像素，应明确改成地址驱动或配置正确的行基址；不能直接串接后保留默认 `WRITE_V_FLIP=1`。参考例程忽略 `full_flag` 的做法不能用于有背压的正式数据链。

## 完成与换帧

一次加载的后台帧仅在以下条件全部成立后成为候选帧：

- storage 成功 `done` 已锁存，且本事务没有 `error`。
- memory 确认该帧全部排队像素和所有 SDRAM 写事务完成。
- 元数据与目标显示模式匹配，或整机已实现明确的缩放/黑边规则。

再通过跨域请求/确认，在显示 VSYNC 边界提交帧槽与元数据。`done` 是一个周期，memory 完成可能更晚，需要分别锁存，不能简单组合相与。不能以队列暂时空、`pixel_eof` 或 `meta_valid` 代替成功完成。错误时废弃后台帧并排空/隔离旧事务；确认队列与写入器空闲后才发起重试，前台继续显示旧图。

`dispay` 分支的 `frame_ready/pix_underflow` 尚未实现相应控制；`pix_req` 每有效行包含 642 个请求周期，而有效像素只有 640 个；`frame_sync` 是整行电平。接线前需修正或适配这些契约，详见设计文档的仓库接口分析。

## 联合验收

先用 640×480 色条确认 RGB 字节序、上下方向与每行像素数，再验证奇数宽度、正负高度和 32 位 BMP。主动制造队列满、SD CRC 错误及后半图读取失败，确认成功帧不丢像素，失败帧不提交，重新加载不混入上次残留像素。最后对整机重新做资源、时序与 CDC 检查；独立存储验证的资源数字不能作为整机报告。
