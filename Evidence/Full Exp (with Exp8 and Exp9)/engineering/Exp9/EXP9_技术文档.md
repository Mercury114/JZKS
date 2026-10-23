# EXP9 技术文档

## 1. 实验定位

EXP9 是《计算机组成原理课程设计指导书（LA 版）》第五章小组作业的算术扩展实验。本工程在 EXP8 的系统结构基础上，使用学校提供的 `ex9_obj` 程序镜像，重点验证有符号/无符号乘法、乘法高位、除法、取模以及前序指令和外设功能的联合回归。

EXP9 的验证范围覆盖整个 CPU/SoC，而不是只检查算术单元。测试程序通过配置寄存器驱动数码管输出功能点，`tb_top` 监测 `num_monitor` 和 `num_data`，同时保留 CPU 写回 debug 端口，便于与参考模型 Trace 对照。

## 2. 基础结构

工程按课程五阶段接口组织 CPU 和 SoC 外设结构；当前交付 RTL 以有限状态机顺序推进 IF 取指、ID 译码、EXE 算术/地址计算、MEM 访存和 WB 写回。写回阶段输出 `debug_wb_pc`、`debug_wb_rf_we`、`debug_wb_rf_wnum` 和 `debug_wb_rf_wdata`。

`loongson_remote_top.v` 负责板级时钟、复位和引脚；`soc_lite_top.v` 连接 CPU、指令 RAM、数据 RAM、`bridge_1x2` 和 `confreg`。EXP9 的 `tests/ex9/inst_ram.mif` 与 EXP8 镜像严格分开，保证仿真、Trace 和 bitstream 使用同一组程序。

## 3. 算术扩展实现

### 3.1 指令译码

在 `mycpu_top.v` 中，乘法指令使用 `op_31_26=0`、`op_25_22=0`、`op_21_20=1` 的编码，利用 `op_19_15` 区分 `mul.w`、`mulh.w` 和 `mulh.wu`；除法/取模使用 `op_21_20=2`，再由 `op_19_15` 区分 `div.w`、`mod.w`、`div.wu` 和 `mod.wu`。这些译码结果纳入 `inst_known`，不会被当作非法指令。

### 3.2 乘法

有符号乘法先将两个 32 位操作数转换为有符号值，形成 64 位 `signed_product`；无符号乘法形成 `unsigned_product`。`mul.w` 返回乘积低 32 位，`mulh.w` 返回有符号乘积高 32 位，`mulh.wu` 返回无符号乘积高 32 位。结果经过统一的写回路径写入 `rd`，当 `rd=0` 时保持零寄存器不变。

### 3.3 除法与取模

有符号除法和取模显式把 `rj`、`rk` 符号扩展到 64 位后再进行运算，避免 Verilog 表达式中混合位宽和符号属性造成仿真器差异。`div.w`/`mod.w` 使用有符号运算，`div.wu`/`mod.wu` 使用无符号运算。除数为 0 时结果按工程约定写回 0，避免产生 X 值和不可复现的仿真结果。

## 4. 访存、分支和前序功能回归

EXP9 不是孤立的乘除法测试。测试镜像同时回归 EXP8 的访存、字节/半字扩展、分支跳转、CSR、异常、计时器、LED 和数码管功能。访存地址仍由 `rj + sign_extend(i12)` 生成，byte lane 和半字 lane 由地址低位选择，未对齐访问进入地址错处理。分支目标、链接写回和 CSR 异常路径保持与 EXP8 一致，因此算术扩展不会破坏原有控制流。

## 5. 硬件时钟和时序处理

组合除法/取模路径比普通加法和逻辑运算更长。为使远程 FPGA 实现满足时序，硬件模式下 `clk_50M` 经 4 位计数器分频，CPU 使用 `cpu_clk=clk_50M/16=3.125 MHz`，周期为 320 ns；仿真模式下仍直接使用测试时钟。复位采用异步断言，分频计数器在复位时清零。XDC 对分频后的 `cpu_clk` 建立 320 ns 时钟约束。

这一修改只改变硬件执行速度，不改变指令执行顺序、写回数据和功能点编号。它是实现时序修复，不应与功能仿真通过混为同一个结论。

