// WB（写回级）：保存 MEM 送来的结果，产生寄存器堆写口和调试接口信号。
// 本级每拍都能接收；有效指令要求写寄存器且目的不是 r0 时，才允许写入。
// 写口连回 ID 内的寄存器堆，在时钟上升沿完成实际写入。
`timescale 1ns/1ps
`default_nettype none
`include "mycpu_head.v"

module wb_stage(
    // 时钟与内部高有效复位
    input  wire        clk,
    input  wire        reset,
    // Part 6: 写回级统一更新 CSR、保存异常现场并发出冲刷。
    input  wire [ 7:0] hw_int_in,
    output wire        ws_busy,
    output wire        ws_system,
    output wire        wb_flush,
    output wire [31:0] flush_pc,
    output wire        has_int,
    output wire [ 1:0] current_plv,

    // WB 始终能接收 MEM 的结果
    output wire        ws_allowin,

    // MEM → WB：有效标志与待写回数据
    input  wire        ms_to_ws_valid,
    input  wire [`MS_TO_WS_BUS_WD - 1:0] ms_to_ws_bus,

    // WB → ID：寄存器堆写使能、编号和写入值
    output wire [`WS_TO_RF_BUS_WD - 1:0] ws_to_rf_bus,

    // 写回调试接口：写使能有效时，其余字段才表示一次寄存器写回
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

reg         ws_valid;
reg  [`MS_TO_WS_BUS_WD - 1:0] bus_r;

// Part 6: 控制/异常信息与本条指令一起流动。
wire [ 7:0] sys_op;
wire        ex_valid;
wire [ 5:0] ex_code;
wire [31:0] ex_badv;
wire [13:0] csr_num;
wire [31:0] csr_wmask;
wire [31:0] csr_wvalue;
wire [31:0] csr_rvalue;
wire [31:0] ex_entry;
wire [31:0] ex_era;
wire [63:0] stable_counter;
wire [31:0] counter_id;
wire [31:0] final_result;
wire        wb_ex;
wire        ertn_flush;
wire        csr_we;

wire        gr_we;
wire [ 4:0] dest;
wire [31:0] result;
wire [31:0] ws_pc;
wire        rf_we;

assign {
    sys_op,
    ex_valid,
    ex_code,
    ex_badv,
    csr_num,
    csr_wmask,
    csr_wvalue,
    gr_we,
    dest,
    result,
    ws_pc
} = bus_r;

// 当前没有等待写回的情况，因而不会阻塞 MEM。
assign ws_allowin = 1'b1;
assign ws_busy    = ws_valid;
assign ws_system  = ws_valid && (|sys_op);
assign wb_ex      = ws_valid && ex_valid && ~reset;
assign ertn_flush = ws_valid && sys_op[3] && ~ex_valid && ~reset;
assign wb_flush   = wb_ex || ertn_flush || (ws_valid && sys_op[7] && ~ex_valid && ~reset);
assign flush_pc   = wb_ex ? ex_entry : sys_op[7] ? ws_pc + 32'd4 : ex_era;
assign csr_we     = ws_valid && (sys_op[1] || sys_op[2]) && ~ex_valid && ~reset;
assign final_result = (|sys_op[2:0]) ? csr_rvalue : sys_op[4] ? stable_counter[31:0] :
                      sys_op[5] ? stable_counter[63:32] : sys_op[6] ? counter_id : result;

// Part 6: CSR 读取旧值与软件写入在同一个提交时钟沿完成。
csr u_csr(
    .clk            (clk           ),
    .reset          (reset         ),
    .hw_int_in      (hw_int_in     ),
    .csr_num        (csr_num       ),
    .csr_we         (csr_we        ),
    .csr_wmask      (csr_wmask     ),
    .csr_wvalue     (csr_wvalue    ),
    .wb_ex          (wb_ex         ),
    .wb_ecode       (ex_code       ),
    .wb_pc          (ws_pc         ),
    .wb_badv        (ex_badv       ),
    .ertn_flush     (ertn_flush    ),
    .csr_rvalue     (csr_rvalue    ),
    .ex_entry       (ex_entry      ),
    .ex_era         (ex_era        ),
    .current_plv    (current_plv   ),
    .has_int        (has_int       ),
    .stable_counter (stable_counter),
    .counter_id     (counter_id    )
);

always @(posedge clk) begin
    if (reset || wb_flush) begin
        ws_valid <= 1'b0;
    end
    else begin
        ws_valid <= ms_to_ws_valid;
    end

    if (ms_to_ws_valid) begin
        bus_r <= ms_to_ws_bus;
    end
end

// 即使总线里留有旧值，空拍、写 r0 或复位都不会触发寄存器写入。
assign rf_we = ws_valid && gr_we && (dest != 0) && ~reset && ~ex_valid && ~sys_op[3];
assign ws_to_rf_bus = {
    rf_we,
    dest,
    final_result
};

// PC、编号、数据来自同一条 WB 指令，供测试环境逐次核对写回。
// rf_we=0 时，其余调试字段可能保留旧值，不应当作一次有效写回。
assign debug_wb_pc       = ws_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = dest;
assign debug_wb_rf_wdata = final_result;

endmodule

`default_nettype wire
