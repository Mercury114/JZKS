# D-Cache＋写入机制

已实现并通过 Vivado 2023.2/XSim 模块级回归。

- RTL：`rtl/cache.v`
- 测试平台：`tb/cache_top.v`、`tb/testbench.v`
- 仿真脚本：`run_cache_sim.tcl`
- 仿真日志：`cache_sim.log`
- 技术文档：`docs/DCache_写入机制技术文档.md`

测试日志完成 `index 00` 至 `index ff`，最终输出 `----PASS!!!`。该目录是 D-Cache 独立实现，尚未替换已有 Exp9 CPU，也不声称 I-Cache 和整机公共接入已经完成。
