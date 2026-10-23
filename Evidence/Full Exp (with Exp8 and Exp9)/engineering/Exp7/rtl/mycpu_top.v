`include "mycpu_head.v"

module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    output wire        inst_sram_en,
    output wire [3:0]  inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    output wire        data_sram_en,
    output wire [3:0]  data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    output wire [31:0] debug_wb_pc,
    output wire [3:0]  debug_wb_rf_we,
    output wire [4:0]  debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

wire         reset;
assign reset = ~resetn;

wire [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus;
wire [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus;
wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus;
wire [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus;

wire fs_to_ds_valid;
wire ds_to_es_valid;
wire es_to_ms_valid;
wire ms_to_ws_valid;

wire ds_allowin;
wire es_allowin;
wire ms_allowin;
wire ws_allowin;

wire [32:0] br_bus;
wire [4:0]  ws_to_rf_waddr;
wire [31:0] ws_to_rf_wdata;
wire        ws_to_rf_we;
wire        ms_hazard_valid;
wire        ms_hazard_gr_we;
wire [4:0]  ms_hazard_dest;
wire        ms_forward_valid;
wire [31:0] ms_forward_data;

IF_stage u_if_stage(
    .clk(clk),
    .reset(reset),
    .ds_allowin(ds_allowin),
    .fs_to_ds_valid(fs_to_ds_valid),
    .fs_to_ds_bus(fs_to_ds_bus),
    .br_bus(br_bus),
    .inst_sram_en(inst_sram_en),
    .inst_sram_we(inst_sram_we),
    .inst_sram_addr(inst_sram_addr),
    .inst_sram_wdata(inst_sram_wdata),
    .inst_sram_rdata(inst_sram_rdata)
);

ID_stage u_id_stage(
    .clk(clk),
    .reset(reset),
    .es_allowin(es_allowin),
    .ds_allowin(ds_allowin),
    .fs_to_ds_valid(fs_to_ds_valid),
    .fs_to_ds_bus(fs_to_ds_bus),
    .ds_to_es_valid(ds_to_es_valid),
    .ds_to_es_bus(ds_to_es_bus),
    .br_bus(br_bus),
    .es_to_ms_valid(es_to_ms_valid),
    .es_to_ms_bus(es_to_ms_bus),
    .ms_hazard_valid(ms_hazard_valid),
    .ms_hazard_gr_we(ms_hazard_gr_we),
    .ms_hazard_dest(ms_hazard_dest),
    .ms_forward_valid(ms_forward_valid),
    .ms_forward_data(ms_forward_data),
    .ws_to_rf_we(ws_to_rf_we),
    .ws_to_rf_waddr(ws_to_rf_waddr),
    .ws_to_rf_wdata(ws_to_rf_wdata)
);

EXE_stage u_exe_stage(
    .clk(clk),
    .reset(reset),
    .ms_allowin(ms_allowin),
    .es_allowin(es_allowin),
    .ds_to_es_valid(ds_to_es_valid),
    .ds_to_es_bus(ds_to_es_bus),
    .es_to_ms_valid(es_to_ms_valid),
    .es_to_ms_bus(es_to_ms_bus)
);

MEM_stage u_mem_stage(
    .clk(clk),
    .reset(reset),
    .ws_allowin(ws_allowin),
    .ms_allowin(ms_allowin),
    .es_to_ms_valid(es_to_ms_valid),
    .es_to_ms_bus(es_to_ms_bus),
    .ms_to_ws_valid(ms_to_ws_valid),
    .ms_to_ws_bus(ms_to_ws_bus),
    .data_sram_en(data_sram_en),
    .data_sram_we(data_sram_we),
    .data_sram_addr(data_sram_addr),
    .data_sram_wdata(data_sram_wdata),
    .data_sram_rdata(data_sram_rdata),
    .ms_hazard_valid(ms_hazard_valid),
    .ms_hazard_gr_we(ms_hazard_gr_we),
    .ms_hazard_dest(ms_hazard_dest),
    .ms_forward_valid(ms_forward_valid),
    .ms_forward_data(ms_forward_data)
);

WB_stage u_wb_stage(
    .clk(clk),
    .reset(reset),
    .ms_to_ws_valid(ms_to_ws_valid),
    .ms_to_ws_bus(ms_to_ws_bus),
    .ws_to_rf_we(ws_to_rf_we),
    .ws_to_rf_waddr(ws_to_rf_waddr),
    .ws_to_rf_wdata(ws_to_rf_wdata),
    .debug_wb_pc(debug_wb_pc),
    .debug_wb_rf_we(debug_wb_rf_we),
    .debug_wb_rf_wnum(debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata)
);

assign ws_allowin = 1'b1;

endmodule
