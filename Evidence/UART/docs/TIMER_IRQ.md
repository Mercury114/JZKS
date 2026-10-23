# 五级流水定时器IRQ修复与演示

## 根因

旧的多周期实现已被替换为五级流水，不能继续假定进入/退出中断时没有在途指令。

1. CSR编号与普通立即数字段重叠，旧ID路径把CSR读值加上了编号。
   例如SAVE0初始0却返回0x30；TCFG初始0可能被读成0x41，IRQ ON误以为已经开启。
2. CSRXCHG的GPR返回值误用了掩码，应返回旧CSR；CSRWR的rd源也需要加载相关检查。
3. CSR读组合函数只以编号作为显式输入；相邻同号访问的读值更新不可靠，改为显式组合case。
4. 仅在ID空泡进入中断并不代表EX/MEM已提交，旧ERA还用取指地址减4猜测。
5. ERTN/CSR/异常可能在前面恢复寄存器、访存尚未完成时生效；控制副作用也需受真实ID握手约束。
6. 板级分频时钟初始保持低，仿真从低复位开始时需确定cpu_resetn上电值。

## 修复方法

`ID_stage.v`：CSR和计数器读回以0为ALU加数，CSRXCHG单独保留旧CSR与写掩码路径，
补CSRWR加载依赖；副作用使用 `ds_fire = valid && ready && es_allowin`。
CSR、异常、ERTN和CACOP等串行控制等待旧EX/MEM排空，普通算术/访存仍按原流水前递运行。
定时器中断挂起时停止ID发射，让旧指令自然提交；待ID有下一条未执行指令且EX/MEM空时响应。
`mycpu_top.v`保存这条ID指令的真实PC到ERA，屏蔽IE并跳EENTRY；不再从取指地址反推。
`ERTN`等待最后一条寄存器恢复提交后返回，所有GPR和SP得到保留。

复用主线原单次加载的 `uart_echo.S` 和两份COE，没有合入WIP中的重复加载、NOP或跳过异常原因检查。
UART FIFO保持主线已修复的“同步MMIO读请求只弹出一次”实现。
测试保留严格的一次ISR一次计数写入及全部31个非零GPR恢复检查，不忽略非预期写入。

## 行为

串口9600、8N1、换行LF，逐条命令等待响应：

| 命令 | 行为 |
| --- | --- |
| IRQ ON | 关闭状态开始新一轮，次数归零、LED全灭；已开启时重复ON不重置 |
| IRQ OFF | 停止闪灯，保留最后LED状态和次数 |
| IRQ COUNT | 返回32位十六进制次数快照，0x0000000A即10次 |
| LED xxxx / MIRROR ON | 参数合法后先停中断闪灯，再接管LED |
| CODE / DISP / SW / STAT | 可在闪灯时使用，CODE和DISP关闭MIRROR但不停止独立IRQ |
| START / STOP / TIME / RESET | 仍为独立秒表，不改变中断闪灯状态 |

硬件CPU时钟50MHz/16=3.125MHz，TCFG初值1562500，间隔1562501拍，约0.5秒切换亮灭。
快速仿真通过SIMU_FLAG使用25001拍/50MHz，即约0.5毫秒。
CPU内部CSR定时器与confreg的50MHz秒表计数器相互独立。

## 生成正确的UART工程和bit

官方Exp9固件与UART固件必须区分，官方镜像不覆盖。
UART MIF由跟踪的两份COE生成，放在忽略的sw/obj中；无需重新汇编即可从clone重建工程。

```powershell
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode create -Firmware uart
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode irq -Firmware uart
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode bitstream -Firmware uart
```

需安装Python3；可用 `-Python` 指定解释器，用 `-Vivado` 指定Vivado路径。
UART工程为 `vivado/console_build_uart/pipeline_uart.xpr`，UART bit为
`vivado/console_build_uart/pipeline_uart.runs/impl_1/looongson_remote_top.bit`。
官方Exp9仍用 `-Firmware ex9` 和原 `vivado/console_build/pipeline_uart.xpr`。
省略Firmware时，create/bitstream默认ex9，各UART仿真模式默认uart。

## 平台验收

上传新UART bit，打开串口后复位，应收到UART CONSOLE READY。
IRQ ON后等待几秒观察约0.5秒亮灭切换；IRQ COUNT约每秒增加2。
闪灯时执行CODE A、DISP 3A、SW、秒表命令，检查前台响应仍正确。
IRQ OFF后间隔两次查询次数应保持；LED 00FF接管后不应再被ISR覆盖。

## 波形

观察 `dut.cpu.interrupt_redirect`、`timer_has_int`、`id_pc`、`id_valid`、`pipeline_busy`、
`csr_estat`、`csr_era`、`csr_eentry`、`csr_crmd`、`id_ertn`、
`dut.cpu_data_en/we/addr/wdata`和`web_led`。
确认IRQ响应时ID有效且旧流水为空，ERA等于被暂停的ID PC；PC跳0x1c001000，
TICLR清标志、LED地址0xBFAFF020写入，ERTN在所有寄存器恢复后返回。
不能再使用旧多周期的state==S_EXEC/has_int作为一次IRQ入口判据，也不能用重定向后的取指PC充当ERA。

最新测试结果见VERIFICATION.md和pipeline-irq-verification.json。
已修复指令RAM综合初始化并生成新bit；综合后板级启动及实现时序通过，平台重测待完成。详见VERIFICATION.md。
