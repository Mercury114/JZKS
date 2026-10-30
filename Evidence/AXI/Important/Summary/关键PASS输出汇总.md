# AXI 仿真关键 PASS 输出汇总

## 1. AXI 桥接模块

测试台：`Cache/tb/cache_axi_bridge_tb.v`；波形与日志：`../AXI_PASS/bridge/`。

```text
PASS cache_axi_bridge: independent channels, backpressure, completion, error
$finish called at time : 240 ns
```

测试检查了：读请求 `0x103` 对齐为 `ARADDR=0x100`，AR 在反压期间保持有效、85 ns 完成握手，115 ns 收到 `RDATA=A1B2C3D4`；半字写 `WSTRB=C` 时 AW、W 分别在 135 ns、165 ns 握手，195 ns 收到 B；字节写 `WSTRB=2` 时 W、AW 分别在 215 ns、225 ns 握手，235 ns 接收故意注入的 `BRESP=2` 并置位 `axi_error`。测试台用 `$fatal` 检查地址、大小、字节选通、完成次数和错误标志。

原始 Vivado 截图：`../AXI_PASS/screenshots/axi_read_vivado.png`、`axi_write_vivado.png`。

## 2. 五级 CPU、Cache 与 AXI 集成

测试台：`Cache/tb/mycpu_top_axi_tb.v`；波形与日志：`../AXI_PASS/cpu/`。

```text
PASS AXI five-stage CPU/cache/MMIO: AR=12 R=12 AW=1 W=1 B=1
$finish called at time : 1335 ns
```

测试程序经 AXI 存储器模型取指，执行缓存区存取、load-use 相关和 MMIO 写。测试台检查最终 `wb_num=29`、`wb_data=0x12B`、`mmio_value=0x12A`、MMIO 写次数为 1、AR/R 各 12 次、AW/W/B 各 1 次、`axi_error=0`。约 1245 ns，MMIO 写的 AW/W 握手，写地址 `0xBFAFF050`、写数据 `0x12A`、`WSTRB=F`；1295 ns 收到 B 响应。

## 验证边界

这两项 PASS 证明当前测试激励下的 AXI 单拍读写及 CPU/Cache/MMIO 集成路径。它们不等同于 FPGA 实板验证，也不覆盖 AXI burst、多笔 outstanding 或任意外设组合。
