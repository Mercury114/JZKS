# Cache集成版本

本目录对应小组分工的“A：I-Cache＋公共接入”，并补齐截图中的四项缓存内容。
从 `D-cache` 分支 `3487cdd` 继续，未覆盖 `D-cache/` 或原 `Exp9_源码_v文件/`。

## 先看这三个文件

1. [我的完成说明](docs/我的完成说明.md)：我做了什么、哪些来自同伴、哪些仍需硬件验证。
2. [缓存设计与测试报告](docs/缓存设计与测试报告.md)：统一接口、结构与实测结果。
3. [Vivado验证与上板操作](docs/Vivado验证与上板操作.md)：Windows/Vivado操作入口。

## 对应课程要求

| 要求 | 本目录实现 |
|---|---|
| 一路直接映射Cache，I/D均支持 | `WAY_NUM=1`；模块、整机、原教师程序回归 |
| Cache指令 | `CACOP`：00/01、08/09、10/11；实际CPU译码和缓存执行，不只是控制端口 |
| 多路组相连 | `WAY_NUM=2/4`；无效路优先、真正LRU；D脏块先写回 |
| Cache流水化 | I-Cache请求寄存与查询/响应两阶段；热命中连续每周期一请求、一响应 |

## 源码入口

```text
rtl/cache_system.v          五级CPU＋缓存系统，通用逐字主存接口
rtl/cache_subsystem.v       I/D连接、外设旁路、CACOP管理路由
rtl/cache_icache.v          1/2/4路只读缓存与命中流水化
rtl/cache_dcache.v          从同伴实现扩展的写回/写分配缓存
rtl/cache_mem_arbiter.v     五来源轮转仲裁与整行拆字
rtl/cache_sram_bridge.v     逐字握手转换为一拍同步SRAM
rtl/cache_soc_lite_top.v    课程SoC连接，复用原confreg
rtl/cache_remote_top.v      CDP远程板复位、拨码、LED与数码管接入
rtl/cache_board_ram.v       可综合的一拍RAM描述，程序从hex初始化
rtl/cpu/                   真正IF/ID/EXE/MEM/WB五级核心
tb/                        独立模块、总线、CPU、整机测试
tests/                     一键回归、独立ISA参考、教师原程序回归
fixtures/                  原教师ex4~ex9 COE的无损压缩副本与哈希
scripts/                   Vivado输入准备、工程、仿真和综合脚本
constraints/               有来源记录的CDP远程板引脚/时钟约束
docs/                      贡献说明、团队报告、验证结果
```

不要把本目录CPU与旧 `Exp9_源码_v文件/rtl/mycpu_top.v` 或个人项目的另一份CPU混编。
`tests/` 和Vivado脚本已经提供明确文件集，不依赖个人项目目录。

## 配置

- 默认：256组、2路、16B行，I/D各8KiB；地址为 `tag[31:12]/index[11:4]/offset[3:0]`。
- `WAY_NUM=1/2/4` 选择直接映射/两路/四路；行长固定16B。
- `INDEX_WIDTH` 改变组数，tag宽度自动随之调整。
- `ENABLE_CACHE=0`：同一五级CPU经同一仲裁器访问主存，用于功能及性能对照。
- `cache_system.BOARD_ADDR_MAP=0` 默认保留完整地址；课程SoC设1，在缓存前归一化原data_ram低18位镜像，避免同一物理字出现两个脏副本。
- `bfaf_xxxx` / `1faf_xxxx` 按原桥的地址掩码旁路，不分配缓存、不整行访问、不重复写外设。

## 本地复现

在仓库根目录运行：

```sh
python3 Cache/tests/run_all.py
```

默认执行全部模块、528次CPU变延迟回归、24次整机参考对照、教师ex4~ex9、ex9其它路数/无缓存对照。
`--quick` 跳过教师程序，不作为完整交付记录。

也可分别执行：

```sh
python3 Cache/tests/run_cpu.py
python3 Cache/tests/run_system.py
python3 Cache/tests/run_teacher.py
python3 Cache/tests/run_teacher.py --exp 9 --ways 1
python3 Cache/tests/run_teacher.py --exp 9 --ways 4
python3 Cache/tests/run_teacher.py --exp 9 --no-cache
```

构建、详细日志与仿真数据在 `Cache/build/`，不提交；完整回归结果与源码SHA256清单保存在
[docs/verification-results.json](docs/verification-results.json)。

## 实现边界

I-Cache本体具备每周期命中吞吐；CPU取指目前仅一笔未完成请求，不承诺整机每周期一条指令。
D-Cache为阻塞式写回缓存，不声称D侧也实现了流水化或多笔未完成miss。
缓存数据数组采用寄存器描述；其资源与频率须由Vivado实测。板级主存的块RAM推断也须查看综合报告。
本课程版本无MMU/DMW/MAT、无AXI、无DMA或多核硬件一致性；CACOP初始化采用教学用清tag/无效化，不实现任意CSR.CTAG写入。
