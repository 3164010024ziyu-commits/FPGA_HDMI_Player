# 刷新仲裁验证

结论和边界见 [SDRAM_REFRESH_VERIFICATION.md](../../docs/SDRAM_REFRESH_VERIFICATION.md)。`production_final` 是当前生产文件的三场景测试；`production_matrix_180` 保留1094个读回错误，`production_matrix_phase270_diagnostic`仅为测试台相位诊断，不能冒充工程PLL修复。`final_summary.json`汇总最终结果及生产源码哈希。

本机重跑（ModelSim、TD、APUG011路径与脚本默认值一致时）：

```powershell
python verification/refresh_arbitration_20261025/run_refresh.py --scenario continuous --tag rerun
python verification/refresh_arbitration_20261025/run_functional.py --name rerun_formal --profile 2 --duration-us 1950
```

第一条检查512us连续写入及真实刷新端口，默认125MHz/180°。第二条完整11场景，在现有正式配置预期仍报1094个读回错误。可添加 `--phase-diag --phase-degrees 270` 进行诊断，但不会修改工程PLL。两脚本均保存输入快照、哈希、命令、退出码和事件，不自动更新进度。

重跑依赖FFF中已编译的al/eg仿真库；迁移机器时需调整脚本中的ModelSim、TD、器件模型和库路径。逐步同步文档的原始执行脚本、全部日志和每版快照在 `C:/Users/31640/Documents/ChatGPT/FFF/memory_followup_20261025`。不要重用原始结果目录名覆盖证据。

Git中refresh_events.csv保留刷新请求、确认、占用、pending、内部活动及实际刷新事件；仅省略每组应用写拍及顶层busy跳变。未筛选原始events.csv完整保存在FFF，request_waits.csv保留每个请求的配对时间。entrypoint_check保存重跑入口检查结果。
