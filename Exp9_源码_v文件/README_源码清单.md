# Exp9 Verilog 源码清单

来源工程：`Exp9_第五章_完整工程`

本目录收集该 Exp9 工程中的全部 13 个 `.v` 文件，共约 423 KiB。目录层级与原工程保持一致，因此两个 IP 目录中的同名 `blk_mem_gen_v8_4.v` 不会互相覆盖。

## 课程 RTL

```text
rtl/mycpu_top.v
rtl/soc_lite_top.v
rtl/bridge_1x2.v
rtl/confreg.v
rtl/remote2local.v
rtl/loongson_remote_top.v
```

其中 `mycpu_top.v` 是 CPU 核心；`soc_lite_top.v` 是 SoC 连接和硬件/仿真时钟选择；`bridge_1x2.v` 连接 CPU 数据端口与数据 RAM/配置寄存器；`confreg.v` 实现 LED、数码管、按键和计时器；`loongson_remote_top.v` 是板级顶层。

## 测试平台

```text
tb_top.v
```

该文件实例化 `soc_lite_top`，产生时钟和复位，并检查数码管功能点。Exp9 应看到功能点 1 至 58 全部通过。

## Vivado IP Verilog 文件

```text
ip_ascii/clk_pll/clk_pll.v
ip_ascii/clk_pll/clk_pll_clk_wiz.v
ip_ascii/data_ram/sim/data_ram.v
ip_ascii/data_ram/simulation/blk_mem_gen_v8_4.v
ip_ascii/inst_ram/sim/inst_ram.v
ip_ascii/inst_ram/simulation/blk_mem_gen_v8_4.v
```

`sim` 目录中的 `data_ram.v` 和 `inst_ram.v` 是对应 RAM IP 的仿真封装；`simulation/blk_mem_gen_v8_4.v` 是 Block Memory Generator 的仿真模型。两个 RAM 目录各自保留一份同名模型，编译时应只加入对应 IP 的模型，不能把两个同名文件同时重复加入同一编译单元。

## 建议阅读顺序

1. `tb_top.v`：先了解功能点检查方式。
2. `rtl/loongson_remote_top.v`：查看板级顶层。
3. `rtl/soc_lite_top.v`：查看 CPU、RAM、桥和外设连接。
4. `rtl/mycpu_top.v`：阅读指令译码、乘除法、访存和写回。
5. `rtl/bridge_1x2.v`、`rtl/confreg.v`：阅读总线分发和外设。
6. `ip_ascii`：最后查看 Vivado 自动生成的 IP 封装和 RAM 仿真模型。

该目录只收集 `.v` 文件；`.xci`、`.xdc`、`.mif`、`.coe` 等工程配置和初始化文件仍在完整工程目录中。
