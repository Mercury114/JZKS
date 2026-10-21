# 五级流水 CPU、D-Cache 与 UART 集成说明

本分支 `pipeline-cache-uart` 以课程 Exp7 的五级流水实现为 CPU 基线，整理了第五章 Exp8/Exp9 所需的访存、CSR、异常、中断和计数器逻辑，并保留 `D-cache` 与 `innovation/uart-echo` 两个分支的扩展资产。`main`、`D-cache`、`innovation/uart-echo` 均未被覆盖。

## 工程入口

- Vivado 工程：`vivado/console_build/pipeline_uart.xpr`
- 顶层：`Exp9_源码_v文件/rtl/loongson_remote_top.v`
- CPU 顶层：`Exp9_源码_v文件/rtl/mycpu_top.v`
- 第五章测试镜像：`Exp9_源码_v文件/ip_ascii/{inst_ram,data_ram}/`
- 构建脚本：`vivado/run.ps1`

在 Vivado 2023.2 中使用：

```powershell
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode bitstream -Vivado 'D:\Vivado2023\Vivado\2023.2\bin\vivado.bat'
```

为避开课程 2018.3 XCI 在 Vivado 2023.2 中锁定的问题，工程使用 `rtl/course_ram.v` 中的可综合 BRAM 包装器，并读取同目录的 MIF 初始化文件；不依赖旧 XCI 的输出产物。

## 五级流水实现

CPU 由以下独立级组成，所有级之间使用 `valid/allowin` 握手：

- `IF_stage.v`：顺序取指、分支/异常/中断重定向与 IF/ID 有效位。
- `ID_stage.v`：LoongArch 基础整数、乘除、访存、分支、CSR、异常、计数器和 `cacop` 译码；含 EXE/MEM 前递和 load-use 暂停。
- `EXE_stage.v`：ALU、乘除法、有效地址计算。
- `MEM_stage.v`：课程同步 SRAM 访问，字节/半字读写和符号/零扩展。
- `WB_stage.v`：通用寄存器写回及课程在线测评所需的 debug 写回接口。

第五章相关控制状态放在 `mycpu_top.v`：CRMD、PRMD、ECFG、ESTAT、ERA、BADV、EENTRY、SAVE0~3、TID、TCFG 和 TVAL。支持 CSR 读写交换、`syscall`、`break`、非法指令、地址错、`ertn`、定时器中断、`rdcntid`、`rdcntvl.w`、`rdcntvh.w`。分支、异常、返回和中断通过同一重定向总线清空年轻流水级。

访存级保持课程 Block Memory Generator 所要求的读使能时序。这个细节对 Exp9 的 `ld.b/ld.h/ld.bu/ld.hu` 压力测试是必需的。

## D-Cache 扩展

`D-cache/` 是独立、可回归的 D-Cache 交付目录，包含：

- `rtl/dcache.v`：256 组、4 路组相联、16-byte line，write-back/write-allocate、dirty 位、LRU、字节写使能、整行回写与 refill。
- `rtl/dcache_sram_adapter.v`：课程单字 SRAM 请求到四拍 cache-line 事务的适配器及参考 backing store。
- `tb/dcache_tb.v`：write-allocate、部分字节写、LRU 替换、脏块回写和 cache 控制操作的独立测试。
- `docs/DCache_写入机制技术文档.md`：接口、状态机和验证覆盖说明。

同一份 Cache RTL 也在 `Exp9_源码_v文件/rtl/` 中保留，便于板级工程进一步接入。默认 Exp9 bitstream 保持课程原始单字 SRAM 数据通路，避免把未完成的 cache miss 握手接入在线测评路径。要启用 D-Cache，必须将 MEM 级改为等待 `addr_ok/data_ok`，让 MMIO 绕过 cache，并把 `cacop` 控制请求接到 cache；这些接口在模块侧已经具备，但不是当前 bitstream 的宣称功能。

## UART 扩展

UART 资产来自 `innovation/uart-echo`：

- `rtl/UART/uart_tx.v`、`uart_rx.v`、`uart_mmio.v`
- `confreg.v` 的 TXDATA、RXDATA、STATUS MMIO 寄存器
- `innovation_uart/sw/` 中的演示程序、链接脚本和镜像生成材料
- `innovation_uart/sim/` 中的 FIFO、回显、秒表和中断测试台

UART 硬件接口已保留在 SoC 顶层。默认 bitstream 使用官方 Exp9 指令镜像，而不是 UART 演示固件；UART 功能回归需要先用相应 LoongArch 工具链生成并替换演示镜像，不能把默认 Exp9 测试结果解释为 UART 固件已执行。

## 验证状态

- Vivado 2023.2 对五级流水源码完成了综合、布局、布线与 bitstream 生成。
- 修复后的实现路由前 DRC 为 `0 Errors / 0 Warnings / 0 Critical Warnings`，无组合环；已生成 bitstream 的路由估算 WNS 为 `16.572 ns`。
- 独立 D-Cache 测试台覆盖 writeback、write-allocate、byte-enable、LRU 和控制操作；历史回归记录为 `PASS D-Cache writeback/write-allocate/byte-enable/LRU/control regression`。
- 官方 Exp9 测试台可由 `Exp9_源码_v文件/tb_top.v` 启动。当前机器上的 Vivado 2023.2 XSim 在重新 elaboration 阶段报 `XSIM 43-3409`（生成 C 文件编译失败），因此本分支不把未重新跑出的 58 点结果标为通过。该问题不影响 Vivado 的综合、实现和 bitstream 生成。

临时仿真目录和 Vivado 构建目录都在 `.gitignore` 中；版本库只保留源码、测试台、镜像、脚本、文档及明确交付的 artifact。
