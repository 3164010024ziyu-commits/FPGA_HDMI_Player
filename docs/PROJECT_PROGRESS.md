# FPGA HDMI Player 项目进度

更新日期：2026-11-04（北京时间）

核对范围：本机工程、FFF验证记录和资料。当前状态以最上方“最新”章节为准；下方旧日期的失败、待实现和未提交说明保留为历史记录，不代表最新版本仍然存在相同问题。

协作约定：用户负责主要模块代码；助手负责资料查阅、接口核对、验证和必要提示。助手默认不修改用户模块实现、不直接提供模块实现代码；用户明确授权的定点修改按指定范围执行并展示差异。











## 最新：2026-11-04 Git版本保存：中文字幕与音画同步

本次提交将已验证的统一CAPTION.TXT中文字幕、按需SD字库、同名WAV图片配音、SW3停用、两路暂停及五秒预读时间轴，连同RTL、ADC/SDC、TD清单、回归脚本和使用文档纳入memory分支版本管理。GitHub同步目标为origin/memory，先前FAT BRAM优化提交9604f48一并同步；未修改main分支。后文“未提交/未推送”是各功能实施结束时的历史状态，当前版本以本节与Git记录为准。

提交前逐文件SHA-256核对59个待保存文件，功能源码与已验收版本一致；本次仅补版本记录，沿用原仿真、完整布局布线及24983项无负裕量时序检查，不重复编译。最终LUT17142/19600、BRAM9K41/64，setup+0.278ns、整体min/hold+0.030ns。仍待实板验收。

bit、四组图片/WAV、FONT16.BIN和交付ZIP仍位于FFF/av_sync_20261103交付目录，不纳入源码仓库。字库生成/素材准备脚本及许可证随源码保存；新电脑可按文档重建SD文件。未烧写开发板或Flash。

## 最新：2026-11-03 同名配音音画同步、暂停与五秒时间轴

按用户确认实现每张BMP自动匹配同名WAV：切图开始时从对应音频开头播放；SW3/C6端口/ADC/SDC删除；J1-6/H14和J1-7/J14由静音改保持电平暂停，PCM不出队、左上时间不推进。非轮播时配音循环；轮播每5秒按实际转场起点计时，图片提前约2秒预读、配音截止前约10ms才预读以持续补充旧PCM，暂停音频不暂停轮播，暂停中换图后新配音停在零等待恢复。保留16级淡出/淡入、导航、FFT、音量、图像调整与64字TXT。用户picture目录只读，四组英文8.3副本已准备；音乐.wav的44.1kHz重采样副本为48kHz，其余原样复制。

新增双2048帧PCM银行和epoch隔离，转场像素事件回SYS触发播放；配音就绪/轮播截止握手到memory只阻挡转场，不改SDRAM地址/读写/刷新/IP/PLL。银行独立复位寄存器避免误清正在播放的一侧。FAT按SFN主体匹配WAV，且MBR流式选择首个FAT32分区减少冗余状态以解除布线拥塞；全部原分区/缓存回归通过。

最终LUT17142/19600（87.46%），相对TXT版17055净变化+87、剩2458；寄存器8364，BRAM9K41/64（原40），DSP16、PLL2不变。setup+0.278ns、整体min/hold+0.030ns；24983项导出检查无负裕量，含64DQ读/64DQ写。整机9次转场、8次首采样检查最大19.24微秒、23599音频消费采样、66循环、2自动间隔通过；正常上一张/下一张、两路暂停、暂停中换图/循环、TXT并发通过。7组配音、MBR18+SPI6、缓存23、TXT各项、原字幕4608000像素、WAV10/SPI5000/HDMI4796回归，以及4段实际配音头/256采样通过。

交付`FFF/av_sync_20261103/HDMI_Player_AV_Sync_20261103.zip`，bit SHA-256 `6d73052b310aba31457a65f4a43a07a0ef57682083d9bedbdf1510f193bbff35`。详细用法、素材配对表、源码变化和测量边界见[音画同步](AV_SYNC.md)。本轮代码/约束/测试/文档已同步实际memory工程，保留原TXT未提交状态，未额外提交/推送、未上板；同步偏差以FPGA视频事件至HDMI音频消费计，不包含显示器/扬声器延迟。下一步用准备好的素材与新bit进行实板验收，特别核对SW3无作用、两路暂停、五秒换图和音频切换。

## 最新：2026-11-03 SD 卡 UTF-8 中文字幕与按需字形缓存

按用户要求先保存 FAT BRAM 版为本地memory `9604f48`，然后实现统一根目录CAPTION.TXT：UTF-8（可带BOM）、最多64码点，FONT16.BIN按Unicode索引提供16×16字形，原图片信息字幕位置显示TXT；SW2显示、原左右短按/长按滚动、同时归位保持，SW1音频时间不变。字库34MiB在SD上，FPGA只缓存本段字形，双银行在视频帧边界交换。没有TXT/空文本/字体读取失败回退图片信息；未收录的生僻字方框，非全Unicode排版系统。TXT与BMP顺序复用现有图片FAT实例，WAV通过原扇区仲裁并发。补新任务启动一拍等待，修复缺图后的粘滞FAT错误污染TXT，六图循环已回归。FAT参数校验加流水拍，SDC补字形握手与原初始化首级综合名称匹配；PLL/memory/IP/ADC/按键分配未改。

最终完整布线LUT17055/19600（87.02%），对比16293增加762，剩2545；寄存器8673，BRAM9K40/64（原34），BRAM32K0/16、DSP16、PLL2不变。setup+0.177ns、整体min/hold+0.023ns；24971项导出检查无负裕量，含64DQ读与64DQ写。新增UTF-8/FAT/双时钟/逐像素/SPI/整机并发通过；原MBR18+SD6、缓存23、字幕4608000像素、六图循环和10300805转场像素通过。字库126641字形/2026256行独立比对通过。完整证据、用法、字库范围及复现命令见[TXT中文字幕](TXT_SUBTITLES.md)。

交付`FFF/txt_subtitles_20261103/HDMI_Player_TXT_Subtitles_20261103.zip`（bit＋SD卡文件＋许可）；bit SHA-256 `9875793f5a59165803610e2c21b3da01ad12f73baebd60bbc8bde899bf0a5709`。本次源码、测试和文档已应用实际工程，新增实现未再次提交、未推送、未上板；整机采用既有应用SDRAM模型，物理IP长回归未重复，板级电气签核仍待实测。下一步复制CAPTION.TXT/FONT16.BIN到卡根目录，用最终bit验收中文滚动、换图、音频并发。

## 最新：2026-11-03 FAT扇区缓存BRAM化，完整布线净省1150 LUT

用户明确授权实现和测量。基于memory `7d154f4`干净工作区，在FFF建立原版/改版隔离副本，同一TD流程重新综合、place/route/fix_hold和bitgen。生产RTL只改fat32_bmp_reader.v：512×8位sector改同步块RAM，增加CACHE_PRIME首字预取和按握手前瞻地址；背压保持data/last，扇区内仍每拍1字节。MBR/BPB/FAT格式检查、碎片链、错误码和两套文件上下文保留。PLL、SDRAM/IP/FIFO、ADC/SDC、顶层和音视频显示逻辑不变。

实测最终LUT 17443→16293（88.99%→83.13%，净省1150，原占用约6.59%），余量2157→3307；寄存器8164→8168；BRAM9K 32→34（两套FAT各1块），BRAM32K仍0/16，DSP16、PLL2不变。同阶段综合LUT16927→15783（省1144）。新版SWNS +0.335ns、HWNS +0.023ns；24886项唯一端点检查无负余量，含64项DQ输入/64项DQ输出。旧封装SDRAM位置/两条时钟局部布线提示留档，不宣称零警告。

验证：原版/改版MBR18+SD引脚6场景均通过；新增23场景在两版分别比较22845字节，覆盖长度1/511/512/513/1023/1024/1250、长/随机背压、每拍吞吐、跨簇目录、末图、错误、两种中途复位及不同数据覆盖。WAV10场景、SPI5000采样、HDMI4796采样、板级与核心并发通过。实际Storage/SPI/字幕/频谱/HDMI整机19294音频CDC采样、10循环通过；六图轮播与手动切换、8次字幕绑定、10300805渐变像素通过。系统使用应用层SDRAM模型；本轮未重新运行真实器件模型长回归，生产SDRAM代码/约束未改，DQ物理时序已重新审计。

新bit：FFF/fat_sector_bram_20261103/HDMI_Player_FAT_BRAM_20261103.bit，SHA-256 `523d34068dcb66ef38c12db236f33fe926fc87e5784474b1d8b71fff2e19101b`。源码、测试和文档已应用到主工程，并按用户要求保存为本地Git检查点；未推送GitHub，未上板/烧Flash。复现与边界见[FAT扇区缓存优化](FAT_SECTOR_BRAM.md)。下一步实板长时间轮播和WAV并发；本轮没有实现音画时间轴、LOGO、任意中文TXT或传感器场景，也未共享FAT文件服务。

## 2026-11-03 图片信息字幕与当前音频播放进度

基于memory `a2ee12a`，按用户确认实现：SW2显示当前前台图片的1起始序号、8.3短文件名、尺寸；无图显示“暂无图片”。SW1显示当前音频HH:MM:SS，依据HDMI实际消费的有效立体声采样计数，48000帧/秒；循环首样本归零，静音继续，关闭重启重新开始，隐藏时间/切图不重置进度。PCM首标记与样本同队列跨域，不靠SD读进度或开机时长估计。

新subtitle_overlay位于底部y452和左上y12，与频谱/参数OSD错开。J1-8/9短按释放左右16像素、长按0.5秒自动滚动、同时按归位。紧凑内嵌字体不依赖旧D盘初始化路径，保留OFL来源。修复旧OSD槽容量/末字预取边界。图片信息随实际reader采用前台帧后通过握手送达，下一帧整体更新；复用既有描述载荷的稳定期，移除208位重复寄存器。

为装入器件，频谱16路柱高log换算改为分时复用并整组发布，FFT/频段/柱高黄金结果不变。检测到队友20档音量的百分比组合除法导致长路径，改精确查表并寄存控制值一拍，20档行为保留，RGB无额外像素延迟。PLL、SDRAM厂商IP、写控制器、刷新/读地址算法和GPIO接线保持原样。

验证：15帧4608000个RGB像素独立比较通过；48000采样/秒、循环/欠载/停播/复位和BCD进位通过；六图轮播与手动切换8次采用事件的标题/尺寸绑定正确；实际Storage/SPI/WAV/HDMI/字幕/频谱并发通过。原WAV十场景、共享SD/HDMI包、Memory14帧、真实厂商层级及原样SDRAM模型读回通过。

最终TD setup +0.132ns、hold +0.030ns，24927个导出检查无负余量，含64个DQ输入与64个DQ输出。资源17443 LUT（88.99%）、8164寄存器、32 BRAM9K、16 DSP、2 PLL。历史封装SDRAM位置/两条时钟局部布线提示留档，不宣称零警告。bit为FFF/subtitles_20261103/HDMI_Player_subtitles_20261103.bit，SHA-256 `f29926bcf24c9d497d108b82e7e9941dc01978cf2522e1d99a2a87333c5296c0`。

代码/约束/测试/文档已于2026-11-03保存到本地memory分支Git；尚未上板，未推送GitHub。此次保存未重新编译，沿用上述已验证版本。此项为默认信息与音频时间实现；任意中文说明配置、64字自定义/SD字幕包和真实日期时间仍为后续增强。说明及复现入口见[SUBTITLES.md](SUBTITLES.md)。下一步用新bit实测SW1/SW2、音频循环归零、静音时间继续、切图/轮播和字幕移动并发。


## 新增：2026-11-02 音频频谱可视化

基于memory `b995975`，按用户授权完成拓展五。已搜索GitHub并采用mebner86/icesugar-pro_sound2fft的MIT许可FFT核心作512点适配，保留版权/完整许可；新增Hann窗、整块声道能量选择、16段正频聚合、近似log柱高与右下角288×116半透明面板。新增常开键J1-13/GPIOA_10/M14接GND12/30，按一次显示/再按隐藏，约10.49ms消抖，上电关闭。音频关闭时隐藏、重启保留选择；音量与源/HDMI两路静音均反映到柱形，关闭频谱不影响声音。main按键布局和J1-10轮播保留；按用户决定不开发FPGA图片缩放。

FFT分析已有HDMI FIFO消费采样，像素域处理，不阻塞音频、不增加SDRAM/PLL。每块512样本、频点间隔93.75Hz，16柱覆盖1..255正频点，柱高逐帧快升慢落。WAV只新增注册playing状态，原播放算法及memory/IP/PLL/写控制器代码保持。最终补齐显示状态返回SYS同步首级约束，并用TD fix_hold修复物理短路径，未保留复位边沿试验或额外最小延迟选项。

测试通过：FFT16组/8192频点与独立定点参考一致，NumPy复数误差上限6量化单位；12组声道/频率/窗/静音/音量频谱及面板边界/逐帧快照通过。实际板级SPI/WAV/HDMI并发两次图像加载256源像素、15262音频CDC采样、25频谱更新、80922叠加像素，启停/两路静音/音频关闭隐藏/重启/复位通过，错误0。原音频/轮播/导航/FAT/SPI回归通过；真PLL/厂商IP/未改SDRAM模型768像素/6帧读回错误和Z均0。44源完整构建通过。

