# FPGA HDMI Multimedia Player

基于安路 FPGA 的 HDMI 多媒体播放系统。

## 项目功能
- SD/TF 卡读取 BMP 图片
- SDRAM 图像帧缓存
- HDMI 图像显示
- HDMI 音频输出
- 按键切换和自动轮播
- 图片转场与 OSD 扩展

## 项目分工
- storage：SD 卡读取与 BMP 解析
- memory：FIFO 与 SDRAM 控制
- display：HDMI 视频与音频输出

## 工程目录
- rtl：Verilog 设计源码
- tb：Testbench 仿真文件
- constraints：引脚与时序约束
- docs：项目文档
