// ID（译码级）：保存 IF 送来的指令，识别操作、读取寄存器并生成控制信号。
// 分支在本级决定；其余控制信息、操作数和 PC 一起交给 EXE。
// Part 5: 按 EXE > MEM > WB 前递；load 等实际返回后进入 MEM 前递，除法等结果就绪。
`timescale 1ns/1ps
`default_nettype none
`include "mycpu_head.v"

module id_stage(
    // 时钟与内部高有效复位
    input  wire        clk,
    input  wire        reset,
    // Part 6: CSR 指令串行处理；异常和 ERTN 在 WB 冲刷。
    input  wire        wb_flush,
    input  wire        pipeline_busy,
    input  wire        system_pending,
    input  wire        has_int,
    input  wire [ 1:0] current_plv,

    // EXE 能接收本级指令时为 1
    input  wire        es_allowin,

    // ID 是否能接收 IF 的指令
    output wire        ds_allowin,

    // IF → ID：有效标志与指令内容
    input  wire        fs_to_ds_valid,
    input  wire [`FS_TO_DS_BUS_WD - 1:0] fs_to_ds_bus,

    // ID → EXE：有效标志与译码结果
    output wire        ds_to_es_valid,
    output wire [`DS_TO_ES_BUS_WD - 1:0] ds_to_es_bus,

    // 送回 IF 的跳转决定和目标地址
    output wire [`BR_BUS_WD - 1:0] br_bus,

    // Part 2: EXE/MEM 提供前递结果和有效写者；WB 复用寄存器堆写口
    input  wire [`ES_TO_DS_BUS_WD - 1:0] es_to_ds_bus,
    input  wire [`MS_TO_DS_BUS_WD - 1:0] ms_to_ds_bus,

    // WB 送回的寄存器写口信息
    input  wire [`WS_TO_RF_BUS_WD - 1:0] ws_to_rf_bus
);

// 流水寄存器：valid 表示本级有指令，不表示该指令编码一定受支持。
reg         ds_valid;
reg  [`FS_TO_DS_BUS_WD - 1:0] fs_to_ds_bus_r;

// 本级指令与 PC，以及 WB 返回的寄存器写口。
wire [31:0] ds_inst;
wire [31:0] ds_pc;
wire        rf_we;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;

// 从指令中取出的操作码、寄存器编号和立即数字段。
wire [ 5:0] op_31_26;
wire [ 3:0] op_25_22;
wire [ 1:0] op_21_20;
wire [ 4:0] op_19_15;
wire [ 4:0] rd;
wire [ 4:0] rj;
wire [ 4:0] rk;
wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;

// 译码器输出：每个编号对应一位，便于组合判断指令类型。
wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;

// 每个 inst_* 信号表示“当前编码是这一种指令”。
wire        inst_add_w;
wire        inst_sub_w;
wire        inst_slt;
wire        inst_sltu;
wire        inst_nor;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_slli_w;
wire        inst_srli_w;
wire        inst_srai_w;
wire        inst_addi_w;
wire        inst_ld_w;
wire        inst_st_w;
wire        inst_jirl;
wire        inst_b;
wire        inst_bl;
wire        inst_beq;
wire        inst_bne;
wire        inst_lu12i_w;

// Part 3: 新增指令复用原有 ALU、前递和分支通路，编码以 LA32R 手册附录 B 为准。
wire        inst_slti;
wire        inst_sltui;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_sll_w;
wire        inst_srl_w;
wire        inst_sra_w;
wire        inst_pcaddu12i;
wire        inst_blt;
wire        inst_bge;
wire        inst_bltu;
wire        inst_bgeu;
wire        inst_cond_branch;

// Part 4: 字节和半字访存类型。
wire        inst_ld_b;
wire        inst_ld_h;
wire        inst_ld_bu;
wire        inst_ld_hu;
wire        inst_st_b;
wire        inst_st_h;
wire        inst_load;
wire        inst_store;
wire [ 1:0] mem_size;
wire        load_unsigned;

// Part 5: 乘除指令使用 rj、rk 两个真实源。
wire        inst_mul_w;
wire        inst_mulh_w;
wire        inst_mulh_wu;
wire        inst_div_w;
wire        inst_mod_w;
wire        inst_div_wu;
wire        inst_mod_wu;
wire        inst_muldiv;
wire [ 6:0] muldiv_op;

