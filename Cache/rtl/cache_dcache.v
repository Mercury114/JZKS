`timescale 1ns / 1ps

// 继承同伴 D-cache/rtl/dcache.v 的写回、写分配和四拍整行主存协议。
// 新增：1/2/4 路参数化、完整 LRU、索引/命中管理握手、复位屏蔽及统计。
// 普通请求在 addr_ok 握手时锁存，只执行一次，不再使用后续变化的 CPU 数据。
module cache_dcache #(
    parameter INDEX_WIDTH  = 8,
    parameter TAG_WIDTH    = 32 - INDEX_WIDTH - 4,
    parameter OFFSET_WIDTH = 4,
    parameter WAY_NUM      = 2,
    parameter SET_NUM      = 1 << INDEX_WIDTH
)(
    input  wire                 clk,
    input  wire                 resetn,

    input  wire                 valid,
    input  wire                 op,          // 0: 读，1: 写
    input  wire [INDEX_WIDTH-1:0] index,
    input  wire [TAG_WIDTH-1:0]   tag,
    input  wire [OFFSET_WIDTH-1:0] offset,
    input  wire [3:0]             wstrb,
    input  wire [31:0]            wdata,
    // 管理 op：0 无效化/索引初始化，1 写回但保留有效，2 写回后无效。
    // ctrl_ready握手后可立即撤valid；一直保持valid只产生一次完成脉冲。
    input  wire                    ctrl_valid,
    input  wire [1:0]              ctrl_op,
    input  wire [INDEX_WIDTH-1:0]  ctrl_index,
    input  wire [TAG_WIDTH-1:0]    ctrl_tag,
    input  wire                    ctrl_index_mode,
    input  wire [1:0]              ctrl_way,
    output wire                    ctrl_ready,
    output wire                    ctrl_done,
    output reg [31:0]              access_count,
    output reg [31:0]              hit_count,
    output reg [31:0]              miss_count,

    output wire                 addr_ok,
    output wire                 data_ok,
    output wire [31:0]           rdata,

    output wire                 rd_req,
    output wire [2:0]            rd_type,
    output wire [31:0]           rd_addr,
    input  wire                 rd_rdy,
    input  wire                 ret_valid,
    input  wire                 ret_last,
    input  wire [31:0]           ret_data,

    output wire                 wr_req,
    output wire [2:0]            wr_type,
    output wire [31:0]           wr_addr,
    output wire [3:0]            wr_wstrb,
    output wire [127:0]          wr_data,
    input  wire                 wr_rdy
);

    localparam ST_IDLE        = 4'd0;
    localparam ST_WB_REQ      = 4'd1;
    localparam ST_REFILL_REQ  = 4'd2;
    localparam ST_REFILL_WAIT = 4'd3;
    localparam ST_REFILL_APPLY= 4'd4;
    localparam ST_RESP        = 4'd5;
    localparam ST_CTRL_WB     = 4'd6;
    localparam ST_CTRL_DONE   = 4'd7;

    reg [3:0] state;
    reg [TAG_WIDTH-1:0] tag_mem   [0:WAY_NUM-1][0:SET_NUM-1];
    reg                  valid_mem [0:WAY_NUM-1][0:SET_NUM-1];
    reg                  dirty_mem [0:WAY_NUM-1][0:SET_NUM-1];
    reg [1:0]            age_mem   [0:WAY_NUM-1][0:SET_NUM-1];
    reg [31:0]           data_mem  [0:WAY_NUM-1][0:SET_NUM-1][0:3];

    reg [INDEX_WIDTH-1:0] req_index;
    reg [TAG_WIDTH-1:0]   req_tag;
    reg [OFFSET_WIDTH-1:0] req_offset;
    reg                    req_op;
    reg [3:0]              req_wstrb;
    reg [31:0]             req_wdata;
    reg [1:0]              req_way;
    reg [1:0]              refill_beat;
    reg [31:0]             response_data;
    reg                    ctrl_done_r;
    reg [1:0]              ctrl_op_r;
    reg                    ctrl_armed; // valid 撤销后才能接受下一条管理请求

    integer i;
    integer j;
    integer k;
    integer hit_way;
    integer victim_way;
    integer victim_age;
    integer hit_age;

    function [31:0] merge_bytes;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  byte_enable;
        begin
            merge_bytes = old_value;
            if (byte_enable[0]) merge_bytes[7:0]   = new_value[7:0];
            if (byte_enable[1]) merge_bytes[15:8]  = new_value[15:8];
            if (byte_enable[2]) merge_bytes[23:16] = new_value[23:16];
            if (byte_enable[3]) merge_bytes[31:24] = new_value[31:24];
        end
    endfunction

    // 管理优先。即使管理 valid 被保持，也不能误确认普通请求。
    assign ctrl_ready = resetn && state == ST_IDLE && ctrl_armed;
    assign addr_ok = resetn && state == ST_IDLE && !ctrl_valid;
    assign data_ok = resetn && state == ST_RESP;
    assign rdata   = response_data;
    assign ctrl_done = resetn && ctrl_done_r;

    assign rd_req  = resetn && state == ST_REFILL_REQ;
    assign rd_type = 3'b100; // 四字整行读
    assign rd_addr = {req_tag, req_index, 4'b0000};

    assign wr_req   = resetn && ((state == ST_WB_REQ) || (state == ST_CTRL_WB));
    assign wr_type  = 3'b100; // 四字整行写
    assign wr_addr  = {tag_mem[req_way][req_index], req_index, 4'b0000};
    assign wr_wstrb = 4'b1111;
    assign wr_data  = {data_mem[req_way][req_index][3],
                       data_mem[req_way][req_index][2],
                       data_mem[req_way][req_index][1],
                       data_mem[req_way][req_index][0]};

    always @(posedge clk) begin
        if (!resetn) begin
            state         <= ST_IDLE;
            req_index     <= {INDEX_WIDTH{1'b0}};
            req_tag       <= {TAG_WIDTH{1'b0}};
            req_offset     <= {OFFSET_WIDTH{1'b0}};
            req_op        <= 1'b0;
            req_wstrb     <= 4'b0;
            req_wdata     <= 32'b0;
            req_way       <= 2'b0;
            refill_beat   <= 2'b0;
            response_data <= 32'b0;
            ctrl_done_r   <= 1'b0;
            ctrl_op_r     <= 2'b0;
            ctrl_armed    <= 1'b1;
            access_count  <= 0;
            hit_count     <= 0;
            miss_count    <= 0;
            for (i = 0; i < WAY_NUM; i = i + 1) begin
                for (j = 0; j < SET_NUM; j = j + 1) begin
                    valid_mem[i][j] <= 1'b0;
                    dirty_mem[i][j] <= 1'b0;
                    age_mem[i][j]   <= i[1:0];
                    tag_mem[i][j]   <= {TAG_WIDTH{1'b0}};
                end
            end
        end else begin
            ctrl_done_r <= 1'b0;
            if (!ctrl_valid) ctrl_armed <= 1'b1;
            case (state)
                ST_IDLE: begin
                    if (ctrl_valid && ctrl_ready) begin
                        ctrl_armed <= 1'b0;
                        req_index <= ctrl_index;
                        req_tag   <= ctrl_tag;
                        ctrl_op_r <= ctrl_op;
                        hit_way = -1;
                        for (k = 0; k < WAY_NUM; k = k + 1)
                            if (valid_mem[k][ctrl_index] && tag_mem[k][ctrl_index] == ctrl_tag)
                                hit_way = k;
                        // 索引模式直接选路，1/2/4 路分别取 way 的低 0/1/2 位。
                        if (ctrl_index_mode) hit_way = ctrl_way & (WAY_NUM - 1);
                        if (hit_way >= 0) begin
                            req_way <= hit_way;
                            if ((ctrl_op == 2'd1 || ctrl_op == 2'd2) && valid_mem[hit_way][ctrl_index] && dirty_mem[hit_way][ctrl_index])
                                state <= ST_CTRL_WB;
                            else begin
                                if (ctrl_op == 2'd0 || ctrl_op == 2'd2) begin
                                    valid_mem[hit_way][ctrl_index] <= 1'b0;
                                    dirty_mem[hit_way][ctrl_index] <= 1'b0;
                                end
                                // 只有索引初始化清 tag；命中无效化保留 tag 无妨。
                                if (ctrl_op == 2'd0 && ctrl_index_mode)
                                    tag_mem[hit_way][ctrl_index] <= 0;
                                state <= ST_CTRL_DONE;
                            end
                        end else begin
                            state <= ST_CTRL_DONE;
                        end
                    end else if (valid && addr_ok) begin
                        access_count <= access_count + 1'b1;
                        hit_way = -1;
                        for (k = 0; k < WAY_NUM; k = k + 1) begin
                            if (valid_mem[k][index] && tag_mem[k][index] == tag)
                                hit_way = k;
                        end

                        if (hit_way >= 0) begin
                            hit_count <= hit_count + 1'b1;
                            req_index <= index;
                            req_tag   <= tag;
                            req_offset<= offset;
                            req_op    <= op;
                            req_wstrb <= wstrb;
                            req_wdata <= wdata;
                            req_way   <= hit_way;
                            if (op && |wstrb) begin
                                data_mem[hit_way][index][offset[3:2]] <=
                                    merge_bytes(data_mem[hit_way][index][offset[3:2]], wdata, wstrb);
                                dirty_mem[hit_way][index] <= 1'b1;
                            end else begin
                                response_data <= data_mem[hit_way][index][offset[3:2]];
                            end
                            // 真 LRU：0 为最近使用。全部路保持唯一排名，
                            // 无效路也参与重排，避免无效化后出现相同排名。
                            hit_age = age_mem[hit_way][index];
                            for (k = 0; k < WAY_NUM; k = k + 1) begin
                                if (k == hit_way)
                                    age_mem[k][index] <= 2'd0;
                                else if (age_mem[k][index] < hit_age)
                                    age_mem[k][index] <= age_mem[k][index] + 1'b1;
                            end
                            state <= ST_RESP;
                        end else begin
                            miss_count <= miss_count + 1'b1;
                            req_index <= index;
                            req_tag   <= tag;
                            req_offset<= offset;
                            req_op    <= op;
                            req_wstrb <= wstrb;
                            req_wdata <= wdata;
                            victim_way = -1;
                            for (k = 0; k < WAY_NUM; k = k + 1)
                                if (!valid_mem[k][index] && victim_way < 0) victim_way = k;
                            if (victim_way < 0) begin
                                victim_way = 0;
                                victim_age = age_mem[0][index];
                                for (k = 1; k < WAY_NUM; k = k + 1)
                                    if (age_mem[k][index] > victim_age) begin
                                        victim_way = k;
                                        victim_age = age_mem[k][index];
                                    end
                            end
                            req_way <= victim_way;
                            refill_beat <= 2'b0;
                            if (valid_mem[victim_way][index] && dirty_mem[victim_way][index])
                                state <= ST_WB_REQ;
                            else
                                state <= ST_REFILL_REQ;
                        end
                    end
                end

                ST_WB_REQ: begin
                    if (wr_rdy) begin
                        valid_mem[req_way][req_index] <= 1'b0;
                        dirty_mem[req_way][req_index] <= 1'b0;
                        state <= ST_REFILL_REQ;
                    end
                end

                ST_CTRL_WB: begin
                    if (wr_rdy) begin
                        dirty_mem[req_way][req_index] <= 1'b0;
                        if (ctrl_op_r == 2'd2)
                            valid_mem[req_way][req_index] <= 1'b0;
                        state <= ST_CTRL_DONE;
                    end
                end

                ST_CTRL_DONE: begin
                    ctrl_done_r <= 1'b1;
                    state <= ST_IDLE;
                end

                ST_REFILL_REQ: begin
                    if (rd_rdy) begin
                        // 允许主存接受读请求的同一拍就返回首字。
                        if (ret_valid) begin
                            data_mem[req_way][req_index][0] <= ret_data;
                            refill_beat <= 2'd1;
                            state <= ret_last ? ST_REFILL_APPLY : ST_REFILL_WAIT;
                        end else begin
                            refill_beat <= 2'b0;
                            state <= ST_REFILL_WAIT;
                        end
                    end
                end

                ST_REFILL_WAIT: begin
                    if (ret_valid) begin
                        data_mem[req_way][req_index][refill_beat] <= ret_data;
                        if (ret_last || refill_beat == 2'd3) begin
                            state <= ST_REFILL_APPLY;
                        end else begin
                            refill_beat <= refill_beat + 1'b1;
                        end
                    end
                end

                ST_REFILL_APPLY: begin
                    tag_mem[req_way][req_index]   <= req_tag;
                    valid_mem[req_way][req_index] <= 1'b1;
                    dirty_mem[req_way][req_index] <= req_op && |req_wstrb;
                    // 四拍已经入数组；写缺失只合并锁存请求所选的字节。
                    if (req_op) begin
                        data_mem[req_way][req_index][req_offset[3:2]] <=
                            merge_bytes(data_mem[req_way][req_index][req_offset[3:2]], req_wdata, req_wstrb);
                    end else begin
                        response_data <= data_mem[req_way][req_index][req_offset[3:2]];
                    end
                    hit_age = age_mem[req_way][req_index];
                    for (k = 0; k < WAY_NUM; k = k + 1) begin
                        if (k == req_way)
                            age_mem[k][req_index] <= 2'd0;
                        else if (age_mem[k][req_index] < hit_age)
                            age_mem[k][req_index] <= age_mem[k][req_index] + 1'b1;
                    end
                    state <= ST_RESP;
                end

                ST_RESP: begin
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
