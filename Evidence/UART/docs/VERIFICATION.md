# 五级流水 UART IRQ 修复验证

日期：2026-10-21。基于最新main `a6223e5`，复核诊断分支 `4a8d6ba`。
实际验证对象为 `Exp9_源码_v文件/rtl` 的课程五级流水SoC。
旧多周期CPU的证据保存在 `VERIFICATION_MULTICYCLE_20261020.md`，不能混用CPU哈希或测试结果。

## 当前修复版结果

| Icarus模式 | 场景 | 检查数 |
| --- | --- | --- |
| console | 17 | 962 |
| console_hw | 8 | 230 |
| stopwatch | 11 | 1099 |
| stopwatch_hw | 11 | 1099 |
| irq | 10 | 1246 |
| irq_hw | 10 | 29608 |
| fifo | — | 118 |
| 合计 | — | 34362 |

额外架构回归：CSR读/写/交换/零寄存器/加载依赖6项通过；
精确中断压力测试3514项通过，32次进入与返回，1164次完整前台递增/加载/存储迭代。
两个最小测试在未修改的a6223e5上均失败，分别检出CSR返回值混入CSR编号、未排空流水线即进入中断。
相同测试在本次修复后通过，不靠修改期望值、重复加载或插NOP绕过。

Vivado 2018.3/XSim另行验证IRQ：10组、1246项、11次进入及返回，UART固件镜像正确装载。
Icarus硬件分频IRQ：703次进入及703次返回，UART按标准9600波特率。
为缩短硬件模式仿真，仅推进定时器接近到期；没有强制修改GPR、ERA、IE、ISR次数或LED结果。

Cache目录独立回归：46个CPU场景/528次随机反压通过；24组系统精确GPR轨迹和提交内存比对通过。
Cache/D-cache源码、原UART FIFO及confreg、官方Exp9镜像、原汇编ISR和两份COE保持与a6223e5一致。
UART在课程五级SoC上验证，Cache回归使用Cache自己的SoC；不是新增一次Cache/UART同SoC集成。

## 复现命令（已安装Icarus和Python3的Linux/WSL）

```bash
python3 innovation_uart/sim/run_control.py
python3 innovation_uart/sim/run_regression.py --mode all
python3 Cache/tests/run_cpu.py
python3 Cache/tests/run_system.py
```

负例命令预期失败，证明能检出原问题：

```bash
python3 innovation_uart/sim/run_control.py --baseline a6223e5 --case csr
python3 innovation_uart/sim/run_control.py --baseline a6223e5 --case irq
```

机器可读记录为 `pipeline-irq-verification.json`；运行日志在忽略的 `innovation_uart/build/`。
本次未commit、未push。已修复下述硬件初始化问题并生成新bit；平台重新上传验收待完成。


## 2026-10-21 板上无串口响应修复

旧 bit 对应综合网表在板级复位后仍无 TX 字节、LED=ffff，复现了平台现象。
检查发现综合后的指令 RAM 起始内容全零；正确的 RTL MIF 并不能证明 bit 内的 BRAM 已正确初始化。
`course_ram.v` 将仿真补零循环放入 synthesis translate_off/on，综合仅以 MIF 为初始化来源。
原 UART 固件、两份 COE 和 CPU 指令集不变。

新增 `tb_uart_board_boot.v`，实例化真正板级顶层，使用50MHz时钟、板级复位和实际9600波特率。
综合后功能仿真检查复位时TX空闲为高、CPU启动后LED输出为0000、CPU触发TX起始位，3项检查通过。
这是启动冒烟测试；完整命令功能由原有RTL回归覆盖，不宣称此测试检查了所有命令。
本次另行重跑 console 的17组/962项和 irq 的10组/1246项，均通过，11次中断进入与返回匹配。

补充 `cpu_clk` 的 /16 生成时钟约束，周期320ns；重新实现后的setup/hold检查通过。
`run.ps1 -Mode bitstream -Firmware uart` 会先综合并执行板级启动自检，再实现和生成bit，最后检查实际CPU时序。
机器可读证据见 `board-build-verification.json`，实际FPGA平台需重新上传新bit验证。
