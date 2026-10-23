# UART 关键 PASS 输出汇总

原始测试日期为 2026-10-21，归档日期为 2026-10-23。检查数表示自动断言/比对执行次数，不表示功能种类或指令条数。

| 模式 | 场景数 | 检查数 | 结果 |
| --- | --- | --- | --- |
| console | 17 | 962 | PASS |
| console_hw | 8 | 230 | PASS |
| stopwatch | 11 | 1099 | PASS |
| stopwatch_hw | 11 | 1099 | PASS |
| irq | 10 | 1246 | PASS |
| irq_hw | 10 | 29608 | PASS |
| fifo | — | 118 | PASS |
| 合计 | — | 34362 | PASS |

console 覆盖初始化启动、命令解析、ASCII 显示、LED/开关联动、非法输入和长行恢复。
fifo 覆盖 16 字节容量、顺序、回绕、满溢出和同时读写。
stopwatch 覆盖启停、暂停继续、清零、32 位计数回绕及 64 位累计输出。
irq 覆盖中断闪灯、开关幂等性、计数、前台命令共存及现场恢复。
_hw 使用实际 CPU 分频路径和标准 9600 波特率；为了缩短 IRQ 等待，测试会推进定时器接近到期，不能视为实板长时间压力测试。

### console

```text
UART_CONSOLE_PASS: hardware_clock=0 cases=17 checks=962
```

### console_hw

```text
UART_CONSOLE_PASS: hardware_clock=1 cases=8 checks=230
```

### stopwatch

```text
UART_STOPWATCH_PASS: hardware_clock=0 cases=11 checks=1099
```

### stopwatch_hw

```text
UART_STOPWATCH_PASS: hardware_clock=1 cases=11 checks=1099
```

### irq

```text
UART_IRQ_PASS: hardware_clock=0 cases=10 checks=1246 entries=11 returns=11
```

### irq_hw

```text
UART_IRQ_PASS: hardware_clock=1 cases=10 checks=29608 entries=703 returns=703
```

### fifo

```text
UART_FIFO_PASS: checks=118
```

## XSim 波形对应结果

```text
UART_IRQ_PASS: hardware_clock=0 cases=10 checks=1246 entries=11 returns=11
```

来源：UART_PASS/uart_irq_xsim.log；对应 UART_PASS/tb_uart_irq_behav.wdb。
这是相同模式的另一工具验证，1246 不重复累加进 34362。

## 附加架构检查（不计入上表）

```text
PIPELINE_CONTROL_PASS: case=csr checks=6
PIPELINE_CONTROL_PASS: case=irq checks=3514 entries=32 returns=32 iterations=1164
```

来源：UART_PASS/pipeline_csr.log、pipeline_irq_context.log。