最终TD setup +0.120ns、hold +0.030ns，20939项已导出检查无负余量，64项DQ输入；资源16415LUT、28BRAM9k、16DSP、2PLL。bit：FFF/audio_spectrum_20261102/HDMI_Player_audio_spectrum_20261102.bit，SHA-256 `a1cc81444cb0b9006b10518323980a9a25cbd8cd5cf55940eca1d990f7d43923`。验证包含bit、接线说明、MIT许可、RTL预览与13秒测试WAV。本轮频谱代码、约束、MIT许可、回归测试及文档已纳入2026-11-02本地memory分支Git保存，未推送GitHub、未上板。本次保存沿用已通过的验证与时序结果，未重复编译。拓展五可视为代码/仿真已完成，仍待实板验收；字幕/时间戳仍未启用。详见[音频频谱说明与来源](AUDIO_SPECTRUM.md)。

## 合并：2026-11-02 采用main新按键布局并保留轮播

用户在VS Code发起origin/main合并，当前memory `a8bfc01`，目标 `feb3844`。唯一Git冲突为ADC，但自动合并部分也移动了复位/加载/图像调整/静音；简单接受HEAD会令D14、G11、G12分别重复占用。用户明确选择队友main新布局，因此保留main完整引脚表及key_in输入，轮播迁移至J1-10/GPIOA_9/L14，31逻辑引脚无重复。SW4改复位、SW3音频，KEY1/2音量、KEY3/4切图，J1-1加载、J1-2..5图像调整、J1-6/7静音；SW1/SW2字幕仍未启用。

补充key_in异步输入约束和测试台新端口，TD页首恢复本机路径；按main保留删除旧字幕说明，docs/key.txt更新为UTF-8实测对应表。轮播、淡入淡出、音频及memory逻辑保持。新key_in实际板级路由的音量减、长按一次、静音/恢复与导航隔离通过；六图轮播/转场、原WAV全链路、导航/FAT/SPI、41源厂商层次通过。最终TD setup +0.152ns、hold +0.004ns，17251项已导出检查无负余量，64项DQ输入。

新bit：FFF/merge_main_conflict_20261102/HDMI_Player_main_layout_20261102.bit，SHA-256 `75f6050911debad4cdd65c4444e63382661391f73064a90756375dadad155daf`。本轮解决冲突并完成本地合并提交，未推送GitHub、未上板。下一步按新表接线、下载新bit，实测复位/切图/轮播、音量/两路静音及音频并发。详见[main接线表和合并记录](MAIN_KEY_LAYOUT.md)。

## 新增：2026-11-02 五秒轮播与黑场淡入淡出

基于本地memory `9711c52`，按用户要求增加一只轮播按键并搜索GitHub/厂商/教学原始资料。选J1第3脚GPIOA_2/G12接常开按键至GND（内部上拉、LVCMOS33），两级同步/20ms消抖、长按一次。上电关闭，按一次启用、再按停止；无图先加载第一张，每张完全淡入后计满50MHz×5秒再请求下一张，首尾循环。忙时不堆积自动请求，手动切图优先且重计时；停止后已接受事务完成。首次加载失败后也等五秒再重试。

已实现新图完整写后台后，旧图16帧淡出到黑、垂直消隐且读事务排空后换缓存、新图16帧淡入；单侧约0.269秒。RGB逐通道定点乘法/右移，加在亮度对比度之后、参数OSD之前，不加像素延迟，不增加SDRAM读带宽。渐变每个消隐沿只更新一次，经Gray编码与两级同步跨像素域；淡入完成前保持加载忙。PLL、厂商SDRAM、sdram_write_ctrl和音频RTL保持原实现；实际生产41源文件。

测试通过：五秒缩参计数边界/失败重试、按键消抖启停、生产16级渐变/取消恢复、256值×17系数RGB运算、真实Storage/SPI/双缓存/HDMI六图自动循环0→1→2→3→4→5→0及停止后手动切图（7次黑场换帧、9,216,000显示像素）。实际应用核心并发WAV与转场：2次图像加载、5916音频CDC采样、115静音采样全部正确且错误0。原音频、导航/FAT/SPI、Memory/Display14帧回归及41源厂商层次通过。

最终TD setup +0.288ns、hold +0.023ns；17101项已导出检查无负余量，64项DQ输入。bit：FFF/slideshow_transition_20261102/HDMI_Player_slideshow_fade_20261102.bit，SHA-256 `b8e4e5b6aa3a506db8462810496681ed97acfe8704730e0fa59f6754aff41bd9`。转交包slideshow_fade_board_package_20261102.zip含bit、接线操作说明和六张640×480测试BMP。本轮代码、约束、回归及文档已纳入2026-11-02本地memory分支Git保存，未推送GitHub、尚未上板；本次保存未重复编译。下一步断电接第三只按键，下载新bit，检查连续轮播、黑场转场、停播/手动切图与音频并发。方案、来源和完整结果见[轮播与淡入淡出](SLIDESHOW_FADE.md)。

## 修复：2026-11-02 导航不再沿用旧末图上限

用户再次确认按下一张为A→B→A，图片在队友电脑E盘根目录，卡/硬件不在当前电脑，尚未取得真实文件头或目录报告。原版六张有效BMP的完整板级/SD SPI/双帧缓存/HDMI仿真可通过，因此不是双帧缓存只允许两张图。

定位到一个可复现该现象的代码缺陷：原image_navigation_ctrl把一次0x36查询结果永久缓存为last_index，之后不再请求更大编号。模拟目录先可见两张、后恢复六张时，原版仍在0/1间循环；单测及完整系统均断言“期望编号2、实际0”失败。本次仅修改导航RTL，移除末图编号缓存；下一张始终实际查询current+1，实际到末尾才回零；第一张上一张每次重新查询末图。Storage/Memory/PLL/音频/显示/引脚/SDC保持原实现。目录变化测试不表示物理热插拔已实现。

修复后：六图顺序0→1→2→3→4→5→0→5→0通过（9加载、1152源像素、2457600显示像素）；旧边界恢复六图场景通过（11加载、1408源像素、3072000显示像素）；目录增长/缩短、导航与GPIO、FAT28/SPI6、音频全链路及实际应用核心回归通过，40源真实层次通过。最终TD setup +0.192ns、HWNS +0.023ns，16975项已导出终点检查无负余量，64项SDRAM DQ输入检查。

新bit：FFF/image_switch_fix_20261102/HDMI_Player_image_navigation_fixed_20261102.bit，SHA-256 `37cb4a00cc7cb1d28d252aedab9840a83235417326ed3e3a983d092c07014b12`。另提供可直接转交队友的image_switch_verification_20261102.zip（bit+六张不同640×480/24位BMP+只读FAT/BMP检查脚本）。脚本在测试卷正确识别六张，并检测出第三张compression=3不支持。工程内新增verification/image_navigation_20261102可重复回归。

本轮修复、回归测试及文档已纳入2026-11-02本地Git保存，分支memory；未推送GitHub、尚未上板。本次仅保存已验证版本，未重复编译。本次证实的是旧上限缺陷及其修复；未经真实E盘报告与新bit上板，不能断言它是实板唯一原因。下一步由队友下载新bit、SW1复位、先关闭音频验证六张不同测试图；若仍有问题，提供只读检查报告、LED4状态与bit名称。详见[多图切换修复](IMAGE_SWITCH_FIX.md)。

## Git 保存与用户反馈：2026-11-01 WAV音频版本

按用户要求，将基于 `d7f3204` 的WAV背景音频、SW3/SW4控制、共享SD扇区仲裁、音频FIFO/打包修复、约束、测试及文档保存到本地 memory 分支。40源文件等43项唯一构建输入与上一轮验证版本逐字节一致，沿用 setup +0.191ns、HWNS +0.010ns 和已通过的音频/图像回归；本次保存未重复编译、未推送GitHub、未下载硬件。

用户新反馈：此前外接切图版本在SD卡放多张图片后，只能在两张间切换；尚未确认实际图片文件、目录枚举及错误码，当前仅记录为待定位。双帧缓存只限制同时驻留的两个显示缓冲区，并不限制SD卡可枚举的图片数量；本次Git保存不代表该实板问题已解决。后续将独立记录排查结果。

## 新增：2026-11-01 SD卡WAV背景音频与HDMI输出

基于 memory `d7f3204`，按用户授权实现音频。用户确认 SW3 开关、SW4 静音，循环首首兼容WAV；无需额外按钮。已核对手册PDF第18页：SW3=C6、SW4=C5，向下为0，均两级同步/20ms消抖。SW3向下开启，向上关闭并清空缓冲；SW4向下静音但播放位置继续推进，向上恢复声音；关再开SW3从头播放。

SD卡FAT32根目录支持48kHz/16位/双声道/格式1整数PCM的RIFF WAV，检查fmt/data/块边界并跳过附加元数据与奇数填充；顺序尝试最多256个WAV，跳过不兼容文件，选定后循环，每文件上限512MiB。增加双文件上下文的扇区仲裁、约16KiB PCM BRAM缓冲与48k节拍；同一张卡可同时读取图片和背景音频，音频不占图片SDRAM。修复既有HDMI打包误发上一组四样本的问题，并同步释放音频写域复位；BMP默认接口行为、Memory、PLL和厂商SDRAM IP实现保留。

测试通过：WAV解析10场景；真实SPI至HDMI包逐值验证5000播放采样、6148HDMI采样/1537音频包/128ACR，覆盖静音、循环、碎片簇、BMP并发、取消排空、CRC隔离恢复及无兼容WAV；独立HDMI4796样本/1199包通过；SW3/SW4映射消抖、LED4及原GPIO切图通过。实际应用核心/VHDL/音频FIFO/Memory应用模型并发两次图像加载（256源像素）、1820音频CDC样本、115静音采样，所有错误标志0。40源真实IP层次、原Memory/Display14帧1792像素、原图像系统、MBR18+6、末图FAT28/SPI6与导航回归通过。

最终TD综合/布线/bitgen通过：setup +0.191ns、HWNS +0.010ns，17002项已导出终点检查无负余量、64项SDRAM DQ输入检查；12691LUT(64.75%)、21/64 BRAM9k、9/29DSP、2/4PLL。处理了WAV解析建立违例和音频/已有状态同步CDC约束，未放宽内部数据路径或PLL/SDRAM时序。仍有原厂SIP布局等已有告警。

本轮bit：FFF/audio_wav_20261101/HDMI_Player_WAV_audio_20261101.bit，SHA-256 `6e75833233f07b36de1a400143fecbf11091a01e96e5faeb0604111e9977b8ed`；测试音源FFF/audio_wav_20261101/fixtures/TEST48K.WAV。新增工程内可重复测试 verification/wav_audio_20261101/run.py。音频错误计入LED4锁存，SD/FAT或缓冲问题可看audio_error_code；关闭音频不影响BMP，未实现热插拔/选曲/暂停/格式转换，原四字尾包限制保留。SD长延迟/极短文件可能欠载，转静音重缓冲；不能承诺无缝循环。

代码、约束和测试已同步到工程；尚未下载或试听实板，未提交/推送本轮Git。下一步将测试WAV复制到卡根目录，使用支持声音的HDMI接收设备，下载新bit；SW1复位释放后SW3向下、SW4向上试听，再检查静音、重新开启与播放中切图。详见[WAV音频说明](WAV_AUDIO.md)。

## Git 保存：2026-11-01 外接按键循环切图

按用户要求，在 memory 分支保存基于 `09e1061` 的当前工程：J1-1/D14 上一张、J1-2/G11 下一张、首尾循环、按键同步消抖、忙时排队、末图目录查询、对应 ADC/SDC/TD 清单及可重复回归测试和文档。当前36个源文件与约束等39项唯一构建输入均与上一轮验证版本逐字节一致；实际工程回归通过，沿用本轮 TD setup +0.145ns、HWNS +0.030ns 的结果，本次保存无需重复编译。

本次为本地Git提交，未推送GitHub、未下载或烧录硬件；实板外接按键验证仍待完成。下面功能交付记录中的“未提交”表示交付当时状态，以本条保存记录为准。

## 新增：2026-11-01 J1 外接按键循环切图

在 memory `09e1061` 上新增 J1-1（GPIOA_0 / D14）上一张、J1-2（GPIOA_1 / G11）下一张，使用内部上拉及常开按键接 GND（J1-12 或 J1-30）。引脚依据 HX4S20 手册 PDF 第13页，并由最终 TD 物理报告确认；禁止将 GPIO 接到 J1-11 的 5V。

按用户确认实现首尾循环：首张上一张到末张、末张下一张到首张。两级同步、20ms 消抖、长按一次、忙时保留一个命令（最后一次有效按下优先），完整写入并等 load_ready 恢复后才更新当前索引。正常末尾查询的 0x36 自动回到0且不触发 LED4，空目录/坏图仍报错并保留原图。SW1(C8)仍复位，SW2(C7)重载当前选中图；四个 KEY 的亮度/对比度功能保留。排序仍是根目录 BMP 目录项顺序，不是文件名排序。

新增 image_navigation_ctrl；board_top 接入按键，core/storage 传递 select_last/opened_index，fat32_bmp_reader 增加末图目录扫描；ADC/SDC/TD清单及相关仿真夹具同步，共36个源文件。未修改 Memory、PLL、SDRAM IP 或 Display 图像处理实现。

