# LoongArch32R 创新 CDE 工程

本仓库是北京科技大学《计算机组成原理课程设计》小组的最终工程整理版，基于远端 `main`，源自团队工程基线 `308b6aa`。工程围绕课程五级流水 CPU，整理了 I-Cache、D-Cache、UART 外设和 AXI 主接口四条扩展链路，并保留可复现的 RTL、测试台、脚本、初始化镜像、验证摘要和工程文档。

## 老师先看这里

1. **[教师验收导航](docs/教师验收导航.md)**：按推荐顺序进入源码、测试和证据。
2. **[姜皓凯个人贡献](docs/个人贡献_姜皓凯.md)**：个人负责范围、代码位置、集成工作和验证数据。
3. **[Cache 设计与测试报告](Cache/docs/缓存设计与测试报告.md)**：I/D Cache、公共接入、CACOP、仲裁器和性能对照。
4. **[UART 验证记录](innovation_uart/docs/VERIFICATION.md)** 与 [定时器中断说明](innovation_uart/docs/TIMER_IRQ.md)：命令终端、秒表、FIFO、IRQ 和板级启动检查。
5. **[AXI 验证摘要](Evidence/AXI/Important/Summary/verification-results.json)**：读写握手、窄写、反压和响应检查。
6. **[压缩包交付说明](docs/交付说明.md)**：最终提交包的内容、清理规则和复现入口。
7. **[本次整理验收](docs/本次整理验收.md)**：基线、当前快速回归和压缩前验收记录。

个人贡献在工程入口处单独列出，便于从源码和验证记录逐项核对；团队成员的模块边界也在该文档中明确标注。

## 工程结构

| 路径 | 内容 | 主要入口 |
| --- | --- | --- |
| `Exp9_源码_v文件/` | 课程 Exp8/Exp9 五级流水 SoC、板级顶层、UART 接口和教师测试台 | `rtl/mycpu_top.v`、`rtl/loongson_remote_top.v`、`tb_top.v` |
| `Cache/` | I-Cache、集成 D-Cache、五来源仲裁、SRAM bridge、缓存 CPU、AXI 顶层及回归 | `tests/run_all.py`、`rtl/cache_system.v` |
| `D-cache/` | 独立 D-Cache、写回/写分配实现和原始测试台 | `rtl/dcache.v`、`tb/dcache_tb.v` |
| `innovation_uart/` | UART 固件、FIFO/命令/秒表/IRQ 测试台和修复记录 | `sim/run_regression.py`、`sw/uart_echo.S` |
| `vivado/` | 官方 Exp9 与 UART 固件工程的创建、仿真和综合脚本 | `run.ps1`、`run.tcl` |
| `Evidence/` | 按 AXI、D-Cache、UART、Full Exp 分组的日志、截图、摘要、清单和哈希 | 各目录 `README.md` 与 `Important/Summary/` |
| `artifacts/` | 已归档的工程交付产物和来源说明 | `artifacts/pipeline-cache-uart/` |
| `Junwei_Jian's Exp1~Exp7/` | 组内课程实验备份，保留在远端主线 | 目录内 `README.md` |

`Cache/` 和 `D-cache/` 是两个接口不同的交付树：前者是 I/D Cache 与五级流水的公共集成版本，后者保留独立 D-Cache 贡献，不能把两套 CPU、测试台或工程文件混编。课程官方 Exp9 与 UART 演示也使用不同固件入口，见 `PIPELINE_CACHE_UART.md`。

## 创新内容总览

### I-Cache 与公共接入

`Cache/rtl/cache_icache.v` 支持 16 B cache line、1/2/4 路配置、无效路优先和真 LRU；命中路径加入请求寄存与查询/响应流水。`cache_subsystem.v`、`cache_mem_arbiter.v`、`cache_sram_bridge.v` 和板级顶层把 I 回填、D 回填、D 脏块写回及 I/D 非缓存访问统一到逐字主存握手上，并保持外设低位地址和字节使能。五级流水 CPU 处理可变延迟访存、跳转/异常后的旧取指响应丢弃、load 等待、store 去重和 CACOP 串行完成。

### D-Cache

D-Cache 支持写命中 byte-enable merge、write-allocate、16 B 整行回填、128 bit 脏块写回、真 LRU 和 1/2/4 路配置。缓存管理路径覆盖初始化、无效化、写回和写回后无效化；外设地址走 uncached bypass。完整接口和状态机说明见 `Cache/docs/缓存设计与测试报告.md`，独立版本见 `D-cache/DCache_写入机制技术文档.md`。

### UART 外设

`innovation_uart/` 和 `Exp9_源码_v文件/rtl/UART/` 提供 TX、RX、16 字节接收 FIFO、状态/错误标志、命令终端、LED/数码管控制、秒表和定时器 IRQ 演示。`TIMER_IRQ.md` 记录了 CSR 读回、精确 ERA、流水线排空和 RAM 初始化问题的修复路径。

