// IF（取指级）：由原五级 IF 适配，每次最多保留一个已接受、尚未返回的取指请求。
// 跳转/冲刷可取消未接受请求；已经接受的旧请求必须等返回并丢弃，不能当成新 PC 的指令。
`timescale 1ns/1ps
`default_nettype none
`include "mycpu_head.v"

module if_stage(
    input  wire        clk,
    input  wire        reset,
    input  wire        wb_flush,
    input  wire [31:0] flush_pc,
    input  wire [ 1:0] current_plv,
    input  wire        ds_allowin,
    input  wire [`BR_BUS_WD - 1:0] br_bus,
    output wire        fs_to_ds_valid,
    output wire [`FS_TO_DS_BUS_WD - 1:0] fs_to_ds_bus,
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    input  wire        inst_addr_ok,
    input  wire        inst_data_ok
);

    // fs_* 保存已经返回、等待 ID 接收的指令；fetch_pc 是下一笔待发送的地址。
    reg         fs_valid;
    reg         fs_adef;
    reg  [31:0] fs_pc;
    reg  [31:0] fs_inst;
    reg  [31:0] fetch_pc;
    reg  [31:0] pending_pc;
    reg         pending;       // 已被 addr_ok 接受，尚未收到 data_ok
    reg         discard;       // 该未决请求属于被取消的旧路径

    wire        br_taken = br_bus[32];
    wire        redirect = wb_flush || br_taken;
    wire [31:0] redirect_pc = wb_flush ? flush_pc : br_bus[31:0];
    wire        fetch_adef = |fetch_pc[1:0] || (current_plv == 3 && fetch_pc[31]);
    wire        accept = inst_sram_en && inst_addr_ok;

    // 地址接受前保持请求；接受后撤销 valid，等待对应返回，避免重复取指。
    assign inst_sram_en = !reset && !redirect && !pending && !fs_valid && !fetch_adef;
    assign inst_sram_addr = fetch_pc;
    assign inst_sram_we = 0;
    assign inst_sram_wdata = 0;
    assign fs_to_ds_valid = fs_valid && !redirect && !reset;
    assign fs_to_ds_bus = {fs_adef, fs_inst, fs_pc};

    always @(posedge clk) begin
        if (reset) begin
            fs_valid <= 0;
            fs_adef <= 0;
            pending <= 0;
            discard <= 0;
            fetch_pc <= 32'h1c000000;
        end else begin
            if (fs_valid && ds_allowin) begin
                fs_valid <= 0;
            end
            if (!pending && !fs_valid && !fetch_adef && accept) begin
                pending <= 1;
                pending_pc <= fetch_pc;
                discard <= 0;
                fetch_pc <= fetch_pc + 4;
            end

            // 错误取指地址不访问缓存，直接携带 PC 和 ADEF 标记进入精确异常通路。
            if (!pending && !fs_valid && fetch_adef && !redirect) begin
                fs_valid <= 1;
                fs_adef <= 1;
                fs_pc <= fetch_pc;
                fs_inst <= 0;
                fetch_pc <= fetch_pc + 4;
            end

            // 也支持接受与返回同拍；这种情况下使用本拍 fetch_pc，而非旧 pending_pc。
            if (inst_data_ok && (pending || accept)) begin
                pending <= 0;
                discard <= 0;
                if (!discard && !redirect) begin
                    fs_valid <= 1;
                    fs_adef <= 0;
                    fs_inst <= inst_sram_rdata;
                    fs_pc <= pending ? pending_pc : fetch_pc;
                end
            end

            // 重定向优先：清返回缓冲，但保留已接受旧请求的归属，直到旧响应排空。
            if (redirect) begin
                fs_valid <= 0;
                fetch_pc <= redirect_pc;
                if (pending && !inst_data_ok) begin
                    discard <= 1;
                end
            end
        end
    end

endmodule

`default_nettype wire