// Part 6: 第二阶段增加计数器与异常；两阶段使用同一最终核心。
wire        inst_csrrd;
wire        inst_csrwr;
wire        inst_csrxchg;
wire        inst_ertn;
wire        inst_syscall;
wire        inst_break;
wire        inst_rdcntvl;
wire        inst_rdcntvh;
wire        inst_rdcntid;
wire        inst_system;
wire        inst_cacop;
// CACOP 的低三位选择 I/D，类型只接受初始化、索引管理和命中管理。
assign inst_cacop = ds_inst[31:22] == 10'b0000011000
                 && rd[2:0] <= 1 && rd[4:3] < 3;
wire        fs_adef;
wire        ds_exception;
wire [ 5:0] ds_ecode;
wire        privilege_error;
wire        system_wait;
wire [ 7:0] sys_op;

// ALU 控制、立即数与跳转偏移；偏移最终都以字节为单位。
wire [11:0] alu_op;
wire        need_ui5;
wire        need_ui12;
wire        need_si20;
wire        need_si26;
wire [31:0] imm;
wire [31:0] br_offs;
wire [31:0] jirl_offs;

// 寄存器读值与写回控制：rkd_value 是 rk 或 rd 指定的寄存器内容。
wire        src_reg_is_rd;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] rf_rdata1;
wire [31:0] rf_rdata2;
wire        inst_valid;
wire        gr_we;
wire        mem_we;
wire        res_from_mem;
wire        src1_is_pc;
wire        src2_is_imm;
wire [ 4:0] dest;

// Part 2: 只比较真正会读取的源寄存器，不能把立即数的位段误当寄存器。
wire        need_rj;
wire        need_rkd;
wire [ 4:0] rkd;
wire        es_write_valid;
wire        es_result_pending;
wire [ 4:0] es_dest;
wire [31:0] es_result;
wire        ms_write_valid;
wire [ 4:0] ms_dest;
wire [31:0] ms_result;
wire        rj_from_es;
wire        rj_from_ms;
wire        rj_from_ws;
wire        rkd_from_es;
wire        rkd_from_ms;
wire        rkd_from_ws;
wire        rj_wait;
wire        rkd_wait;
wire        ds_ready_go;

// 给 IF 的分支决定。
wire        br_taken;
wire [31:0] br_target;
// Part 3: 分支决定与目标先寄存，下一拍再向 IF 发出重定向。
wire        br_decision;
wire [31:0] br_target_next;
reg         br_pending;
reg  [31:0] br_target_r;

// Part 3: 分别按有符号和无符号解释前递后的两个分支源值。
wire        rj_lt_rd;
wire        rj_ltu_rd;

// 输入总线解包：PC 必须和指令一起保存，不能使用 IF 正在取下一条时的 PC。
assign {
    fs_adef, // Part 6: 来自 IF 的地址错标记
    ds_inst,
    ds_pc
} = fs_to_ds_bus_r;

assign {
    rf_we,
    rf_waddr,
    rf_wdata
} = ws_to_rf_bus;

assign {
    es_write_valid,
    es_result_pending,
    es_dest,
    es_result
} = es_to_ds_bus;

assign {
    ms_write_valid,
    ms_dest,
    ms_result
} = ms_to_ds_bus;

// Part 2: 等待时保留 ID 的 valid/指令/PC，同时不给 EXE 重复发射旧指令。
// Part 5: load 在 EXE 等 data_ok，进入 MEM 后才可前递；除法同样通过 es_allowin 阻塞前端。
// Part 6: CSR/计数器等待旧指令写回，再独占 EXE～WB；后继指令等待提交。
assign system_wait    = system_pending || (inst_system && pipeline_busy);
assign ds_ready_go    = ~system_wait && (ds_exception || ~(rj_wait || rkd_wait));
assign ds_allowin     = br_taken || ~ds_valid || (ds_ready_go && es_allowin);
assign ds_to_es_valid = ds_valid && ds_ready_go && ~wb_flush && ~br_taken;