### AXI 主接口

`Cache/rtl/cache_axi_bridge.v` 将缓存和 MMIO 的逐字请求接到 AXI4 五通道。读通道保持 AR 反压下的稳定载荷，写通道分别跟踪 AW/W 握手，按 WSTRB/AWSIZE 支持字节和半字窄写，等 B 响应后才向内部请求报告完成，并检查响应 ID、RESP 和 RLAST。

## 验证结果

以下数字来自仓库中的机器可读摘要和日志，按验证层级分别记录：

| 验证对象 | 已归档结果 | 证据入口 |
| --- | --- | --- |
| I/D Cache 集成 | 完整入口 30 项检查；CPU 46 个场景、528 次变延迟/反压运行；D-Cache 1/2/4 路共 1800 次随机读写；整机 24 次独立 ISA 对照 | `Cache/docs/verification-results.json` |
| 教师程序 | ex4～ex9 分别通过 29/33/39/46/47/58 项；ex9 在 1/2/4 路和禁用 Cache 配置均为 58/58 | `Evidence/Full Exp (with Exp8 and Exp9)/Important/Summary/关键 PASS 输出汇总.md` |
| UART | console、硬件分频 console、stopwatch、硬件分频 stopwatch、IRQ、硬件分频 IRQ、FIFO 共 34,362 项检查；另有 CSR 6 项和精确 IRQ 3,514 项 | `innovation_uart/docs/VERIFICATION.md`、`Evidence/UART/Important/Summary/pipeline-irq-verification.json` |
| UART 板级工程 | 综合后启动冒烟 3 项通过，路由 setup/hold 检查通过，CPU 分频时钟约束为 320 ns | `innovation_uart/docs/board-build-verification.json` |
| AXI | bridge 与 CPU/Cache/MMIO 两个 Vivado XSim 测试台通过，覆盖读写反压、AW/W 顺序、窄写、B/R 完成和 SLVERR 传播 | `Evidence/AXI/Important/Summary/verification-results.json` |

Cache 的 30 项回归是本地 RTL 编译与 Icarus 仿真结果；AXI 摘要是 Vivado 2018.3 XSim 结果；UART 还包含 Icarus、Vivado IRQ 仿真和综合后板级启动检查。UART 远程 FPGA 平台重测、Cache 的 Vivado 资源/时序、AXI burst/多 outstanding 与板级验收，均按各摘要中的验证层级保留记录。这样可以直接从证据文件区分模块仿真、整机仿真、综合实现和平台测试。

缓存性能对照使用同一五级 CPU、同一程序、同一主存延迟，并把 I/D 缓存容量固定为各 512 B：热点循环为无缓存 13,121 周期、缓存 3,196 周期；同组冲突为 13,121、14,499、3,285、3,285 周期（无缓存、直接映射、两路、四路）；冷启动加自修改代码与异常为 1,297、1,399、1,399、1,399 周期。完整统计和计数口径见 Cache 报告。

## 复现入口

在安装 Python 3 和 Icarus Verilog 的 Linux、macOS 或 WSL 环境中，从仓库根目录运行：

```bash
python3 Cache/tests/run_all.py
python3 Cache/tests/run_cpu.py
python3 Cache/tests/run_system.py
python3 Cache/tests/run_teacher.py
python3 innovation_uart/sim/run_control.py
python3 innovation_uart/sim/run_regression.py --mode all
```

`Cache/tests/run_all.py` 会生成 `Cache/docs/verification-results.json` 和 `Cache/build/` 下的过程产物；`innovation_uart` 的日志写入被忽略的 `innovation_uart/build/`。教师程序输入保存在 `Cache/fixtures/`，脚本先检查 COE 的 SHA-256，再生成仿真镜像。

Windows/Vivado 入口：

```powershell
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode create -Firmware ex9
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode bitstream -Firmware ex9
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode bitstream -Firmware uart
```

`-Firmware ex9` 使用课程官方镜像，`-Firmware uart` 使用 UART 演示镜像；两者的工程、初始化文件和验收口径分开保存。详细的板级检查顺序见 `innovation_uart/docs/TIMER_IRQ.md` 和 `PIPELINE_CACHE_UART.md`。

## 交付说明

本仓库保留远端 `main` 的完整历史和所有证据。提交给老师的压缩包按 [交付说明](docs/交付说明.md) 清理可再生的仿真波形、Vivado 构建目录和课程实验备份，保留源码、脚本、初始化入口、关键日志、截图、摘要、清单和哈希，确保文件大小不超过 200 MB。

远端 `main` 已于 2026-11-09 与本地整理结果核对一致；其团队工程基线为 `308b6aa85893cbda447d392f140bb3cf34639694`（2026-11-02）。本地整理不覆盖 `uart-irq-wip`，该分支不是 `main` 的合并祖先。
