# 第五章 Exp8 + Exp9 技术、素材与报告写作资料总文档

> 本文是给报告写作模型使用的事实资料库，不是简单的压缩包清单。第五章在报告中合并书写，但 Exp8、Exp9 的镜像、波形、日志、Trace 和 bitstream 必须严格分开引用。

## 1. 实验定位与资料位置

资料根目录：

```text
D:\lasttime\Exp8_Exp9_报告交付
```

两个独立工程包：

```text
Exp8_第五章_完整工程.zip
Exp9_第五章_完整工程.zip
```

两项实验都属于指导书第五章小组作业。Exp8 是系统功能回归、访存和外设验证；Exp9 在同一 SoC 基础上增加乘法、乘高位、除法和取模，并回归 Exp8 的全部既有功能。

报告模板中遗留的 Part 5/Exp5 编号应改成“第五章小组作业”，再分为 Exp8 和 Exp9 两节。

## 2. 最终文件对应关系

### 2.1 Exp8

工程目录：

```text
D:\lasttime\Exp8_Exp9_报告交付\Exp8_第五章_完整工程
```

| 用途 | 文件 |
|---|---|
| Vivado 工程 | `vivado_ex8\loongson_ex8.xpr` |
| 在线提交 bitstream | `bitstream\ex8_looongson_remote_top.bit` |
| 波形配置 | `waveform\tb_top_behav.wcfg` |
| 波形数据 | `waveform\tb_top_behav.wdb` |
| 主 CPU 仿真日志 | `waveform\simulate.log` |
| 参考 Trace 日志 | `reference\run_reference_ex8.log` |
| 参考 Trace 文件 | `reference\golden_trace_ex8.txt` |
| 技术文档 | `EXP8_技术文档.md` |
| 测试镜像 | `tests\ex8\inst_ram.mif`、`tests\ex8\data_ram.mif` |
| 时序报告 | `reports\timing_summary_routed.rpt` |
| DRC 报告 | `reports\drc_routed.rpt` |

Exp8 bitstream SHA-256：

```text
8235414EC1D704F416190786E549AD9155EFFF0673F3A8195CFE60A8FB9C83CB
```

### 2.2 Exp9

工程目录：

```text
D:\lasttime\Exp8_Exp9_报告交付\Exp9_第五章_完整工程
```

| 用途 | 文件 |
|---|---|
| Vivado 工程 | `vivado_ex9\loongson_ex9.xpr` |
| 在线提交 bitstream | `bitstream\ex9_looongson_remote_top.bit` |
| 波形配置 | `waveform\tb_top_behav.wcfg` |
| 波形数据 | `waveform\tb_top_behav.wdb` |
| 主 CPU 仿真日志 | `waveform\simulate.log` |
| 参考 Trace 日志 | `reference\run_reference_ex9.log` |
| 参考 Trace 文件 | `reference\golden_trace_ex9.txt` |
| 技术文档 | `EXP9_技术文档.md` |
| 测试镜像 | `tests\ex9\inst_ram.mif`、`tests\ex9\data_ram.mif` |
| 时序报告 | `reports\timing_summary_routed.rpt` |
| DRC 报告 | `reports\drc_routed.rpt` |

Exp9 bitstream SHA-256：

```text
D388E3A17CF680CC545BE16345541E30DE3DDDB371E9E1B868B2CFE20879F813
```

## 3. 系统总体结构

```text
loongson_remote_top
    └── soc_lite_top
          ├── mycpu_top
          ├── inst_ram
          ├── data_ram
          ├── bridge_1x2
          └── confreg
```

`loongson_remote_top.v` 负责板级时钟、复位和引脚；`soc_lite_top.v` 连接 CPU、指令 RAM、数据 RAM、桥接器和配置寄存器；`mycpu_top.v` 实现 LoongArch 32 位 CPU；`confreg.v` 提供 LED、数码管、按键和计时器。

当前交付的 `mycpu_top.v` 是按阶段推进的有限状态机，不应在报告中虚构为完全并行五级流水。主要状态为：

```text
S_FETCH          取指请求
S_FETCH_WAIT     等待指令 RAM 返回
S_EXEC           译码并执行算术/逻辑/分支/CSR
S_MEM_READ       发起数据 RAM 读
S_MEM_READ_WAIT  等待读数据并形成写回值
S_MEM_WRITE      发起数据 RAM 写
S_WB             通用寄存器写回
```

报告可以用 IF、ID、EXE、MEM、WB 五个“功能阶段”解释数据通路，但应说明当前 RTL 采用有限状态机顺序推进。CPU 对外保留课程 SRAM 接口和写回 debug 接口：

```text
debug_wb_pc
debug_wb_rf_we
debug_wb_rf_wnum
debug_wb_rf_wdata
```

## 4. Exp8 技术内容

### 4.1 测试目标和镜像

Exp8 使用学校提供的 `ex8_obj` 程序镜像：

```text
tests/ex8/inst_ram.mif
tests/ex8/data_ram.mif
```

覆盖基础算术、逻辑、移位、立即数、分支跳转、访存、CSR/异常、计时器和显示外设。不能用 `tests/ex9` 镜像替代，否则功能点数量和执行轨迹都会改变。