always @(posedge clk) begin
    if (reset || wb_flush || br_taken) begin
        ds_valid <= 1'b0;
    end
    else if (ds_allowin) begin
        ds_valid <= fs_to_ds_valid;
    end

    // 只在接收有效输入时更新内容；空拍只需由 valid 标记，不必清空所有数据。
    if (ds_allowin && fs_to_ds_valid) begin
        fs_to_ds_bus_r <= fs_to_ds_bus;
    end
end

// 拆出操作码和三个寄存器编号；具体位段由 LoongArch 指令格式规定。
assign op_31_26 = ds_inst[31:26];
assign op_25_22 = ds_inst[25:22];
assign op_21_20 = ds_inst[21:20];
assign op_19_15 = ds_inst[19:15];

assign rd = ds_inst[ 4:0];
assign rj = ds_inst[ 9:5];
assign rk = ds_inst[14:10];

// i26 在指令中分成两段，先拼回完整偏移，之后再符号扩展并乘 4。
assign i12 = ds_inst[21:10];
assign i20 = ds_inst[24:5];
assign i16 = ds_inst[25:10];
assign i26 = {ds_inst[ 9:0], ds_inst[25:10]};

// 先把各操作码字段译成独热信号（只有对应编号那一位为 1）。
decoder_6_64 d0(
    .in  (op_31_26  ),
    .out (op_31_26_d)
);

decoder_4_16 d1(
    .in  (op_25_22  ),
    .out (op_25_22_d)
);

decoder_2_4 d2(
    .in  (op_21_20  ),
    .out (op_21_20_d)
);

decoder_5_32 d3(
    .in  (op_19_15  ),
    .out (op_19_15_d)
);

// Part 3: 基础 20 条和本次新增 13 条分别译码，立即数字段不参与操作码判断。
assign inst_add_w   = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[0];
assign inst_sub_w   = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[2];
assign inst_slt     = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[4];
assign inst_sltu    = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[5];
assign inst_nor     = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[8];
assign inst_and     = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[9];
assign inst_or      = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[10];
assign inst_xor     = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[11];
assign inst_slli_w  = op_31_26_d[0] & op_25_22_d[1] & op_21_20_d[0] & op_19_15_d[1];
assign inst_srli_w  = op_31_26_d[0] & op_25_22_d[1] & op_21_20_d[0] & op_19_15_d[9];
assign inst_srai_w  = op_31_26_d[0] & op_25_22_d[1] & op_21_20_d[0] & op_19_15_d[17];
assign inst_addi_w  = op_31_26_d[0] & op_25_22_d[10];
assign inst_ld_w    = op_31_26_d[10] & op_25_22_d[2];
assign inst_st_w    = op_31_26_d[10] & op_25_22_d[6];
assign inst_jirl    = op_31_26_d[19];
assign inst_b       = op_31_26_d[20];
assign inst_bl      = op_31_26_d[21];
assign inst_beq     = op_31_26_d[22];
assign inst_bne     = op_31_26_d[23];
assign inst_lu12i_w = op_31_26_d[5] & ~ds_inst[25];

assign inst_slti      = op_31_26_d[0] & op_25_22_d[8];
assign inst_sltui     = op_31_26_d[0] & op_25_22_d[9];
assign inst_andi      = op_31_26_d[0] & op_25_22_d[13];
assign inst_ori       = op_31_26_d[0] & op_25_22_d[14];
assign inst_xori      = op_31_26_d[0] & op_25_22_d[15];
assign inst_sll_w     = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[14];
assign inst_srl_w     = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[15];
assign inst_sra_w     = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[16];
assign inst_pcaddu12i = op_31_26_d[7] & ~ds_inst[25];
assign inst_blt       = op_31_26_d[24];
assign inst_bge       = op_31_26_d[25];
assign inst_bltu      = op_31_26_d[26];
assign inst_bgeu      = op_31_26_d[27];

// Part 4: si12 始终符号扩展；无符号加载只改变数据扩展方式。
assign inst_ld_b  = op_31_26_d[10] & op_25_22_d[0];
assign inst_ld_h  = op_31_26_d[10] & op_25_22_d[1];
assign inst_ld_bu = op_31_26_d[10] & op_25_22_d[8];
assign inst_ld_hu = op_31_26_d[10] & op_25_22_d[9];
assign inst_st_b  = op_31_26_d[10] & op_25_22_d[4];
assign inst_st_h  = op_31_26_d[10] & op_25_22_d[5];
assign inst_load  = inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu;
assign inst_store = inst_st_w | inst_st_b | inst_st_h;
assign mem_size   = (inst_ld_b | inst_ld_bu | inst_st_b) ? 2'b01 :
                  (inst_ld_h | inst_ld_hu | inst_st_h) ? 2'b10 : 2'b00;
