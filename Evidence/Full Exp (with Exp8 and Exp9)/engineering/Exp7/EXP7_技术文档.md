# EXP7 技术文档

## 1. 实验定位

本工程使用指导书 `for_test_obj/ex7_obj` 作为测试对象。按照本课程指导书的编号，EXP7 是乘除法指令扩展实验；按照课程章节的对应关系，它属于课本第五章内容。本工程在已完成访存扩展的五级流水 CPU 上继续增加乘法、乘高位、除法和取模指令。

工程使用 Vivado 2018.3，目标器件为 `xc7a200tfbg676-1`。工程位于包含中文的目录中，因此自动化综合、实现脚本使用 `Y:` 映射盘符访问工程，避免 Vivado 2018.3 在 BRAM 初始化阶段处理中文路径时出现兼容性异常。

## 2. 实验目标

本实验增加以下七条 LoongArch 指令：

| 指令 | 运算含义 | 结果 |
| --- | --- | --- |
| `mul.w` | 32 位乘法 | 乘积低 32 位 |
| `mulh.w` | 有符号 32 位乘法 | 乘积高 32 位 |
| `mulh.wu` | 无符号 32 位乘法 | 乘积高 32 位 |
| `div.w` | 有符号除法 | 商 |
| `mod.w` | 有符号除法 | 余数 |
| `div.wu` | 无符号除法 | 商 |
| `mod.wu` | 无符号除法 | 余数 |

除上述新增指令外，EXP7 继续保留前面实验已实现的基础算术、逻辑、分支、访存和立即数指令，测试程序会对完整指令集合进行 trace 比对。

## 3. 流水线结构

CPU 继续采用原有简单五级流水结构：

1. IF：根据 PC 取指，并计算顺序 PC。
2. ID：解析指令字段、读取寄存器、生成立即数和 ALU 控制码。
3. EXE：由 ALU 完成算术、逻辑、乘法、除法和取模运算。
4. MEM：完成数据 RAM 访问以及前一实验中的 byte/half load/store 处理。
5. WB：把最终结果写回通用寄存器，并输出测试平台需要的写回 trace。

EXP7 没有重新设计流水线，也没有修改在线测评接口。新增运算在 EXE 阶段作为组合 ALU 运算完成，结果沿已有 `EXE -> MEM -> WB` 通路传递。

## 4. 控制信号扩展

原 ALU 控制信号能够表示 12 类基础运算。本实验把 `alu_op` 从 12 位扩展为 19 位：

| 位 | 操作 |
| --- | --- |
| `alu_op[0]` | add |
| `alu_op[1]` | sub |
| `alu_op[2]` | signed less-than |
| `alu_op[3]` | unsigned less-than |
| `alu_op[4]` | and |
| `alu_op[5]` | nor |
| `alu_op[6]` | or |
| `alu_op[7]` | xor |
| `alu_op[8]` | sll |
| `alu_op[9]` | srl |
| `alu_op[10]` | sra |
| `alu_op[11]` | lui |
| `alu_op[12]` | `mul.w` |
| `alu_op[13]` | `mulh.w` |
| `alu_op[14]` | `mulh.wu` |
| `alu_op[15]` | `div.w` |
| `alu_op[16]` | `mod.w` |
| `alu_op[17]` | `div.wu` |
| `alu_op[18]` | `mod.wu` |

`DS_TO_ES_BUS` 和后续流水总线同步使用 19 位 ALU 控制字段，保证控制信号在流水寄存器中不发生错位。

## 5. 指令译码

新增指令在 `rtl/ID_stage.v` 中按照 LoongArch 指令字段进行译码。乘法指令使用 `op_21_20 = 2'h1`，除法和取模指令使用 `op_21_20 = 2'h2`，再由 `op_19_15` 区分具体操作：

```text
mul.w   : op_21_20 = 1, op_19_15 = 0x18
mulh.w  : op_21_20 = 1, op_19_15 = 0x19
mulh.wu : op_21_20 = 1, op_19_15 = 0x1a
div.w   : op_21_20 = 2, op_19_15 = 0x00
mod.w   : op_21_20 = 2, op_19_15 = 0x01
div.wu  : op_21_20 = 2, op_19_15 = 0x02
mod.wu  : op_21_20 = 2, op_19_15 = 0x03
```

七条指令均为寄存器-寄存器运算，两个源操作数来自 `rj` 和 `rk`，目的寄存器为 `rd`，不访问数据 RAM，且 `gr_we` 置为有效。

## 6. ALU 实现

### 6.1 乘法

ALU 同时生成有符号和无符号的 64 位乘积：

```text
signed_product   = signed(alu_src1) * signed(alu_src2)
unsigned_product = alu_src1 * alu_src2
```

结果选择如下：

```text
mul.w   -> unsigned_product[31:0]
mulh.w  -> signed_product[63:32]
mulh.wu -> unsigned_product[63:32]
```

`mul.w` 的低 32 位与操作数是否按有符号解释无关，因此使用无符号乘积低位即可。

### 6.2 除法和取模

ALU 分别保留有符号和无符号的商、余数：

```text
signed_quotient     = signed(alu_src1) / signed(alu_src2)
signed_remainder    = signed(alu_src1) % signed(alu_src2)
unsigned_quotient   = alu_src1 / alu_src2
unsigned_remainder  = alu_src1 % alu_src2
```

结果选择如下：

```text
div.w   -> signed_quotient
mod.w   -> signed_remainder
div.wu  -> unsigned_quotient
mod.wu  -> unsigned_remainder
```