验证通过：导航/真实板级消抖与循环、单图/空目录/坏图恢复；末图 FAT 28场景、末图 SPI 6场景；原MBR 18+6场景；36源真实层次编译；memory/display 14帧1792像素；原系统与新增末图系统仿真各168源像素、922245显示像素、3帧。TD综合/布线/bitgen通过，setup +0.145ns、HWNS +0.030ns，15004项终点检查无负余量，D14/G11上拉约束生效。仍有原厂SIP布局/时钟路由等已有告警，外部接口电气及实板显示待实测。

新 bit：FFF/gpio_navigation_20261101/HDMI_Player_GPIO_navigation_20261101.bit，SHA-256 `afc36ebf7517060179a6730b0fc27e07a0445c4069267723bb34fe66de777f24`。工程内新增可重复测试 verification/gpio_navigation_20261101/run.py。尚未下载硬件，未提交/推送Git；下一步断电接线、下载新bit，实测首尾循环、长按、加载中再按、原亮度/对比度及LED。详情见[外接按键说明](GPIO_NAVIGATION.md)。末图缓存需复位后更新，未增加SD卡热插拔，原四字尾包限制保留。

## 合并同步：2026-11-01 origin/main → 本地memory

用户明确要求把远程main的更改同步到本地memory。原memory为 `01208eb`，备份分支 `backup/memory-before-main-20261101`；获取的main为 `21afadf`。合并无文本冲突，保留memory中的display_pixel_fifo修复，引入main新增亮度/对比度按键、参数OSD和InfoFrame调整。

注意：main将Reset_n从A2改为C8，KEY_LOAD_N从B2改为C7；C1/B1用于亮度±，B2/A2用于对比度±。当前板级ADC按main保留这些分配。补齐既有测试替代模块的key_img端口并将测试输入固定未按下，TD工程页首路径恢复为本机路径。源码清单变为35个Verilog/VHDL文件。

本次真实35源文件编译/层次、memory/display 14帧1792像素回归、Storage/SPI/HDMI集成（168源像素、922245显示像素）及普通/诊断板级测试通过。未重新布局布线或生成下载文件，合并后不能沿用旧bit及旧时序报告作为新功能验证结果。仅完成本地合并提交，不自动推送GitHub。

## Git 保存：2026-10-30 memory 注释与代码整理

按用户要求保存基于 `b4ce099` 的当前版本：补充async_fifo占用量、格雷码及跨域指针说明，调整同步寄存器声明位置，简化frame_buffer_ctrl及sdram_app_arbiter模块说明，整理sdram_refresh_ctrl的else排版。保留用户当前代码；仅清理刷新模块一处行尾空格。

本次未改动读写算法、接口、PLL或约束，不重复运行功能仿真或布局布线；此前记录仍对应其注明的测试范围。最新帧清空修复的实板确认状态未收到新的结果，继续保留待复测。此次为本地Git提交，未推送远端。

## Git 保存：2026-10-29 显示欠载诊断、读返回流水与帧清空毛刺修复

按用户要求，在memory分支保存基于 `f5e9a4c` 的当前版本，包含独立错误分类诊断、reader边收边送、read_RAM帧清空寄存输出、毛刺/行对齐/背压/整帧回归和进度文档。保留用户async_fifo新增注释；核对其逻辑与验证版本一致，其余生产源文件/约束均与最新记录一致。

最新布局布线setup +0.224ns、min +0.032ns，毛刺对照及功能回归通过。最新文件为FFF/frame_flush_glitch_20261029/HDMI_Player_frame_flush_fixed_20261029.bit。当前仍待用户实板确认列恢复、底部完整且LED4灭；本次保存不代表实板验收通过。仅创建本地提交，未推送远端。

## 修复待实板复测：2026-10-29 frame_sync组合译码误复位FIFO

用户确认重新编译下载后底部可见，但固定列错位且普通LED4亮。发现read_RAM的组合 `vcnt==480` 直接进入显示FIFO异步复位；行计数多位翻转可能瞬间命中480。延迟注入在383→384复现旧版假清空；寄存输出后消失。预取FIFO误清与reader未同步重启可造成丢字、固定列偏移和欠载；2048%640=128与照片相符，但尚无实板毛刺/实际丢字数采样。上轮单一吞吐诊断不完整。

仅将read_RAM的frame信号改为像素时钟寄存、行边界更新，仍精确覆盖第480行800拍，保留reader吞吐优化。毛刺对照、两帧行对齐、实际BMP三帧921600像素压力测试、14帧应用回归、真实Storage/SPI/HDMI集成及生产层次均通过。新routed setup +0.224ns、min +0.032ns，无负裕量；新普通模式bit为FFF/frame_flush_glitch_20261029/HDMI_Player_frame_flush_fixed_20261029.bit。尚待实板确认图像完整、列恢复且LED4灭，未提交Git。详见[帧清空毛刺修复](FRAME_FLUSH_GLITCH_FIX.md)。

## 修复待实板复测：2026-10-29 显示FIFO欠载与底部缺失

用户确认诊断版仅LED2亮，LED3/LED4灭。优化sdram_read_ctrl：四字返回可以边收边送显示FIFO，保留四字缓冲、满背压、完整四拍请求、flush和超时保护；黑边补零组标记为四字就绪。只改reader功能，PLL/FIFO容量/约束/引脚/刷新及写控制器保持。

实际BMP+每组额外4拍延迟下，旧版在x616/y337欠载；修改版同条件3帧921600像素通过。此延迟是受控压力条件，不是已测实板参数。两组真实PLL/厂商IP/未改模型的实际BMP两帧614400像素、真实小帧768像素、14帧应用回归及9光栅背压/取消测试均通过。最终routed setup +0.161ns、min +0.010ns，13152项无负裕量。尚待实板下载确认底部完整，不宣称硬件验收已通过。

新普通灯模式bit：FFF/display_underflow_fix_20261029/HDMI_Player_underflow_fixed_20261029.bit。普通含义恢复为LED1=memory、LED2=SD、LED3=前台帧、LED4=错误；不是上一轮分类灯含义。预期加载后前三灯亮、LED4灭。已补充可复现对照测试与[修复记录](DISPLAY_UNDERFLOW_FIX.md)，未下载硬件、未提交Git。

## 实板诊断准备：2026-10-29 独立区分欠载、读超时和加载/刷新错误

用户授权定位修复底部黑区。当前仿真未复现实板失效，不能直接认定带宽不足。已增加可选错误观测输出和DIAGNOSTIC_LEDS参数（正常工程默认0，原灯含义不变），专用bit使用1：LED1=memory就绪、LED2=FIFO欠载锁存、LED3=读超时锁存、LED4=加载/刷新错误锁存，KEY1清除。数据通路、PLL、引脚及约束均未改，保留用户FIFO注释修改。

正常板级回归、错误分类灯测试、实际控制器错误输出连接验证和真实工程层次检查通过。诊断bit routed setup +0.214 ns、min +0.030 ns，完整路径检查无负裕量，bitgen成功。文件位于FFF的 `bottom_black_fix_20261029/HDMI_Player_error_diagnostic_20261029.bit`。尚未取得该bit的实板错误分类结果，因此底部缺失尚未确认修复；下一步请下载专用bit，KEY1复位后KEY2加载并记录四灯。详见[错误分类诊断](DISPLAY_ERROR_DIAGNOSTIC.md)。本轮未提交Git，未连接/下载硬件。

## 实板反馈：2026-10-29 已显示，底部黑白测试区缺失且 LED4 亮

用户确认图片已能显示，上部色条/灰阶正常，底部缺失且LED4亮。已核对 FFF 原图 `test_pattern_640x480_24bit.bmp` 为640×480/24位BI_RGB，底部376～479行均有图案。用当前BMP解码模块对实际原图加入背压验证，307200个像素、地址、坐标全部匹配，底部最后一行640像素输出完整。

当前应用模型的欠载/读超时恢复测试再次通过，确认任一次欠载会屏蔽本帧后续像素；但该受控测试不能证明实板的底层原因。LED4为加载/显示错误汇总锁存，尚未区分FIFO欠载、读超时与早先加载错误，不能直接断言SDRAM漏写或总带宽不足。下一步需分别捕获underflow/read_error/load_error及首次错误行列和FIFO水位。本轮未修改模块、生成新bit或提交Git。详见[底部缺失诊断](BOTTOM_BLACK_DIAGNOSTIC.md)。

## Git 保存：2026-10-29 当前集成与首次上板准备版本

按用户要求在 `memory` 分支保存当前工作区，提交基于 `cc21299`。范围包含 storage/memory/display 对接与双帧缓存、写地址及时序修复、100 MHz/306° SDRAM 配置、板级封装和 ADC/SDC、可复现测试、display 历史资料归档及项目文档。原有用户修改及已删除 demo 顶层一并保存。

提交前确认 34 个源码和 ADC/SDC/工程清单共 37 项仍与本轮构建版本逐字节一致；最近 routed setup +0.104 ns、min +0.031 ns，13,194 项无负裕量，板级控制仿真通过。本次保存不重复执行长仿真，不改变硬件验收状态。首次上板新 bit 保存在 FFF 的 `board_readiness_20261029/`，不混入主工程旧构建目录；路径及 SHA-256 见 [BOARD_READINESS.md](BOARD_READINESS.md)。本次仅创建本地提交，未推送远端，尚未上板。

## 当前状态：2026-10-29 首次上板准备检查与新 bit

当前主工程 34 个源文件及 ADC/SDC/工程清单共 37 项与上一轮通过的最终副本一致。本轮重新综合、布局布线，setup +0.104 ns、min +0.031 ns，13,194 项无负裕量；板级上电/外部复位、按键、待处理加载和 LED 测试通过。确认外部 PAD 分配不变，并复核 SIP 初始位置调整及局部时钟布线提示，未修改 RTL/连接/PLL/约束。

发现主工程 `HDMI_Player_Runs` 中现有 bit 是旧 125 MHz/-6.565 ns 版本，不用于最新验证。已另生成 `C:/Users/31640/Documents/ChatGPT/FFF/board_readiness_20261029/HDMI_Player_20261029_100MHz_306deg.bit`；本次可以用该新文件进行首次分阶段 JTAG 功能验证，尚未下载或实测屏幕。外部 SPI/HDMI 签核、25 MHz 显示器兼容性、四字尾包及运行中失锁自动重播仍未完成；音频/OSD 关闭。未提交 Git。详见[上板准备及操作步骤](BOARD_READINESS.md)。

## 当前状态：2026-10-29 display 目录整理

按用户要求整理文件位置，未修改模块逻辑或连接。`rtl/display/` 现在保留 `src/`、`ipsrc/clock_ip/`、`tb/`、`tools/`、`docs/` 和导航 README；274 个重复副本、旧独立工程、未使用的 SDRAM IP、历史构建结果、日志及旧 bitstream 原样移至 `archive/display_legacy/`，归档清单保留新旧路径及 SHA-256。

274 个搬迁文件及 70 个保留文件校验通过；当前 RTL、字库、约束、PLL、TD 清单内容保持不变，34 个源文件路径有效。ModelSim 使用真实厂商库完成 Verilog/VHDL 编译和当前板级顶层层次展开，`REAL_HIERARCHY_PASS`。仅整理路径，本轮没有重新跑长功能仿真或布局布线，先前 SDRAM 时序和功能结论的测试范围不变。

补充目录导航和生成文件忽略规则，旧资料完整保留。原有修改及用户删除的 demo 顶层保持不变；本轮未提交/推送 Git，未生成/下载 bitstream。详见[整理记录](DIRECTORY_ORGANIZATION.md)。

## 当前状态：2026-10-28 DQ、FIFO、复位时序及第四字 Z 修复

本轮用户授权定位并修改。生产 memory 改为100 MHz，SDRAM转发时钟100 MHz/306°（8.5 ns），display仍125/25 MHz。同步SDR_CLK_PERIOD=10 ns、手动刷新1500拍=15 µs。修复低水位比较长链、PREPARE/EMIT请求空档造成的写入抢占；reader仍四字一组，低水位活跃光栅保留读优先，物理排空后单空闲拍交接。PLL只在配置时启动复位，普通外部Reset_n清理任务但不断SDRAM时钟。

SDC精确绑定跨域源网络及目标时钟，解决TD打包后.d引脚失配/邻寄存器误包含；FIFO四组5/5/12/12、req1、ack/done2、描述数据19条均受8 ns限制。只豁免复位同步链SR，后级正常计时。实际读窗口证明32位DQ输入使用第二个控制器采样沿，设置setup2/hold1；memory捕获额外0.6 ns预算，TD另加默认0.1 ns。没有整组时钟false path。

最终布线整体setup +0.104 ns、min/hold +0.031 ns；普通及例外路径13194项无负裕量。DQ输入最小+0.335 ns、输出最小+1.374 ns；FIFO/reader/仲裁774项最小+0.062 ns，复位recovery/removal2188项最小+0.031 ns。此前-6.565 ns不再存在。

真实PLL/IP：周期/306°相位100次断言；6帧768像素（含正反行序、换槽、普通复位后重初始化）零Z/零错误；640×480在后台满速源写入下通过7帧2150400像素、8865次刷新，无欠载，第二张完整图写完并消隐提交后结束。该大帧测试未继续逐像素读第二张全尺寸图，其换槽读回另由小帧覆盖。应用模型14帧/1792像素、全光栅3帧/921600像素、真实Storage/SPI/HDMI的168源像素/922245显示像素及错误恢复均通过。

