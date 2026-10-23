# 五级流水UART回归入口（2026-10-21）

以下命令在仓库根目录的Linux/WSL中执行，需要Python3和Icarus Verilog：

```bash
python3 innovation_uart/sim/run_control.py
python3 innovation_uart/sim/run_regression.py --mode all
```

run_control覆盖精确CSR返回值、掩码、load依赖及32次中断的寄存器/内存完整性。
run_regression支持console、console_hw、stopwatch、stopwatch_hw、irq、irq_hw、fifo。
真实CPU和源级同步RAM不替换运算结果，初始化来自当前两份UART COE。
Vivado使用run.ps1的-Firmware uart，完整操作与证据见docs/TIMER_IRQ.md和VERIFICATION.md。

## 旧测试说明

# UART FIFO与命令终端仿真

当前使用 `tb_uart_fifo.v` 与 `tb_uart_console.v`，工程仿真顶层默认 `tb_uart_console`。
旧的基本回显自检文件只对应旧汇编程序，不参与当前工程。

- `fifo`：真实串行输入验证16字节FIFO、读写指针回绕、满、溢出、同时读写。
- `simulate`：真实仓库CPU、真实RAM IP、命令固件；快速UART时钟参数64拍/位。
- `simulate_hw`：实际硬件 /16 CPU时钟分支，3.125MHz、326拍/位，外部测试端使用标准9600波特率。

命令测试逐字节解码TX响应，检查LED/数码管、开关极性、计时器实际读值、联动模式及错误恢复。
硬件时钟模式运行8组核心场景，快速模式运行17组场景。
测试平台不会替换CPU，不会强制修改运算结果。

响应包含回车时，Verilog-2001使用八进制转义 `\015`；不能把 `\r` 当作ASCII回车。
运行方法见仓库根目录README。

## 秒表自检

`tb_uart_stopwatch.v` 包含快速模式和硬件分频模式两个顶层。
使用 `run.ps1 -Mode stopwatch` 和 `-Mode stopwatch_hw` 运行。
串口发送START/STOP/TIME/RESET，逐字节解析十进制响应，与独立64位tick模型比对。
通过设置硬件计数器起点加速回绕测试，CPU及软件结果不被强制修改。
当前TIME未开始或RESET后应为0.000秒，原命令回归自检已按该语义更新。

## 定时器中断自检

新增 `tb_uart_irq.v`，包含tb_uart_irq和tb_uart_irq_hwclk两个顶层。
运行 `run.ps1 -Mode irq`、`run.ps1 -Mode irq_hw`。
逐次核对中断现场、ERA/PRMD、TICLR、ERTN、全部通用寄存器恢复、次数和LED相位，
并验证中断期间串口命令及秒表不被破坏。
快速模式的0.5ms周期不作强制修改；硬件模式仅推进定时器接近到期以缩短运行时间。
具体时钟、命令与波形见 `innovation_uart/docs/TIMER_IRQ.md`。


## 综合后板级启动自检

`tb_uart_board_boot.v` 使用真正板级顶层和硬件UART配置，检查复位TX空闲、LED初始化和CPU触发TX起始位。
UART bitstream构建会自动运行该综合后功能仿真；失败则停止，防止RTL仿真通过而综合ROM为空。
CPU的 /16 时钟在XDC中显式约束为320ns，构建结束另查实际布线后的setup/hold。
这项冒烟测试不替代已有完整命令、FIFO、秒表和IRQ回归。
