`timescale 1ns / 1ps
`default_nettype none

// AXI4 top for the integrated five-stage CPU, I-Cache and D-Cache.
// The original SRAM board top remains available for the course FPGA build.
module mycpu_top_axi #(
    parameter INDEX_WIDTH = 8,
    parameter WAY_NUM = 2,
    parameter ENABLE_CACHE = 1,
    parameter BOARD_ADDR_MAP = 0,
    parameter AXI_ID_WIDTH = 4
)(
    input  wire                    clk,
    input  wire                    resetn,
    input  wire [7:0]              hw_int_in,
    output wire [31:0]             debug_wb_pc,
    output wire [3:0]              debug_wb_rf_we,
    output wire [4:0]              debug_wb_rf_wnum,
    output wire [31:0]             debug_wb_rf_wdata,
    output wire                    axi_error,

    output wire [AXI_ID_WIDTH-1:0] m_axi_awid,
    output wire [31:0]             m_axi_awaddr,
    output wire [7:0]              m_axi_awlen,
    output wire [2:0]              m_axi_awsize,
    output wire [1:0]              m_axi_awburst,
    output wire                    m_axi_awlock,
    output wire [3:0]              m_axi_awcache,
    output wire [2:0]              m_axi_awprot,
    output wire                    m_axi_awvalid,
    input  wire                    m_axi_awready,
    output wire [31:0]             m_axi_wdata,
    output wire [3:0]              m_axi_wstrb,
    output wire                    m_axi_wlast,
    output wire                    m_axi_wvalid,
    input  wire                    m_axi_wready,
    input  wire [AXI_ID_WIDTH-1:0] m_axi_bid,
    input  wire [1:0]              m_axi_bresp,
    input  wire                    m_axi_bvalid,
    output wire                    m_axi_bready,
    output wire [AXI_ID_WIDTH-1:0] m_axi_arid,
    output wire [31:0]             m_axi_araddr,
    output wire [7:0]              m_axi_arlen,
    output wire [2:0]              m_axi_arsize,
    output wire [1:0]              m_axi_arburst,
    output wire                    m_axi_arlock,
    output wire [3:0]              m_axi_arcache,
    output wire [2:0]              m_axi_arprot,
    output wire                    m_axi_arvalid,
    input  wire                    m_axi_arready,
    input  wire [AXI_ID_WIDTH-1:0] m_axi_rid,
    input  wire [31:0]             m_axi_rdata,
    input  wire [1:0]              m_axi_rresp,
    input  wire                    m_axi_rlast,
    input  wire                    m_axi_rvalid,
    output wire                    m_axi_rready
);
    wire mem_valid, mem_write, mem_ready, mem_rvalid;
    wire [3:0] mem_wstrb;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;

    cache_system #(
        .INDEX_WIDTH(INDEX_WIDTH), .WAY_NUM(WAY_NUM),
        .ENABLE_CACHE(ENABLE_CACHE), .BOARD_ADDR_MAP(BOARD_ADDR_MAP)
    ) u_system (
        .clk(clk), .resetn(resetn), .hw_int_in(hw_int_in),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_ready(mem_ready),
        .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .debug_wb_pc(debug_wb_pc), .debug_wb_rf_we(debug_wb_rf_we),
        .debug_wb_rf_wnum(debug_wb_rf_wnum), .debug_wb_rf_wdata(debug_wb_rf_wdata),
        .i_access_count(), .i_hit_count(), .i_miss_count(),
        .d_access_count(), .d_hit_count(), .d_miss_count(), .uncached_count()
    );

    cache_axi_bridge #(.AXI_ID_WIDTH(AXI_ID_WIDTH)) u_axi (
        .clk(clk), .resetn(resetn),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_ready(mem_ready),
        .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata), .axi_error(axi_error),
        .m_axi_awid(m_axi_awid), .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awlock(m_axi_awlock),
        .m_axi_awcache(m_axi_awcache), .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready), .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready), .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock(m_axi_arlock), .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot(m_axi_arprot), .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready), .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );
endmodule
`default_nettype wire