assign load_unsigned = inst_ld_bu | inst_ld_hu;

// Part 5: 固定操作码不含低 15 位 rk/rj/rd。
assign inst_mul_w   = ds_inst[31:15] == 17'h00038;
assign inst_mulh_w  = ds_inst[31:15] == 17'h00039;
assign inst_mulh_wu = ds_inst[31:15] == 17'h0003a;
assign inst_div_w   = ds_inst[31:15] == 17'h00040;
assign inst_mod_w   = ds_inst[31:15] == 17'h00041;
assign inst_div_wu  = ds_inst[31:15] == 17'h00042;
assign inst_mod_wu  = ds_inst[31:15] == 17'h00043;
assign muldiv_op    = {
    inst_mod_wu,
    inst_div_wu,
    inst_mod_w,
    inst_div_w,
    inst_mulh_wu,
    inst_mulh_w,
    inst_mul_w
};
assign inst_muldiv = |muldiv_op;

// Part 6: CSR 的 rj=0/1 分别编码读/写，其余值编码掩码交换。
assign inst_csrrd   = (ds_inst[31:24] == 8'h04) && (rj == 5'd0);
assign inst_csrwr   = (ds_inst[31:24] == 8'h04) && (rj == 5'd1);
assign inst_csrxchg = (ds_inst[31:24] == 8'h04) && (rj != 5'd0) && (rj != 5'd1);
assign inst_ertn    = ds_inst == 32'h06483800;
assign inst_syscall = ds_inst[31:15] == 17'h00056;
assign inst_break   = ds_inst[31:15] == 17'h00054;
assign inst_rdcntvl = (ds_inst[31:10] == 22'h000018) && (rj == 5'd0);
assign inst_rdcntvh = (ds_inst[31:10] == 22'h000019) && (rj == 5'd0);
assign inst_rdcntid = (ds_inst[31:10] == 22'h000018) && (rd == 5'd0) && (rj != 5'd0);
assign sys_op = {
    inst_cacop,
    inst_rdcntid,
    inst_rdcntvh,
    inst_rdcntvl,
    inst_ertn,
    inst_csrxchg,
    inst_csrwr,
    inst_csrrd
};
assign inst_system = |sys_op;
// Part 6: 中断优先，其次取指错误，再是互斥的译码异常；ALE 在 EXE 判断。
assign privilege_error = (current_plv != 2'd0) && (inst_csrrd | inst_csrwr | inst_csrxchg | inst_ertn | inst_cacop);
assign ds_exception = has_int | fs_adef | inst_syscall | inst_break | ~inst_valid | privilege_error;
assign ds_ecode = has_int ? 6'h00 : fs_adef ? 6'h08 : ~inst_valid ? 6'h0d :
                  privilege_error ? 6'h0e : inst_syscall ? 6'h0b : 6'h0c;

assign inst_cond_branch = inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu;

// Part 3: 仍使用原有 12 位 ALU 控制；立即数和寄存器运算选相同的运算通路。
// Part 3: pcaddu12i 与地址/链接计算都复用加法，寄存器移位由 ALU 取第二操作数低 5 位。
assign alu_op = {
    inst_lu12i_w,              // Part 3: [11] 立即数装入高位
    inst_srai_w | inst_sra_w,   // Part 3: [10] 算术右移
    inst_srli_w | inst_srl_w,   // Part 3: [ 9] 逻辑右移
    inst_slli_w | inst_sll_w,   // Part 3: [ 8] 左移
    inst_xor | inst_xori,       // Part 3: [ 7] 异或
    inst_or | inst_ori,         // Part 3: [ 6] 或
    inst_nor,                  // Part 3: [ 5] 或非
    inst_and | inst_andi,       // Part 3: [ 4] 与
    inst_sltu | inst_sltui,     // Part 3: [ 3] 无符号小于
    inst_slt | inst_slti,       // Part 3: [ 2] 有符号小于
    inst_sub_w,                // Part 3: [ 1] 减法
    inst_add_w | inst_addi_w | inst_load | inst_store | inst_cacop
               | inst_jirl | inst_bl | inst_pcaddu12i // Part 4: [0] 所有访存仍复用加法
};

// Part 3: ui12 用于逻辑立即数；si20 用于高位装入及 PC 相对加法。
assign need_ui5  = inst_slli_w | inst_srli_w | inst_srai_w;
assign need_ui12 = inst_andi | inst_ori | inst_xori;
assign need_si20 = inst_lu12i_w | inst_pcaddu12i;
assign need_si26 = inst_b | inst_bl;

// Part 3: slti/sltui 都符号扩展 i12，sltui 只改变比较方式，不改变扩展方式。
// Part 3: 逻辑立即数零扩展；si20 拼接后正好 32 位；jirl/bl 保留链接常数 4。
assign imm = (inst_jirl | inst_bl) ? 32'd4               :
             need_si20           ? {i20, 12'b0}        :
             need_ui5            ? {27'b0, rk}         :
             need_ui12           ? {20'b0, i12}        :
                                   {{20{i12[11]}}, i12};

// 分支偏移的编码单位是 4 字节：低位补两个 0，同时向高位复制符号位。
assign br_offs = need_si26 ? {{4{i26[25]}}, i26, 2'b0} :
                            {{14{i16[15]}}, i16, 2'b0};
assign jirl_offs = {{14{i16[15]}}, i16, 2'b0};

// Part 4: 条件分支和全部 store 从第二读口读取 rd。
// Part 6: CSRWR/CSRXCHG 的写值来自旧 rd。
assign src_reg_is_rd = inst_cond_branch | inst_store | inst_csrwr | inst_csrxchg;
assign rkd           = src_reg_is_rd ? rd : rk;

assign need_rj = inst_cacop | inst_csrxchg | inst_add_w | inst_sub_w | inst_slt | inst_sltu
               | inst_nor | inst_and | inst_or | inst_xor
               | inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w
               | inst_load | inst_store | inst_jirl | inst_cond_branch
               | inst_slti | inst_sltui | inst_andi | inst_ori | inst_xori
               | inst_sll_w | inst_srl_w | inst_sra_w | inst_muldiv;
assign need_rkd = inst_csrwr | inst_csrxchg | inst_add_w | inst_sub_w | inst_slt | inst_sltu
                | inst_nor | inst_and | inst_or | inst_xor
                | inst_store | inst_cond_branch | inst_sll_w | inst_srl_w | inst_sra_w | inst_muldiv;

// Part 2: r0 永远为 0；立即数字段、无效级和不写寄存器指令均不构成源相关。
assign rj_from_es  = need_rj && (rj != 5'd0) && es_write_valid && (es_dest == rj);
assign rj_from_ms  = need_rj && (rj != 5'd0) && ms_write_valid && (ms_dest == rj);
assign rj_from_ws  = need_rj && (rj != 5'd0) && rf_we && (rf_waddr == rj);
assign rkd_from_es = need_rkd && (rkd != 5'd0) && es_write_valid && (es_dest == rkd);
assign rkd_from_ms = need_rkd && (rkd != 5'd0) && ms_write_valid && (ms_dest == rkd);
assign rkd_from_ws = need_rkd && (rkd != 5'd0) && rf_we && (rf_waddr == rkd);

// Part 5: 最近写者为未就绪 load 或除法时等待，不越过它使用 MEM/WB 的旧值。
assign rj_wait  = rj_from_es && es_result_pending;
assign rkd_wait = rkd_from_es && es_result_pending;

assign rj_value = rj_from_es ? es_result :
                  rj_from_ms ? ms_result :
                  rj_from_ws ? rf_wdata  :
                               rf_rdata1;
assign rkd_value = rkd_from_es ? es_result :
                   rkd_from_ms ? ms_result :
                   rkd_from_ws ? rf_wdata  :
                                 rf_rdata2;

regfile rf(
    .clk    (clk                    ),
    .raddr1 (rj                     ),
    .rdata1 (rf_rdata1              ),
    .raddr2 (rkd                    ),
    .rdata2 (rf_rdata2              ),
    .we     (rf_we                  ),
    .waddr  (rf_waddr               ),
    .wdata  (rf_wdata               )
);

// Part 6: 基础 46 条加控制/计数器指令；未识别的编码触发 INE。
assign inst_valid = inst_system | inst_syscall | inst_break | inst_add_w | inst_sub_w | inst_slt | inst_sltu
                  | inst_nor | inst_and | inst_or | inst_xor
                  | inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w
                  | inst_load | inst_store | inst_jirl | inst_b | inst_bl
                  | inst_cond_branch | inst_lu12i_w | inst_pcaddu12i
                  | inst_slti | inst_sltui | inst_andi | inst_ori | inst_xori
                  | inst_sll_w | inst_srl_w | inst_sra_w | inst_muldiv;

// Part 3: 所有条件分支和 b 不写寄存器；pcaddu12i 写 rd，bl 仍写 r1。
assign gr_we        = inst_valid & ~(inst_store | inst_cond_branch | inst_b
                                   | inst_ertn | inst_syscall | inst_break | inst_cacop);
assign mem_we       = inst_store;
assign res_from_mem = inst_load;
assign src1_is_pc   = inst_jirl | inst_bl | inst_pcaddu12i;

assign src2_is_imm = inst_cacop | inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w
                   | inst_load | inst_store | inst_lu12i_w | inst_jirl | inst_bl
                   | inst_slti | inst_sltui | inst_andi | inst_ori | inst_xori
                   | inst_pcaddu12i;

// Part 6: RDCNTID 的目的寄存器编码在 rj；它不读取 rj。
assign dest = inst_bl ? 5'd1 : inst_rdcntid ? rj : rd;

// Part 3: $signed 明确两边的符号性，避免把有符号分支误写成无符号比较。
assign rj_lt_rd  = $signed(rj_value) < $signed(rkd_value);
assign rj_ltu_rd = rj_value < rkd_value;

// Part 3: 仅在本条真正发射时保存分支决定；未就绪的 load 不会提前跳转。
assign br_decision = ds_to_es_valid & es_allowin & ~reset & ~ds_exception
               & ((inst_beq & (rj_value == rkd_value))
                | (inst_bne & (rj_value != rkd_value))
                | (inst_blt & rj_lt_rd)
                | (inst_bge & ~rj_lt_rd)
                | (inst_bltu & rj_ltu_rd)
                | (inst_bgeu & ~rj_ltu_rd)
                | inst_jirl | inst_bl | inst_b);

// Part 3: 六条条件分支、b/bl 都以本条 PC 加符号扩展偏移；jirl 使用 rj 基址。
assign br_target_next = (inst_cond_branch | inst_bl | inst_b) ? ds_pc + br_offs :
                                                             rj_value + jirl_offs;

// Part 3: 重定向只持续一拍；此拍取消 ID/IF 错路，禁止年轻指令进入 EXE。
// Part 6: WB 异常/返回冲刷优先，清除尚未执行的普通分支重定向。
always @(posedge clk) begin
    if (reset || wb_flush) begin
        br_pending <= 1'b0;
    end
    else begin
        br_pending <= br_decision;
    end

    if (br_decision) begin
        br_target_r <= br_target_next;
    end
end

assign br_taken  = br_pending && ~reset && ~wb_flush;
assign br_target = br_target_r;
assign br_bus = {
    br_taken,
    br_target
};

// 后级需要的信息必须随同一条指令传递；字段顺序与 EXE 解包完全一致。
assign ds_to_es_bus = {
    sys_op,          // Part 6: WB 控制指令类型
    ds_exception,    // Part 6: 本条指令的异常标记
    ds_ecode,        // Part 6: 异常编码
    ds_pc,           // Part 6: ADEF 的 BADV，ALE 会在 EXE 改为访存地址
    ds_inst[23:10],  // Part 6: 14 位 CSR 编号
    inst_csrwr ? 32'hffffffff : rj_value, // Part 6: 全写或掩码写
    rkd_value,       // Part 6: CSR 的旧 rd 写值
    muldiv_op,
    load_unsigned,
    mem_size,
    alu_op,
    res_from_mem,
    gr_we,
    mem_we,
    dest,
    imm,
    rj_value,
    rkd_value,
    ds_pc,
    src1_is_pc,
    src2_is_imm
};

endmodule

`default_nettype wire