512 µs的空闲、持续写、4096字后暂停各有34请求/34确认/34占用/34真实AUTO REFRESH；pending到命令最长分别118.5/268.5/268.5 ns，命令间隔最长15.090 µs。保留旧失败实验；仅降频确实不够，补齐仲裁带宽后才通过。

尚未上板；外部SPI/HDMI时序、电气/显示器兼容性及小正裕量仍需板级验证。四字尾包仍未实现；运行中PLL失锁后的自动重播尚未实现。writer、async_fifo核心、加密IP、display PLL、外部管脚与board_top未改。本轮未提交/推送Git，未生成/下载bitstream。详见[修复、验证与下一步](SDRAM_TIMING_CLOSURE.md)和[可重复生产时钟测试](../verification/sdram_timing_20261028/README.md)。

## 当前状态：2026-10-28 写地址长组合路径修复

用户授权检查并修复 -6.566ns 写地址建立时间违例。原路径串联倒序行号减法、乘宽度、基址和列号加法，综合路径14.450ns，125MHz建立预算7.884ns；可能导致有效地址采样不稳定，但不能据此证明每拍必错，元数据保持和空闲间隔不等于已证明的多周期时序例外。

本次只修改sdram_write_ctrl的地址生成/就绪门控：每帧锁存首行、宽度、末列和正负行步长，用后续两拍分别完成乘法与基址相加；WRITE阶段地址直接来自current_addr，普通字加1，行尾加/减width。write_request和进入WRITE均等待address_ready。原四字数据节奏、完成排空、刷新、接口和复位协议保留；PLL/ADC/SDC/厂商IP/FIFO/reader均未改变。

验证：新84帧地址矩阵777752字、旧24字地址回归、14帧memory功能、3帧640×480共921600显示像素、实际Storage/SPI/HDMI共168源像素与922245显示像素均通过。真实IP短帧180°仍复现32Z/512像素，270°测试台对照零错；未把已知读相位问题改记为通过。gate综合与实际布局布线已完成，未生成下载文件。

写地址输出Routed setup +6.656ns、hold +0.223ns；writer内部217个物理终点setup最小+0.019ns、hold +0.076ns，相关报告未见负值。完整21位地址由功能回归逐字检查，物理合并后的终点数不同。writer控制余量很薄，PLL抖动等预算仍待核定。

**整机仍未过时序：Routed setup最差-6.565ns，hold +0.030ns。** 当前最差是SDRAM DQ→PAD，另有FIFO水位到reader状态及异步复位recovery报告；与原高度描述→写地址乘加路径不是同一条。下一步处理这些独立时序项及正式SDRAM读相位，不能据本次写地址修复直接宣称整机可稳定上板。详见 [ADDRESS_TIMING_FIX.md](ADDRESS_TIMING_FIX.md)。本次未自动提交或推送Git；下方保留历史过程。

## 前序记录：2026-10-28 板级约束与加载封装

用户要求编写约束文件，并明确选择“图片序号和缓存基址固定为0，新增薄板级封装并用按键启动”。已核对 HX4S20 手册、FPGA/外设原理图和官方示例 ADC；新增 hx4s20_hdmi_player.adc、hx4s20_hdmi_player.sdc 和 hdmi_player_board_top。TD 主工程切换到 board_top，原 hdmi_player_top 继续作为内部系统核心，所有原业务 RTL 和 PLL 参数未改。

上电或 KEY1 复位后延迟约20ms同步释放，KEY2经同步消抖后请求加载第0张图、缓存池字基址0。未就绪时保留一个请求，长按只发一次。四个独立LED高电平点亮，依次表示memory就绪、卡初始化、有效前台帧、曾发生加载/欠载错误。默认HDMI A。ADC共绑定15个逻辑信号，TD自动占用4个HDMI负端，合计19个PAD；SIP SDRAM不分配外部GPIO。

SDC约束50MHz并按真实PLL自动推导100/125/125MHz(180°)、125/25MHz，定向限制FIFO Gray总线和帧描述CDC路径到8ns，不作跨时钟全局false path。最终匹配17位写Gray、17位读Gray、3位标量握手/完成同步和优化后19位帧描述，均生效。未填入未经核定的SD/HDMI外部I/O延迟或PLL抖动预算。

验证：封装消抖/长按单次/请求保留/上电及外部复位/LED同步和错误保持测试通过；34个实际Verilog/VHDL文件及真实厂商库的板级层级展开通过；TD加载ADC/SDC和gate综合通过。**真实时钟约束下的时序未通过：最差setup slack -6.566ns，写地址路径约14.450ns，125MHz预算8ns。** 当前结果仅为综合估计，尚未布局布线验收；不能将“综合成功”写成“时序通过”。本次按授权未修改写地址实现，也未通过无证明的多周期/假路径掩盖该问题。

下一步审查写地址乘加路径及有效采样周期，核定SDRAM正式读相位（原第四字Z问题仍在），补齐外部接口预算后再做布局布线与分阶段上板。本次没有生成下载文件、自动提交或推送Git。具体管脚、证据和复现入口见 [BOARD_CONSTRAINTS.md](BOARD_CONSTRAINTS.md)。以下为历史过程。

## 前序记录：2026-10-28 display 与 memory 双缓冲对接

本节为最新状态，下方旧段落保留历史过程；旧的“读接口关闭 / display 未对接”描述已被本次更新取代。

用户明确授权本次连接新增 display、使用异步 FIFO 并增加帧缓存。已在 memory 分支的工作区实现：实际 hdmi_tx_display 顶层例化、SDRAM 四字读回、整组读写仲裁、刷新优先、2048×24 显示异步 FIFO、两字输出预取，以及 SDRAM 两块 640×480 帧缓存。写入异步 FIFO 保留；frame_sync 消隐期统一清队列、排空在途读并切换完整后台帧。连续写入时显示 FIFO 低水位优先，避免前台被写流饿死。

新增 frame_buffer_ctrl、sdram_app_arbiter、sdram_read_ctrl、display_pixel_fifo；修改系统顶层、memory 总装、writer 请求出口、async_fifo 水位出口、display 像素请求与锁定复位、显示 PLL 锁定出口、TD 33 个混合语言文件清单及显示测试替身。原 storage、SDRAM 加密 IP 和 memory PLL 配置保持；用户注释和已删除 demo 状态保留。

支持 640×480 以内、宽度为 4 倍数的小图左上显示并补黑，自动选择前后台槽；frame_base_addr 现在表示固定的双缓存池字地址基址。未实现四字尾包，非法尺寸/地址/运行中更换缓存池报 E1，取消源事务并允许重试。当前系统启用视频，音频/字幕组件保留但未连接数据源。导入显示 PLL 实际是 25 MHz / 125 MHz，未改成文档中的 25.175 MHz。

验证：14 帧功能检查（1792 像素）、完整 640×480 三帧逐像素检查（921600 像素，后台连续写入及 4383 次刷新）、实际 Storage / SPI / HDMI 链路（168 个源像素、922245 个显示像素，含 E1 后恢复）、真实 IP 短帧相位诊断、真实厂商库完整层级及 TD gate 综合。欠载/读超时下一帧恢复、取消、同高度帧、上下方向、补黑、前台保护和外部复位均覆盖。

补充真实 IP 连续长行诊断：640×16、3 帧、30720 像素、424 次刷新及后台并行写通过；仍为测试台 270°。最后复核补强后台槽位/可写状态 CDC 顺序，重新完成相关功能、整帧、系统、短帧相位和 gate 综合回归；可写状态先寄存，再比槽号多一级同步。

当前正式 125 MHz / 180° 的参考模型读回仍有每组第四字 Z：512 显示像素中 32 个错误；测试台 270° 对照同样 512 像素为零错误，工程 PLL 未改。完整真实 IP 长跑 600 秒超时前已检查两帧 614400 像素、未见错误，但没有最终 PASS，单独记为未完成。以上结果不等于正式相位/布局布线/管脚/跨域时序或板上 HDMI 已验收。

下一步先核定 EM638325 读采样窗口与 SDRAM 时钟相位，再完成板级管脚及 CDC/时序约束、布局布线和上板彩条/图片检查。之后按需求扩展尾包、缩放、音频及字幕源。

结构和接口细节见 [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)、[DISPLAY_MEMORY_INTEGRATION.md](DISPLAY_MEMORY_INTEGRATION.md)；复现入口见 [集成测试](../verification/display_memory_20261028/README.md)。本次未自动提交或推送 Git。

## 前序阶段记录

最新storage状态：MBR误识别已在fat32_bmp_reader中修复，121场景复测通过；此前快照中的0x34误判记录作为历史保留。memory尾包、FIFO最小深度和正式读采样问题仍独立跟踪。

存储部分已具备同步 FIFO、异步 FIFO 和四字预取写控制器；写控制器的历史单模块自动检查与真实同步 FIFO 连接测试通过。用户已新增 `memory_top.v` 和 `include/global_def.v`，完成 32 位、深度 16 的同步 FIFO 与写控制器之间的连接，以及上游写数据、写使能和满标志端口。复位极性、数据位宽、FIFO 深度和端口分隔符已在静态复核中纠正。

已在 `memory` 分支导入匹配板载 50 MHz 输入的 PLL，以及 APUG011 的 `sdr_as_ram`、`sdr_init_ref`、`sdr_wrrd`；现有 `sdram_write_ctrl` 复用用户文件。此前 TD 源文件清单与顶层调整为 `memory_top`；本轮接口对接后已增加 storage 与系统顶层，切换为 `hdmi_player_top`。PLL 使用配套例程的 100/125/125 MHz、0/0/180° 配置，刷新周期参数同步为 125 MHz。ModelSim 编译和零时层次加载通过，PLL 输出周期及相位测量通过；物理 SDRAM 总线与 SIP 原语已按参考例程接入并经零时层次检查；未用读请求已停用，LED已按用户选择指示PLL锁定且初始化完成，尚不表示数据校验通过。

当前已接入帧描述CDC、行列写地址、帧完成保持电平及50MHz返回同步。本轮已把外部Reset_n接入memory：两域异步进入、各自两级同步释放，FIFO内部按读写域释放，SDRAM重新初始化前关闭像素/描述接收和就绪状态。12组复位及回归通过；PLL保持锁定的WRITE中复位后，真实IP重新初始化并正确完成新8字；真实storage与memory在替身IP下的中途复位重读也通过。尾包、帧中止、整机单独失锁恢复及正式读采样继续独立处理；未宣称SDRAM物理内容/读回和实板时序验收。

2026-10-25新方案：15µs周期的应用侧刷新仲裁，pending暂停启动新四字组，等待在途写入与下游忙解除后发送单拍请求。三种512µs最终生产场景均34请求/34确认/34占用/34实际刷新；pending到实际刷新最长196ns，相邻刷新最长15.064µs。11场景4376字模型存储全部正确、刷新覆盖通过，但工程125MHz/180°仍每组第四字读回Z，共1094错。仅测试台270°诊断的11场景全部通过，未改工程PLL。帧缓存、显示、板级时序和实板运行尚未完成。详见 [刷新修复记录](SDRAM_REFRESH_VERIFICATION.md)。

## 2026-10-28 memory外部复位接入与验证

已按用户授权检查整个工程复位，并让外部Reset_n清除memory旧任务。仅修改memory_top、async_fifo两个RTL及原异步FIFO测试台：共同请求由外部复位或PLL失锁产生，50MHz/125MHz分别两级释放；FIFO端口不变但内部按写/读域释放；writer/refresh/IP使用125MHz复位，CDC两侧分别复位。初始化状态同步回50MHz，就绪和写入握手在复位及重新初始化期间关闭，PLL配置保持不变。原有顶层/storage复位无需改动。

12组检查通过：8种锁定PLL下的外部复位、7次新帧/56字无旧数据；6组FIFO矩阵共49152条目；原4字FIFO测试；完整TD层次；真实IP在WRITE中复位并两次初始化、新8字完成；原同高度两帧16字完成回归；真实storage和memory在替身IP下接收2像素后复位、改基址和颜色重读8像素正确。复位不清物理存储阵列，只使旧内容失效，不再消费旧FIFO和帧状态。

FIFO在复位/两拍释放阶段full=1、empty=1，表示暂不可读写；原测试台新增等待full解除。源码和记录见[MEMORY_RESET_VERIFICATION.md](MEMORY_RESET_VERIFICATION.md)、[测试结果](C:/Users/31640/Documents/ChatGPT/FFF/memory_reset_integration_20261028/verification_results.json)。真实IP验证使用受控时钟，不含物理内容/读回和板级时序；单独PLL失锁的整机自动重播仍未实现。未创建Git提交，保留此前未提交修复和用户注释。

## 2026-10-28 帧完成与50MHz同步最小修复

用户明确授权先保存Git、再尽量少改修复三个完成问题。已原样提交修复前检查点35b7335；后续修复代码保留在工作区供查看。修改4个RTL和TD清单：修正用户同步块的端口/复位及旧输出名连接；writer新增Sdr_busy、有效帧与4拍排空保护；新描述优先清done；顶层首次空闲可启动，任务等待本次done低后高并等storage空闲，保留头部失败且无描述时的重试；TD加入CDC为第16项。四字状态机和地址公式字节比对不变，FIFO/PLL/刷新/IP及storage哈希不变。

