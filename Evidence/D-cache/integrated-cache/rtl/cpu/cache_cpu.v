// 五级流水 CPU 的接线入口：IF 取指 → ID 译码 → EXE 运算 → MEM 访存结果 → WB 写回。
// fs/ds/es/ms/ws 分别是上述五级的信号前缀；数据向后传，allowin 向前传。
// Part 2: EXE/MEM/WB 向 ID 前递；EXE 的 load 尚无结果时保持 IF/ID，后级继续前进。
`timescale 1ns/1ps
`default_nettype none
`include "mycpu_head.v"

module cache_cpu(
    // 外部时钟与低有效复位
    input  wire        clk,
    input  wire        resetn,
    // Part 6: 八路电平硬件中断；课程 BRAM 板级环境未接外设时显式接零。
    input  wire [ 7:0] hw_int_in,

    input  wire        inst_addr_ok,
    input  wire        inst_data_ok,
    input  wire        data_addr_ok,
    input  wire        data_data_ok,
    output wire        cacop_valid,
    output wire [ 4:0] cacop_code,
    output wire [31:0] cacop_addr,
    input  wire        cacop_ready,
    input  wire        cacop_done,

    // 指令缓存接口：en 为请求 valid，addr_ok 接受后等待 data_ok 返回
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,

    // 数据缓存请求：valid、字节写使能、地址和写数据
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,

    // 写回调试接口：写使能有效时，其余字段才表示一次寄存器写回
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

wire        reset = ~resetn;

// valid 表示这一级有指令要交给后级；allowin 表示后级能接收。
wire        fs_to_ds_valid;
wire        ds_to_es_valid;
wire        es_to_ms_valid;
wire        ms_to_ws_valid;
wire        ds_allowin;
wire        es_allowin;
wire        ms_allowin;
wire        ws_allowin;

// Part 6: CSR 串行等待、异常提交与全流水冲刷。
wire        es_busy;
wire        ms_busy;
wire        ws_busy;
wire        es_system;
wire        ms_system;
wire        ws_system;
wire        ms_cancel;
wire        pipeline_busy;
wire        system_pending;
wire        wb_flush;
wire [31:0] flush_pc;
wire        has_int;
wire [ 1:0] current_plv;

assign pipeline_busy  = es_busy || ms_busy || ws_busy;
assign system_pending = es_system || ms_system || ws_system;

// 总线把同一条指令的控制信号和数据一起传递，字段表见 mycpu_head.v。
wire [`BR_BUS_WD - 1:0]       br_bus;
wire [`FS_TO_DS_BUS_WD - 1:0] fs_to_ds_bus;
wire [`DS_TO_ES_BUS_WD - 1:0] ds_to_es_bus;
wire [`ES_TO_MS_BUS_WD - 1:0] es_to_ms_bus;
wire [`MS_TO_WS_BUS_WD - 1:0] ms_to_ws_bus;
wire [`WS_TO_RF_BUS_WD - 1:0] ws_to_rf_bus;
wire [`ES_TO_DS_BUS_WD - 1:0] es_to_ds_bus;
wire [`MS_TO_DS_BUS_WD - 1:0] ms_to_ds_bus;

// CPU 与缓存共用 resetn，在同一时钟沿清除所有未决请求归属。

// IF：发出取指地址，并把取到的指令交给 ID。
if_stage u_if(
    .wb_flush        (wb_flush       ), // Part 6: 异常/返回冲刷
    .flush_pc        (flush_pc       ), // Part 6: 异常入口或 ERA
    .current_plv     (current_plv    ), // Part 6: 取指地址权限检查
    .clk             (clk            ),       // 时钟，各级在上升沿更新流水寄存器
    .reset           (reset          ),       // 内部高有效同步复位
    .ds_allowin      (ds_allowin     ),       // ID → IF：ID 能否接收新指令
    .br_bus          (br_bus         ),       // ID → IF：是否跳转、跳转目标地址
    .fs_to_ds_valid  (fs_to_ds_valid ),       // IF → ID：本次传递的指令是否有效
    .fs_to_ds_bus    (fs_to_ds_bus   ),       // IF → ID：指令编码、该指令的 PC
    .inst_sram_en    (inst_sram_en   ),       // IF → 指令 RAM：取指片选
    .inst_sram_we    (inst_sram_we   ),       // IF → 指令 RAM：字节写使能，只读故恒为 0000
    .inst_sram_addr  (inst_sram_addr ),       // IF → 指令 RAM：本次请求的取指地址
    .inst_sram_wdata (inst_sram_wdata),       // IF → 指令 RAM：写数据，不写故固定为 0
    .inst_addr_ok    (inst_addr_ok   ),
    .inst_data_ok    (inst_data_ok   ),
    .inst_sram_rdata (inst_sram_rdata)        // 指令缓存 → IF：data_ok 对应的返回指令
);

// ID：识别指令、读取寄存器，并将跳转决定送回 IF。
id_stage u_id(
    .wb_flush       (wb_flush      ), // Part 6: 取消 ID 的年轻指令
    .pipeline_busy  (pipeline_busy ), // Part 6: CSR 等待旧指令完成
    .system_pending (system_pending), // Part 6: 等待控制指令提交
    .has_int        (has_int       ), // Part 6: 已使能的中断
    .current_plv    (current_plv   ), // Part 6: 特权指令权限
    .clk            (clk           ),         // 时钟，各级在上升沿更新流水寄存器
    .reset          (reset         ),         // 内部高有效同步复位
    .es_allowin     (es_allowin    ),         // EXE → ID：EXE 能否接收新指令
    .ds_allowin     (ds_allowin    ),         // ID → IF：ID 能否接收新指令
    .fs_to_ds_valid (fs_to_ds_valid),         // IF → ID：本次传递的指令是否有效
    .fs_to_ds_bus   (fs_to_ds_bus  ),         // IF → ID：指令编码、该指令的 PC
    .ds_to_es_valid (ds_to_es_valid),         // ID → EXE：本次传递的指令是否有效
    .ds_to_es_bus   (ds_to_es_bus  ),         // ID → EXE：运算/访存/写回控制、操作数、PC
    .br_bus         (br_bus        ),         // ID → IF：是否跳转、跳转目标地址
    .es_to_ds_bus   (es_to_ds_bus  ),         // Part 2: EXE → ID：写者、load 标志与 ALU 结果
    .ms_to_ds_bus   (ms_to_ds_bus  ),         // Part 2: MEM → ID：写者与最终写回结果
    .ws_to_rf_bus   (ws_to_rf_bus  )          // WB → ID 寄存器堆：实际写使能、目的编号、写入值
);

// EXE：运算或计算访存地址，向数据 RAM 发出请求。
exe_stage u_exe(
    .wb_flush        (wb_flush       ), // Part 6: 取消指令和除法状态
    .older_cancel    (ms_cancel      ),
    .older_busy      (ms_busy || ws_busy), // 老指令提交后才能发出访存/管理请求
    .data_addr_ok    (data_addr_ok   ),
    .data_data_ok    (data_data_ok   ),
    .data_sram_rdata (data_sram_rdata),
    .cacop_valid     (cacop_valid    ),
    .cacop_code      (cacop_code     ),
    .cacop_addr      (cacop_addr     ),
    .cacop_ready     (cacop_ready    ),
    .cacop_done      (cacop_done     ),
    .es_busy         (es_busy        ), // Part 6: 本级持有指令
    .es_system       (es_system      ), // Part 6: 本级持有控制指令
    .clk             (clk            ),       // 时钟，各级在上升沿更新流水寄存器
    .reset           (reset          ),       // 内部高有效同步复位
    .ms_allowin      (ms_allowin     ),       // MEM → EXE：MEM 能否接收新指令
    .es_allowin      (es_allowin     ),       // EXE → ID：EXE 能否接收新指令
    .ds_to_es_valid  (ds_to_es_valid ),       // ID → EXE：本次传递的指令是否有效
    .ds_to_es_bus    (ds_to_es_bus   ),       // ID → EXE：运算/访存/写回控制、操作数、PC
    .es_to_ms_valid  (es_to_ms_valid ),       // EXE → MEM：本次传递的指令是否有效
    .es_to_ms_bus    (es_to_ms_bus   ),       // EXE → MEM：结果选择、写回控制、ALU 结果、存储数据、PC
    .es_to_ds_bus    (es_to_ds_bus   ),       // Part 2: EXE → ID：有效写者、load 标志、编号、ALU 结果
    .data_sram_en    (data_sram_en   ),       // EXE → 数据 RAM：有效 load/store 的访问片选
    .data_sram_we    (data_sram_we   ),       // EXE → 数据 RAM：字节写使能，st.w 时为 1111
    .data_sram_addr  (data_sram_addr ),       // EXE → 数据 RAM：ALU 算出的访存地址
    .data_sram_wdata (data_sram_wdata)        // EXE → 数据 RAM：st.w 要存入的寄存器值
);

// MEM：选择 RAM 读数据或 ALU 结果，交给 WB。
mem_stage u_mem(
    .wb_flush        (wb_flush       ), // Part 6: 取消年轻指令
    .ms_busy         (ms_busy        ), // Part 6: 本级持有指令
    .ms_system       (ms_system      ), // Part 6: 本级持有控制指令
    .ms_cancel       (ms_cancel      ), // Part 6: 阻止年轻 RAM 请求
    .clk             (clk            ),       // 时钟，各级在上升沿更新流水寄存器
    .reset           (reset          ),       // 内部高有效同步复位
    .ws_allowin      (ws_allowin     ),       // WB → MEM：WB 能否接收，当前恒为 1
    .ms_allowin      (ms_allowin     ),       // MEM → EXE：MEM 能否接收新指令
    .es_to_ms_valid  (es_to_ms_valid ),       // EXE → MEM：本次传递的指令是否有效
    .es_to_ms_bus    (es_to_ms_bus   ),       // EXE → MEM：结果选择、写回控制、ALU 结果、存储数据、PC
    .ms_to_ws_valid  (ms_to_ws_valid ),       // MEM → WB：本次传递的指令是否有效
    .ms_to_ws_bus    (ms_to_ws_bus   ),       // MEM → WB：写回使能、目的寄存器号、最终结果、PC
    .ms_to_ds_bus    (ms_to_ds_bus   ),       // Part 2: MEM → ID：有效写者、编号、最终结果
    .data_sram_rdata (data_sram_rdata)        // 保留历史 MEM 端口；实际 load 响应已由 EXE 随流水总线锁存传递
);

// WB：产生寄存器写回信息，送回 ID 内的寄存器堆。
wb_stage u_wb(
    .hw_int_in         (hw_int_in        ), // Part 6: 硬件中断采样
    .ws_busy           (ws_busy          ), // Part 6: 本级持有指令
    .ws_system         (ws_system        ), // Part 6: 控制指令提交等待
    .wb_flush          (wb_flush         ), // Part 6: 全流水冲刷
    .flush_pc          (flush_pc         ), // Part 6: 重定向地址
    .has_int           (has_int          ), // Part 6: ID 中断标记
    .current_plv       (current_plv      ), // Part 6: 当前/重定向后的特权级
    .clk               (clk              ),   // 时钟，各级在上升沿更新流水寄存器
    .reset             (reset            ),   // 内部高有效同步复位
    .ws_allowin        (ws_allowin       ),   // WB → MEM：WB 能否接收，当前恒为 1
    .ms_to_ws_valid    (ms_to_ws_valid   ),   // MEM → WB：本次传递的指令是否有效
    .ms_to_ws_bus      (ms_to_ws_bus     ),   // MEM → WB：写回使能、目的寄存器号、最终结果、PC
    .ws_to_rf_bus      (ws_to_rf_bus     ),   // WB → ID 寄存器堆：实际写使能、目的编号、写入值
    .debug_wb_pc       (debug_wb_pc      ),   // WB → 调试环境：写回指令的 PC
    .debug_wb_rf_we    (debug_wb_rf_we   ),   // WB → 调试环境：有效写回为 1111，否则为 0000
    .debug_wb_rf_wnum  (debug_wb_rf_wnum ),   // WB → 调试环境：写回的目的寄存器编号
    .debug_wb_rf_wdata (debug_wb_rf_wdata)    // WB → 调试环境：写回寄存器的数据
);

endmodule

`default_nettype wire