## 6. 功能点监测与仿真证据

顶层测试平台 `tb_top` 生成时钟/复位并实例化完整 SoC。当测试程序写入功能点编号时，日志输出 `FUNCTIONAL_POINT_PASS n`。EXP9 共覆盖 58 个功能点，当前 `waveform/simulate.log` 中 1 至 58 全部通过，随后输出 `----PASS!!!`。

本目录保存与该工程和测试镜像对应的一组波形文件：

```text
waveform/tb_top_behav.wcfg
waveform/tb_top_behav.wdb
waveform/simulate.log
```

建议在 Vivado 波形窗口中观察 `clk`、`resetn`、`soc_clk`、`debug_wb_pc`、`num_monitor`、`num_data` 和 `led`。算术指令的写回结果可由 `debug_wb_rf_wnum` 与 `debug_wb_rf_wdata` 配合 `debug_wb_rf_we` 定位。

## 7. 参考模型 Trace

参考模型使用仓库 `mycpu_env/gettrace`，加载同一份 `ex9_obj` 指令镜像，独立生成黄金写回序列。交付文件为：

```text
reference/golden_trace_ex9.txt
reference/run_reference_ex9.log
```

`run_reference_ex9.log` 末尾包含 `gettrace end!` 和 `----Succeed in generating trace file!`，并记录功能点 1 至 58 全部通过。`golden_trace_ex9.txt` 用于按 PC、寄存器号和写回数据逐条比对 CPU 行为；参考模型日志和主 CPU 仿真日志分开保存，避免混淆两种验证来源。

## 8. 工程文件说明

* `rtl/mycpu_top.v`：算术指令译码、乘法/除法/取模运算、CSR、访存和写回。
* `rtl/soc_lite_top.v`：SoC 连接及仿真/硬件时钟分频。
* `rtl/bridge_1x2.v`：CPU 数据端口到 RAM/配置寄存器的分发。
* `rtl/confreg.v`：数码管、LED、按键和计时器。
* `rtl/loongson_remote_top.v`：板级封装和时钟复位。
* `tests/ex9/inst_ram.mif`、`tests/ex9/data_ram.mif`：EXP9 程序和数据镜像。
* `vivado_ex9/loongson_ex9.xpr`：Vivado 工程。
* `bitstream/ex9_looongson_remote_top.bit`：EXP9 在线测评使用的 bitstream。
* `reference/golden_trace_ex9.txt`、`reference/run_reference_ex9.log`：参考 Trace 证据。
* `reports/timing_summary_routed.rpt`、`reports/drc_routed.rpt`：实现报告。

## 9. Vivado 复现步骤

1. 用 Vivado 2023.2 打开 `vivado_ex9/loongson_ex9.xpr`。
2. 确认 `inst_ram`、`data_ram` 使用 `tests/ex9` 下的初始化镜像；必要时重新 Generate Output Products。
3. 以 `tb_top` 启动行为仿真，在 Tcl Console 执行 `restart` 和 `run all`。
4. 检查 58 个 `FUNCTIONAL_POINT_PASS` 以及最终 `----PASS!!!`。
5. 加载 `waveform/tb_top_behav.wdb` 和 `waveform/tb_top_behav.wcfg` 查看保存的波形快照。
6. 重新综合/实现/生成 bitstream 后，检查 `reports` 目录中的时序与 DRC 结果。

## 10. 结果与注意事项

本工程已完成 EXP9 功能仿真、参考模型 Trace、综合实现和 bitstream 生成。实现报告显示 WNS=14.540 ns、TNS=0、WHS=0.106 ns、THS=0，所有用户时序约束满足。DRC 报告中的 32 项为 Block Memory Generator 的 DPIP/DPOP 性能建议 Warning，不是阻止 bitstream 生成的 Error。

EXP9 bitstream 已用于在线平台并通过测评。提交时只选择 `bitstream/ex9_looongson_remote_top.bit`；不要用 EXP8 的镜像、Trace 或 bitstream 替换本目录中的对应文件。报告中应分别陈述功能仿真、参考 Trace 和硬件时序结果，不虚构未保存的上板照片或串口输出。
