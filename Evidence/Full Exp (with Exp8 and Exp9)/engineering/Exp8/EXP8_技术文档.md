# EXP8 技术文档

## 1. 实验定位

EXP8 属于《计算机组成原理课程设计指导书（LA 版）》第五章小组作业。本目录使用学校提供的 `ex8_obj` 测试镜像，验证前序实验已经实现的 LoongArch 32 位 CPU、SoC 总线、指令 RAM、数据 RAM 和外设显示链路。EXP8 的目标是对既有功能进行一次完整回归，并为后续 EXP9 的算术扩展提供基线。

本工程的验证对象不是单独的 ALU，而是从取指、译码、执行、访存、写回到数码管监测的完整系统。测试程序把每一个功能点的结果写入约定的显示寄存器，`tb_top` 根据 `num_monitor` 和 `num_data` 检查结果，并在日志中输出 `FUNCTIONAL_POINT_PASS`。

## 2. CPU 和 SoC 结构

CPU 按课程实验约定把取指、译码、执行、访存和写回功能分阶段组织；当前交付 RTL 使用有限状态机顺序推进这些阶段，接口和验证信号与课程五级流水版本保持一致。主要阶段如下：

1. IF：用 PC 访问指令 RAM，处理顺序 PC 和分支目标 PC。
2. ID：解析 LoongArch 指令字段，读取寄存器堆，生成立即数及控制信号。
3. EXE：完成算术逻辑运算、比较、移位、分支条件判断和访存地址计算。
4. MEM：通过 `bridge_1x2` 访问数据 RAM 或配置寄存器，并处理字节写使能。
5. WB：将 ALU、访存或 CSR 结果写回通用寄存器，同时输出 trace 所需的写回信息。

顶层连接关系为 `loongson_remote_top -> soc_lite_top -> mycpu_top`。SoC 内部包括 `inst_ram`、`data_ram`、`bridge_1x2` 和 `confreg`。CPU 通过独立的指令 SRAM 和数据 SRAM 接口访问存储器，配置寄存器模块负责 LED、数码管、按键和计时器等外设。

## 3. EXP8 覆盖的指令与功能

EXP8 使用 `tests/ex8/inst_ram.mif` 初始化指令 RAM，`tests/ex8/data_ram.mif` 初始化数据 RAM。测试镜像覆盖前序实验的基础算术、逻辑、移位、立即数、分支跳转、访存、CSR/异常以及显示外设通路。工程中的译码逻辑同时保留 EXP9 所需的乘除法编码，因此 EXP8 可以作为扩展前的系统回归基线。

访存地址由 `rj + sign_extend(i12)` 计算。字访问要求地址按 4 字节对齐；半字访问要求最低位为 0；不满足对齐条件时进入地址错例程。数据 RAM 采用 32 位字宽，字节和半字操作由地址低位选择 byte lane，并通过写使能避免覆盖同一字中的其他字节。

## 4. 数据通路和控制要点

### 4.1 分支和跳转

`b`、`bl`、条件分支和 `jirl` 在执行阶段计算目标地址。`bl` 将 `PC+4` 写入 `$r1`，`jirl` 将 `PC+4` 写入 `rd`（当 `rd=0` 时禁止写回）。条件分支分别支持有符号和无符号比较，未跳转时 PC 顺序加 4。

### 4.2 访存控制

`mycpu_top.v` 保存访存地址、写数据、写使能、访存类型和目的寄存器。字节写使用 `4'b0001 << addr[1:0]`，半字写根据 `addr[1]` 选择 `0011` 或 `1100`，字写使用 `1111`。读数据在写回阶段按 `mem_op` 完成符号扩展或零扩展。

### 4.3 CSR、异常和计时器

工程实现了课程测试需要的 CRMD、PRMD、ECFG、ESTAT、ERA、BADV、EENTRY、SAVE、TID、TCFG 和计时器寄存器。系统调用、断点、非法指令、地址错和外部/计时器中断统一保存异常现场并跳转到 `EENTRY`。`rdcntid`、`rdcntvl` 和 `rdcntvh` 由稳定计数器提供读数。

### 4.4 硬件时钟约束

乘除法组合逻辑在 FPGA 上会形成较长路径。为保证远程板卡实现的时序，硬件模式下 `clk_50M` 经 4 位分频得到 3.125 MHz 的 `cpu_clk`，仿真模式仍直接使用测试时钟，以免改变功能仿真时序。XDC 为 `cpu_clk` 设置 320 ns 周期约束。该处理只影响硬件运行频率，不改变指令语义和仿真结果。

