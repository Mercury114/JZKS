# 当前硬件源码

CPU仍使用仓库原版 `rtl/mycpu_top.v`，内容与Git HEAD一致，没有引入外部流水级文件。
本扩展为UART接收FIFO、汇编命令终端及现有外设交互。

- `rtl/UART/`：TX、RX和16字节接收FIFO。
- `rtl/confreg.v`：UART寄存器及FIFO状态映射。
- `rtl/soc_lite_top.v`：UART连接和时钟参数，保留原有CPU /16硬件时钟。
- `rtl/loongson_remote_top.v`、`remote2local.v`：板级串口、LED和数码管适配。
- `ip/inst_ram`、`ip/data_ram`：分别加载指令程序和字符串数据COE。
- `constraints/loongson_remote.xdc`：远程开发板引脚及时钟约束。

当前工程由仓库根目录 `vivado/run.ps1` 生成，路径为 `vivado/console_build/uart_console.xpr`。
完整命令及演示步骤见仓库根目录README。
