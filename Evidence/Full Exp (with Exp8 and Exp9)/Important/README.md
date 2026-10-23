# Full Exp 重点证据

这里集中保存 Exp4--Exp9 主线实验最适合答辩和报告引用的证据副本；完整工程仍在本目录上一级的 `engineering/`、`evidence/`、`waveforms/` 和 `reports/` 中。

## 目录

| 目录 | 内容 | 优先级 |
|---|---|---|
| `Full-Exp_PASS/` | Exp8/Exp9 日志、bitstream、golden trace、波形配置和教师回归 | 首先阅读 |
| `Summary/` | 统一验证结果 JSON 与 PASS 输出汇总 | 报告引用 |

## 证据边界

- `Full-Exp_PASS/teacher-ex4-to-ex9-two-way.log` 汇总了学校教师程序 Exp4--Exp9 的通过结果；Exp9 的 ways=1、ways=2、ways=4、禁用 Cache 配置也分别保留。
- 本地仿真 PASS 不等于 FPGA 上板或在线测评平台 PASS；bitstream 仅表示对应工程已生成过可下载产物。
- UART IRQ WIP 诊断分支及未通过内容没有放入“已通过证据”。

## 波形数据

Exp8/Exp9 的 XSim `.wdb` 原始文件超过 GitHub 单文件限制，因此按 90,000,000 字节无损分片保存在上一级 `waveforms/Exp8` 与 `waveforms/Exp9`。在 Windows PowerShell 中恢复：

```powershell
$parts = Get-ChildItem .\waveforms\Exp8\tb_top_behav.wdb.part* | Sort-Object Name
$out = [IO.File]::Create('.\tb_top_behav_ex8.wdb')
try { foreach ($p in $parts) { $in=[IO.File]::OpenRead($p); try { $in.CopyTo($out) } finally { $in.Dispose() } } } finally { $out.Dispose() }
```

Exp9 只需将 `Exp8` 替换为 `Exp9`。对应 `.wcfg`、`simulate.log`、`run_reference_ex*.log` 和 golden trace 位于同级 `evidence` 与工程目录。

## 校验

同目录的 `manifest.json` 给出每个归档文件的相对路径、大小和 SHA256；`SHA256SUMS.txt` 可用于检查传输或下载后的完整性。

同目录的 `manifest.json` 给出每个归档文件的相对路径、大小、来源和用途；`SHA256SUMS.txt` 可用于检查传输或下载后的完整性。
