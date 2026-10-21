`timescale 1ns / 1ps

// 只读指令缓存：16 字节一行，支持 1 / 2 / 4 路组相联。
// CPU 在 valid && addr_ok 的上升沿提交请求；随后一级查询。
// 命中在下一上升沿产生 data_ok，且该沿可同时接收下一请求。
// 未命中从查询当拍开始关闭 addr_ok，因此不会多接收、覆盖后续请求。
// 数据数组采用寄存器描述；此实现不假定 FPGA BRAM 的异步读能力。
module cache_icache #(
    parameter INDEX_WIDTH = 8,
    parameter TAG_WIDTH = 32 - INDEX_WIDTH - 4,
    parameter WAY_NUM = 2,
    parameter SET_NUM = 1 << INDEX_WIDTH
) (
    input wire clk,
    input wire resetn,
    input wire valid,
    input wire [INDEX_WIDTH-1:0] index,
    input wire [TAG_WIDTH-1:0] tag,
    input wire [3:0] offset,
    output wire addr_ok,
    output reg data_ok,
    output reg [31:0] rdata,

    output wire rd_req,
    output wire [2:0] rd_type,
    output wire [31:0] rd_addr,
    input wire rd_rdy,
    input wire ret_valid,
    input wire ret_last,
    input wire [31:0] ret_data,

    input wire ctrl_valid,
    input wire [1:0] ctrl_op,
    input wire [INDEX_WIDTH-1:0] ctrl_index,
    input wire [TAG_WIDTH-1:0] ctrl_tag,
    input wire ctrl_index_mode,
    input wire [1:0] ctrl_way,
    output wire ctrl_ready,
    output reg ctrl_done,
    output reg [31:0] access_count,
    output reg [31:0] hit_count,
    output reg [31:0] miss_count
);
    localparam IDLE = 2'd0;
    localparam LOOKUP = 2'd1;
    localparam MISS_REQ = 2'd2;
    localparam REFILL = 2'd3;

    reg [1:0] state;
    reg line_valid [0:SET_NUM-1][0:WAY_NUM-1];
    reg [TAG_WIDTH-1:0] line_tag [0:SET_NUM-1][0:WAY_NUM-1];
    reg [31:0] line_data [0:SET_NUM-1][0:WAY_NUM-1][0:3];
    // rank=0 是最近访问，rank 最大的是最久未访问；不是轮转或近似 LRU。
    reg [1:0] lru_rank [0:SET_NUM-1][0:WAY_NUM-1];
    reg [INDEX_WIDTH-1:0] req_index;
    reg [TAG_WIDTH-1:0] req_tag;
    reg [1:0] req_word;
    reg [1:0] refill_word;
    reg [1:0] victim_way;
    reg victim_valid;
    reg [1:0] victim_rank;

    reg lookup_hit;
    reg [1:0] hit_way;
    reg [1:0] replace_way;
    reg invalid_found;
    reg [1:0] oldest_rank;
    reg ctrl_match;
    reg [1:0] ctrl_match_way;
    integer lookup_w;
    integer ctrl_w;
    integer set_i;
    integer way_i;

    // 组合查询和 invalid-first 选择；低编号无效路优先。
    always @(*) begin
        lookup_hit = 1'b0;
        hit_way = 2'd0;
        replace_way = 2'd0;
        invalid_found = 1'b0;
        oldest_rank = 2'd0;
        for (lookup_w = 0; lookup_w < WAY_NUM; lookup_w = lookup_w + 1) begin
            if (line_valid[req_index][lookup_w]
                && line_tag[req_index][lookup_w] == req_tag) begin
                lookup_hit = 1'b1;
                hit_way = lookup_w;
            end
            if (!line_valid[req_index][lookup_w] && !invalid_found) begin
                invalid_found = 1'b1;
                replace_way = lookup_w;
            end
            if (!invalid_found && lru_rank[req_index][lookup_w] >= oldest_rank) begin
                oldest_rank = lru_rank[req_index][lookup_w];
                replace_way = lookup_w;
            end
        end
    end

    // index 模式屏蔽不存在的 way 位，tag 模式只操作命中的行。
    always @(*) begin
        ctrl_match = ctrl_index_mode;
        ctrl_match_way = ctrl_way & (WAY_NUM - 1);
        for (ctrl_w = 0; ctrl_w < WAY_NUM; ctrl_w = ctrl_w + 1) begin
            if (!ctrl_index_mode && line_valid[ctrl_index][ctrl_w]
                && line_tag[ctrl_index][ctrl_w] == ctrl_tag) begin
                ctrl_match = 1'b1;
                ctrl_match_way = ctrl_w;
            end
        end
    end

    // 管理请求有优先权，但必须先排空普通请求和最后一拍响应。
    assign ctrl_ready = resetn && state == IDLE && !data_ok;
    assign addr_ok = resetn && !ctrl_valid
                     && (state == IDLE || (state == LOOKUP && lookup_hit));
    assign rd_req = resetn && state == MISS_REQ;
    assign rd_type = 3'b100;
    assign rd_addr = {req_tag, req_index, 4'b0000};

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= IDLE;
            data_ok <= 1'b0;
            rdata <= 32'd0;
            ctrl_done <= 1'b0;
            access_count <= 32'd0;
            hit_count <= 32'd0;
            miss_count <= 32'd0;
            req_index <= {INDEX_WIDTH{1'b0}};
            req_tag <= {TAG_WIDTH{1'b0}};
            req_word <= 2'd0;
            refill_word <= 2'd0;
            victim_way <= 2'd0;
            victim_valid <= 1'b0;
            victim_rank <= 2'd0;
            // 仅有效位、tag 和 LRU 需要初始化，数据在有效前绝不会读取。
            for (set_i = 0; set_i < SET_NUM; set_i = set_i + 1) begin
                for (way_i = 0; way_i < WAY_NUM; way_i = way_i + 1) begin
                    line_valid[set_i][way_i] <= 1'b0;
                    line_tag[set_i][way_i] <= {TAG_WIDTH{1'b0}};
                    lru_rank[set_i][way_i] <= 2'd0;
                end
            end
        end else begin
            data_ok <= 1'b0;
            ctrl_done <= 1'b0;

            if (valid && addr_ok) begin
                req_index <= index;
                req_tag <= tag;
                req_word <= offset[3:2];
                access_count <= access_count + 1'b1;
            end

            case (state)
                IDLE: begin
                    if (ctrl_valid && ctrl_ready) begin
                        // I-Cache 没有脏数据，op=1 为完成但不修改的写回空操作。
                        if (ctrl_match && (ctrl_op == 2'd0 || ctrl_op == 2'd2)) begin
                            line_valid[ctrl_index][ctrl_match_way] <= 1'b0;
                            line_tag[ctrl_index][ctrl_match_way] <= {TAG_WIDTH{1'b0}};
                            lru_rank[ctrl_index][ctrl_match_way] <= 2'd0;
                            // 删除一个有效排名后压紧其余排名，避免反复管理导致溢出。
                            for (way_i = 0; way_i < WAY_NUM; way_i = way_i + 1) begin
                                if (line_valid[ctrl_index][ctrl_match_way]
                                    && line_valid[ctrl_index][way_i]
                                    && lru_rank[ctrl_index][way_i]
                                       > lru_rank[ctrl_index][ctrl_match_way]) begin
                                    lru_rank[ctrl_index][way_i] <= lru_rank[ctrl_index][way_i] - 1'b1;
                                end
                            end
                        end
                        ctrl_done <= 1'b1;
                    end else if (valid && addr_ok) begin
                        state <= LOOKUP;
                    end
                end
                LOOKUP: begin
                    if (lookup_hit) begin
                        rdata <= line_data[req_index][hit_way][req_word];
                        data_ok <= 1'b1;
                        hit_count <= hit_count + 1'b1;
                        for (way_i = 0; way_i < WAY_NUM; way_i = way_i + 1) begin
                            if (line_valid[req_index][way_i]
                                && lru_rank[req_index][way_i] < lru_rank[req_index][hit_way]) begin
                                lru_rank[req_index][way_i] <= lru_rank[req_index][way_i] + 1'b1;
                            end
                        end
                        lru_rank[req_index][hit_way] <= 2'd0;
                        state <= (valid && addr_ok) ? LOOKUP : IDLE;
                    end else begin
                        victim_way <= replace_way;
                        victim_valid <= line_valid[req_index][replace_way];
                        victim_rank <= lru_rank[req_index][replace_way];
                        refill_word <= 2'd0;
                        miss_count <= miss_count + 1'b1;
                        state <= MISS_REQ;
                    end
                end
                MISS_REQ: begin
                    if (rd_rdy) begin
                        // 也允许主存在请求握手同拍返回第一字。
                        if (ret_valid) begin
                            line_data[req_index][victim_way][0] <= ret_data;
                            refill_word <= 2'd1;
                        end
                        state <= REFILL;
                    end
                end
                REFILL: begin
                    // ret_valid=0 时计数和数据均保持，允许任意空拍。
                    if (ret_valid) begin
                        line_data[req_index][victim_way][refill_word] <= ret_data;
                        if (refill_word == 2'd3 && ret_last) begin
                            line_valid[req_index][victim_way] <= 1'b1;
                            line_tag[req_index][victim_way] <= req_tag;
                            for (way_i = 0; way_i < WAY_NUM; way_i = way_i + 1) begin
                                if (line_valid[req_index][way_i] && way_i != victim_way
                                    && (!victim_valid || lru_rank[req_index][way_i] < victim_rank)) begin
                                    lru_rank[req_index][way_i] <= lru_rank[req_index][way_i] + 1'b1;
                                end
                            end
                            lru_rank[req_index][victim_way] <= 2'd0;
                            // 最后一字尚未写入数组时直接旁路返回。
                            rdata <= req_word == 2'd3 ? ret_data
                                     : line_data[req_index][victim_way][req_word];
                            data_ok <= 1'b1;
                            state <= IDLE;
                        end else begin
                            refill_word <= refill_word + 1'b1;
                        end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
