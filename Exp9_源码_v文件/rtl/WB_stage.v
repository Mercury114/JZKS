`include "mycpu_head.v"

module WB_stage(
    input  wire        clk,
    input  wire        reset,
    input  wire        ms_to_ws_valid,
    input  wire [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus,
    output wire        ws_to_rf_we,
    output wire [4:0]  ws_to_rf_waddr,
    output wire [31:0] ws_to_rf_wdata,
    output wire [31:0] debug_wb_pc,
    output wire [3:0]  debug_wb_rf_we,
    output wire [4:0]  debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

wire [31:0] final_result;
wire        gr_we;
wire [4:0]  dest;
wire [31:0] ds_pc; // 新增：用于接收传下来的 PC

// 修改：解包时加入 ds_pc
assign {final_result, gr_we, dest, ds_pc} = ms_to_ws_bus;

assign ws_to_rf_we    = gr_we && ms_to_ws_valid;
assign ws_to_rf_waddr = dest;
assign ws_to_rf_wdata = final_result;

// 修改：将真正的 PC 赋值给 debug_wb_pc，而不是恒为 0
assign debug_wb_pc       = ds_pc;
assign debug_wb_rf_we    = {4{ws_to_rf_we}};
assign debug_wb_rf_wnum  = ws_to_rf_waddr;
assign debug_wb_rf_wdata = ws_to_rf_wdata;

endmodule