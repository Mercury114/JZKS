# Important：优先阅读证据

这里是给答辩和报告写作模型优先读取的最小证据集合。文件均为归档副本，完整原件仍在两个主目录中。

## D-Cache_PASS

- `final_sim.log`：独立 D-Cache 扩展回归，覆盖写回、写分配、脏块、byte-enable、LRU 和控制路径。
- `school_cache_verify.log`：学校兼容 Cache 回归，`00`--`ff` 全索引完成并输出 `----PASS!!!`。
- `dcache_extension.xpr`、`dcache_tb.wcfg`、`dcache_tb_wave.wdb`：可打开的 Vivado 工程和波形材料。
- `dcache-extended.log`：集成测试中 ways=1/2/4 的扩展检查。

## Full-Exp_PASS

包含教师程序 Exp4--Exp9 汇总、Exp9 多种 Cache 配置、Exp8/Exp9 仿真日志、bitstream、golden trace 和波形配置。日志中的 PASS 行是报告可直接引用的客观输出。

## Summary

`verification-results.json` 保留测试命令、结果、时间、源文件 SHA256 和“本地仿真/FPGA边界”说明。
