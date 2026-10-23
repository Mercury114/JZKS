`timescale 1ns / 1ps
`default_nettype none

// 一拍同步、按字节写的推断式块RAM。独立于旧工程的厂商IP与绝对路径。
// 初始化只描述上电内容，不给整个数组增加运行时复位，便于综合推断BRAM。
module cache_board_ram #(
    parameter ADDR_WIDTH = 16,
    parameter INIT_FILE = ""
)(
    input  wire                  clk,
    input  wire                  en,
    input  wire [3:0]            we,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [31:0]           wdata,
    output reg  [31:0]           rdata
);
    (* ram_style = "block" *) reg [31:0] mem [0:(1 << ADDR_WIDTH)-1];
    integer i;
    integer lane;
    initial begin
        for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1) mem[i] = 0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end
    always @(posedge clk) begin
        if (en) begin
            rdata <= mem[addr];
            for (lane = 0; lane < 4; lane = lane + 1)
                if (we[lane]) mem[addr][lane * 8 +: 8] <= wdata[lane * 8 +: 8];
        end
    end
endmodule
`default_nettype wire
