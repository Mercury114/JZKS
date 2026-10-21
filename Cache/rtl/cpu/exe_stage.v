// EXE（执行级）：锁存 ID 送来的控制信息和操作数，再进行 ALU 运算。
// 普通运算把结果送给 MEM；load/store 用 ALU 结果作为数据 RAM 地址。
// Part 5: ALU 为组合逻辑；乘法先寄存结果，除法迭代期间保持 EXE。
// 缓存适配：RAM 请求通过 addr_ok 接受，data_ok 完成后才进入 MEM。
`timescale 1ns/1ps
`default_nettype none
`include "mycpu_head.v"

module exe_stage(
    // 时钟与内部高有效复位
    input  wire        clk,
    input  wire        reset,
    // Part 6: 老异常取消年轻指令的 RAM 请求，WB 冲刷也复位除法器。
    input  wire        wb_flush,
    input  wire        older_cancel,
    // 更老指令提交后才允许访存/管理，避免年轻 store 在老异常之前产生副作用。
    input  wire        older_busy,
    input  wire        data_addr_ok,
    input  wire        data_data_ok,
    input  wire [31:0] data_sram_rdata,
    output wire        cacop_valid,
    output wire [ 4:0] cacop_code,
    output wire [31:0] cacop_addr,
    input  wire        cacop_ready,
    input  wire        cacop_done,
    output wire        es_busy,
    output wire        es_system,

    // MEM 能接收本级指令时为 1
    input  wire        ms_allowin,

    // 本级 EXE 能接收前级指令时为 1
    output wire        es_allowin,

    // ID → EXE：有效标志与译码结果
    input  wire        ds_to_es_valid,
    input  wire [`DS_TO_ES_BUS_WD - 1:0] ds_to_es_bus,

    // EXE → MEM：有效标志与运算结果
    output wire        es_to_ms_valid,
    output wire [`ES_TO_MS_BUS_WD - 1:0] es_to_ms_bus,

    // Part 2: 送回 ID 的结果及写者信息；load 在本级还不能前递数据
    output wire [`ES_TO_DS_BUS_WD - 1:0] es_to_ds_bus,

    // 数据缓存请求：valid、字节写使能、地址和写数据；接受/完成由握手决定
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata
);

