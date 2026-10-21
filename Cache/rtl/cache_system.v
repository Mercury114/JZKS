`timescale 1ns / 1ps
`default_nettype none

// 真正的五级流水 CPU + 缓存系统。外部只需实现一个带完成应答的逐字主存端口。
module cache_system #(
    parameter INDEX_WIDTH = 8,
    parameter WAY_NUM = 2,
    parameter ENABLE_CACHE = 1,
    parameter BOARD_ADDR_MAP = 0
)(
    input  wire        clk,
    input  wire        resetn,
    input  wire [7:0]  hw_int_in,
    output wire        mem_valid,
    output wire        mem_write,
    output wire [3:0]  mem_wstrb,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    input  wire        mem_ready,
    input  wire        mem_rvalid,
    input  wire [31:0] mem_rdata,
    output wire [31:0] debug_wb_pc,
    output wire [3:0]  debug_wb_rf_we,
    output wire [4:0]  debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,
    output wire [31:0] i_access_count,
    output wire [31:0] i_hit_count,
    output wire [31:0] i_miss_count,
    output wire [31:0] d_access_count,
    output wire [31:0] d_hit_count,
    output wire [31:0] d_miss_count,
    output wire [31:0] uncached_count
);
    wire i_valid, i_addr_ok, i_data_ok;
    wire [31:0] i_addr, i_rdata;
    wire d_valid, d_addr_ok, d_data_ok;
    wire [3:0] d_wstrb;
    wire [31:0] d_addr, d_wdata, d_rdata;
    wire cacop_valid, cacop_ready, cacop_done;
    wire [4:0] cacop_code;
    wire [31:0] cacop_addr;
    // 仅原课程板级 RAM 有高位镜像：数据 RAM 只使用低18位。
    // 必须在进入缓存前归一化，否则同一物理字会有两份不同tag的脏副本。
    // 通用外部主存端口默认不截位，不能将板级镜像规则强加给真实主存。
    function [31:0] physical_address;
        input [31:0] address;
        begin
            if (!BOARD_ADDR_MAP || address[31:20] == 12'h1c0 ||
                (address & 32'h1fff0000) == 32'h1faf0000)
                physical_address = address;
            else physical_address = {14'b0, address[17:0]};
        end
    endfunction
    cache_cpu u_cpu(
        .clk(clk), .resetn(resetn), .hw_int_in(hw_int_in),
        .inst_sram_en(i_valid), .inst_sram_we(), .inst_sram_addr(i_addr), .inst_sram_wdata(),
        .inst_sram_rdata(i_rdata), .inst_addr_ok(i_addr_ok), .inst_data_ok(i_data_ok),
        .data_sram_en(d_valid), .data_sram_we(d_wstrb), .data_sram_addr(d_addr),
        .data_sram_wdata(d_wdata), .data_sram_rdata(d_rdata),
        .data_addr_ok(d_addr_ok), .data_data_ok(d_data_ok),
        .cacop_valid(cacop_valid), .cacop_code(cacop_code), .cacop_addr(cacop_addr),
        .cacop_ready(cacop_ready), .cacop_done(cacop_done),
        .debug_wb_pc(debug_wb_pc), .debug_wb_rf_we(debug_wb_rf_we),
        .debug_wb_rf_wnum(debug_wb_rf_wnum), .debug_wb_rf_wdata(debug_wb_rf_wdata)
    );
    cache_subsystem #(.INDEX_WIDTH(INDEX_WIDTH), .WAY_NUM(WAY_NUM), .ENABLE_CACHE(ENABLE_CACHE)) u_cache(
        .clk(clk), .resetn(resetn),
        .i_valid(i_valid), .i_addr(physical_address(i_addr)), .i_addr_ok(i_addr_ok), .i_data_ok(i_data_ok), .i_rdata(i_rdata),
        .d_valid(d_valid), .d_write(|d_wstrb), .d_wstrb(d_wstrb), .d_addr(physical_address(d_addr)), .d_wdata(d_wdata),
        .d_addr_ok(d_addr_ok), .d_data_ok(d_data_ok), .d_rdata(d_rdata),
        .cacop_valid(cacop_valid), .cacop_code(cacop_code), .cacop_addr(physical_address(cacop_addr)),
        .cacop_ready(cacop_ready), .cacop_done(cacop_done),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_ready(mem_ready), .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .i_access_count(i_access_count), .i_hit_count(i_hit_count), .i_miss_count(i_miss_count),
        .d_access_count(d_access_count), .d_hit_count(d_hit_count), .d_miss_count(d_miss_count),
        .uncached_count(uncached_count)
    );
endmodule
`default_nettype wire
