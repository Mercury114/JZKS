# Vivado验证与上板操作

## 1. 当前状态

RTL、完整本地回归和原教师程序自检已通过；Vivado脚本、程序镜像准备和CDP板级连接已交付。
本次未运行真实Vivado/XSim、综合、布局布线、bitstream或FPGA平台测评。
下面步骤用于完成这些剩余环节，不能把脚本存在或本地PASS当作它们已通过。

## 2. 取正确分支并准备镜像

在Windows取得本仓库 `D-cache` 分支，不是只下载原 `D-cache/` 目录，也不是使用旧Exp9工程继续综合。
需要完整的 `Cache/` 和 `Exp9_源码_v文件/rtl/`，后者只复用原 `confreg.v`、`remote2local.v`。

在仓库根目录终端运行：

```sh
python Cache/scripts/prepare_vivado.py --exp 9
```

该步骤检查教师COE哈希，生成 `Cache/build/vivado_input/program.hex` 和 `settings.tcl`。
程序镜像补零到262144个32位字，数据RAM在上电时初始化为零。
换测其它组时把9改成4～8；每组程序不同，不能用同一个未更新程序的bit文件冒充全部组通过。

如果Windows已安装Icarus，也可以先运行：

```sh
python Cache/tests/run_all.py
```

这一步仍是本地RTL回归，不是XSim。

## 3. 创建Vivado 2023.2工程

1. 打开Vivado 2023.2，关闭其它工程。
2. 在Tcl Console切到本仓库根目录。
3. 执行：

```tcl
source ./Cache/scripts/create_project.tcl
```

工程生成在 `Cache/build/vivado_project/cache_course.xpr`，脚本拒绝覆盖已有工程；已经存在时直接打开，不要重复创建。
默认器件 `xc7a200tfbg676-1` 与已有课程CDP来源配置一致。
若实际使用其它板卡，必须先核对器件与XDC，不能只修改part后继续套用引脚。

脚本使用：

- 综合顶层 `cache_remote_top`，连接板载50MHz时钟、BTN6复位、拨码、LED和两个远程数码管。
- `cache_soc_lite_top` 连接五级CPU、缓存、同步RAM和原confreg。
- CPU文件仅 `Cache/rtl/cpu/`，不混入旧 `mycpu_top.v`。
- 指令/数据主存使用 `cache_board_ram` 推断式同步RAM，无需导入旧IP及其缺失的MIF绝对路径。
- `constraints/cdp_remote.xdc` 的引脚来自个人课设已使用的CDP约束（来源提交见文件头），内部CPU/缓存/RAM路径没有设为false path。
- 仿真顶层 `teacher_cache_tb`；程序和功能点数取本次准备的实验组。

工程引用仓库源文件；运行期间不要改RTL。需要冻结证据时记录Git提交和 `verification-results.json` 的源码哈希。

## 4. XSim功能仿真

在已打开工程的Tcl Console运行：

```tcl
source ./Cache/scripts/run_sim.tcl
```

脚本把 `program.hex` 复制到XSim工作目录，再启动仿真。
Exp9应依次出现：

```text
PASS teacher point 1/58 ...
...
PASS teacher point 58/58 ...
PASS teacher cache SoC: 58 points ...
```

若未找到 `program.hex`、端口不匹配、出现 `$fatal`、功能点乱序或超时，先处理仿真问题，不继续生成bit。
不要只截“编译完成”当作程序通过。

建议在波形中观察：

| 目标 | 建议信号 |
|---|---|
| 取指接受与返回 | `dut.u_system.i_valid/i_addr_ok/i_data_ok/i_addr` |
| 数据等待与单次store | `dut.u_system.d_valid/d_addr_ok/d_data_ok/d_wstrb/d_addr` |
| Cache hit/miss | `dut.u_system.u_cache` 内I/D统计、I查询状态、D状态 |
| 主存背压与完成 | `dut.mem_valid/mem_ready/mem_rvalid/mem_addr` |
| 异常取消 | `dut.u_system.u_cpu.wb_flush`、IF pending/discard |
| Cache管理 | `dut.u_system.cacop_valid/cacop_ready/cacop_done/cacop_code` |
| 程序功能点 | `dut.num_data`、写回PC和寄存器写回 |

`teacher_cache_tb` 测试的是SoC，`cache_remote_top` 是板级适配；两者都参与本地编译，但XSim SoC通过仍需再核对板级复位/显示极性。

## 5. 综合与资源报告

关闭仿真，打开工程后执行：

```tcl
source ./Cache/scripts/run_synthesis.tcl
```

检查Synthesis真正成功，查看 `reports/utilization.rpt` 和 `post_synth_timing.rpt`。
至少记录LUT、FF、BRAM、DSP及综合后时序，不把综合后时序当成布线后时序。

重点核查：

1. 只有新五级CPU及缓存被综合，没有旧CPU重复实例。
2. `cache_board_ram` 确实推断为块RAM，指令初始化文件找到且不是全零。
3. I/D缓存数据数组目前是寄存器描述，应以实际资源报告为准，不能预先填写“全部缓存使用BRAM”。
4. 复位数组、tag查询、多路数据选择和乘除法路径有没有造成资源或关键路径问题。
5. 如果资源/时序不足，可先用较小 `INDEX_WIDTH` 做实现验证；此时报告必须记录新容量，并重新运行对应功能回归。

## 6. 布局布线与bit文件

1. 确认实际板卡就是约束中的CDP板、器件一致，时钟为50MHz。
2. 在GUI中Run Implementation。
3. 检查DRC、所有未约束路径、时钟约束和布线后Timing Summary。
4. 时序必须满足要求；不能通过降低报告等级或把CPU路径加false path掩盖失败。
5. 通过后Generate Bitstream，记录Git提交、实验号、容量/路数、时钟、资源和布线时序。

本版本没有提供基于MMI/UpdateMEM的“一次实现换全部实验”保证。
最直接的办法是每组准备对应教师程序、更新工程镜像并重新完成生成流程。
若以后采用增量更新RAM，必须先取得真实MMI和匹配bit，再独立验证内存映射和每组程序，不能直接套用旧CPU的MMI。

## 7. 平台运行和报告补齐

- 提交/下载与本组程序匹配的bit，记录LED和远程数码管显示。
- 核对原平台功能点及最终结果，出现问题先保留日志和对应源码提交。
- 做一次复位后的重复运行，排除未初始化Cache有效位或旧请求造成的偶然通过。
- 若展示Cache指令和流水化，用本目录定向测试补充波形；原教师ex9并不等价于覆盖全部新Cache功能。

待填记录：

| 项目 | 当前状态 | 完成后填写 |
|---|---|---|
| XSim原教师程序 | 未运行 | 实验号、通过功能点、日志 |
| 综合 | 未运行 | LUT/FF/BRAM/DSP、报告 |
| 布线时序 | 未运行 | 周期、WNS/TNS、DRC |
| bit生成 | 未运行 | 实验号、镜像哈希、bit路径 |
| 平台/FPGA验收 | 未运行 | 结果、显示截图、提交时间 |

团队最终报告保留本次本地结果，在完成以上环节后补实际截图和数值，不把待办直接改成“全部通过”。
