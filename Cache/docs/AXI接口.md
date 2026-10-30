# 五级流水 CPU 的 AXI4 顶层

`Cache/rtl/mycpu_top_axi.v` 是新的 AXI4 主设备顶层。它复用 `cache_system.v` 中已验证的五级流水 CPU、I/D Cache、CACOP、外设旁路和仲裁器；原课程 SRAM 板级顶层继续用于现有工程。将 Vivado 仿真或综合顶层设为 `mycpu_top_axi`，并只加入 `Cache/rtl/*.v` 与 `Cache/rtl/cpu/*.v` 这套文件，不要与 `Exp9_源码_v文件/rtl` 中的同名流水级混编。

## 外部接口

- `clk`、低有效 `resetn`、`hw_int_in[7:0]`、原写回调试信号。
- 32 位 AXI4 主接口：AW、W、B、AR、R 五通道，ID 宽度由 `AXI_ID_WIDTH` 参数控制，默认 4 位且发出的 ID 固定为 0。
- `axi_error`：检测到非 OKAY 的 `RRESP/BRESP`、错误响应 ID，或单拍读响应缺少 `RLAST` 时置 1，直到复位才清除。
- `INDEX_WIDTH`、`WAY_NUM`、`ENABLE_CACHE`、`BOARD_ADDR_MAP` 透传给原 `cache_system`。连接通用 AXI 主存时，`BOARD_ADDR_MAP` 保持默认的 0；仅复刻课程板级 RAM 地址镜像时才设为 1。

`cache_axi_bridge.v` 将原有逐字请求转换成 **32 位、单拍、单笔未完成** AXI4 事务：`AxLEN=0`、`AxBURST=INCR`。读在 R 通道握手后完成，写在 B 通道握手后完成；AW 与 W 可以分别被接收。读访问发送对齐字地址和 `ARSIZE=2`，供 CPU 按地址低位提取字节或半字。写访问保留原字节地址，`AWSIZE` 为字节、半字或字宽，目标字节由 `WSTRB` 选择。缓存行仍由原仲裁器拆成四次逐字事务，因此目前不使用 AXI 突发传输。

`bfaf_xxxx`、`1faf_xxxx` 外设地址沿用原 `cache_subsystem` 的无缓存旁路。一次外设请求只在 AXI 完成后反馈给 CPU；AXI 从设备应在一次成功握手时执行一次有副作用的读写。读地址按字对齐，适用于现有按字对齐的外设寄存器；字节和半字写地址保留低位，可供外设按完整字节地址译码。

`axi_error` 是总线错误诊断输出。当前 CPU 没有总线访问异常的架构入口，因此错误响应仍结束该事务，读数据直接交给原主存接口；系统集成时应监控 `axi_error`，不能把它当作完整的 LoongArch 总线异常实现。

## 验证

在 Windows PowerShell 的仓库根目录运行：

```powershell
& .\Cache\scripts\run_axi_sim.ps1 -VivadoBin 'D:\Xilinx\Vivado\2018.3\bin'
```

`cache_axi_bridge_tb` 检查 AR 反压、AW/W 不同顺序握手、B/R 才能完成事务、字节写使能和错误标记。`mycpu_top_axi_tb` 让真实五级 CPU 通过 I/D Cache 从带独立反压的 AXI 内存取指，执行 cached store/load、load-use 相关和 uncached 外设写，检查写回结果、外设值及五通道事务次数。仿真产物写入被忽略的 `Cache/build/axi/`。

要生成 Vivado 2018.3 可直接打开的波形数据库与信号布局，在仓库根目录运行：

```powershell
& .\Cache\scripts\run_axi_wave.ps1 -VivadoBin 'D:\Xilinx\Vivado\2018.3\bin'
```

脚本使用 `xelab -debug typical` 编译，并在仿真开始前记录所有信号。完成后，`Cache/build/axi/` 中分别生成 `cache_axi_bridge_tb.wdb/.wcfg/.vcd`（AXI 桥接读写、反压与错误响应）和 `mycpu_top_axi_tb.wdb/.wcfg/.vcd`（CPU、Cache、MMIO 集成读写）。在 Vivado GUI 的 Tcl Console 中先执行 `open_wave_database {完整 WDB 路径}`，再执行 `open_wave_config {完整 WCFG 路径}`。使用波形窗口的 **Zoom Range X** 分别查看读、写及 CPU 集成局部时序；点击 Zoom Fit 只适合查看全程概览。

报告用的归档证据位于 `Evidence/AXI/`，包括 Vivado 直接截图、原始 WDB/WCFG、VCD、XSim 日志、PASS 汇总与文件哈希清单；两个测试台及复现脚本保留在 `Cache/` 中。
