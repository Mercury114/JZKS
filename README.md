# JZKS：计组课设小组作业

当前缓存集成工作位于 **`D-cache` 分支的 `Cache/`**，在同伴已有提交上继续开发，原交付保留。

- [我的完成说明](Cache/docs/我的完成说明.md)：分工对应、个人贡献与当前验收状态。
- [缓存版本入口](Cache/README.md)：源码、配置和一键本地回归。
- [团队缓存设计与测试报告](Cache/docs/缓存设计与测试报告.md)：接口、状态机、Cache指令、流水化、真实性能对比。
- [Vivado验证与上板操作](Cache/docs/Vivado验证与上板操作.md)：可移植工程创建与剩余硬件验证。

保留目录：`D-cache/` 是同伴原四路D-Cache独立交付；`Exp9_源码_v文件/` 是原Exp9多周期CPU版本。
新增 `Cache/` 使用真正五级流水CPU，支持 I/D直接映射、两路/四路LRU、写回写分配、CACOP与I-Cache命中流水化。

本地运行（需Python 3.9+与Icarus Verilog）：

```sh
python3 Cache/tests/run_all.py
```

测试记录见 [verification-results.json](Cache/docs/verification-results.json)。本地编译/仿真与Vivado综合、布线时序、bitstream、平台验收分开记录。
