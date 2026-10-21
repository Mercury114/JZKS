`timescale 1ns / 1ps
`default_nettype none

// 将逐字握手转成原课程的一拍同步 SRAM：接受请求的上升沿只打一拍 en。
// RAM 在该沿采样；随后 rvalid=1，读数据或写完成在下一上升沿被主设备消费。
module cache_sram_bridge(
    input  wire        clk,
    input  wire        resetn,
    input  wire        mem_valid,
    input  wire        mem_write,
    input  wire [3:0]  mem_wstrb,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    output wire        mem_ready,
    output wire        mem_rvalid,
    output wire [31:0] mem_rdata,
    output wire        sram_en,
    output wire [3:0]  sram_we,
    output wire [31:0] sram_addr,
    output wire [31:0] sram_wdata,
    input  wire [31:0] sram_rdata
);
    reg pending;
    assign mem_ready = resetn && !pending;
    assign mem_rvalid = resetn && pending;
    assign mem_rdata = sram_rdata;
    assign sram_en = mem_valid && mem_ready;
    assign sram_we = mem_write ? mem_wstrb : 4'b0;
    assign sram_addr = mem_addr;
    assign sram_wdata = mem_wdata;
    always @(posedge clk) begin
        if (!resetn) pending <= 0;
        else pending <= sram_en;
    end
endmodule
`default_nettype wire