## 5. 功能点监测与本地仿真

顶层测试平台为 `tb_top`。测试平台生成复位和时钟，实例化 `soc_lite_top`，并监测数码管控制信号。当测试程序写入约定的功能点编号时，平台输出：

```text
FUNCTIONAL_POINT_PASS n
```

EXP8 共检查 47 个功能点，仿真日志中 1 至 47 全部出现 `FUNCTIONAL_POINT_PASS`，随后输出 `----PASS!!!`。本次交付保留了与该仿真快照对应的波形配置和波形数据库：

```text
waveform/tb_top_behav.wcfg
waveform/tb_top_behav.wdb
waveform/simulate.log
```

建议重点观察 `clk`、`resetn`、`soc_clk`、`debug_wb_pc`、`num_monitor`、`num_data` 和 `led`。其中 `debug_wb_pc` 可用于定位写回指令，`num_monitor/num_data` 用于对应功能点，`led` 用于观察外设写入。

## 6. 参考模型 Trace

参考模型位于学校仓库的 `mycpu_env/gettrace`，使用相同的 `ex8_obj` 指令镜像生成黄金写回序列。生成脚本实例化参考 SoC 和测试平台，输出文件为：

```text
reference/golden_trace_ex8.txt
reference/run_reference_ex8.log
```

日志末尾应包含 `gettrace end!` 和 `----Succeed in generating trace file!`，并记录 47 个功能点通过。黄金 Trace 的作用是提供独立参考实现的 PC、寄存器号和写回数据序列；它不替代主 CPU 的功能点测试，而是用于逐条比对写回行为。

## 7. 工程文件说明

* `rtl/mycpu_top.v`：CPU 状态机、指令译码、ALU、访存、CSR 和 debug 写回接口。
* `rtl/soc_lite_top.v`：CPU、RAM、桥接器和配置寄存器的 SoC 连接，包含仿真/硬件时钟选择。
* `rtl/bridge_1x2.v`：将 CPU 数据端口分发到数据 RAM 和配置寄存器。
* `rtl/confreg.v`：数码管、LED、按键和计时器外设。
* `rtl/loongson_remote_top.v`：开发板引脚和顶层时钟复位连接。
* `tests/ex8/inst_ram.mif`、`tests/ex8/data_ram.mif`：EXP8 的程序和数据镜像。
* `vivado_ex8/loongson_ex8.xpr`：Vivado 工程文件。
* `bitstream/ex8_looongson_remote_top.bit`：可提交在线平台的 bitstream。
* `reports/timing_summary_routed.rpt`、`reports/drc_routed.rpt`：实现后的时序和 DRC 报告。

## 8. Vivado 复现步骤

1. 用 Vivado 2023.2 打开 `vivado_ex8/loongson_ex8.xpr`。
2. 检查 `inst_ram` 和 `data_ram` 的初始化文件分别指向 `tests/ex8` 镜像；如 IP 输出产品过期，执行 Generate Output Products。
3. 在 Simulation Sources 中确认顶层为 `tb_top`，启动行为仿真。
4. 在 Tcl Console 执行 `restart`、`run all`，观察 47 个功能点及最终 `----PASS!!!`。
5. 打开 `waveform/tb_top_behav.wdb`，再加载 `waveform/tb_top_behav.wcfg` 查看本次交付的波形布局。
6. 需要重新生成硬件文件时依次执行 Synthesis、Implementation 和 Generate Bitstream，并检查时序报告。

## 9. 实现结果与注意事项

本目录已保存可复现的 Vivado 工程、RTL、IP 文件、测试镜像、仿真波形、仿真日志、参考 Trace、时序报告和 bitstream。当前实现报告显示 WNS=14.540 ns、TNS=0、WHS=0.106 ns、THS=0，用户约束满足。DRC 报告中的 DPIP/DPOP 项为 Block Memory Generator 的性能建议 Warning，不是 Error；没有阻止 bitstream 生成的致命 DRC。

EXP8 与 EXP9 必须使用各自目录下的镜像、波形、Trace 和 bitstream，不能交叉替换。在线平台只提交 `bitstream/ex8_looongson_remote_top.bit`，不要提交 `.bin`、`.mcs` 或整个工程目录。
