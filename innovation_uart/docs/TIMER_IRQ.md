# 定时器中断驱动LED闪烁

## 版本保存

2026-10-20修改前版本位于本机：
`D:/2026_ComputerOrganizationLab/JZKS_backups/before_timer_irq_20261020_214806`。
包含源码、配置、完整编译输出和此前已生成的 `verified_before_irq.bit`。
`manifest.json`记录52个文件的SHA256；修改前已逐字节核对源码备份。
备份位于仓库外，本次没有commit或push。

## 修改范围与控制路径

仅增加汇编程序、链接布局、字符串和自检，不修改原CPU及UART硬件。
`sw/uart_echo.S`中的初始化设置EENTRY=0x1c001000、ECFG.LIE[11]=1，默认保持全局中断关闭。
`command_irq`解析ON/OFF/COUNT，`irq_on`配置周期定时器并开启CRMD.IE。
`irq_disable`先关闭全局IE，再停止TCFG、清TICLR，供OFF、LED和MIRROR ON复用。
`sw/uart.lds`将`.text.irq`固定在指令RAM偏移0x1000，链接时检查主程序不能覆盖入口。

CPU已有中断条件为 `CRMD.IE && |(ESTAT.IS & ECFG.LIE)`。
当前CPU是多周期状态机，在S_EXEC执行当前指令之前判断中断。
进入中断时硬件保存ERA和PRMD、关闭IE、跳转EENTRY；当前指令尚未执行。
处理程序为使用的r12..r15分配32字节栈帧，保存寄存器并检查中断原因。
随后写TICLR[0]清定时器中断，累计次数、切换LED，恢复寄存器与SP，执行ERTN。
ERTN恢复CRMD并返回ERA，被打断的指令继续执行，不跳过一条指令。
中断中不调用串口打印、不重新开启IE、不进行嵌套中断。
非预期同步异常停在irq_fault保留现场，不把它当作定时器事件返回。

## 时钟与周期

硬件CPU时钟=50MHz/16=3.125MHz，TCFG=1562503。
其中初值1562500、周期模式bit1=1、使能bit0=1。
当前CPU计数器从初值递减至0，再触发并重装，间隔为1562501个CPU周期：约0.50000032秒。
全部16个LED每次中断在全亮/全灭之间切换，完整亮灭周期约1秒。
快速仿真检测已有SIMU_FLAG，将TCFG设置为25003，50MHz下每25001拍触发，约0.5毫秒。
板上SIMULATION=0，不会使用快速仿真的周期。

CPU内部CSR定时器与confreg中0xBFAFE000的50MHz计数器相互独立。
秒表仍读取原有confreg计数器，不因IRQ ON/OFF改变计时语义。

## 命令语义

| 命令 | 行为 |
| --- | --- |
| IRQ ON | 从关闭状态开启时清次数、LED全灭；自动关闭MIRROR；已开启时重复ON幂等 |
| IRQ OFF | 停止闪灯，保留最后LED状态和中断次数；重复OFF幂等 |
| IRQ COUNT | 返回32位十六进制次数快照，例如IRQ_COUNT=0x0000000A表示10次 |
| LED xxxx | 参数合法后关闭闪灯和MIRROR，再设置全部16个LED |
| MIRROR ON | 关闭闪灯，转为开关控制LED和数码管 |
| CODE / DISP | 更新数码管并关闭MIRROR，不停止独立的中断闪灯 |
| START / STOP / TIME / RESET | 只操作秒表，与中断闪灯独立 |

关闭闪灯后重新ON开始新一轮次数；次数为32位，达到最大值后模2^32回绕。
COUNT先读取快照再打印，因此响应期间实际次数可能继续增加。
未知参数、ONX、额外参数等返回ERR，不改变中断状态。

## 验证方法

`tb_uart_irq.v`实例化真实仓库CPU、真实RAM IP和当前固件，通过串行输入命令并逐字节检查输出。
独立监视S_EXEC的has_int、通用寄存器快照、ERA/PRMD、TICLR、ERTN和实际LED总线写入。
每次返回前检查全部31个非零通用寄存器（包括SP）与进入时相同，返回后PC和IE恢复。
中断次数的内存写入、串口COUNT快照和LED相位相互交叉检查。
覆盖默认关闭、非法参数、重复ON/OFF、后台ASCII/数码管/开关/秒表、手动LED与MIRROR接管。

快速模式不强制修改定时器，直接验证相邻到期事件间隔为25001拍。
硬件模式使用真实/16分频、326拍UART和外部标准9600波特率；核对TCFG初值及逐拍递减。
为缩短硬件模式仿真，测试平台仅把CPU内定时器timer_cnt推进至接近到期，再让真实硬件触发。
不强制修改CPU状态、通用寄存器、CSR使能/屏蔽、软件中断次数、RAM结果或LED数据。
这部分是硬件仿真加速手段，实体板仍需通过新bit确认实际约0.5秒的闪灯效果。

## 截图信号

在IRQ自检中加入：
`dut.cpu.pc`、`state`、`has_int`、`timer_cnt`、`csr_crmd`、`csr_ecfg`、
`csr_estat`、`csr_era`、`csr_eentry`、`inst_ertn`、
`dut.cpu_data_en`、`cpu_data_we`、`cpu_data_addr`、`cpu_data_wdata`、`web_led`。
展示定时到期/ESTAT[11]置位、PC进入0x1c001000、LED地址0xBFAFF020写入、
TICLR清标志、ERTN恢复ERA的完整过程。控制台应出现UART_IRQ_PASS和UART_IRQ_VERIFIED。

工程仍为 `vivado/console_build/uart_console.xpr`，默认仿真顶层保持tb_uart_console。
汇编重新构建后，两份COE都需要更新，脚本已自动重新生成RAM输出产品。
本次未重新生成bit、未在远程实体板测试中断版本，需用户重新综合、实现、生成bit并上传演示。
