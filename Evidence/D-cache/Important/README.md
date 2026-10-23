# Important：优先阅读证据

这里是给答辩和报告写作模型优先读取的 D-Cache 证据集合。文件均为归档副本，完整原件仍在 `D-cache/build/`、`D-cache/integrated-cache/` 和 `D-cache/source-material/` 中。

## D-Cache_PASS

- `final_sim.log`：独立 D-Cache 扩展回归，覆盖写回、写分配、脏块、byte-enable、LRU 和控制路径。
- `school_cache_verify.log`：学校兼容 Cache 回归，`00`--`ff` 全索引完成并输出 `----PASS!!!`。
- `dcache_extension.xpr`、`dcache_tb.wcfg`、`dcache_tb_wave.wdb`：可打开的 Vivado 工程和波形材料。
- `dcache-extended.log`：集成测试中 ways=1/2/4 的扩展检查。

课程主线的重点证据位于 `../Full Exp (with Exp8 and Exp9)/Important/`，这里仅保留 D-Cache 相关证据。
