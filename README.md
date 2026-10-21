# JZKS：UART命令终端、外设交互、秒表与定时器中断

直接使用仓库原版 `Exp9_源码_v文件/rtl/mycpu_top.v`，CPU 文件与 Git HEAD 完全一致。
本扩展增加16字节 UART 接收 FIFO，由 CPU 执行汇编程序，按行解析命令并操作现有外设。
没有引入外部工程的 CPU 文件，没有新增指令或修改 CPU 结构。

## 支持的命令

命令每行一条，支持 LF、CR、CRLF。命令名不区分大小写，CODE 的字符参数保留大小写。
数值参数采用十六进制，可省略 `0x`。LED最多4位，DISP最多2位。

| 输入示例 | 串口响应 | 外设效果 |
| --- | --- | --- |
| `HELP` | 命令列表 | 显示可用操作 |
| `CODE A` | `ASCII=0x41` | 数码管显示41 |
| `CODE a` | `ASCII=0x61` | 数码管显示61 |
| `A` | `ASCII=0x41` | 单字符加回车的快捷写法 |
| `LED 00FF` | `OK` | 网页低8位 LED 亮，高8位灭 |
| `DISP 3A` | `OK` | 数码管显示3A |
| `SW` | 例如 `SW=0x5A` | 返回网页低8位拨码开关状态 |
| `IRQ ON` | `OK` | 定时器中断驱动全部16个LED约每0.5秒切换一次；关闭MIRROR |
| `IRQ OFF` | `OK` | 关闭闪灯，保留次数和LED最后状态 |
| `IRQ COUNT` | 例如 `IRQ_COUNT=0x00000004` | 查询本轮闪灯的中断次数快照 |
| `START` | `OK` | 开始或继续计时；重复执行不清零 |
| `STOP` | `OK` | 暂停并保存累计用时，再次START继续 |
| `TIME` | 例如 `TIME=12.345 s` | 显示当前或停止后的用时，单位为秒，保留3位毫秒 |
| `RESET` | `OK` | 仅清零秒表并停止，不复位CPU或其他外设 |
| `STAT` | 例如 `STATUS=0x00000000` | 查询 UART 状态及接收缓存计数 |
| `MIRROR ON` | `OK` | 开关状态实时映射到 LED 和数码管 |
| `MIRROR OFF` | `OK` | 停止联动，输出保持最后的值 |

`CODE`、`LED`、`DISP` 手动输出命令会退出 MIRROR 模式。
支持退格 BS/DEL、空格及 Tab 分隔。CODE适用于一个非空白可打印ASCII字符。
非法命令或参数返回 `ERR`；超过63个字符的整行丢弃并返回 `ERR LINE TOO LONG`，下一行可正常执行。
串口收到命令后返回的是响应文本，不会逐字回显输入行。

## 网页演示

1. 用当前工程重新生成 bit，上传到远程平台。
2. 选择直连 txd/rxd，9600、无校验、8数据位、1停止位。
3. **换行符选择 LF**，命令每行一条；CR或CRLF也可。
4. 打开串口，复位并释放，启动后应看到 `UART CONSOLE READY`。
5. 依次输入 `HELP`、`CODE A`、`LED 00FF`、`DISP 3A`、`SW`、`TIME`。
6. 输入 `START`，等待几秒后输入 `TIME`；输入 `STOP` 后连续输入 `TIME`，结果应保持。
7. 再输入 `START` 继续累计，暂停期间不计入；需要从零重新计时时，先 `RESET` 再 `START`。
8. 输入 `RESET` 后 `TIME` 应返回 `TIME=0.000 s`。
9. 输入 `MIRROR ON` 后拨动网页低8位开关，观察 LED 和数码管跟随；输入 `MIRROR OFF` 停止。

板级 `remote2local` 对本地开关和 LED 取反，汇编程序已转换成网页的直观逻辑：1表示开关ON/灯亮。
高24位拨码开关目前没有接入 SoC；本版本不增加按钮外设。
收到响应后再发送下一条命令。FIFO最多暂存16字节，满时保留旧字节、丢弃新字节并记录溢出。
错误标志在复位时清除，`STAT`只读取状态。

## 文件与实现步骤

1. `rtl/UART/uart_mmio.v`：16字节 FIFO、读写指针、计数及溢出记录。
2. `rtl/confreg.v`：UART寄存器映射和状态返回，保留原同步读时序。
3. `innovation_uart/sw/uart_echo.S`：输入行缓冲、命令解析、外设操作、MIRROR后台循环、秒表状态和时间格式化。
4. `innovation_uart/sw/generate_data.py`：生成字符串数据和命名常量；适配课程汇编器的li.w限制。
5. `innovation_uart/sw/uart.lds`：指令在0x1c000000，字符串在数据RAM的0地址，行缓冲0x1000，栈顶0x3fff0。
6. `sw/build.sh`、`bin_to_coe.py`：生成独立的指令RAM和数据RAM COE。
7. `innovation_uart/sim/`：FIFO单元自检、真实CPU命令测试和实际分频路径自检。

本CPU采用多周期状态机实现；本扩展保持其结构。
指令和数据RAM是分离的，字符串必须加载到数据RAM，不能只放在指令RAM中让普通load指令读取。

## 编译和打开工程

当前两份COE已生成，可直接建工程。修改汇编后，在已配置LA32R工具链的WSL中执行：

```powershell
wsl -d Ubuntu -- bash /mnt/d/2026_ComputerOrganizationLab/JZKS/innovation_uart/sw/build.sh
```