reg         es_valid;
reg  [`DS_TO_ES_BUS_WD - 1:0] bus_r;

// Part 6: 控制/异常信息与本条指令一起流动。
wire [ 7:0] sys_op;
wire        ex_valid;
wire [ 5:0] ex_code;
wire [31:0] ex_badv;
wire [13:0] csr_num;
wire [31:0] csr_wmask;
wire [31:0] csr_wvalue;
wire        address_error;
wire        es_exception;
wire [ 5:0] es_ecode;
wire [31:0] es_badv;
wire        divider_reset;

// Part 4: 访存类型和低地址位随流水传递。
wire        load_unsigned;
wire [ 1:0] mem_size;
wire [ 3:0] store_mask;
// Part 5: 乘法多等一拍保存结果；除法启动一次，完成前阻塞 EXE。
wire [ 6:0] muldiv_op;
wire        is_mul;
wire        is_div;
reg         mul_done;
reg  [63:0] product_r;
wire        div_signed;
wire        div_start;
wire        div_done;
wire        div_busy;
reg         div_started;
wire        es_ready_go;
wire [31:0] quotient;
wire [31:0] remainder;
wire signed [32:0] mul_a;
wire signed [32:0] mul_b;
wire signed [65:0] product;
wire [31:0] exe_result;
wire [11:0] alu_op;
wire        res_from_mem;
wire        gr_we;
wire        mem_we;
wire        src1_is_pc;
wire        src2_is_imm;
wire [ 4:0] dest;
wire [31:0] imm;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] es_pc;
wire [31:0] alu_result;

// 请求归属与完成状态：pending 表示等待外部完成，done 表示本条指令已完成。
reg         mem_pending;
reg         mem_done;
reg         cache_pending;
reg         cache_done;
reg         mem_killed;
reg         cache_killed;
reg  [31:0] load_response_r;
wire        mem_access = res_from_mem || mem_we;
wire        mem_accept = data_sram_en && data_addr_ok;
wire        cache_accept = cacop_valid && cacop_ready;

// 已接受请求不能因冲刷而遗忘：旧响应仍要排空，但不得完成后来的年轻指令。
always @(posedge clk) begin
    if (reset) begin
        mem_pending <= 0;
        mem_done <= 0;
        mem_killed <= 0;
        cache_pending <= 0;
        cache_done <= 0;
        cache_killed <= 0;
    end else begin
        if (mem_accept) begin
            mem_pending <= 1;
            mem_killed <= 0;
        end
        if (data_data_ok && (mem_pending || mem_accept)) begin
            mem_pending <= 0;
            load_response_r <= data_sram_rdata;
            // 新请求接受与返回可同拍，不能沿用上一笔请求残留的 killed 标记。
            if (!wb_flush && (!mem_killed || mem_accept)) begin
                mem_done <= 1;
            end
        end
        if (cache_accept) begin
            cache_pending <= 1;
            cache_killed <= 0;
        end
        if (cacop_done && (cache_pending || cache_accept)) begin
            cache_pending <= 0;
            if (!wb_flush && (!cache_killed || cache_accept)) begin
                cache_done <= 1;
            end
        end
        if (wb_flush) begin
            if (mem_pending) begin
                mem_killed <= 1;
            end
            if (cache_pending) begin
                cache_killed <= 1;
            end
        end
        if (wb_flush || es_allowin) begin
            mem_done <= 0;
            cache_done <= 0;
        end
    end
end

// CACOP 串行执行；接受后撤 valid，完成后继续流向 WB，由 WB 冲刷旧预取。
assign cacop_valid = es_valid && sys_op[7] && !es_exception && !cache_pending && !cache_done
                   && !older_busy && !older_cancel && !reset && !wb_flush;
assign cacop_code = dest;
assign cacop_addr = alu_result;

// 解包的是本级寄存器，不直接使用 ID 当前输出，以免混入下一条指令。
// 字段顺序与 ID 的打包顺序相同，位宽见 mycpu_head.v。
assign {
    sys_op,
    ex_valid,
    ex_code,
    ex_badv,
    csr_num,
    csr_wmask,
    csr_wvalue,
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
    es_pc,
    src1_is_pc,
    src2_is_imm
} = bus_r;

assign is_mul         = |muldiv_op[2:0];
assign is_div         = |muldiv_op[6:3];
assign div_signed     = muldiv_op[3] | muldiv_op[4];
assign div_start      = es_valid && is_div && ~div_started && ~reset && ~wb_flush && ~es_exception;
// 普通访存/CACOP 必须等真实完成；异常指令不发请求，直接传递异常信息。
assign es_ready_go    = es_exception || ((is_mul ? mul_done :
                                        (~is_div || (div_started && div_done)))
                      && (!mem_access || mem_done) && (!sys_op[7] || cache_done));
assign es_allowin     = ~es_valid || (es_ready_go && ms_allowin);
assign es_to_ms_valid = es_valid && es_ready_go && ~wb_flush;
assign es_busy        = es_valid;
assign es_system      = es_valid && (|sys_op);
assign divider_reset  = reset || wb_flush;
// Part 6: 自然对齐：字低两位为零、半字低一位为零；字节不限制。
assign address_error = (res_from_mem || mem_we)
                    && ((mem_size == 2'b00 && (|alu_result[1:0]))
                     || (mem_size == 2'b10 && alu_result[0]));
assign es_exception  = ex_valid || address_error;
assign es_ecode      = ex_valid ? ex_code : 6'h09;
assign es_badv       = ex_valid ? ex_badv : alu_result;

// Part 5: 补符号位或零后统一做有符号乘法，结果仍取原 64 位乘积的对应部分。
assign mul_a      = {~muldiv_op[2] && rj_value[31], rj_value};
assign mul_b      = {~muldiv_op[2] && rkd_value[31], rkd_value};
assign product    = mul_a * mul_b;
assign exe_result = muldiv_op[0] ? product_r[31:0] :
                    (muldiv_op[1] | muldiv_op[2]) ? product_r[63:32] :
                    (muldiv_op[3] | muldiv_op[5]) ? quotient :
                    (muldiv_op[4] | muldiv_op[6]) ? remainder : alu_result;

// Part 5: 首个执行沿保存乘积，下一周期才允许前递和进入 MEM。
// Part 5: 等待时保持本条操作数；结果保存后不重复计算，后级未接收时也不覆盖。
// Part 5: 复位、异常冲刷或本条离开时清完成标志，防止下一条误用旧乘积。
always @(posedge clk) begin
    if (reset || wb_flush || es_allowin) begin
        mul_done <= 1'b0;
    end
    else if (es_valid && is_mul && ~mul_done && ~es_exception) begin
        product_r <= product[63:0];
        mul_done  <= 1'b1;
    end
end

always @(posedge clk) begin
    if (reset || wb_flush || es_allowin) begin
        div_started <= 1'b0;
    end
    else if (div_start) begin
        div_started <= 1'b1;
    end
end

divider u_divider(
    .clk        (clk          ),
    .reset      (divider_reset),
    .start      (div_start    ),
    .signed_div (div_signed   ),
    .dividend   (rj_value     ),
    .divisor    (rkd_value    ),
    .busy       (div_busy     ),
    .done       (div_done     ),
    .quotient   (quotient     ),
    .remainder  (remainder    )
);

assign es_to_ds_bus = {
    es_valid && gr_we && (dest != 5'd0) && ~reset && ~es_exception && ~wb_flush && ~(|sys_op),
    res_from_mem || ~es_ready_go,
    dest,
    exe_result
};

// valid 决定内容能否生效；数据寄存器只在接收有效指令时更新，无须随复位清零。
always @(posedge clk) begin
    if (reset || wb_flush) begin
        es_valid <= 1'b0;
    end
    else if (es_allowin) begin
        es_valid <= ds_to_es_valid;
    end

    if (es_allowin && ds_to_es_valid) begin
        bus_r <= ds_to_es_bus;
    end
end

// 第一操作数选 PC 或 rj；第二操作数选立即数或第二个源寄存器值。
alu a(
    .alu_op     (alu_op                       ),
    .alu_src1   (src1_is_pc ? es_pc : rj_value),
    .alu_src2   (src2_is_imm ? imm : rkd_value),
    .alu_result (alu_result                   )
);

// Part 4: 写数据复制到各通道，只打开目标字节；其余字节保持不变。
// Part 6: 非对齐访存只传异常信息，不发出 RAM 请求。
assign store_mask = mem_size == 2'b01 ? (4'b0001 << alu_result[1:0]) :
                    mem_size == 2'b10 ? (alu_result[1] ? 4'b1100 : 4'b0011) : 4'b1111;
assign data_sram_en = es_valid && mem_access && !mem_pending && !mem_done
                   && !older_busy && !reset && !es_exception && !older_cancel && !wb_flush;
assign data_sram_we    = {4{data_sram_en && mem_we}} & store_mask;
assign data_sram_addr  = alu_result;
assign data_sram_wdata = mem_size == 2'b01 ? {4{rkd_value[7:0]}} :
                         mem_size == 2'b10 ? {2{rkd_value[15:0]}} : rkd_value;

assign es_to_ms_bus = {
    sys_op,       // Part 6: 控制指令类型
    es_exception, // Part 6: 汇合 ID 异常与 EXE 的 ALE
    es_ecode,     // Part 6: 保留较早检测到的异常优先级
    es_badv,      // Part 6: 出错地址
    csr_num,      // Part 6: CSR 编号
    csr_wmask,    // Part 6: 写掩码
    csr_wvalue,   // Part 6: 写值
    load_unsigned, // Part 4: 加载是否零扩展
    mem_size,      // Part 4: 字/字节/半字
    res_from_mem,  // 是否以 RAM 读数据作为写回值
    gr_we,        // 指令是否要求写通用寄存器
    dest,         // 目的寄存器编号
    exe_result,   // Part 5: ALU/乘除结果；访存时仍为有效地址
    load_response_r, // 已完成的 load 响应随本条指令传给 MEM
    es_pc         // 用于跟踪同一条指令
};

endmodule

`default_nettype wire