7组验证通过：writer无描述和同高度连续两帧/延迟busy/尾包保护、50MHz同步高低/共同复位、24字正反行序及刷新暂停、顶层5场景启动/旧done/错误重试、完整TD零时层次、真实IP两帧16字，以及真实storage配测试memory的3场景782像素接线。真实IP完成均在末次App提交后120ns、Sdr_busy解除后32ns，busy=0后才done。同步代码不再有ack重复驱动和done同步寄存器未复位问题。

测试边界：真实IP时序使用测试台受控时钟并绕过PLL模型启动，没有改工程PLL或检查SDRAM物理内容/读回；storage接线回归用memory替身，不等于391字尾包已修好。metadata后的部分帧错误/abort仍可能保持占用，外部复位和实板时序仍待处理。详见[FRAME_COMPLETION_FIX.md](FRAME_COMPLETION_FIX.md)，[完整命令/源码哈希/结果](C:/Users/31640/Documents/ChatGPT/FFF/completion_minimal_fix_20261028/verification_results.json)。

## 2026-10-28 CDC修正验证与开发前Git检查点

用户已自行修正frame_desc_cdc中ack_sync的声明顺序。本轮直接使用当前生产文件快照编译和测试，未修改模块代码：原文件编译通过，20/8ns、8/20ns、14/22ns及20/20ns错相四种时钟组合各512组帧描述、共2048组传输全部通过；共同复位并错开释放后恢复测试通过。结果不再依赖上轮仅调整声明顺序的诊断副本。

两侧独立复位的协议边界仍沿用上轮记录：目标侧独立复位可能重放旧描述，源侧独立复位可能产生全零伪描述；当前实现需协调两侧复位。数字仿真未替代器件CDC时序签核。

当前frame_desc_cdc尚未加入TD文件清单，也未在memory_top中例化；memory仍未消费帧基址、宽高与方向，外部Reset_n和frame_write_done的内部逻辑仍待用户实现。下一步先在memory_top中接入CDC并建立描述先于像素生效的控制，再由用户扩展sdram_write_ctrl的帧基址/行列地址处理及完成条件。四字尾包和正式读采样问题继续独立跟踪。

按用户要求，准备把当前已有的storage MBR修复及回归资料、storage/memory接口、系统顶层接线、TD文件清单、用户新增并修正的CDC及同步文档一并保存为memory分支的本地Git检查点。本轮不改PLL、写控制器或其他模块逻辑；本地保存范围不含FFF临时仿真库。

[本轮真实CDC测试结果](C:/Users/31640/Documents/ChatGPT/FFF/git_checkpoint_20261028/cdc_results.json)。上轮错误定位与复位边界见[检查记录](C:/Users/31640/Documents/ChatGPT/FFF/project_review_20261028/README.md)。

## 2026-10-26 storage / memory 接口与系统顶层对接

**接口和接线已更新，memory内部帧逻辑由用户继续完成。** 按用户授权仅改memory端口，并补全hdmi_player_top；storage端口无需增删，全部实现保留。删除未定义的frame_id，新增21位字地址frame_base_addr、16位宽高、frame_top_down、frame_abort、Reset_n和预留输出frame_write_done；保留像素valid/data/ready及frame_start/end。frame_start来自meta_valid，frame_end来自storage.done，frame_abort来自error。

顶层补全SD SPI、复位释放、读取启动/文件选择、请求基址锁存、图像元信息、像素握手和状态。初始化完成前不启动或传像素。load_done表示源端成功结束，memory_frame_write_done另行表示真实帧写完；目前后者没有驱动。load_ready仅表示storage空闲且memory已初始化；后续启动下一帧、复用缓冲区还必须等待memory完成并处理错误恢复。TD添加5个源文件条目、顶层设为hdmi_player_top；未执行板级管脚/布局布线/时序签核。

- 真实工程ModelSim编译、零时刻层次加载：通过，0错误；保留两项参考IP常量告警和一项PLL模型位宽告警。
- 顶层接线功能测试：真实storage + SPI卡模型 + 测试memory接收模型，3场景通过；两次成功帧各391像素，共782像素和2314次背压保持检查；错误BMP返回0x20/abort后恢复成功。覆盖基址锁存、元信息、过早启动门控、长背压和源完成/写完成区分。
- 本轮边界：memory从localparam开始的模块体与修改前逐字节相同；新端口尚未驱动内部地址/复位/完成逻辑。模型接线测试不等于真实SDRAM帧地址功能验证。391字尾部3字等待、正式180度读采样问题及异步FIFO深度2边界仍在，不因端口修改而解决。
- 用户下一步：先在SYS_CLK域按frame_start锁存帧基址、尺寸与方向，再设计与125MHz写侧的可靠跨时钟控制、行地址、尾包/取消/复位及排空完成。完整约定见[STORAGE_MEMORY_INTERFACE.md](STORAGE_MEMORY_INTERFACE.md)。

[本轮命令、快照和结果](C:/Users/31640/Documents/ChatGPT/FFF/storage_memory_interface_20261026/results.json)。本轮未提交Git，原有未提交修改保留。

## 2026-10-26 storage MBR识别修复

**已修复并复测通过。** 仅修改fat32_bmp_reader，新增单次MBR回退；18项FAT专项、6项SPI专项、原92场景及5项背压共121场景通过。有效MBR和superfloppy均可读取，坏分区仍按原规则报错；其他RTL哈希未变。详见 [STORAGE_MBR_FIX.md](STORAGE_MBR_FIX.md)，随工程保留24项专项重跑入口。

用户已授权修复FAT32/MBR识别问题；先用成功加载为预期复现错误，再修改单一storage模块并重跑回归。每步完成即记录，未涉及memory尾包或模块对接。

- **baseline/targeted_fat**：修复前按成功加载预期测试；已复现0x34错误，正常MBR对照通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/baseline/targeted_fat/results.json)。

- **baseline/targeted_spi**：修复前按成功加载预期测试；已复现0x34错误，正常MBR对照通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/baseline/targeted_spi/results.json)。

- **应用修复，等待回归**：仅修改fat32_bmp_reader，新增MBR回退状态与LBA0探测标志；扇区0的完整BPB或几何校验失败且存在支持的分区时，转读分区启动扇区；进入分区读取后关闭再次回退。未修改memory及其他RTL。[差异与哈希](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/applied.json)。

- **fixed/targeted_fat**：通过；# MBR_REGRESSION_PASS cases=18 [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/targeted_fat/results.json)。

- **fixed/targeted_spi**：通过；# MBR_PIN_REGRESSION_PASS cases=6 [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/targeted_spi/results.json)。

- **fixed/bmp_stream_decoder**：通过；# PASS bmp_stream_decoder: 49 cases, randomized stalls and bubbles [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/bmp_stream_decoder/results.json)。

- **fixed/fat32_bmp_reader**：通过；# PASS fat32_bmp_reader: 24 cases, fragmented files/root, stalls, corruption [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/fat32_bmp_reader/results.json)。

- **fixed/sd_spi_reader**：通过；# PASS sd_spi_reader: 9 cases, SDHC/SDSC, CRC rejection, timeouts, recovery [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/sd_spi_reader/results.json)。

- **fixed/storage_pipeline**：通过；# PASS storage_pipeline: 6 pin-level end-to-end cases [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/storage_pipeline/results.json)。

- **fixed/hx4s20c_storage_bringup**：通过；# PASS hx4s20c_storage_bringup: 4 board-wrapper cases [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/hx4s20c_storage_bringup/results.json)。

- **fixed/backpressure**：通过；# STORAGE_BACKPRESSURE_PASS cases=5 pixels_per_case=391 normal_transaction=1 [记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_mbr_fix_20261026/fixed/backpressure/results.json)。

- **工程内重跑入口复核**：随工程保存的run_mbr_regression.py已在当前生产RTL上再次跑通18项FAT与6项SPI专项；这24项重复检查不另计入121场景。源码哈希与已测试修复一致。[入口](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/verification/storage_mbr_fix_20261026/README.md)。

## 2026-10-26 当前底层模块全面回归

以下为MBR修复前的历史快照；其中MBR失败已由上面的修复及新回归解决，其余问题状态不变。

**本轮已完成：30项验证任务，24项通过、1项仅诊断通过、3项既有功能失败复现、1项最小深度参数不支持、1项尾包限制确认。** 两项MBR复现属于同一缺陷。底层常用配置未见新的功能回归；当前顶层按用户要求作为未完成草稿隔离。新增问题为async_fifo的ADDR_WIDTH=1不能展开，当前深度16不受影响。正式读回1094个末字Z和MBR识别错误仍未修复；各任务证据如下。

本轮按用户要求冻结当前工作区，独立测试底层模块；memory_top与hdmi_player_top正在编写的接口/连接不作为底层失败项。验证夹具只存在FFF，实例化本轮当前底层RTL；不修改用户模块，不把历史测试结果直接当作本轮通过。每项完成即同步本节。

[完整回归记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/README.md)。

- **sync_w8_d2_10_10**：同步FIFO，宽8/深2，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/sync_w8_d2_10_10/results.json)。

- **sync_w8_d4_10_10**：同步FIFO，宽8/深4，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/sync_w8_d4_10_10/results.json)。

- **sync_w32_d16_10_10**：同步FIFO，宽32/深16，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/sync_w32_d16_10_10/results.json)。

- **sync_w56_d16_10_10**：同步FIFO，宽56/深16，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/sync_w56_d16_10_10/results.json)。

- **async_w8_d4_10_4**：异步FIFO，宽8/深4，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_w8_d4_10_4/results.json)。

- **async_w32_d16_10_4**：异步FIFO，宽32/深16，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_w32_d16_10_4/results.json)。

- **async_w56_d16_10_4**：异步FIFO，宽56/深16，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_w56_d16_10_4/results.json)。

- **async_w32_d16_4_10**：异步FIFO，宽32/深16，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_w32_d16_4_10/results.json)。

- **async_w8_d4_4_10**：异步FIFO，宽8/深4，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_w8_d4_4_10/results.json)。

- **async_w56_d4_10_4**：异步FIFO，宽56/深4，满空、随机背压、回绕和非空复位；两轮各4096有效条目；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_w56_d4_10_4/results.json)。

- **async_depth2_boundary**：异步FIFO深度2参数边界（ADDR_WIDTH=1）；未通过；见展开/仿真错误，不影响默认ADDR_WIDTH=4的独立结果 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/async_depth2_boundary/results.json)。

- **writer_unit_11**：写控制器历史11项自检查，当前新增pending输入在本组绑0；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/writer_unit_11/results.json)。

- **writer_sync_fifo**：实际同步FIFO到当前写控制器20字；其中占用标志中途注入仅验证输出行为；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/writer_sync_fifo/results.json)。

- **writer_pending**：pending禁止新组、已开始四拍完成、下一组等待后恢复；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/writer_pending/results.json)。

- **writer_tail**：四字尾包限制：391字只输出388字、缓存3字；392字对照全部输出，尚无尾包协议 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/writer_tail/results.json)。

- **refresh_unit_7**：刷新仲裁7项，包括手动/周期相邻、排空、超时锁存与复位；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/refresh_unit_7/results.json)。

- **pll**：实际PLL行为模型50MHz输入、100/125/125MHz输出及180度相位；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/pll/results.json)。

- **storage_bmp_stream_decoder**：storage历史回归49场景，生产模块为当前快照；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/storage_bmp_stream_decoder/results.json)。

- **storage_fat32_bmp_reader**：storage历史回归24场景，生产模块为当前快照；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/storage_fat32_bmp_reader/results.json)。

- **storage_sd_spi_reader**：storage历史回归9场景，生产模块为当前快照；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/storage_sd_spi_reader/results.json)。

- **storage_storage_pipeline**：storage历史回归6场景，生产模块为当前快照；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/storage_storage_pipeline/results.json)。

- **storage_hx4s20c_storage_bringup**：storage历史回归4场景，该组独立包装层来自历史提交，仅作补充；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/storage_hx4s20c_storage_bringup/results.json)。

- **storage_backpressure**：storage首/行末/中/末及随机背压5项，最长200微秒、每项391像素；通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/storage_backpressure/results.json)。

- **mbr_fat_probe**：既有MBR识别缺陷：仅改引导代码3字节，合法分区卡只读LBA0即0x34，扇区接口层复现 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/mbr_fat_probe/results.json)。

- **mbr_pin_probe**：既有MBR识别缺陷在SPI引脚完整链路复现；不是新增回归通过项 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/mbr_pin_probe/results.json)。

- **refresh_idle**：512微秒真实IP刷新场景：idle；50MHz异步写入、125MHz后端；通过；请求/确认/占用/命令=34/34/34/34；最长pending→命令=92.0ns，命令间隔=15000.0ns [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/refresh_idle/results.json)。

- **refresh_continuous**：512微秒真实IP刷新场景：continuous；50MHz异步写入、125MHz后端；通过；请求/确认/占用/命令=34/34/34/34；最长pending→命令=212.0ns，命令间隔=15064.0ns [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/refresh_continuous/results.json)。

- **refresh_pause**：512微秒真实IP刷新场景：pause；50MHz异步写入、125MHz后端；通过；请求/确认/占用/命令=34/34/34/34；最长pending→命令=212.0ns，命令间隔=15064.0ns [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/refresh_pause/results.json)。