在本实验测试数据范围内，除数有效且不会触发除零行为。除法和乘法均为组合逻辑，未额外增加流水停顿状态；因此功能上保持一条写回 trace 与参考模型严格一致，但实现报告中应注意组合路径较长的问题。

## 7. 数据相关和旁路

新增指令使用已有的寄存器相关处理逻辑：

- EXE 阶段非访存结果通过 EXE 旁路提供给 ID 阶段。
- MEM 阶段结果通过 MEM 旁路提供给 ID 阶段。
- 如果前一条指令是 load，结果尚未产生，则由 hazard 控制暂停流水线。
- 乘除法指令的 `rj`、`rk` 都参与相关检测，因此连续乘除法和乘除法结果立即被后继指令使用的场景可以正确处理。
- 乘除法结果继续通过已有 WB 通路写回寄存器，trace 的 PC、寄存器号和写回数据格式没有改变。

## 8. 工程文件说明

核心设计文件如下：

- `rtl/ID_stage.v`：新增七条指令的编码识别、ALU 控制码和源寄存器控制。
- `rtl/alu.v`：19 位 ALU 控制解码、乘法、除法、取模及结果选择。
- `rtl/mycpu_head.v`：流水线总线宽度定义。
- `rtl/EXE_stage.v`：接收扩展后的 ALU 控制并把结果传给 MEM。
- `rtl/MEM_stage.v`：保留 EXP6 的访存控制并传递 ALU 结果。
- `rtl/WB_stage.v`：结果写回和 debug trace 输出。
- `ip_ascii/inst_ram/inst_ram.xci`：Vivado 2018.3 指令 RAM IP。
- `ip_ascii/inst_ram/inst_ram.mif`：EXP7 指令初始化镜像。
- `for_test_obj/ex7_obj/`：指导书提供的 EXP7 测试程序和初始化文件。
- `vivado_ex7/loongson_ex7.xpr`：可直接打开的 Vivado 工程。

## 9. 本地验证证据

### 9.1 参考模型

参考模型工程使用 EXP7 的 `inst_ram.mif` 生成黄金 trace：

```text
local_gettrace_ex7/golden_trace_ex7.txt
```

对应日志为：

```text
local_gettrace_ex7/run_reference_ex7.log
```

日志末尾包含：

```text
----Succeed in generating trace file!
```

### 9.2 主 CPU 仿真

主 CPU 使用 `tb_top` 顶层，将每次写回的 PC、寄存器号和数据与黄金 trace 逐条比较。主仿真日志为：

```text
vivado_ex7/loongson_ex7.sim/sim_1/behav/xsim/simulate.log
```

本次结果：

- 功能点 `01` 至 `46` 全部 `PASS`。
- 没有出现 trace `Error!!!`。
- 日志末尾为 `----PASS!!!`。

批处理仿真日志为：

```text
vivado_ex7/run_ex7_sim.log
```

## 10. 波形文件

主仿真波形数据库为：

```text
vivado_ex7/loongson_ex7.sim/sim_1/behav/xsim/tb_top_behav.wdb
```

本次自动仿真已生成 `.wdb`。如果需要在 Vivado 中生成或保存专用波形布局，可启动 `tb_top` 仿真，在波形窗口加入所需信号后使用 `File -> Save Waveform Configuration` 保存 `.wcfg`。

## 11. Vivado 2018.3 复现步骤

直接打开：

```text
vivado_ex7/loongson_ex7.xpr
```

仿真步骤：

1. 打开工程并进入 Simulation。
2. 启动 `tb_top` 行为仿真。
3. 在 Tcl Console 输入：

```tcl
restart
run all
```

4. 在 Tcl Console 或仿真日志中检查功能点 `01~46` 和最终 `----PASS!!!`。
5. 在波形窗口中观察 `debug_wb_pc`、`debug_wb_rf_wnum`、`debug_wb_rf_wdata` 以及流水线内部信号。

综合、实现和 bitstream 步骤：

1. 在 Vivado 中运行 `Run Synthesis`。
2. 综合完成后运行 `Run Implementation`。
3. 实现完成后执行 `Generate Bitstream`。
4. 在线测评平台只上传 `.bit` 文件。

若从原始中文路径直接运行 Vivado 2018.3 时出现 `TclStackFree` 或 IP 初始化错误，可临时执行：

```powershell
subst Y: "D:\something_not_funny\final\计组课设la版\计组课设la版\chapter7_ex7_project"
```

然后从 `Y:` 盘符打开 `Y:\vivado_ex7\loongson_ex7.xpr`。脚本中的 `setup_vivado_ex7.tcl`、`run_ex7_sim.ps1` 和 `run_ex7_build.ps1` 已按该方式配置。

## 12. 生成文件和提交文件

Vivado 2018.3 已成功完成综合、实现、布线和写 bitstream。提交用文件为：

```text
vivado_ex7/loongson_ex7.runs/impl_1/looongson_remote_top.bit
```

同目录还生成了：

```text
vivado_ex7/loongson_ex7.runs/impl_1/looongson_remote_top.bin
```

在线平台只需要 `.bit`，不要把 `.bin`、`.wdb` 或整个 `runs` 目录上传为提交文件。

实现过程的客观结果：

- 综合完成，0 errors。
- 实现完成，0 errors。
- 路由完成，未布通网络数为 0。
- 写 bitstream 完成，DRC 为 0 errors，存在乘法器未流水化的性能警告。
- 由于新增乘除法采用组合实现，时序报告存在较大负裕量；这属于性能/时序收敛问题，不等同于功能仿真失败。报告中应分别描述功能通过和时序结果。
