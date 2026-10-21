// 流水总线字段表：花括号中越靠左的字段，放在总线越高的位。
// 打包与解包必须使用相同顺序；valid/allowin 独立传递，不计入下列位宽。
// fs/ds/es/ms/ws 分别代表 IF/ID/EXE/MEM/WB。
`ifndef MYCPU_HEAD_V
`define MYCPU_HEAD_V

// ID → IF：决定是否跳转，以及跳到哪里。1 + 32 = 33 位。
// [32]    br_taken：跳转成立
// [31:0]  br_target：目标地址
`define BR_BUS_WD 33

// Part 6: 供自编测试兼容历史接口，教师输入不变。
`define PART6_CORE

// IF → ID：取到的指令和它自己的 PC。32 + 32 = 64 位。
// [63:32] inst：32 位指令（IF 锁存的 fs_inst，ID 的 ds_inst）
// [31:0]  pc：指令地址（fs_pc → ds_pc）
// Part 6: 新增 [64] 取指地址错误；原低 64 位不变。
`define FS_TO_DS_BUS_WD 65

// ID → EXE：控制信息、操作数及 PC。
// 12 + 1 + 1 + 1 + 5 + 32 + 32 + 32 + 32 + 1 + 1 = 150 位。
// [149:138] alu_op：12 位 ALU 运算选择，逐位含义见 id_stage.v 和 alu.v
// [137]     res_from_mem：写回值是否来自数据 RAM
// [136]     gr_we：指令是否要求写通用寄存器（WB 还要检查 valid、r0 和复位）
// [135]     mem_we：是否写数据 RAM
// [134:130] dest：目的寄存器编号
// [129:98]  imm：已经扩展成 32 位的立即数
// [97:66]   rj_value：第一个源寄存器的值
// [65:34]   rkd_value：第二个源寄存器的值，也是 st.w 的写数据
// [33:2]    pc：指令地址（ds_pc → es_pc）
// [1]       src1_is_pc：ALU 第一操作数选 PC 而非 rj
// [0]       src2_is_imm：ALU 第二操作数选立即数而非 rkd
// Part 5: 新增 [159:153] muldiv_op：mod.wu/div.wu/mod.w/div.w/mulh.wu/mulh.w/mul.w。
// Part 4: [152] load_unsigned；[151:150] mem_size（00 字、01 字节、10 半字）；原低 150 位不变。
// Part 6: 高 125 位增加 SYS_META，原低 160 位不变；总宽度 285。
`define DS_TO_ES_BUS_WD 285

// EXE → MEM：结果与写回信息。1 + 1 + 5 + 32 + 32 + 32 = 103 位。
// [102]   res_from_mem：选择 RAM 读数据还是 ALU 结果
// [101]   gr_we：指令的通用寄存器写入请求
// [100:96] dest：目的寄存器编号
// [95:64] alu_result：ALU 结果
// [63:32] load_response：EXE 等待 data_ok 后锁存的加载原始字，交给 MEM 扩展
// [31:0]  pc：指令地址（es_pc → ms_pc）
// Part 4: 新增 [105] load_unsigned、[104:103] mem_size；原低 103 位位置不变。
// Part 5: [95:64] 为 EXE 最终结果；load/store 时仍是地址。
// Part 6: 高 125 位增加 SYS_META，原低 106 位不变；总宽度 231。
`define ES_TO_MS_BUS_WD 231

// MEM → WB：最终结果及对应 PC。1 + 5 + 32 + 32 = 70 位。
// [69]    gr_we：指令的通用寄存器写入请求
// [68:64] dest：目的寄存器编号
// [63:32] result：根据 res_from_mem 选出的 RAM 读值或 ALU 结果
// [31:0]  pc：指令地址（ms_pc → ws_pc）
// Part 6: 高 125 位增加 SYS_META，原低 70 位不变；总宽度 195。
`define MS_TO_WS_BUS_WD 195

// WB → ID 内的寄存器堆：实际写口。1 + 5 + 32 = 38 位。
// [37]    rf_we：已检查有效位、目的编号和复位后的写使能
// [36:32] dest：目的寄存器编号（ID 中的 rf_waddr）
// [31:0]  result：待写入值（ID 中的 rf_wdata）
`define WS_TO_RF_BUS_WD 38

// Part 2: 前递版：EXE → ID。1 + 1 + 5 + 32 = 39 位。
// Part 2: [38]    write_valid：本级有效、要求写寄存器、目的非 r0 且非复位
// Part 5: [37]    result_pending：load 或除法未就绪，命中该写者的 ID 必须等待
// Part 2: [36:32] dest：目的寄存器编号
// Part 5: [31:0]  exe_result：ALU/乘除最终值；pending 为 1 时不可消费
`define ES_TO_DS_BUS_WD 39

// Part 2: MEM → ID。1 + 5 + 32 = 38 位；WB → ID 复用 WS_TO_RF_BUS。
// Part 2: [37]    write_valid：有效写寄存器标志，条件同上
// Part 2: [36:32] dest：目的寄存器编号
// Part 2: [31:0]  final_result：本条指令锁存并扩展的加载值或 ALU 结果
`define MS_TO_DS_BUS_WD 38

// Part 6: SYS_META 从高到低：sys_op(8)、ex_valid(1)、ex_code(6)、ex_badv(32)、
// Part 6: csr_num(14)、csr_wmask(32)、csr_wvalue(32)，合计 125 位。
// Part 6: sys_op[7] 为 CACOP；sys_op[6:0]：rdcntid/rdcntvh/rdcntvl/ertn/csrxchg/csrwr/csrrd。
// Part 6: 三级均在原总线前拼接同一字段顺序；ALE 在 EXE 更新 ex_valid/code/badv。
`endif

// 缓存适配：SYS_META 为 125 位；sys_op[7] 表示串行执行的 CACOP。
