`timescale 1ns / 1ps
`default_nettype none

// 与 CPU 无关的公共接入层：I/D Cache + CACOP 路由 + 外设旁路 + 单端口仲裁。
// ENABLE_CACHE=0 使用同一 CPU、同一主存协议，作为公平的无缓存对照。
module cache_subsystem #(
    parameter INDEX_WIDTH = 8,
    parameter WAY_NUM = 2,
    parameter ENABLE_CACHE = 1
)(
    input  wire        clk,
    input  wire        resetn,
    input  wire        i_valid,
    input  wire [31:0] i_addr,
    output wire        i_addr_ok,
    output wire        i_data_ok,
    output wire [31:0] i_rdata,
    input  wire        d_valid,
    input  wire        d_write,
    input  wire [3:0]  d_wstrb,
    input  wire [31:0] d_addr,
    input  wire [31:0] d_wdata,
    output wire        d_addr_ok,
    output wire        d_data_ok,
    output wire [31:0] d_rdata,
    input  wire        cacop_valid,
    input  wire [4:0]  cacop_code,
    input  wire [31:0] cacop_addr,
    output wire        cacop_ready,
    output wire        cacop_done,
    output wire        mem_valid,
    output wire        mem_write,
    output wire [3:0]  mem_wstrb,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    input  wire        mem_ready,
    input  wire        mem_rvalid,
    input  wire [31:0] mem_rdata,
    output wire [31:0] i_access_count,
    output wire [31:0] i_hit_count,
    output wire [31:0] i_miss_count,
    output wire [31:0] d_access_count,
    output wire [31:0] d_hit_count,
    output wire [31:0] d_miss_count,
    output reg  [31:0] uncached_count
);
    localparam TAG_WIDTH = 28 - INDEX_WIDTH;
    localparam U_IDLE = 2'd0, U_REQUEST = 2'd1, U_WAIT = 2'd2;
    localparam D_IDLE = 2'd0, D_CACHE = 2'd1, D_REQUEST = 2'd2, D_WAIT = 2'd3;
    localparam C_IDLE = 2'd0, C_ISSUE = 2'd1, C_WAIT = 2'd2, C_DONE = 2'd3;
    reg [1:0] iu_state;
    reg [1:0] d_state;
    reg [1:0] c_state;
    reg [2:0] i_outstanding;
    reg [31:0] iu_addr_r;
    reg [31:0] du_addr_r;
    reg [31:0] du_data_r;
    reg [3:0] du_strobe_r;
    reg du_write_r;
    reg [4:0] code_r;
    reg [31:0] control_addr;

    // 与原 bridge_1x2 一致：bfaf_xxxx 和 1faf_xxxx 都是 uncached 外设。
    // 本课程核心没有 MMU/DMW，除此之外的地址按原值缓存，不伪装完整 MAT 支持。
    wire i_bypass = !ENABLE_CACHE || (i_addr & 32'h1fff0000) == 32'h1faf0000;
    wire d_bypass = !ENABLE_CACHE || (d_addr & 32'h1fff0000) == 32'h1faf0000;
    wire normal_enable = resetn && c_state == C_IDLE && !cacop_valid;
    wire ic_addr_ok, ic_data_ok, dc_addr_ok, dc_data_ok;
    wire [31:0] ic_rdata, dc_rdata;
    wire iu_ready, iu_done, du_ready, du_done;
    wire [31:0] iu_rdata, du_rdata;
    wire ic_valid = normal_enable && iu_state == U_IDLE && !i_bypass && i_valid;
    wire dc_valid = normal_enable && d_state == D_IDLE && !d_bypass && d_valid;
    wire i_uncached_ready = iu_state == U_IDLE && i_outstanding == 0;

    assign i_addr_ok = normal_enable && iu_state == U_IDLE &&
                       (i_bypass ? i_uncached_ready : ic_addr_ok);
    assign i_data_ok = resetn && (ic_data_ok || (iu_state == U_WAIT && iu_done));
    assign i_rdata = iu_state == U_WAIT ? iu_rdata : ic_rdata;
    assign d_addr_ok = normal_enable && d_state == D_IDLE && (d_bypass || dc_addr_ok);
    assign d_data_ok = resetn && ((d_state == D_CACHE && dc_data_ok) ||
                                 (d_state == D_WAIT && du_done));
    assign d_rdata = d_state == D_CACHE ? dc_rdata : du_rdata;
    assign cacop_ready = resetn && c_state == C_IDLE && d_state == D_IDLE && iu_state == U_IDLE;
    assign cacop_done = resetn && c_state == C_DONE;

    wire target_d = code_r[2:0] == 3'd1;
    wire supported = code_r[4:3] != 2'd3 && (code_r[2:0] == 0 || target_d);
    wire [1:0] ctrl_op = code_r[4:3] == 0 ? 2'd0 : 2'd2;
    wire ctrl_index_mode = code_r[4:3] != 2'd2;
    wire ic_ctrl_ready, ic_ctrl_done, dc_ctrl_ready, dc_ctrl_done;
    wire ctrl_valid = resetn && ENABLE_CACHE && supported && c_state == C_ISSUE;
    wire control_ready = target_d ? dc_ctrl_ready : ic_ctrl_ready;
    wire control_done = target_d ? dc_ctrl_done : ic_ctrl_done;

    wire i_rd_req, i_rd_rdy, i_ret_valid, i_ret_last;
    wire [31:0] i_rd_addr, i_ret_data;
    wire d_rd_req, d_rd_rdy, d_ret_valid, d_ret_last;
    wire [31:0] d_rd_addr, d_ret_data;
    wire d_wr_req, d_wr_rdy;
    wire [31:0] d_wr_addr;
    wire [127:0] d_wr_data;

    cache_icache #(.INDEX_WIDTH(INDEX_WIDTH), .TAG_WIDTH(TAG_WIDTH), .WAY_NUM(WAY_NUM)) u_icache(
        .clk(clk), .resetn(resetn), .valid(ic_valid),
        .index(i_addr[INDEX_WIDTH+3:4]), .tag(i_addr[31:INDEX_WIDTH+4]), .offset(i_addr[3:0]),
        .addr_ok(ic_addr_ok), .data_ok(ic_data_ok), .rdata(ic_rdata),
        .rd_req(i_rd_req), .rd_type(), .rd_addr(i_rd_addr), .rd_rdy(i_rd_rdy),
        .ret_valid(i_ret_valid), .ret_last(i_ret_last), .ret_data(i_ret_data),
        .ctrl_valid(ctrl_valid && !target_d), .ctrl_op(ctrl_op),
        .ctrl_index(control_addr[INDEX_WIDTH+3:4]), .ctrl_tag(control_addr[31:INDEX_WIDTH+4]),
        .ctrl_index_mode(ctrl_index_mode), .ctrl_way(control_addr[1:0]),
        .ctrl_ready(ic_ctrl_ready), .ctrl_done(ic_ctrl_done),
        .access_count(i_access_count), .hit_count(i_hit_count), .miss_count(i_miss_count)
    );
    cache_dcache #(.INDEX_WIDTH(INDEX_WIDTH), .TAG_WIDTH(TAG_WIDTH), .WAY_NUM(WAY_NUM)) u_dcache(
        .clk(clk), .resetn(resetn), .valid(dc_valid), .op(d_write),
        .index(d_addr[INDEX_WIDTH+3:4]), .tag(d_addr[31:INDEX_WIDTH+4]), .offset(d_addr[3:0]),
        .wstrb(d_wstrb), .wdata(d_wdata), .addr_ok(dc_addr_ok), .data_ok(dc_data_ok), .rdata(dc_rdata),
        .rd_req(d_rd_req), .rd_type(), .rd_addr(d_rd_addr), .rd_rdy(d_rd_rdy),
        .ret_valid(d_ret_valid), .ret_last(d_ret_last), .ret_data(d_ret_data),
        .wr_req(d_wr_req), .wr_type(), .wr_addr(d_wr_addr), .wr_wstrb(),
        .wr_data(d_wr_data), .wr_rdy(d_wr_rdy),
        .ctrl_valid(ctrl_valid && target_d), .ctrl_op(ctrl_op),
        .ctrl_index(control_addr[INDEX_WIDTH+3:4]), .ctrl_tag(control_addr[31:INDEX_WIDTH+4]),
        .ctrl_index_mode(ctrl_index_mode), .ctrl_way(control_addr[1:0]),
        .ctrl_ready(dc_ctrl_ready), .ctrl_done(dc_ctrl_done),
        .access_count(d_access_count), .hit_count(d_hit_count), .miss_count(d_miss_count)
    );
    cache_mem_arbiter u_arbiter(
        .clk(clk), .resetn(resetn),
        .i_rd_req(i_rd_req), .i_rd_addr(i_rd_addr), .i_rd_rdy(i_rd_rdy),
        .i_ret_valid(i_ret_valid), .i_ret_last(i_ret_last), .i_ret_data(i_ret_data),
        .d_rd_req(d_rd_req), .d_rd_addr(d_rd_addr), .d_rd_rdy(d_rd_rdy),
        .d_ret_valid(d_ret_valid), .d_ret_last(d_ret_last), .d_ret_data(d_ret_data),
        .d_wr_req(d_wr_req), .d_wr_addr(d_wr_addr), .d_wr_data(d_wr_data), .d_wr_rdy(d_wr_rdy),
        .iu_req(iu_state == U_REQUEST), .iu_addr(iu_addr_r),
        .iu_ready(iu_ready), .iu_done(iu_done), .iu_rdata(iu_rdata),
        .du_req(d_state == D_REQUEST), .du_write(du_write_r), .du_wstrb(du_strobe_r),
        .du_addr(du_addr_r), .du_wdata(du_data_r),
        .du_ready(du_ready), .du_done(du_done), .du_rdata(du_rdata),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_ready(mem_ready),
        .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata)
    );

    always @(posedge clk) begin
        if (!resetn) begin
            iu_state <= U_IDLE;
            d_state <= D_IDLE;
            c_state <= C_IDLE;
            i_outstanding <= 0;
            iu_addr_r <= 0;
            du_addr_r <= 0;
            du_data_r <= 0;
            du_strobe_r <= 0;
            du_write_r <= 0;
            code_r <= 0;
            control_addr <= 0;
            uncached_count <= 0;
        end else begin
            case ({ic_valid && ic_addr_ok, ic_data_ok})
                2'b10: i_outstanding <= i_outstanding + 1'b1;
                2'b01: i_outstanding <= i_outstanding - 1'b1;
                default: ;
            endcase
            case (iu_state)
                U_IDLE: if (i_valid && i_addr_ok && i_bypass) begin
                    iu_addr_r <= i_addr;
                    iu_state <= U_REQUEST;
                end
                U_REQUEST: if (iu_ready) iu_state <= U_WAIT;
                U_WAIT: if (iu_done) iu_state <= U_IDLE;
                default: iu_state <= U_IDLE;
            endcase
            case (d_state)
                D_IDLE: if (d_valid && d_addr_ok) begin
                    if (d_bypass) begin
                        du_addr_r <= d_addr;
                        du_data_r <= d_wdata;
                        du_strobe_r <= d_wstrb;
                        du_write_r <= d_write;
                        d_state <= D_REQUEST;
                    end else d_state <= D_CACHE;
                end
                D_CACHE: if (dc_data_ok) d_state <= D_IDLE;
                D_REQUEST: if (du_ready) d_state <= D_WAIT;
                D_WAIT: if (du_done) d_state <= D_IDLE;
                default: d_state <= D_IDLE;
            endcase
            uncached_count <= uncached_count +
                (i_valid && i_addr_ok && i_bypass) + (d_valid && d_addr_ok && d_bypass);
            case (c_state)
                C_IDLE: if (cacop_valid && cacop_ready) begin
                    code_r <= cacop_code;
                    control_addr <= cacop_addr;
                    c_state <= C_ISSUE;
                end
                C_ISSUE: begin
                    if (!ENABLE_CACHE || !supported) c_state <= C_DONE;
                    else if (control_ready) c_state <= C_WAIT;
                end
                C_WAIT: if (control_done) c_state <= C_DONE;
                C_DONE: c_state <= C_IDLE;
                default: c_state <= C_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
