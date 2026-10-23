# UART 创新部分证据

按仓库 Evidence 的“功能分块 / Important / PASS / Summary”格式归档。
优先阅读 [Important/README.md](Important/README.md) 和
[关键PASS输出汇总](Important/Summary/关键PASS输出汇总.md)。

## 创新功能

- UART 9600、8N1 串口收发及 MMIO 寄存器接口，16 字节接收 FIFO。
- CPU 执行汇编命令终端，实现 CODE、LED、DISP、SW、MIRROR 等外设交互。
- START / STOP / TIME / RESET 秒表，支持暂停继续、计数回绕及十进制输出。
- CPU 定时器中断驱动 LED 闪烁，支持 IRQ ON / OFF / COUNT，前台仍可处理串口命令。

## 版本和范围

- 实际对象：课程五级流水 CPU SoC。
- 归档来源提交：`0bb61f5a7e5a4283d0e9cf0b88fd72bf146fe26c`，本地源码工作区在打包时干净。
- 原始测试记录日期：2026-10-21；归档日期：2026-10-23。
- 本包复制已有测试产物并核对 PASS 标记、汇总、源码哈希和文件完整性；打包不表示重新运行全部仿真。
- 7 种 UART 回归模式共 34362 项检查；CSR 和精确中断附加测试分别为 6、3514 项，另计。
- 串口接收采用轮询；IRQ 是 CPU 定时器中断，不是 UART 接收中断。
- 硬件时钟模式仍是仿真；本包不包含平台截图或录屏，不据此声明实板验收通过。
- docs 和 pipeline-irq-verification.json 为原始记录，保留其中历史待验收状态和上下文；其中提及的 Cache 结果不计入 UART 检查数。

## 目录

| 目录 | 用途 |
| --- | --- |
| Important/UART_PASS | 功能日志、中断 WDB、对应 XSim 日志和附加架构日志 |
| Important/Summary | 机器可读回归结果及关键 PASS 汇总 |
| docs | 原始验证说明和定时器中断设计说明 |

截图可用于演示，但在现有 Evidence 格式中没有发现必须提供截图的要求。
WDB 和对应日志已提供；波形查看方法见 Important/README.md。
源码和复现脚本继续使用仓库中的 innovation_uart、Exp9_源码_v文件和 vivado 目录，不重复打包整个工程。
