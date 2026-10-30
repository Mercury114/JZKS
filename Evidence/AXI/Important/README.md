# AXI 重点证据

## 优先阅读

1. `Summary/关键PASS输出汇总.md`：两项测试的覆盖点、PASS 行与边界。
2. `AXI_PASS/screenshots/axi_read_vivado.png`、`axi_write_vivado.png`：Vivado GUI 直接截取的读写握手波形。
3. `AXI_PASS/bridge/xsim.log`、`cpu/xsim.log`：WDB 仿真的实际控制台输出；各目录的 `vcd_export.log` 记录 VCD 导出时再次运行同一测试台的结果。
4. 两个测试目录中的 `.wdb` 和 `.wcfg`：可在 Vivado 中重新缩放、查看信号与截图。

## 打开原始波形

使用 Vivado **2018.3 图形界面**，在 Tcl Console 中执行（路径换成实际克隆位置）：

```tcl
source {仓库完整路径/Evidence/AXI/Important/AXI_PASS/bridge/open_wave.tcl}
```

CPU 集成波形改用 `cpu/open_wave.tcl`。脚本按自身所在目录定位 WDB/WCFG，不依赖归档电脑的原始路径。打开后建议将桥接读事务缩放到约 35–125 ns，写事务缩放到约 120–240 ns；CPU MMIO 写缩放到约 1220–1335 ns。

## 复现

在完整 JZKS 仓库根目录，安装 Vivado 2018.3 后运行：

```powershell
& .\Cache\scripts\run_axi_wave.ps1 -VivadoBin 'D:\Xilinx\Vivado\2018.3\bin'
```

脚本会重新编译 RTL 和两个测试台，生成 WDB/WCFG 和 VCD，产物写入被忽略的 `Cache/build/axi/`。本归档的 `.wdb`、`.vcd` 和日志是 2026-10-30 重新运行所得副本；保留的 `.wcfg` 为适合查看的布局配置。两张读写截图由用户在 2026-10-29 使用 Vivado 直接截取，与重新运行使用同一代码和测试台。`Supplementary` 中的 PNG 是 VCD 数据绘制图，不能当作 Vivado GUI 截图。
