# 关键 PASS 输出汇总

## D-Cache 独立验证

- `final_sim.log`：`PASS D-Cache writeback/write-allocate/byte-enable/LRU/control regression`
- `school_cache_verify.log`：索引 `00` 到 `ff` 全部完成，末尾为 `Test end!` 和 `----PASS!!!`
- `dcache-extended.log`：`WAYS=1`、`WAYS=2`、`WAYS=4` 均通过 strobe、write-allocate、4-word write-back、true-LRU、control、stall、gap、first-beat、reset 检查。

## 课程教师回归

- Exp4：`29/29 points`
- Exp5：`33/33 points`
- Exp6：`39/39 points`
- Exp7：`46/46 points`
- Exp8：`47/47 points`
- Exp9：`58/58 points`

## Exp9 配置交叉验证

- ways=1、ways=2、ways=4 且 Cache enabled：均为 `58/58 points`。
- ways=2 且 Cache disabled：保留为基线对照，同样为 `58/58 points`。

## 解释边界

这些行来自本地 Verilog/XSim/Icarus 回归，不应表述为在线平台或 FPGA 上板结果。UART IRQ 的 WIP 诊断没有纳入本汇总。