### 4.2 访存数据通路

有效地址为 `rj + sign_extend(i12)`。字访问要求 `addr[1:0]==0`，半字访问要求 `addr[0]==0`，否则触发地址错异常。32 位 RAM 中，字节由地址低两位选择：

```text
00 -> rdata[7:0]    01 -> rdata[15:8]
10 -> rdata[23:16]  11 -> rdata[31:24]
```

字节写使用 `4'b0001 << addr[1:0]`，半字写根据 `addr[1]` 使用 `0011` 或 `1100`，字写使用 `1111`。读回阶段按访存类型进行符号扩展或零扩展，避免覆盖同一字的其他 byte lane。

### 4.3 分支、CSR 和异常

`b`、`bl`、条件分支和 `jirl` 计算目标 PC；`bl` 把 `PC+4` 写入 `$r1`，`jirl` 把 `PC+4` 写入 `rd`。CSR 覆盖课程测试所需的 CRMD、PRMD、ECFG、ESTAT、ERA、BADV、EENTRY、SAVE、TID、TCFG 等寄存器。系统调用、断点、非法指令、地址错和计时器/外部中断保存异常现场后跳转到 `EENTRY`。

### 4.4 Exp8 验证证据

`waveform/simulate.log` 中 `FUNCTIONAL_POINT_PASS` 共 47 条，编号 1 到 47 全部通过，并出现：

```text
----PASS!!!
```

参考模型日志 `reference/run_reference_ex8.log` 中功能点 1 到 47 全部通过，末尾包含：

```text
gettrace end!
----Succeed in generating trace file!
```

`reference/golden_trace_ex8.txt` 是参考 SoC 生成的黄金写回序列，用于按照 PC、寄存器号和写回数据逐条比对 CPU。

## 5. Exp9 技术内容

### 5.1 测试目标

Exp9 使用：

```text
tests/ex9/inst_ram.mif
tests/ex9/data_ram.mif
```

重点验证有符号/无符号乘法、乘法高位、除法和取模，同时回归 Exp8 的访存、分支、CSR、异常、计时器、LED、数码管和基础整数运算。

### 5.2 指令译码和结果

乘法使用 `op_31_26=0`、`op_25_22=0`、`op_21_20=1`，由 `op_19_15` 区分：

```text
mul.w    -> 低 32 位乘积
mulh.w   -> 有符号乘积高 32 位
mulh.wu  -> 无符号乘积高 32 位
```

除法/取模使用 `op_21_20=2`：

```text
div.w    -> 有符号商       mod.w    -> 有符号余数
div.wu   -> 无符号商       mod.wu   -> 无符号余数
```

乘法同时形成 `signed_product` 和 `unsigned_product`。除法操作数先显式符号扩展为 64 位，避免 Verilog 混合符号和位宽导致仿真器差异。除数为 0 时按工程约定写回 0。

### 5.3 Exp9 验证证据

`waveform/simulate.log` 中功能点 1 到 58 全部通过，并出现 `----PASS!!!`。`reference/run_reference_ex9.log` 中功能点 1 到 58 全部通过，末尾包含：

```text
gettrace end!
----Succeed in generating trace file!
```

`reference/golden_trace_ex9.txt` 是 Exp9 参考模型黄金写回序列。Exp9 bitstream 已用于在线平台并通过测评。

## 6. 硬件时序修复与实现结果

组合除法/取模路径较长，50 MHz 下可能产生时序压力。硬件模式中，`soc_lite_top.v` 用 4 位计数器分频：

```text
clk_50M = 50 MHz
cpu_clk = clk_50M / 16 = 3.125 MHz
cpu_clk 周期 = 320 ns
```

仿真模式仍直接使用测试时钟，分频只影响硬件运行速度，不改变指令语义和执行顺序。XDC 对 `cpu_clk` 施加 320 ns 周期约束。

两套 `timing_summary_routed.rpt` 的关键数字均为：

```text
WNS = 14.540 ns
TNS = 0.000 ns
WHS = 0.106 ns
THS = 0.000 ns
All user specified timing constraints are met.
```

DRC 中的 DPIP-1、DPOP-1、DPOP-2 是 Block Memory Generator 的性能建议 Warning，不是阻止 bitstream 生成的 Error。报告应写“存在性能建议警告，无致命 DRC”，不能写成“DRC 完全没有 Warning”。

## 7. 波形、日志和 Trace 的使用方法

`.wcfg` 与 `.wdb` 必须配对：`.wcfg` 保存信号列表和布局，`.wdb` 保存实际波形数据。建议观察：

```text
clk, resetn, soc_clk, debug_wb_pc,
debug_wb_rf_we, debug_wb_rf_wnum, debug_wb_rf_wdata,
num_monitor, num_data, led
```

`simulate.log` 是被测 CPU 的功能点结果；`run_reference_ex8/ex9.log` 是独立参考模型生成 Trace 的日志；`golden_trace_ex8/ex9.txt` 是参考写回序列。三者作用不同，报告中应分别说明。

