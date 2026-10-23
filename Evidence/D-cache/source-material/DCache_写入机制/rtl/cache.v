`timescale 1ns / 1ps

// Four-way set-associative, write-back/write-allocate data cache.
// The external protocol is the LoongArch teaching-cache protocol used by
// module_verify/cache_verify/cache_top.v.
module cache #(
    parameter INDEX_WIDTH  = 8,
    parameter TAG_WIDTH    = 20,
    parameter OFFSET_WIDTH = 4,
    parameter WAY_NUM      = 4,
    parameter SET_NUM      = 256
)(
    input  wire                 clk,
    input  wire                 resetn,

    input  wire                 valid,
    input  wire                 op,          // 0: read, 1: write
    input  wire [INDEX_WIDTH-1:0] index,
    input  wire [TAG_WIDTH-1:0]   tag,
    input  wire [OFFSET_WIDTH-1:0] offset,
    input  wire [3:0]             wstrb,
    input  wire [31:0]            wdata,

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

    // A request is accepted only while no previous request is being serviced.
    // The requester is expected to hold valid/address/data until addr_ok.
    assign addr_ok = state == ST_IDLE;
    assign data_ok = state == ST_RESP;
    assign rdata   = response_data;

    assign rd_req  = state == ST_REFILL_REQ;
    assign rd_type = 3'b100; // cache-line read
    assign rd_addr = {req_tag, req_index, 4'b0000};

    assign wr_req   = state == ST_WB_REQ;
    assign wr_type  = 3'b100; // cache-line write
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
            for (i = 0; i < WAY_NUM; i = i + 1) begin
                for (j = 0; j < SET_NUM; j = j + 1) begin
                    valid_mem[i][j] <= 1'b0;
                    dirty_mem[i][j] <= 1'b0;
                    age_mem[i][j]   <= i[1:0];
                    tag_mem[i][j]   <= {TAG_WIDTH{1'b0}};
                end
            end
        end else begin
            case (state)
                ST_IDLE: begin
                    if (valid) begin
                        hit_way = -1;
                        for (k = 0; k < WAY_NUM; k = k + 1) begin
                            if (valid_mem[k][index] && tag_mem[k][index] == tag)
                                hit_way = k;
                        end

                        if (hit_way >= 0) begin
                            req_index <= index;
                            req_tag   <= tag;
                            req_offset<= offset;
                            req_op    <= op;
                            req_wstrb <= wstrb;
                            req_wdata <= wdata;
                            req_way   <= hit_way;
                            if (op) begin
                                data_mem[hit_way][index][offset[3:2]] <=
                                    merge_bytes(data_mem[hit_way][index][offset[3:2]], wdata, wstrb);
                                dirty_mem[hit_way][index] <= 1'b1;
                            end else begin
                                response_data <= data_mem[hit_way][index][offset[3:2]];
                            end
                            // True LRU rank update: age 0 is most recently used.
                            hit_age = age_mem[hit_way][index];
                            for (k = 0; k < WAY_NUM; k = k + 1) begin
                                if (k == hit_way)
                                    age_mem[k][index] <= 2'd0;
                                else if (valid_mem[k][index] && age_mem[k][index] < hit_age)
                                    age_mem[k][index] <= age_mem[k][index] + 1'b1;
                            end
                            state <= ST_RESP;
                        end else begin
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

                ST_REFILL_REQ: begin
                    if (rd_rdy) begin
                        refill_beat <= 2'b0;
                        state <= ST_REFILL_WAIT;
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
                    dirty_mem[req_way][req_index] <= req_op;
                    // The refill beat is now present in the array. A write miss
                    // merges only the requested byte lanes (write-allocate).
                    if (req_op) begin
                        data_mem[req_way][req_index][req_offset[3:2]] <=
                            merge_bytes(data_mem[req_way][req_index][req_offset[3:2]], req_wdata, req_wstrb);
                    end else begin
                        response_data <= data_mem[req_way][req_index][req_offset[3:2]];
                    end
                    for (k = 0; k < WAY_NUM; k = k + 1) begin
                        if (k == req_way)
                            age_mem[k][req_index] <= 2'd0;
                        else if (valid_mem[k][req_index] && age_mem[k][req_index] < 2'd3)
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
