# UART 重点证据

## 优先阅读

1. Summary/关键PASS输出汇总.md：覆盖范围、检查数及原始 PASS 行。
2. UART_PASS/ 中的 7 份功能日志：console、console_hw、fifo、stopwatch、stopwatch_hw、irq、irq_hw。
3. UART_PASS/uart_irq_xsim.log 和 tb_uart_irq_behav.wdb：同一 XSim 中断仿真的日志与波形。
4. UART_PASS/pipeline_csr.log 和 pipeline_irq_context.log：CSR 与精确中断现场恢复的附加测试。

## 波形打开

推荐使用原产物工具 Vivado 2018.3。在 Vivado Tcl Console 中执行：

```tcl
cd {解压后的完整路径/Evidence/UART/Important/UART_PASS}
source open_wave.tcl
```

脚本从自身位置加载 WDB，并添加数据库中可用的顶层信号；支持存在的中断内部信号时也会加入。
该数据库对应快速 IRQ 仿真，不是 irq_hw 硬件时钟模式。串口硬件时钟验证见 irq_hw.log。
查看 uart_rx、uart_tx、web_led、num_data、test_end、global_err、checks 等；中断进入/返回和 GPR 恢复的自动判据见日志及仓库 tb_uart_irq.v。
无需依赖原电脑上的 XPR 绝对路径即可查看已记录的波形。

## 复现（在完整 JZKS 仓库根目录）

Linux/WSL，安装 Python3 和 Icarus Verilog 后：

```bash
python3 innovation_uart/sim/run_control.py
python3 innovation_uart/sim/run_regression.py --mode all
```

Windows，安装 Vivado 2018.3 后：

```powershell
powershell -ExecutionPolicy Bypass -File .\vivado\run.ps1 -Mode irq -Firmware uart
```

原始文档：../docs/VERIFICATION.md 和 ../docs/TIMER_IRQ.md。
清单 manifest.json 给出来源、大小和 SHA256；SHA256SUMS.txt 用于完整性核对。
