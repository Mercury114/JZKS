# 课程设计证据归档

本目录集中保存本人负责的 D-Cache、写入机制扩展，以及 Exp8/Exp9 和前置 Exp7 的工程、源码、仿真、Trace、波形、bitstream 与报告素材。资料按 2026-10-23 的本地验证结果整理，目标是让答辩、报告写作和后续复现都能直接定位到原始证据。

## 目录

| 目录 | 内容 | 优先级 |
|---|---|---|
| `Important/` | 最关键的 PASS 日志、工程入口、bitstream、trace、波形配置和结果汇总 | 首先阅读 |
| `D-cache/` | D-Cache 独立实现、写回/写分配验证、学校兼容回归、集成 Cache 源码与测试 | 本人扩展 |
| `Full Exp (with Exp8 and Exp9)/` | Exp7 基线、Exp8/Exp9 完整工程、源码、bitstream、波形、trace 和报告材料 | 课程实验 |

## 证据边界

- `D-cache/` 中的 `final_sim.log` 明确记录独立 D-Cache 的写回、写分配、byte-enable、LRU、控制操作、停顿和复位回归通过。
- `D-cache/` 中的 `school_cache_verify.log` 是学校 Cache 接口兼容回归，包含 `index 00` 到 `index ff` 以及 `Test end! / ----PASS!!!`。
- `Important/Full-Exp_PASS/teacher-ex4-to-ex9-two-way.log` 汇总了学校教师程序 Exp4--Exp9 的通过结果；Exp9 的 ways=1、ways=2、ways=4、禁用 Cache 配置也分别保留。
- 本地仿真 PASS 不等于 FPGA 上板或在线测评平台 PASS；bitstream 仅表示对应工程已生成过可下载产物。
- UART IRQ WIP 诊断分支及未通过内容没有放入“已通过证据”。

## 波形数据

Exp8/Exp9 的 XSim `.wdb` 原始文件超过 GitHub 单文件限制，因此按 90,000,000 字节无损分片保存在 `Full Exp (with Exp8 and Exp9)/waveforms/Exp8` 与 `.../Exp9`。在 Windows PowerShell 中恢复：

```powershell
$parts = Get-ChildItem .\waveforms\Exp8\tb_top_behav.wdb.part* | Sort-Object Name
$out = [IO.File]::Create('.\tb_top_behav_ex8.wdb')
try { foreach ($p in $parts) { $in=[IO.File]::OpenRead($p); try { $in.CopyTo($out) } finally { $in.Dispose() } } } finally { $out.Dispose() }
```

Exp9 只需将 `Exp8` 替换为 `Exp9`。对应 `.wcfg`、`simulate.log`、`run_reference_ex*.log` 和 golden trace 位于同级 `evidence` 与工程目录。

## 校验

`manifest.json` 给出每个归档文件的相对路径、大小、来源和用途；`SHA256SUMS.txt` 可用于检查传输或下载后的完整性。