Vivado 2018.3，器件 `xc7a200tfbg676-1`。在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode create
```

**当前工程：`vivado/console_build/uart_console.xpr`。**
工程直接引用仓库里的源码。脚本会检查两份COE的时间和大小，在重新构建固件后更新RAM输出产品。
IP配置、约束和固件输入都在仓库中。

## 自动检查

```powershell
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode fifo
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode simulate
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode simulate_hw
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode stopwatch
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode stopwatch_hw
```

默认仿真顶层 `tb_uart_console`。图形界面启动 Behavioral Simulation 后选择 Run All。
快速命令测试把UART分频设为64以缩短仿真时间，CPU与RAM模型不替换。
硬件路径测试使用真实 /16 CPU分频：3.125 MHz，每位326周期，测试端按标准9600波特率发送和解码。
FIFO测试使用真实UART串行输入，检查容量、顺序、回绕、溢出及同时读写。
旧 `tb_uart_soc.v` 和 `tb_uart_soc_hwclk.v` 仅对应之前的基本回显程序，不加入当前工程。

## 寄存器

| 地址 | 用途 |
| --- | --- |
| `0xBFAFF100` | TXDATA，写低8位启动发送 |
| `0xBFAFF104` | RXDATA，读取FIFO队首并弹出 |
| `0xBFAFF108` | STATUS，[0]非空，[1]发送忙，[2]溢出，[3]帧错，[8:4]FIFO计数 |
| `0xBFAFF020` | 原有LED寄存器，本地低有效，固件负责转换网页逻辑 |
| `0xBFAFF050` | 原有数码管寄存器 |
| `0xBFAFF060` | 原有低8位开关寄存器，本地逻辑取反 |
| `0xBFAFE000` | 原有计时器原始计数 |

硬件计时器输入为50 MHz，快速仿真模式的计时器也使用50 MHz。
TIME显示累计运行用时，暂停期间不计入，不再输出十六进制原始计数。

## 秒表命令在哪里实现

所有命令都是CPU执行的汇编软件，主要实现位于 `innovation_uart/sw/uart_echo.S`：

- `process_line`：识别输入行，分发到各个命令标签。
- `command_start`：保留累计用时，刷新硬件tick基准后继续；运行中重复执行保持计时。
- `command_stop`：补计最后一段时间并关闭运行标志，保留结果。
- `command_reset`：清零累计值并关闭运行标志。
- `stopwatch_update`：循环读取原有硬件计时器，计算无符号32位差值，累加成64位tick。
- `command_time`：取快照，按50000000 tick/秒换算，输出十进制秒及3位毫秒。
- `divide_u64_u32`、`print_decimal_u64`：64位软件除法和十进制输出。

关键字、HELP文本和响应字符串位于 `innovation_uart/sw/generate_data.py`。
硬件计数器仍是 `rtl/confreg.v` 中原有timer，地址0xBFAFE000，没有为这四条命令修改硬件。
`START/STOP/RESET/TIME` 都不接受参数，多余参数返回ERR且不改变计时状态。
计时以CPU处理命令的时刻为准，串口发送和人工输入有通信延迟，输出毫秒部分向下取整。

运行标志保存在r29，64位累计tick保存在r31:r30，上次原始tick存于数据RAM 0x1100。
TIME快照位于0x1120/0x1124，十进制临时缓冲位于0x1140..0x115f。
主循环和串口忙等待都持续调用更新，原始计数器约85.9秒回绕时用模减法处理，不会因此归零。
RESET只重置软件秒表，硬件原始计数器保持运行。

秒表自检覆盖初始零、运行递增、停止冻结、重复STOP、暂停后START继续、运行中重复START、运行中RESET、非法参数、
原始计数器回绕、累计值进入高32位及输出字符串与独立计数模型的比对。
为快速覆盖回绕场景，测试平台仅设置硬件计数器的起点，再让其正常运行；不强制修改CPU寄存器或软件结果。

## 定时器中断驱动LED

复用CPU已有CSR定时器、中断判断、EENTRY/ERA/PRMD和ERTN，不修改CPU硬件。
主程序仍轮询UART；LED切换确实在定时器中断处理程序中执行。
硬件模式使用CPU的3.125MHz时钟，每1562501拍产生一次中断（约0.5秒）；亮灭完整周期约1秒。
快速仿真通过原有SIMU_FLAG选择25001拍（约0.5毫秒），便于运行自检。

每次从关闭状态执行 `IRQ ON`，次数清零并从全灭开始；已开启时重复ON不重置。
`IRQ OFF` 保留最后状态。`LED xxxx`、`MIRROR ON` 自动停止闪灯后接管LED。
`CODE`、`DISP`、`SW`、`STAT`以及秒表命令可在闪灯时继续使用；秒表RESET不会重置IRQ。

演示：`IRQ ON` → 等几秒观察闪灯 → `IRQ COUNT` → `CODE A` → `TIME` → `IRQ OFF`。
再次查询次数应保持；也可在闪灯时输入 `LED 00FF`，确认手动设置不再被覆盖。
原有串口参数不变：直连txd/rxd、9600、8N1、LF，每行一条，收到响应后再发送下一条。

新增自检命令：

```powershell
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode irq
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode irq_hw
```

实现、波形信号和验证范围见 `innovation_uart/docs/TIMER_IRQ.md`。

## 生成 bit

在当前XPR中依次运行 Synthesis、Implementation、Generate Bitstream，或：

```powershell
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode bitstream
```

输出为 `vivado/console_build/uart_console.runs/impl_1/looongson_remote_top.bit`。
功能仿真通过之后，仍需检查实际实现时序，再在远程板上验证。
生成工程、缓存、仿真日志不加入Git；源码、两个COE、XCI、约束和脚本需要保留。
