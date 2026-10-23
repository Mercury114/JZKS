// 通用寄存器堆：32 个 32 位寄存器，两个组合读口和一个时钟上升沿写口。
// 读口不等时钟，编号变化后给出相应值；写口在上升沿才真正更新寄存器。
// r0 固定读出 0；其余寄存器没有清零复位，程序必须先写后读。
`timescale 1ns/1ps
`default_nettype none

module regfile(
    input  wire        clk,

    // 读口 1：编号 raddr1 → 内容 rdata1
    input  wire [ 4:0] raddr1,
    output wire [31:0] rdata1,

    // 读口 2：独立于读口 1，可同时读取另一个寄存器
    input  wire [ 4:0] raddr2,
    output wire [31:0] rdata2,

    // 写口：we=1 且编号不是 0 时，写入 wdata
    input  wire        we,
    input  wire [ 4:0] waddr,
    input  wire [31:0] wdata
);

reg [31:0] rf[31:0];

// 忽略写 r0 的请求；不对整个数组加复位，以保留当前寄存器堆实现。
always @(posedge clk) begin
    if (we && waddr != 5'd0) begin
        rf[waddr] <= wdata;
    end
end

// 两个读口都单独强制 r0 为零，不依赖 rf[0] 的初始值。
// 本模块没有写口到读口的显式旁路；它不能代替流水线的数据相关处理。
assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : rf[raddr1];
assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : rf[raddr2];

endmodule

`default_nettype wire