- **sdram_formal_180**：正式125MHz/180度的11场景写入、模型存储与读回；独立夹具隔离未完成顶层；统计={"cases": 11, "accepted": 4376, "app_writes": 4376, "reads": 4376, "physical_writes": 1094, "physical_reads": 1094, "physical_refreshes": 57, "write_refresh_overlap": 0, "data_errors": 1094, "storage_checks": 4376, "storage_errors": 0, "coverage_errors": 0}；模型时序错误=0 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/sdram_formal_180/results.json)。

- **sdram_diagnostic_270**：仅测试台270度采样诊断；未改工程PLL，不能计入正式读回通过 [记录](C:/Users/31640/Documents/ChatGPT/FFF/lower_modules_regression_20261026/tests/sdram_diagnostic_270/results.json)。

## 2026-10-26 异步FIFO接线与storage背压验证

- 用户已将memory_top内同步FIFO换为async_fifo，wr_clk接SYS_CLK（50MHz），rd_clk接Clk（125MHz），32位、深度16；助手只检查和验证，未改模块实现。用户同时整理的sdram_refresh_ctrl注释经去注释比较无逻辑变化。
- 当前顶层真实IP/器件模型写入测试通过：上游50MHz域接受1024字，应用写1024拍、物理WRITE256组，模型存储1024字全部正确，覆盖初始化等待、FIFO满背压及1次自然刷新。尚未验证读回或硬件复位释放时序。
- storage背压5场景通过：首像素、行末、最后像素分别停顿1000个50MHz周期（20µs），中途停顿10000拍（200µs），以及随机背压。每场景391像素地址/颜色/坐标/标志正确；有效像素等待时所有载荷及valid保持，恢复后不丢不重，最后像素握手前不done。
- pixel_ready低表示没有交付，已有待传像素应保持valid为1。空输出寄存器可以先缓存一个像素，SD已发起读取也可完成并缓存；不等于所有内部活动立即停止。复位/abort/读卡错误中止另按帧作废处理。
- 接口后续约定：按50MHz侧full及memory可用状态形成pixel_ready，FIFO写使能以pixel_valid与pixel_ready同拍成立为准；复位时full为0不能单独作为可用依据。当前FIFO仍仅32位数据，像素地址/帧协议以及两域同步释放复位仍待用户完善。
- [完整报告、当前源码快照与命令日志](C:/Users/31640/Documents/ChatGPT/FFF/async_fifo_storage_ready_20261026/README.md)。本轮未改PLL、模块代码，也未将storage实际接入memory；原有读采样及MBR识别问题继续跟踪。

## 2026-10-26 storage与memory对接前检查点

- 用户要求再次检查并保存当前Git版本，后续由用户自行连接两个模块；继续使用memory分支，保存基线为0e5c450之后的当前工作区。
- 本次两个RTL文件的差异均为用户新增注释：sdram_refresh_ctrl的interval_count说明，以及sdram_write_ctrl中Sdr_refresh_pending启动条件说明。去除注释与空白后和原提交逐项相同，逻辑未变；原样保存用户注释，没有代写连接代码。
- 注释精度提示：interval_count实际为0到INTERVAL_CYCLES-1，默认0～1874，1875拍为15µs；用户新增注释写到INTERVAL_CYCLES，尚未替用户改动。
- 对接状态仍为：storage输出尚未连接memory_top，现有TD顶层和清单仍为memory部分；50/125MHz跨域、像素地址/颜色、四字分组和帧排空完成由用户后续实现。
- 本日对接前独立测试已验证56位、深度16的async_fifo在50MHz写/125MHz读下，复位前后各4096条地址与颜色正确，覆盖满空、随机背压、回绕和有数据时共同复位；尚非硬件CDC时序签核。391字尾部检查为388字输出、3字留在预取缓存且FIFO空；392字对照全部输出。详见 [对接检查和独立测试记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_memory_readiness_20261026/README.md)。
- 本次检查未重跑功能仿真：两处变化只涉及注释，历史通过及已知失败按原测试配置保留。1094次正式180°读回错误、MBR识别兼容性问题及整机联调仍未解决。
- [本次保存前核对及源码快照](C:/Users/31640/Documents/ChatGPT/FFF/checkpoint_storage_memory_20261026/checks.json)。

## 2026-10-26 GitHub工程同步

- 已获取GitHub `origin/main` 的 `74ebebc`（合并storage PR #2），合入本地 `memory` 分支。合并前本地检查点为 `2690162`，已有PLL、FIFO、SDRAM及刷新修复提交保留，无合并冲突。
- 本轮接收4个storage RTL：`storage_pipeline`、`sd_spi_reader`、`fat32_bmp_reader`、`bmp_stream_decoder`，以及 `docs/storage.md`。每个新文件的Git对象与远端main一致；除本进度文档外，原有受版本控制文件内容未改变。
- Icarus以Verilog-2005模式编译 `storage_pipeline` 及三个子模块通过。这里只确认新文件语法和模块依赖，本轮没有重新运行功能仿真，没有把storage接入memory_top或修改TD源文件清单。
- 2026-10-25审核中原有92个场景已通过（其中4项属于恢复的历史独立包装层）；新增MBR识别测试复现的0x34错误仍在当前同步版本中，本轮没有修改队友实现。审核证据见 [storage审核记录](C:/Users/31640/Documents/ChatGPT/FFF/storage_review_20261025/REVIEW.md)。
- 后续联调仍需处理像素地址、50/125MHz时钟域、四字组对齐及末尾不足4字、写事务排空后换帧。同步不代表这些接口已接通，也不改变正式180°配置1094次末字读回错误的状态。
- [本轮文件一致性和编译记录](C:/Users/31640/Documents/ChatGPT/FFF/github_sync_20261026/verification.json)。

## 2026-10-25 迭代修复与逐步验证

用户授权：先提交当前版本，再按测试证据修改工程；每步测试完成即同步本节。检查点为 `6a6fc1c`，保留原始故障供对照。

- **busy_gate/continuous**：执行失败。来源：`candidate_busy`。这是隔离候选副本，尚未应用到工程的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/busy_gate/continuous/results.json)。

- **explicit_refresh/continuous**：通过执行。来源：`candidate_refresh`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是隔离候选副本，尚未应用到工程的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/explicit_refresh/continuous/results.json)。

- **explicit_refresh/idle**：通过执行。来源：`candidate_refresh`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是隔离候选副本，尚未应用到工程的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/explicit_refresh/idle/results.json)。

- **explicit_refresh/pause**：通过执行。来源：`candidate_refresh`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是隔离候选副本，尚未应用到工程的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/explicit_refresh/pause/results.json)。

- **refresh_matrix_180**：完整11场景回归未全部通过；统计={"cases": 11, "accepted": 4376, "app_writes": 4376, "reads": 4376, "physical_writes": 1094, "physical_reads": 1094, "physical_refreshes": 60, "write_refresh_overlap": 0, "data_errors": 1094, "storage_checks": 4376, "storage_errors": 0, "coverage_errors": 0}；模型时序错误=0。使用工程125MHz/180° PLL；已知末字读采样故障单独统计，不以存储检查替代读回通过。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/refresh_matrix_180/results.json)。

- **refresh_matrix_phase270_diagnostic**：完整11场景回归通过；统计={"cases": 11, "accepted": 4376, "app_writes": 4376, "reads": 4376, "physical_writes": 1094, "physical_reads": 1094, "physical_refreshes": 60, "write_refresh_overlap": 0, "data_errors": 0, "storage_checks": 4376, "storage_errors": 0, "coverage_errors": 0}；模型时序错误=0。仅测试台将SDRAM时钟移到270°进行读采样诊断，工程PLL未改。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/refresh_matrix_phase270_diagnostic/results.json)。

- **refresh_unit**：刷新仲裁器6项单元测试失败：初始化前抑制、精确周期、手动请求保持高仅触发一次、写/读/下游忙排空与静默保护、确认超时锁存、故障及忙中复位。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/refresh_unit/results.json)。

- **refresh_unit_harness_fixed**：刷新仲裁器6项单元测试通过：初始化前抑制、精确周期、手动请求保持高仅触发一次、写/读/下游忙排空与静默保护、确认超时锁存、故障及忙中复位。前次测试的6项断言实际均通过，但测试台$finish被onbreak按退出码1处理；已修复测试结束方式，未更改RTL。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/refresh_unit_harness_fixed/results.json)。

- **apply_verified_refresh**：已应用通过的刷新仲裁候选：新增调度器、写启动pending门控、顶层单一请求来源、TD源清单和旧测试台端口绑0。PLL、加密IP、FIFO哈希与检查点相同；准备生产文件复测。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/applied.json)。

- **production_refresh/continuous**：通过执行。来源：`production`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是工程源码的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/production_refresh/continuous/results.json)。

- **refresh_unit_deadline_overlap**：刷新仲裁器7项单元测试失败：原6项外增加手动请求紧邻周期到期，要求该请求满足本次刷新而不误报超时；完整仿真日志保留。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/refresh_unit_deadline_overlap/results.json)。

- **refresh_unit_deadline_fixed**：刷新仲裁器7项单元测试通过：原6项外增加手动请求紧邻周期到期，要求该请求满足本次刷新而不误报超时；完整仿真日志保留。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/refresh_unit_deadline_fixed/results.json)。

- **apply_deadline_fix**：手动请求紧邻周期到期会误置refresh_error，已复现并修复：接收新的手动请求时重新开始周期计时；忙中额外手动边沿仍合并。新增第7项单元测试修复前失败、修复后通过，已应用工程，准备最终复测。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/applied_final.json)。

- **production_final/idle**：通过执行。来源：`production`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是工程源码的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/production_final/idle/results.json)。

- **production_final/continuous**：通过执行。来源：`production`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是工程源码的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/production_final/continuous/results.json)。

- **production_final/pause**：通过执行。来源：`production`。请求/确认/占用/实际刷新次数=34/34/34/34；最大请求到后续刷新=60.0ns，未响应请求=0。这是工程源码的结果；PLL配置未改。[记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/production_final/pause/results.json)。

- **production_matrix_180**：完整11场景回归未全部通过；统计={"cases": 11, "accepted": 4376, "app_writes": 4376, "reads": 4376, "physical_writes": 1094, "physical_reads": 1094, "physical_refreshes": 57, "write_refresh_overlap": 0, "data_errors": 1094, "storage_checks": 4376, "storage_errors": 0, "coverage_errors": 0}；模型时序错误=0。使用工程125MHz/180° PLL；已知末字读采样故障单独统计，不以存储检查替代读回通过。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/production_matrix_180/results.json)。

- **production_matrix_phase270_diagnostic**：完整11场景回归通过；统计={"cases": 11, "accepted": 4376, "app_writes": 4376, "reads": 4376, "physical_writes": 1094, "physical_reads": 1094, "physical_refreshes": 57, "write_refresh_overlap": 0, "data_errors": 0, "storage_checks": 4376, "storage_errors": 0, "coverage_errors": 0}；模型时序错误=0。仅测试台将SDRAM时钟移到270°进行读采样诊断，工程PLL未改。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/production_matrix_phase270_diagnostic/results.json)。

- **final_source_and_results_audit**：最终生产RTL哈希与测试输入一致；PLL/IP/FIFO哈希与检查点相同，TD的10项源文件存在且编译顺序连续。三场景请求/确认/占用/命令逐项匹配，最长16ns/24ns/60ns，pending到刷新最长196ns，实际刷新间隔最长15.064µs。7项单元通过；正式配置4376字存储正确但1094读回错，270°诊断全通过。此检查不等于TD综合或时序签核。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/final_summary.json)。

- **saved_rerun_entrypoint**：随工程保存的run_refresh.py重跑入口编译及1µs观察器绑定检查通过，源码未改变；只是入口复核，完整功能结论以production_final和production_matrix记录为准。 [记录](C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025/final_summary.json)。

## 当前重点问题（2026-10-26）

读采样、刷新调度、文件系统识别和FIFO参数边界分别跟踪。四字写数据已正确进入参考模型，不把读回Z统称为写入失败；未完成的系统连接不计底层失败。

| 编号 | 问题 | 当前状态 |
| --- | --- | --- |
| 1 | 1094次每组第四字返回Z | 已定位参考模型下的读捕获窗口不匹配；未修复，原125MHz/180°配置读回仍失败 |
| 2 | 连续供数时实际刷新延后 | 15µs仲裁已修复，本轮异步夹具三场景及逐拍测试通过；实板及长期保持未验证 |
| 3 | MBR卡被误判superfloppy | 已修复单次回退路径，18项FAT及6项SPI专项通过，原storage回归及背压通过；实卡待验证 |
| 4 | async_fifo最小深度 | 新发现ADDR_WIDTH=1展开失败；当前ADDR_WIDTH=4以及2均通过 |

### 问题1：第四字读回Z（读采样问题）

