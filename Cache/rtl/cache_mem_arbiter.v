`timescale 1ns / 1ps
`default_nettype none

// 五个来源共用一个逐字主存端口；每次只保留一笔主存事务。
// I/D 回填、D 写回各占完整一行，两个 uncached 通道各只访问一个字。
// 主存的 ready 表示接受请求，rvalid 表示该字读/写真正完成，两者不能混用。
module cache_mem_arbiter(
    input  wire         clk,
    input  wire         resetn,
    input  wire         i_rd_req,
    input  wire [31:0]  i_rd_addr,
    output wire         i_rd_rdy,
    output wire         i_ret_valid,
    output wire         i_ret_last,
    output wire [31:0]  i_ret_data,
    input  wire         d_rd_req,
    input  wire [31:0]  d_rd_addr,
    output wire         d_rd_rdy,
    output wire         d_ret_valid,
    output wire         d_ret_last,
    output wire [31:0]  d_ret_data,
    input  wire         d_wr_req,
    input  wire [31:0]  d_wr_addr,
    input  wire [127:0] d_wr_data,
    output wire         d_wr_rdy,
    input  wire         iu_req,
    input  wire [31:0]  iu_addr,
    output wire         iu_ready,
    output wire         iu_done,
    output wire [31:0]  iu_rdata,
    input  wire         du_req,
    input  wire         du_write,
    input  wire [3:0]   du_wstrb,
    input  wire [31:0]  du_addr,
    input  wire [31:0]  du_wdata,
    output wire         du_ready,
    output wire         du_done,
    output wire [31:0]  du_rdata,
    output wire         mem_valid,
    output wire         mem_write,
    output wire [3:0]   mem_wstrb,
    output wire [31:0]  mem_addr,
    output wire [31:0]  mem_wdata,
    input  wire         mem_ready,
    input  wire         mem_rvalid,
    input  wire [31:0]  mem_rdata
);
    localparam IDLE = 2'd0, SEND = 2'd1, WAIT_REPLY = 2'd2, FINISH = 2'd3;
    reg [1:0] state;
    reg [2:0] owner;
    reg [2:0] next_owner;
    reg [31:0] base_addr;
    reg [127:0] line_data;
    reg [1:0] beat;
    reg [1:0] last_beat;
    reg write_r;
    reg [3:0] strobe_r;
    wire [4:0] requests = {du_req, iu_req, d_wr_req, d_rd_req, i_rd_req};
    integer selected;
    integer candidate;
    integer n;

    // 轮转起点在每次选中事务后前移；持续存在的请求不会被固定优先级饿死。
    always @(*) begin
        selected = -1;
        candidate = 0;
        for (n = 0; n < 5; n = n + 1) begin
            candidate = next_owner + n;
            if (candidate >= 5) candidate = candidate - 5;
            if (selected < 0 && requests[candidate]) selected = candidate;
        end
    end

    assign i_rd_rdy = resetn && state == IDLE && selected == 0;
    assign d_rd_rdy = resetn && state == IDLE && selected == 1;
    // 写回的 wr_rdy 是整行四个字均已收到完成响应，而不是仅仅进入仲裁器。
    assign d_wr_rdy = resetn && state == FINISH && owner == 2;
    assign iu_ready = resetn && state == IDLE && selected == 3;
    assign du_ready = resetn && state == IDLE && selected == 4;
    assign mem_valid = resetn && state == SEND;
    assign mem_write = write_r;
    assign mem_wstrb = write_r ? strobe_r : 4'b0;
    assign mem_addr = base_addr + {28'b0, beat, 2'b0};
    assign mem_wdata = line_data[beat * 32 +: 32];

    // 同时支持零等待响应和先接受、若干周期后响应。没有接受就不能消费响应。
    wire word_done = resetn && mem_rvalid &&
                     (state == WAIT_REPLY || (state == SEND && mem_ready));
    assign i_ret_valid = word_done && owner == 0;
    assign d_ret_valid = word_done && owner == 1;
    assign i_ret_last = i_ret_valid && beat == last_beat;
    assign d_ret_last = d_ret_valid && beat == last_beat;
    assign i_ret_data = mem_rdata;
    assign d_ret_data = mem_rdata;
    assign iu_done = word_done && owner == 3;
    assign du_done = word_done && owner == 4;
    assign iu_rdata = mem_rdata;
    assign du_rdata = mem_rdata;

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            owner <= 0;
            next_owner <= 0;
            base_addr <= 0;
            line_data <= 0;
            beat <= 0;
            last_beat <= 0;
            write_r <= 0;
            strobe_r <= 0;
        end else begin
            case (state)
                IDLE: if (selected >= 0) begin
                    owner <= selected;
                    next_owner <= selected == 4 ? 0 : selected + 1;
                    beat <= 0;
                    last_beat <= selected < 3 ? 2'd3 : 2'd0;
                    write_r <= selected == 2 || (selected == 4 && du_write);
                    strobe_r <= selected == 2 ? 4'b1111 : du_wstrb;
                    case (selected)
                        0: base_addr <= {i_rd_addr[31:4], 4'b0};
                        1: base_addr <= {d_rd_addr[31:4], 4'b0};
                        2: base_addr <= {d_wr_addr[31:4], 4'b0};
                        // 外设按完整字节地址译码；旁路不能擅自创造低位地址别名。
                        // 普通 RAM 会在自己的 addra[...:2] 处选择字。
                        3: base_addr <= iu_addr;
                        4: base_addr <= du_addr;
                    endcase
                    line_data <= selected == 2 ? d_wr_data : {96'b0, du_wdata};
                    state <= SEND;
                end
                SEND, WAIT_REPLY: begin
                    if (word_done) begin
                        if (beat == last_beat) state <= FINISH;
                        else begin
                            beat <= beat + 1'b1;
                            state <= SEND;
                        end
                    end else if (state == SEND && mem_ready) begin
                        state <= WAIT_REPLY;
                    end
                end
                FINISH: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
