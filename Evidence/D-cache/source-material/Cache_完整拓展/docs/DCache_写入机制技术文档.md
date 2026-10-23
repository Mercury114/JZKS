# D-Cache＋写入机制技术文档

## 1. 交付边界

本实现对应分工文档中的“D-Cache＋写入机制”：数据访问命中/未命中、四路组相联、LRU 替换、write-back、write-allocate、dirty 位、字节写使能、脏块回写和 D-Cache 管理操作。uncached 地址的判定和旁路属于整机接入层，本模块通过标准请求握手保持可旁路；I-Cache、取指通路和五级流水 CPU 顶层集成由另一方负责，本目录不把它们标记为本人的完成项。

## 2. Cache 组织

`rtl/dcache.v` 使用 256 组、4 路组相联、每行 16 字节的组织方式。地址划分如下：

```text
tag    = address[31:12]  (20 bit)
index  = address[11:4]   (8 bit, 256 sets)
offset = address[3:0]    (16-byte line)
word   = offset[3:2]     (4 words/line)
```

每个 way/set 保存 `tag`、`valid`、`dirty`、4 个 32 位数据字以及 2 位 LRU age。age=0 表示最近使用，age=3 表示最久未使用；有无效 way 时优先使用无效 way。

## 3. CPU 侧握手

请求端保持 `valid/index/tag/offset/op/wstrb/wdata`，直到 `addr_ok=1`。D-Cache 在空闲态接受一个请求后，`addr_ok` 拉低，直到命中或 miss 处理完成。完成时 `data_ok` 脉冲一个周期；读请求通过 `rdata` 返回，写请求只需检查 `data_ok`。

这套协议避免了 miss 等待期间重复执行 store：请求被接受后，原请求字段全部锁存到 `req_*` 寄存器，后续状态机只使用锁存值。

## 4. 写入策略

### 4.1 写命中

命中 way 的目标 word 使用 `merge_bytes` 按 `wstrb` 合并：

```text
wstrb[0] -> bits 7:0
wstrb[1] -> bits 15:8
wstrb[2] -> bits 23:16
wstrb[3] -> bits 31:24
```

任意字节被修改后置 `dirty=1`。因此半字、字节写不会破坏同一 word 中未使能的字节。

### 4.2 写未命中

采用 write-allocate：先选择 victim，必要时把 victim 的整行写回主存，再发出整行读请求；四个 beat 回填到新行后，对目标 word 做字节合并并置 dirty。这样后续对同一行的写入都变成命中，不会产生每次 store 都直写主存的额外流量。

### 4.3 脏块写回

victim 有效且 dirty 时进入 `ST_WB_REQ`，通过 `wr_addr={victim_tag,index,4'b0}` 和 128 位 `wr_data` 写回整行。只有收到 `wr_rdy` 后才清除 victim 的 valid/dirty 并开始 refill，保证主存不会看到半行数据。

## 5. 状态机

```text
ST_IDLE
  ├─ hit read/write -> ST_RESP
  └─ miss -> (dirty victim ? ST_WB_REQ : ST_REFILL_REQ)
ST_WB_REQ -> ST_REFILL_REQ       (wr_rdy)
ST_REFILL_REQ -> ST_REFILL_WAIT  (rd_rdy)
ST_REFILL_WAIT -> ST_REFILL_APPLY (ret_valid，每行 4 beat)
ST_REFILL_APPLY -> ST_RESP
ST_RESP -> ST_IDLE
```

管理操作使用 `ST_CTRL_WB` 和 `ST_CTRL_DONE`：

- `ctrl_op=0`：按 index/tag invalidate；
- `ctrl_op=1`：按 index/tag writeback，保留 valid；
- `ctrl_op=2`：writeback 后 invalidate。

管理请求通过 `ctrl_valid` 发起，以 `ctrl_done` 作为完成脉冲。若目标行不存在，操作仍会正常完成；若目标行 dirty，writeback 操作会复用同一条整行写回通路。

## 6. 主存侧协议

读请求由 `rd_req/rd_addr/rd_type` 发起，只有收到 `rd_rdy` 才算请求被接受；随后主存以 `ret_valid` 连续返回 4 个 32 位 beat，最后一个 beat 置 `ret_last`。写回由 `wr_req/wr_addr/wr_data/wr_wstrb/wr_type` 发起，收到 `wr_rdy` 即完成整行写入。

## 7. 独立回归内容

`tb/dcache_tb.v` 使用四 beat 行主存模型，依次验证：

1. 写 miss 的整行回填与 write-allocate；
2. 写命中读取回原值；
3. `wstrb=0011` 的低半字合并；
4. 同一 index 的四路填充和第五行替换；
5. dirty victim 的完整 128 位写回；
6. index/tag 管理操作 `writeback+invalidate`；
7. CPU 请求保持、`addr_ok/data_ok` 单次完成。

Vivado 2023.2 实测结果：

```text
PASS D-Cache writeback/write-allocate/byte-enable/LRU/control regression
```

对应素材位于 `build/`：`dcache_project/dcache_extension.xpr` 是工程，`dcache_tb_wave.wdb` 是波形数据，`dcache_tb.wcfg` 是波形配置，`dcache_sim.log` 是独立回归日志，`school_cache_verify.log` 是原学校 `module_verify/cache_verify` 兼容回归日志。

## 8. 与原课程工程的关系

本扩展不改 `Exp8_Exp9_完整工程`、`Exp8_Exp9_报告交付` 或原学校测评工程。原有 `DCache_写入机制/rtl/cache.v` 仍保留学校 `module_verify/cache_verify` 的 `cache` 模块接口；本目录中的 `dcache` 是带管理操作端口的独立增强版，避免覆盖原测评模块名。
