// MEM（访存结果级）：使用 EXE 已锁存的实际访存响应，选择加载结果并交给 WB。
// Part 4: load 按低地址位选择字节/半字并扩展；其他指令使用 EXE 结果。
// EXE 等待 data_ok 后才进入本级；原 store-data 字段现在承载本条 load 的返回数据。
`timescale 1ns/1ps
`default_nettype none
`include "mycpu_head.v"

module mem_stage(
    // 时钟与内部高有效复位
    input  wire        clk,
    input  wire        reset,
    // Part 6: 给前端和 EXE 提供旧控制指令/异常的状态。
    input  wire        wb_flush,
    output wire        ms_busy,
    output wire        ms_system,
    output wire        ms_cancel,

    // WB 能接收本级指令时为 1
    input  wire        ws_allowin,

    // 本级 MEM 能接收前级指令时为 1
    output wire        ms_allowin,

    // EXE → MEM：有效标志与运算结果
    input  wire        es_to_ms_valid,
    input  wire [`ES_TO_MS_BUS_WD - 1:0] es_to_ms_bus,

    // MEM → WB：有效标志与待写回数据
    output wire        ms_to_ws_valid,
    output wire [`MS_TO_WS_BUS_WD - 1:0] ms_to_ws_bus,

    // Part 2: 送回 ID 的最终结果及有效写者信息
    output wire [`MS_TO_DS_BUS_WD - 1:0] ms_to_ds_bus,

    // 保留历史外部端口；加载数据实际由 es_to_ms_bus 随指令传入，不使用此实时信号。
    input  wire [31:0] data_sram_rdata
);

reg         ms_valid;
reg  [`ES_TO_MS_BUS_WD - 1:0] bus_r;

// Part 6: 控制/异常信息与本条指令一起流动。
wire [ 7:0] sys_op;
wire        ex_valid;
wire [ 5:0] ex_code;
wire [31:0] ex_badv;
wire [13:0] csr_num;
wire [31:0] csr_wmask;
wire [31:0] csr_wvalue;

// Part 4: 用本条指令锁存的地址低位，不使用下一条 EXE 的地址。
wire        load_unsigned;
wire [ 1:0] mem_size;
wire [31:0] shifted_data;
wire [31:0] load_result;
wire        res_from_mem;
wire        gr_we;
wire [ 4:0] dest;
wire [31:0] alu_result;
wire [31:0] load_response; // EXE 锁存的 load 响应，与本级地址/类型属于同一条指令
wire [31:0] ms_pc;
wire [31:0] final_result;

assign {
    sys_op,
    ex_valid,
    ex_code,
    ex_badv,
    csr_num,
    csr_wmask,
    csr_wvalue,
    load_unsigned,
    mem_size,
    res_from_mem,
    gr_we,
    dest,
    alu_result,
    load_response,
    ms_pc
} = bus_r;

assign ms_allowin     = ~ms_valid || ws_allowin;
assign ms_to_ws_valid = ms_valid && ~wb_flush;
assign ms_busy        = ms_valid;
assign ms_system      = ms_valid && (|sys_op);
assign ms_cancel      = ms_valid && (ex_valid || sys_op[3]);

assign ms_to_ds_bus = {
    ms_valid && gr_we && (dest != 5'd0) && ~reset && ~ex_valid && ~wb_flush && ~(|sys_op),
    dest,
    final_result
};

// 只清有效位；当 valid=0 时，总线寄存器里的旧值不代表一条有效指令。
always @(posedge clk) begin
    if (reset || wb_flush) begin
        ms_valid <= 1'b0;
    end
    else if (ms_allowin) begin
        ms_valid <= es_to_ms_valid;
    end

    if (ms_allowin && es_to_ms_valid) begin
        bus_r <= es_to_ms_bus;
    end
end

// EXE 锁存的响应与本级控制信息一一对应，不受外部 rdata 后续变化影响。
// Part 2: 同一份最终结果也前递到 ID；load 只能从这里开始提供加载值。
// Part 4: 小端选择完成后再扩展；前递也使用扩展后的最终值。
assign shifted_data = load_response >> {alu_result[1:0], 3'b000};
assign load_result  = mem_size == 2'b01 ? {{24{~load_unsigned && shifted_data[7]}}, shifted_data[7:0]} :
                     mem_size == 2'b10 ? {{16{~load_unsigned && shifted_data[15]}}, shifted_data[15:0]} :
                                        load_response;
assign final_result = res_from_mem ? load_result : alu_result;

assign ms_to_ws_bus = {
    sys_op,
    ex_valid,
    ex_code,
    ex_badv,
    csr_num,
    csr_wmask,
    csr_wvalue,
    gr_we,
    dest,
    final_result,
    ms_pc
};

endmodule

`default_nettype wire
