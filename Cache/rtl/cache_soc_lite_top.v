`timescale 1ns / 1ps
`default_nettype none

// 新增板级连接版本，原 Exp9/soc_lite_top 不修改。
// 代码区 1c00_0000~1c0f_ffff 映射 inst_ram（支持 D 写回以便自修改代码），
// 原 confreg 两个别名旁路；其余访问使用原 data_ram 的低 18 位地址。
// clk 必须是已约束的 CPU 时钟，不使用普通逻辑分频器制造新时钟。
module cache_soc_lite_top #(
    parameter SIMULATION = 1'b0,
    parameter INDEX_WIDTH = 8,
    parameter WAY_NUM = 2,
    parameter ENABLE_CACHE = 1,
    parameter INST_INIT_FILE = ""
)(
    input  wire        resetn,
    input  wire        clk,
    output wire [15:0] led,
    output wire [1:0]  led_rg0,
    output wire [1:0]  led_rg1,
    output wire [7:0]  num_csn,
    output wire [6:0]  num_a_g,
    output wire [31:0] num_data,
    input  wire [7:0]  switch,
    output wire [3:0]  btn_key_col,
    input  wire [3:0]  btn_key_row,
    input  wire [1:0]  btn_step
);
    reg cpu_resetn;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) cpu_resetn <= 0;
        else cpu_resetn <= 1;
    end
    wire mem_valid, mem_write, mem_ready, mem_rvalid;
    wire [3:0] mem_wstrb;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [31:0] debug_wb_pc, debug_wb_rf_wdata;
    wire [3:0] debug_wb_rf_we;
    wire [4:0] debug_wb_rf_wnum;
    cache_system #(.INDEX_WIDTH(INDEX_WIDTH), .WAY_NUM(WAY_NUM), .ENABLE_CACHE(ENABLE_CACHE), .BOARD_ADDR_MAP(1)) u_system(
        .clk(clk), .resetn(cpu_resetn), .hw_int_in(8'b0),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_ready(mem_ready), .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .debug_wb_pc(debug_wb_pc), .debug_wb_rf_we(debug_wb_rf_we),
        .debug_wb_rf_wnum(debug_wb_rf_wnum), .debug_wb_rf_wdata(debug_wb_rf_wdata),
        .i_access_count(), .i_hit_count(), .i_miss_count(),
        .d_access_count(), .d_hit_count(), .d_miss_count(), .uncached_count()
    );
    wire bus_en;
    wire [3:0] bus_we;
    wire [31:0] bus_addr, bus_wdata, bus_rdata;
    cache_sram_bridge u_sram_bridge(
        .clk(clk), .resetn(cpu_resetn),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_ready(mem_ready), .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .sram_en(bus_en), .sram_we(bus_we), .sram_addr(bus_addr), .sram_wdata(bus_wdata),
        .sram_rdata(bus_rdata)
    );
    wire select_conf = (bus_addr & 32'h1fff0000) == 32'h1faf0000;
    wire select_inst = !select_conf && bus_addr[31:20] == 12'h1c0;
    reg [1:0] response_target;
    always @(posedge clk) begin
        if (!cpu_resetn) response_target <= 0;
        else if (bus_en) response_target <= select_conf ? 2'd2 : select_inst ? 2'd1 : 2'd0;
    end
    wire [31:0] inst_rdata, data_rdata, conf_rdata;
    assign bus_rdata = response_target == 2 ? conf_rdata : response_target == 1 ? inst_rdata : data_rdata;
    cache_board_ram #(.ADDR_WIDTH(18), .INIT_FILE(INST_INIT_FILE)) inst_ram(
        .clk(clk), .en(bus_en && select_inst), .we(bus_we),
        .addr(bus_addr[19:2]), .wdata(bus_wdata), .rdata(inst_rdata)
    );
    cache_board_ram #(.ADDR_WIDTH(16)) data_ram(
        .clk(clk), .en(bus_en && !select_inst && !select_conf), .we(bus_we),
        .addr(bus_addr[17:2]), .wdata(bus_wdata), .rdata(data_rdata)
    );
    confreg #(.SIMULATION(SIMULATION)) u_confreg(
        .clk(clk), .timer_clk(clk), .resetn(cpu_resetn),
        .conf_en(bus_en && select_conf), .conf_we(bus_we), .conf_addr(bus_addr),
        .conf_wdata(bus_wdata), .conf_rdata(conf_rdata),
        .led(led), .led_rg0(led_rg0), .led_rg1(led_rg1), .num_csn(num_csn),
        .num_a_g(num_a_g), .num_data(num_data), .switch(switch),
        .btn_key_col(btn_key_col), .btn_key_row(btn_key_row), .btn_step(btn_step)
    );
endmodule
`default_nettype wire