- 2026-10-24共4376字、1094组测试：应用写拍和模型存储内容全部正确，物理DQ也输出第四字；应用返回每组第四字为Z，共1094错。这批错误不是第四字漏写的证据。
- 当前125MHz周期为8ns，逻辑与SDRAM时钟相差180°。以最后字的SDRAM发数沿为0，参考模型的末字有效窗为5.5～10.5ns，两个相邻逻辑采样沿为4ns、12ns，均不在窗口内。控制器先捕获Z，测试台随后才消费该Z；单纯延后比较不能修复。
- 2026-10-25新版本单组四字复现相同窗口。上轮仅在测试台覆盖移相输入为270°时，4376字读回0错；没有把270°写入工程，该历史诊断因刷新覆盖不足未整体通过；本轮刷新修复后的270°诊断11场景已全通过，但仍未改工程PLL。
- 结论适用于IS42s32200 -7参考模型与当前配置组合；不能据此宣称实物EM638325必然失败。模型无输入时序ERROR，也不等于FPGA端读捕获满足时序。
- 下一步：结合EM638325速度档参数、FPGA输入建立/保持及TD时序核定PLL相位与读捕获安排；确认方案后再修改，并对正式配置执行正常及刷新交叉读回回归。
- 证据：[根因复核及当前版本复现](C:/Users/31640/Documents/ChatGPT/FFF/sdram_read_z_root_cause_20261025/README.md)、[4376字正式回归与相位诊断](C:/Users/31640/Documents/ChatGPT/FFF/sdram_functional_20261024/README.md)。

### 问题2：连续四字组供数时的刷新执行等待

- 原逻辑仍为四字一组，组间有间隙；`Sdr_init_ref_vld` 只表示初始化/刷新实际占用，不表示待处理请求。基线512µs连续写入16请求、0确认、0实际刷新，最早等待至少480.828µs；暂停后才刷新，不能指望PREFETCH的占用检查自行终止内部持续忙。
- Etron EM638325 Rev1.4要求4096次刷新/64ms，均摊15.625µs；不能将2048行直接当成刷新次数。新调度器每15µs置pending，完成当前四拍后阻止新组，等待应用和下游空闲连续4拍，再单拍请求；占用拉高、解除且下游空闲后释放pending。内部周期发生器关闭，避免双重调度。
- 2026-10-25的三个512µs生产测试均34/34/34/34、最长pending→命令196ns；2026-10-26采用50MHz异步输入独立夹具重跑，三个场景仍各34/34/34/34，最长pending→命令212ns、IP请求→命令60ns、命令间隔15.064µs。本轮11场景4376字落存0错，刷新覆盖/写占用重叠均0，4096字连续写阶段刷新6次；当前接口草稿未参与该夹具。
- 仅加Sdr_busy启动门控的候选出现间隔8ns的两条刷新及tRC错误，已拒绝，不加入工程。
- 7项仲裁单元测试通过，包含修复后的手动/定时交界；超时将锁存内部refresh_error并保持禁止启动；当前LED仍仅指示初始化。后续读控制器也须遵守pending禁止新组并与写互斥。
- 本次已按用户授权修改RTL及工程源清单；逐步候选结果和生产复测分开保留。没有更改PLL、加密IP、FIFO；正式读回错误尚存，无板级与长期数据保持通过证据。完整记录见 [SDRAM_REFRESH_VERIFICATION.md](SDRAM_REFRESH_VERIFICATION.md)。

## 模块与工程状态

| 部分 | 当前已完成或已确认 | 尚需完成或核实 |
| --- | --- | --- |
| 同步 FIFO `sync_fifo` | 本轮4组参数回归通过：8/32/56位、深度2/4/16的选定组合；满空、并发、回绕、非空复位；32位FIFO到writer的20字也通过 | 其他参数、综合推断和实际时序需按使用配置验证 |
| 异步 FIFO `async_fifo` | 本轮6组参数回归通过：8/32/56位、深度4/16、50→125MHz及125→50MHz；满空、回绕、背压和共同复位通过 | ADDR_WIDTH=1（深度2）位选越界无法展开；实际CDC、复位释放及Gray总线约束待检查 |
| 写控制器 `sdram_write_ctrl` | 本轮11项单元/306次写拍通过，pending启动/中途交界检查通过；四拍连续、地址/数据/DM正确 | 仍要求四字成组；391字只出388，尾部/帧地址与排空协议待后续扩展 |
| FIFO → 写控制器 | 当前同步FIFO20字检查通过；异步FIFO→当前写入/刷新/IP独立夹具4376字应用写及模型落存正确 | 系统顶层连接由用户继续处理；正式读回仍失败，尾包和帧协议待完善 |
| 存储顶层 `memory_top` | 已有FIFO/写入/刷新/SIP连接基础，历史1024字接线检查通过；当前正在重构像素/帧接口 | 本轮隔离该接口草稿，未宣称它当前编译或整机通过；上游接口/复位/地址仍由用户完善 |
| 公共参数 `include/global_def.v` | 数据 32 位、地址 21 位、DM 4 位、行 11 位、BANK 2 位；125 MHz 计时宏已修复分组，常量及两次自动请求检查通过 | 旧内部周期发生器已关闭，该宏当前不控制实际刷新；新仲裁器按1875拍周期运行 |
| PLL `clk_pll` | 本轮真实行为模型周期及相位检查通过：50MHz输入，100/125/125MHz输出，后两路180度 | 正式180度读捕获仍不匹配参考模型；硬件冷启动、板级时序尚未验证 |
| SDRAM 控制器与器件模型 | 本轮原样参考IP和IS42s32200模型完成11场景4376字回归，写入存储0错；三种刷新场景通过 | 正式180度读回1094错；270度仅测试台诊断通过，实板/时序签核待完成 |
| SDRAM 读通路与帧缓存管理 | 当前目录中未发现实现 | 读请求、显示供数、帧地址管理与读写协调 |
| 存储与显示接口 | `docs/.gitkeep` 中有像素接口草稿，包括 pix_clk、pix_req、frame_sync、pix_rgb、pix_valid、frame_ready、pix_underflow | 整理为正式接口文档，明确时钟、复位、请求与返回时序，并落实到 RTL |
| SD 卡与 BMP 解析 | MBR误识别已修复；18项FAT和6项SPI专项通过；原88项直接测试、4项历史包装层及5项背压全部通过 | 真实卡、外部时序和整机接口留待后续；修复后TD时序需重新核定 |
| HDMI 显示与音频 | 本地 `display.v` 为空模块 | 有效实现、显示通路集成与测试；其他成员的外部进度不在本次核对范围内 |
| TD 综合与约束 | `memory` 分支源清单包含参数头文件、PLL、FIFO、写控制器、三个 IP 文件及 `memory_top`，顶层设为 `memory_top`；目标 EG4S20BG256 | 仅完成工程配置，尚未运行新顶层综合；旧报告仍对应 `async_fifo`；约束、布局布线、时序与上板待完成 |

## 2026-10-24 SDRAM模型写读回与刷新交叉回归

**当前125MHz/180°配置整体测试失败。** 本轮仅新增独立测试台、模型副本及验证记录，没有修改工程模块、PLL、计时参数或用户现有测试台。

- 11场景共4376个上游字、1094组四拍；4376应用写拍及物理模型存储逐字检查正确。应用接口返回4376字，其中每组第四字为Z，共1094错，不能认定完整读回通过。
- 四拍各消费位置分别请求刷新，真实IP均把占用和AUTO REFRESH延后；无App写拍与真实刷新占用重叠。真实刷新已有效时供数，新组等待解除后启动的检查通过。这不等于验证了人为强制刷新有效时仍续写三拍安全。
- 连续4096字写窗口98.232μs内没有实际AUTO REFRESH，前后命令最大间隔99.544μs；预期至少两次实际刷新的覆盖未达成。模型不模拟长期缺刷新数据衰减，刷新预算仍未解决。
- 第四字确实正确写入并从物理DQ输出，但当前控制器捕获比模型最后数据有效窗晚1.5ns。仅测试台改为270°的诊断可使4376字全部读回正确；该诊断仍存在刷新覆盖问题，不等于工程或实板通过，未把270°写入PLL。
- 正式回归使用原样IS42s32200 -7参考行为模型，未放宽模型参数，未强制刷新状态、ACK或返回数据；模型没有报告内置时序ERROR。PLL模型启动仍使用200ns测试台复位，原硬件冷启动未验证。
- 详细矩阵、波形、日志、输入哈希、失败和诊断记录见 [功能回归报告](C:/Users/31640/Documents/ChatGPT/FFF/sdram_functional_20261024/README.md)。当前优先项改为读捕获时序及连续写刷新等待预算。

## 2026-10-24 初始化状态指示 Check_ok

- 用户选择让LED暂时表示“PLL锁定且SDRAM初始化完成”。新增组合赋值 `Check_ok = lock && Sdr_init_done`，保持现有LED连接；无锁定或初始化未完成时为0，两者成立时为1。周期刷新不使初始化失效，因此不把刷新占用标志加入这个条件。
- 这只是初始化状态，既不是写入接收握手，也不是存储数据校验通过；LED实际亮灭还取决于板卡极性。
- 保留用户新增的两个 `App_rd_*` 赋零。移除 `assign Sdr_rd_en = 0`：该信号是IP输出，额外驱动会与IP冲突。
- 真实PLL与SDRAM控制器连接的独立测试台先对PLL模型注入200ns复位，再检查锁定前LED为0、初始化完成后LED为1，随后5000个125MHz周期保持为1；强制锁定状态为0后LED立即为0。ModelSim运行1.2ms，输出 `MEMORY_READY_PASS`。测试不涉及存储数据读回。
- 原顶层PLL复位固定0时，本次仿真在1.19ms仍未锁定；失败记录保留在验证目录的without_pll_reset中。带测试台复位的通过不能证明原硬件顶层的冷启动或失锁恢复设计已验证，相关复位策略仍待后续核实。
- 差异、测试台、完整命令和日志见 [Check_ok验证记录](C:/Users/31640/Documents/ChatGPT/FFF/check_ok_20261024/README.md)。FIFO、写控制器、供应商IP、计时头文件及用户测试台保持原样，未创建新Git提交。

## 2026-10-24 物理 SDRAM 原语接入

- 经用户明确授权，在 `memory_top` 新增内部物理信号：时钟及 RAS/CAS/WE 各1位、BA 2位、ADDR 11位、DM 4位、双向DQ 32位；显式声明 `Sdr_busy`。
- 新增 `EG_PHY_SDRAM_2M_32 u_sdram_phy`，连接控制器的物理接口，片选接0、时钟使能接1，DM按四个独立字节端口连接。接线对照 APUG011 原始 `top.v` 与本机 TD6.2 器件模板。
- 该原语由 EG4S20 器件库提供；TD 工程无需加入供应商仿真模型源码，也无需把这些合封器件内部连接添加为外部板级引脚。
- ModelSim 编译及0ns层次加载通过，并加载 `eg.EG_PHY_SDRAM_2M_32`；原BA/ADDR/DM/DQ四类宽度警告消除，保留供应商常量及PLL端口的3条警告。检查不推进数据传输，不能据此认为SDRAM读写或刷新执行已经通过。
- 修改差异和验证凭据见 [SIP接入记录](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sip_integration_20261024/README.md)。本次未修改 FIFO、写控制器或用户现有测试台，未新增Git提交。

## 2026-10-24 刷新计时宏修复

- 经用户明确授权，仅给 `SDR_CLK_PERIOD` 与 `SELF_REFRESH_INTERVAL` 增加表达式分组括号，避免文本宏展开改变除法结合顺序；用户模块、测试台和供应商 IP 均未改写。
- 修复前 ModelSim 对照检查复现 `period=8 interval=0`，测试按预期失败。修复后为 `period=8 interval=3906`，提前请求比较值为 3896；另检查了宏作为除数时的分组效果。
- 以真实 `sdr_init_ref.enc.v` 在 125 MHz 下运行至初始化完成及两次自动请求：首请求在初始化完成后 3897 拍，两次请求间隔 3907 拍（31.256 μs），请求宽度各一拍。运行至 1.2 ms，退出 0，保留一条供应商未定宽常量警告。
- 本次固定手动刷新请求、刷新确认和读写活动输入为 0，仅验证自动请求调度；没有验证刷新确认、物理刷新命令或 SDRAM 数据保持。现有计数为 0 到 3906，含端点；若按 2048 次估算约 64.012288 ms，刷新预算及等待余量仍需单独核对，不能宣称器件 64 ms 要求已满足。
- 完整命令、源码哈希、修复前后头文件、测试台和日志保存在 [刷新宏验证记录](C:/Users/31640/Documents/ChatGPT/FFF/refresh_macro_fix_20261024/README.md)。修复应用时核对工程头文件与已测试副本逐字节一致。

## 2026-10-23 新增顶层与检查结果

用户在原工程新增 `rtl/memory/memory_top.v` 和 `include/global_def.v`。当前静态核对通过的连接包括：

- 上游 `wr_en`、32 位 `wr_data` 和 `full` 接到同步 FIFO 写端；FIFO 的独立地址宽度为 4，深度 16，不与 SDRAM 的 21 位地址宏混用。
- FIFO 读数据为 32 位，读使能、读有效和空标志与写控制器连接，FIFO 和写控制器共用 `Clk`。
- PLL 未锁定时 FIFO、写控制器和 SDRAM IP 都复位；锁定后两种复位极性分别释放。此处只确认逻辑电平关系，未验证实际复位释放时序。
- 写控制器的 `App_wr_*` 输出送入 IP，初始化和刷新状态从 IP 返回。

接入前编译诊断见 `memory_top_review_20261023/write_ports_recheck.log`：当时端口分隔符和宏未定义错误已消除，但缺少 `clk_pll`、`sdr_as_ram`。这是历史失败记录；本轮导入后已经解决缺失模块引用。普通沙箱中的工具 DLL 重定位/异常退出通过沙箱外运行 ModelSim 验证处理，不能把启动异常当作 RTL 通过或失败的依据。

### memory 分支的 IP 接入验证

