# AXI 总线接口仿真证据

本目录按仓库其他 Evidence 的“功能分块 / Important / PASS / Summary”形式归档 AXI 接口验证。优先阅读 [Important/README.md](Important/README.md) 和 [关键 PASS 输出汇总](Important/Summary/关键PASS输出汇总.md)。

## 验证对象

- `cache_axi_bridge_tb`：独立测试 Cache 侧请求到 AXI 五通道的转换，覆盖读地址反压、读数据返回、AW/W 两种先后顺序、半字/字节写选通、B 响应及错误上报。
- `mycpu_top_axi_tb`：五级流水 CPU 经 I/D Cache 和 AXI 存储器模型执行实际指令，检查取指、缓存读写、load-use 相关、MMIO 写及最终寄存器写回。

两项测试均由 **Vivado 2018.3 XSim** 运行并输出 PASS。这里提供的是**仿真验证**，不据此声称 FPGA 上板验证通过。桥接测试使用单拍 AXI 传输；材料也不宣称多拍 burst 或多笔 outstanding 已验证。

## 目录

| 路径 | 内容 |
| --- | --- |
| `Important/AXI_PASS/bridge/` | 桥接模块 WDB/WCFG、VCD、两次 XSim 日志、便携打开脚本 |
| `Important/AXI_PASS/cpu/` | CPU 集成 WDB/WCFG、VCD、两次 XSim 日志、便携打开脚本 |
| `Important/AXI_PASS/screenshots/` | 从 Vivado GUI 直接截取的读、写波形和 CPU 总览 |
| `Important/Summary/` | PASS 摘要、验证结果与文件校验清单 |
| `Supplementary/` | 由 Vivado XSim VCD 绘制的局部放大图，仅供阅读辅助 |

测试台源码位于 `Cache/tb/cache_axi_bridge_tb.v` 和 `Cache/tb/mycpu_top_axi_tb.v`；复现脚本位于 `Cache/scripts/run_axi_wave.ps1`，波形布局与 VCD 导出脚本位于同目录。它们随本分支提交，Evidence 不重复复制源码。原始仿真结果与截图的来源、文件哈希见 `Important/manifest.json` 和 `Important/SHA256SUMS.txt`。

在仓库根目录运行 `python Evidence/AXI/Important/make_manifest.py --verify` 可逐项检查归档文件的大小和 SHA256；需要重新生成清单时去掉 `--verify`。
