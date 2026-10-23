# D-Cache + 写入机制扩展

本目录只交付 `Cache模块双人协作分工.md` 中“D-Cache＋写入机制”一栏的内容，独立于原 Exp8/Exp9 工程，不修改原课程测评工程。

## 目录

- `rtl/dcache.v`：四路组相联、write-back/write-allocate D-Cache。
- `tb/dcache_tb.v`：只实例化 D-Cache 的独立回归。
- `docs/DCache_写入机制技术文档.md`：设计、协议、状态机和测试说明。
- `build/dcache_project/dcache_extension.xpr`：Vivado 2023.2 工程。
- `build/dcache_tb_wave.wdb`、`build/dcache_tb.wcfg`：独立回归波形数据和配置。
- `build/dcache_sim.log`、`build/school_cache_verify.log`：独立回归和学校兼容回归日志。

## 运行

在 Vivado 2023.2 Tcl Console 中执行 `run_dcache_sim.tcl`，或使用命令行按文档中的 `xvlog/xelab/xsim` 顺序运行。独立回归成功标志为：

```text
PASS D-Cache writeback/write-allocate/byte-enable/LRU/control regression
```

原学校 Cache 验证环境仍由 `DCache_写入机制` 目录维护，原 Exp8/Exp9 文件夹保持不变。I-Cache、仲裁和整机接入由协作方负责，不包含在本目录。