- `main` 保留检查点 `ae419c6`，后续本轮修改在 `memory` 分支进行。
- PLL 来自 HX4S20C 配套 `lab_ex4_tf` 的 `sys_pll.v/.ipc`。导入副本仅适配模块名和生成文件名；PLL 原语参数保持供应商配置。原 APUG011 的旧 25 MHz PLL 未混入。
- APUG011 三份加密控制器文件原样导入，现有用户模块实现未改写。只有计时配置头文件从 150 MHz 同步为 125 MHz。
- ModelSim SE-64 2020.4 编译供应商库、IP 和当前层次均退出 0；保留内部访问的 `memory_top` 加载并运行 0 ns 成功。这个检查证明依赖可解析，不代表存储功能通过。
- 层次加载仍报告 SDR_BA、SDR_ADDR、SDR_DM、SDR_DQ 的位宽警告，以及原厂参考代码中未定宽常量与 PLL load_reg 端口的警告；未通过隐藏这些警告获取结果。
- PLL 测试以 50 MHz 驱动原厂行为模型，检查锁定后 C0 周期 10 ns、C1/C2 周期 8 ns、相位间隔 4 ns。PASS 时已检查 16/20/20 个周期及 21 次相位，时间 1111.200 ns；批处理运行到 50 us 退出 0。它不是板级时序结果。
- 记录、测试台和重跑入口随工程保存于 `verification/ip_integration_20261023`。验证在 FFF 暂存副本执行；导入时核对文件 SHA-256 一致。

当前仍需由用户处理的内容：

1. PLL 与控制器依赖已导入；后续修改时钟配置时，需继续保持刷新参数一致，并验证实际器件时序。
2. 用户已将 `App_rd_en`、`App_rd_addr` 固定为0，停用读请求；助手移除对IP输出 `Sdr_rd_en` 的额外赋零，保持输出由IP驱动。
3. SDRAM 物理信号位宽及 SIP 原语例化已于2026-10-24补齐；继续验证器件命令、刷新执行与数据读回。
4. `Sdr_busy` 已声明；`Check_ok` 已按用户选择驱动为PLL锁定且初始化完成，LED不表示写入、读回或数据校验通过。
5. 确定上游写信号所在时钟域。当前同步 FIFO 要求写数据与内部 `Clk` 的采样时序匹配；若后续上游使用其他时钟域，需要重新设计跨域连接。
6. TD 文件清单与顶层已更新；后续在补齐物理连接和约束后运行综合与实现。上游时钟域和接口采样约定仍需明确。

## 历史已通过仿真（2026-10-22）

### 写控制器自动测试

2026-10-22 使用本机 **Icarus Verilog** 编译和运行：`iverilog -g2012 -Wall`、`vvp -n`。独立测试台放在本工作目录，原工程的 `tb/memory/sdram_write_ctrl_tb.v` 仍为 0 字节。

11 项测试全部通过，仿真时间 12,700 ns，逐次检查 306 次写入的数据、地址和字节掩码。覆盖复位与空闲、四字连续输出、多组地址递增、初始化前等待、刷新前等待、FIFO 缺数与恢复、返回延迟，以及预取和写入中的共同复位；另完成间歇供数下的 64 组、256 字测试。

306 次中包含复位打断前已输出的 2 次写入。复位测试采用 FIFO 模型与控制器共同复位，没有验证控制器单独复位后仍收到外部旧响应的情形。

### 真实同步 FIFO 集成

原 `sync_fifo` 配置为 32 位、深度 16，连接原 `sdram_write_ctrl`。测试中 20 个字经过 FIFO 后正确输出，地址为 0–19；五组写入均恰好连续四拍。初始化等待、刷新信号已有效时禁止启动、两字断流等待与恢复均通过。仿真时间为 1,560 ns。

### 波形检查状态

两套测试均生成了 VCD。通过结论来自测试台自动检查和日志；**尚未在 ModelSim 或其他波形查看器中查看这些 VCD，也未直接解析其信号变化**。ModelSim 并未用于上述两套新增测试。

原 `docs/sync_fifo.md` 记录了历史 ModelSim 验证。该历史记录保留，但当前启用的 FIFO 测试激励与本次日志不足以复现文档列出的全部边界场景，应另行补充用例或历史记录。

## 已核实的硬件与参考接口

资料来自 `C:\Users\31640\Desktop\FPGA_Projects\HX4S20_Contest_202606`；详细出处和页码见 FFF 的 `reference_audit_20261023/资料提取摘要.md`。

- 赛题平台为 HX4S20C，较早手册称 HX4S20；核心 EG4S20BG256，与 EM638325 SDRAM 合封，容量 2M×32 bit，即 8 MiB。板载输入晶振为 50 MHz。
- APUG011 v1.2 的 `sdr_as_ram` 接口与当前模块对应：数据 32 位、地址 21 位、DM 4 位。按参考配置每地址对应一个 32 位字，加 1 为 4 字节。
- 四字为一组，共 16 字节，组首低两位为 00，组内递增、组间可跳转。应用层读写必须互斥。
- 应用掩码每位对应一字节，1 为屏蔽；当前 0000 是整字写入。部分字节写入及物理 DM 的处理仍需实际 IP 验证。
- 初始化完成、初始化/刷新有效标志为低后开始读写；接口没有逐拍 ready/ack。明文部分表明 `Sdr_init_ref_vld` 是初始化或刷新占用标志，刷新请求另有信号。
- 参考顶层原用控制器定时刷新；本项目2026-10-25已切换到应用侧15µs调度，关闭内部周期发生器，App_ref_req由仲裁器驱动。部分内部协调逻辑加密，无法据资料确认中途刷新时剩余拍的接收保证。
- 手册对 `Sdr_busy` 存在“暂不使用”与“操作前检查”的不一致，保留为待核实项，不把它直接解释为 ready。

旧 APUG011 PLL 按 25 MHz 输入设计，参考测试台却使用 80 ns 输入周期，即 12.5 MHz，与其声明不一致。本轮已改用配套板卡例程的 50 MHz 输入 PLL，存储时钟为 125 MHz。`SDR_CLK_PERIOD` 只是计时参数，不会改变 PLL 输出频率。

参考包包含 ModelSim 脚本和器件模型 `IS42s32200.v`；该模型名称不代表实际合封器件型号。旧脚本和旧日志不作为本轮通过证据。2026-10-24已使用本机安路库及原样参考器件模型执行写读回，当前配置失败，详见本轮功能回归记录。

## WRITE 期间出现刷新的待办

**已验证输出行为，尚未验证真实存储结果。**

集成测试在第四组首字（地址 12）输出后拉高 `Sdr_init_ref_vld`。当前 RTL 在标志有效时继续输出地址 13、14、15 的三个字，然后等待标志解除才启动下一组。

这项测试按当前 RTL 的“继续完成已启动的四字输出”设置预期，明确允许这三拍重叠。日志的 `INTEGRATION_PASS` 表示满足这套预期，不能用来证明刷新期间的数据最终写入正确。

待确认的问题：

1. 参考明文已确认该标志表示初始化或刷新占用；它与内部请求、应答和实际器件命令的完整时间关系仍需核实。
2. 下游是否保证一组四字输入一旦开始就连续接收？若下游不能接收，内部缓冲如何处理？当前应用写接口没有逐拍接收确认输入。
3. 参考 IP 内部存在读写/刷新握手，但主体加密；应用层应配合启动门控与读写互斥。先确认真实接收行为，再决定是否修改当前写控制器。
4. 接入实际 SDRAM 控制器与器件模型后，覆盖写入前、首拍附近和四拍中途出现刷新，写入后逐字读回比较，确认地址、数量、顺序及数据均正确。

2026-10-24已补充真实控制器加行为模型的测试：合法请求触发的实际刷新延后，无四拍重叠；4376字模型落存正确，应用读回与连续写刷新预算仍有问题。真实器件上板尚未验证，不能认定刷新协调已完全解决。

## 综合记录的使用范围

本轮 `memory` 分支将 `project/td/HDMI_Player.al` 的顶层改为 `memory_top`；保留的旧 `syn_1` 报告仍标注 `async_fifo`，不能解释为新顶层综合结果。旧 `docs/sync_fifo.md` 中 LUT 37、REG 10、OREG 9、BRAM 0 是同步 FIFO 的历史文档记录；未找到与其对应的保留报告，不将其作为本次重新确认的结果。

当前异步 FIFO 的 `HDMI_Player_gate.area` 在 Utilization Statistics 栏记载 LUT 41、REG 40、OREG 11、BRAM 0。该报告另有不同口径的 LUT Statistics，记录资源时需同时注明模块、参数和报告栏目。

现存正时序裕量属于综合阶段报告，不能作为布局布线后或板级时序通过的结论。`constraints` 目录仅有占位文件，尚未看到实际约束和实现阶段完成产物。

## 下一步顺序与完成条件

| 顺序 | 工作 | 完成条件 |
| --- | --- | --- |
| 1 | 处理问题1：读捕获时序 | 依据器件和FPGA时序核定相位/采样安排；正式配置正常及刷新交叉读回无末字Z，不以测试台相位覆盖冒充工程修复 |
| 2 | 扩展刷新修复验证 | 模型短窗三场景和逐拍测试已完成；进一步核对实物速度/温度档、长期调度与板级运行，未来读控制器也遵守pending约定 |
| 3 | 按接口结果完善写通路 | 需要修改时补充相应断言并回归；异步 FIFO 接入和 FIFO 边界用例有可复现记录 |
| 4 | 补齐读通路与显示供数 | 写入的数据能经读通路按帧输出，frame_ready、pix_valid 与缺数处理有明确行为 |
| 5 | 完善工程并推进上板 | 相关 RTL 纳入工程，约束完整，布局布线与时序检查完成，板级读写及显示验证有记录 |

当前优先项是正式读捕获时序与上游时钟域。刷新仲裁已有模型通过证据，后续补实板与长期验证；不得将270°测试台诊断当作正式PLL配置或完整工程通过。

## 证据与重跑入口

| 内容 | 位置 |
| --- | --- |
| 原项目概述 | [README.md](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/README.md) |
| 同步 FIFO 历史说明 | [sync_fifo.md](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/docs/sync_fifo.md) |
| 当前 TD 综合工程 | [HDMI_Player.al](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/project/td/HDMI_Player.al) |
| 当前综合资源报告 | [HDMI_Player_gate.area](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/project/td/HDMI_Player_Runs/syn_1/HDMI_Player_gate.area) |
| FIFO 基础用例复核 | [审核记录](C:/Users/31640/Documents/ChatGPT/FFF/hdmi_audit_20261022/README.md) |
| 写控制器详细仿真报告 | [仿真报告](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/README.md) |
| 单模块结果 | [sdram_write_ctrl.log](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/sdram_write_ctrl.log) |
| 刷新中途拉高的测试与结果 | [集成测试台](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/sdram_fifo_integration_tb.v:181)、[integration.log](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/integration.log:17) |
| 运行命令、退出码与源码 SHA-256 | [results.json](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/results.json) |
| 自动重跑入口 | [run_sim.py](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/run_sim.py) |
| 导出的波形 | [单模块 VCD](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/sdram_write_ctrl.vcd)、[集成 VCD](C:/Users/31640/Documents/ChatGPT/FFF/sdram_sim_20261022/integration.vcd) |
| 当前存储顶层 | [memory_top.v](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/rtl/memory/memory_top.v) |
| 当前参数头文件 | [global_def.v](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/include/global_def.v) |
| 接入前历史编译诊断（未通过） | [write_ports_recheck.log](C:/Users/31640/Documents/ChatGPT/FFF/memory_top_review_20261023/write_ports_recheck.log) |
| 硬件与接口资料摘要 | [资料提取摘要](C:/Users/31640/Documents/ChatGPT/FFF/reference_audit_20261023/资料提取摘要.md) |
| SDRAM 参考接口详细核查 | [SDRAM_reference_findings.md](C:/Users/31640/Documents/ChatGPT/FFF/reference_audit_20261023/controller/SDRAM_reference_findings.md) |
| 随 Git 保存的验证记录 | [verification/README.md](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/verification/README.md) |
| IP 接入编译与零时层次加载 | [elaboration/results.json](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/verification/ip_integration_20261023/elaboration/results.json) |
| PLL 周期与相位验证 | [pll_smoke/results.json](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/verification/ip_integration_20261023/pll_smoke/results.json) |
| Git 内同步的进度总表 | [PROJECT_PROGRESS.md](C:/Users/31640/Desktop/FPGA_Projects/FPGA_HDMI_Player/docs/PROJECT_PROGRESS.md) |

本文件作为截至 2026-10-26 的进度总表，与原工程 `docs/PROJECT_PROGRESS.md` 同步保存。Git 保存用户模块、参考 IP、工程配置和验证证据，不表示完整存储功能通过。助手已导入IP、修复计时宏，并按用户明确授权给顶层增加物理原语连接；2026-10-25按新增授权修改刷新启动门控、顶层仲裁及测试台新端口，PLL/IP/FIFO未改。后续每次更新记录“具体改动、验证方法、证据位置、剩余问题”，历史测试数量不自动代表新版本已经验证。

验证期间 TD 工程曾切回 hdmi_player_top 并移除板级封装清单；用户明确选择恢复 hdmi_player_board_top。已保留其余工程信息，仅恢复该源文件和顶层，语义与本次布局布线所用板级配置一致。