不要用 Exp8 的 `.wcfg` 打开 Exp9 的 `.wdb`，不要把两个实验的 Trace 或 bitstream 混用。

## 8. Vivado 复现步骤

1. 用 Vivado 2023.2 打开对应的 `.xpr`。
2. 确认 `tests/ex8` 或 `tests/ex9` 的指令/数据镜像已加载。
3. 如 IP 输出产品过期，执行 Generate Output Products。
4. 确认仿真顶层为 `tb_top`，运行行为仿真。
5. 执行 `restart`、`run all`，检查 Exp8 的 47 点或 Exp9 的 58 点及 `----PASS!!!`。
6. 加载同一工程的 `.wdb` 和 `.wcfg` 查看波形。
7. 重新综合、实现、生成 bitstream 后检查 timing summary 和 DRC。

工程辅助脚本已经分别指向 Exp8/Exp9 的工程；脚本默认 Vivado 路径为：

```text
D:\Vivado2023\Vivado\2023.2\bin\vivado.bat
```

本机安装路径不同，只需修改 `run_project.ps1`，不要修改镜像和顶层层次。

## 9. 给写作模型的事实边界

可以写：

- Exp8 本地功能点 47/47 通过。
- Exp9 本地功能点 58/58 通过。
- 两套参考模型 Trace 均成功生成。
- Exp9 bitstream 在线测评通过。
- 两套实现报告 WNS=14.540 ns、TNS=0、WHS=0.106 ns、THS=0。
- 硬件 CPU 时钟由 50 MHz 分频为 3.125 MHz，以缓解组合乘除法路径的时序压力。
- 两套工程均保存 `.xpr`、`.bit`、`.wcfg`、`.wdb`、仿真日志、Trace 日志和黄金 Trace。

不要写：

- 没有证据的上板照片、串口截图或板卡实拍结果。
- “Exp8 和 Exp9 共用同一个 bitstream”。两者必须分开。
- “DRC 完全零 Warning”。实际报告有 Block Memory Generator 性能建议 Warning。
- “当前 RTL 是完全并行五级流水”。当前 `mycpu_top.v` 是阶段化有限状态机。
- “功能仿真通过就代表时序一定通过”。两类结论必须分开。

## 10. 报告最终核对表

- [ ] 第五章合并 Exp8 和 Exp9，但有两个清晰小节。
- [ ] Exp8 引用 47/47，Exp9 引用 58/58。
- [ ] Exp8 只引用 `tests/ex8`、`golden_trace_ex8.txt` 和 Exp8 bitstream。
- [ ] Exp9 只引用 `tests/ex9`、`golden_trace_ex9.txt` 和 Exp9 bitstream。
- [ ] 两套 `.wcfg` 与 `.wdb` 配对引用。
- [ ] 两套 `simulate.log`、`run_reference_*.log` 和 `golden_trace_*.txt` 均写入素材说明。
- [ ] 说明访存 byte lane、乘除法符号、CSR/异常、时钟分频和时序结果。
- [ ] 在线平台只提交对应实验的 `.bit` 文件。

最终压缩包：

```text
D:\lasttime\Exp8_Exp9_报告交付\Exp8_第五章_完整工程.zip
D:\lasttime\Exp8_Exp9_报告交付\Exp9_第五章_完整工程.zip
```

压缩包是证据附件；本 Markdown 才是给报告写作模型学习、组织素材和生成第五章正文的主文档。

## 11. 单独证据文件（无需解压）

为便于直接提交、查看或提供给写作模型，以下文件已从两个完整工程中单独复制出来。每个目录内的五个文件属于同一次实验，必须成套使用。

### Exp8 单独证据

目录：

```text
D:\lasttime\Exp8_Exp9_报告交付\Exp8_单独证据
```

```text
tb_top_behav.wcfg       波形配置
tb_top_behav.wdb        波形数据
simulate.log            主 CPU 仿真日志
run_reference_ex8.log   参考模型 Trace 日志
golden_trace_ex8.txt    参考模型 Trace 文件
```

### Exp9 单独证据

目录：

```text
D:\lasttime\Exp8_Exp9_报告交付\Exp9_单独证据
```

```text
tb_top_behav.wcfg       波形配置
tb_top_behav.wdb        波形数据
simulate.log            主 CPU 仿真日志
run_reference_ex9.log   参考模型 Trace 日志
golden_trace_ex9.txt    参考模型 Trace 文件
```

这些单独证据文件与各自完整工程压缩包中的同名文件已逐一复制对应；Exp8 和 Exp9 的文件不能互换。

## 12. Exp9 全部 Verilog 源码

Exp9 的全部 `.v` 文件已单独整理到：

```text
D:\lasttime\Exp8_Exp9_报告交付\Exp9_源码_v文件
```

同时提供压缩包：

```text
D:\lasttime\Exp8_Exp9_报告交付\Exp9_源码_v文件.zip
```

共 13 个 `.v` 文件，保留原工程目录层级，包含 `rtl` 课程源码、`tb_top.v` 测试平台、时钟 IP Verilog 文件和两个 RAM IP 的仿真模型。详细文件列表与阅读顺序见该目录下的 `README_源码清单.md`。
