`timescale 1ns / 1ps
`default_nettype none

// Converts the cache system's serialized word transactions to AXI4 single-beat
// transactions. Completion is reported only on the R or B handshake, never on
// address acceptance. The existing cache arbiter assembles 16-byte lines from
// four word transactions, so this bridge intentionally has one outstanding
// transaction and uses a fixed AXI ID.
module cache_axi_bridge #(
    parameter AXI_ID_WIDTH = 4
)(
    input  wire                    clk,
    input  wire                    resetn,
    input  wire                    mem_valid,
    input  wire                    mem_write,
    input  wire [3:0]              mem_wstrb,
    input  wire [31:0]             mem_addr,
    input  wire [31:0]             mem_wdata,
    output wire                    mem_ready,
    output wire                    mem_rvalid,
    output wire [31:0]             mem_rdata,
    output reg                     axi_error,

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
    localparam [2:0] IDLE = 3'd0, READ_ADDR = 3'd1, READ_DATA = 3'd2,
                     WRITE_SEND = 3'd3, WRITE_RESP = 3'd4;
    reg [2:0] state;
    reg [31:0] addr_r, wdata_r;
    reg [3:0] wstrb_r;
    reg aw_sent, w_sent;

    // Reads fetch an aligned word because the CPU extracts byte/halfword lanes.
    // Writes retain the byte address for MMIO register decoding. The CPU
    // supplies matching WSTRB lanes for byte and halfword stores.
    wire [31:0] word_addr = {addr_r[31:2], 2'b00};
    wire [2:0] write_size = (wstrb_r == 4'b0001 || wstrb_r == 4'b0010 ||
                             wstrb_r == 4'b0100 || wstrb_r == 4'b1000) ? 3'd0 :
                            (wstrb_r == 4'b0011 || wstrb_r == 4'b1100) ? 3'd1 : 3'd2;
    wire aw_fire = m_axi_awvalid && m_axi_awready;
    wire w_fire  = m_axi_wvalid && m_axi_wready;
    wire r_fire  = m_axi_rvalid && m_axi_rready;
    wire b_fire  = m_axi_bvalid && m_axi_bready;

    assign mem_ready  = resetn && state == IDLE;
    assign mem_rvalid = r_fire || b_fire;
    assign mem_rdata  = m_axi_rdata;

    assign m_axi_awid    = {AXI_ID_WIDTH{1'b0}};
    assign m_axi_awaddr  = addr_r;
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = write_size;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0000;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awvalid = resetn && state == WRITE_SEND && !aw_sent;
    assign m_axi_wdata   = wdata_r;
    assign m_axi_wstrb   = wstrb_r;
    assign m_axi_wlast   = 1'b1;
    assign m_axi_wvalid  = resetn && state == WRITE_SEND && !w_sent;
    assign m_axi_bready  = resetn && state == WRITE_RESP;

    assign m_axi_arid    = {AXI_ID_WIDTH{1'b0}};
    assign m_axi_araddr  = word_addr;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = 3'd2;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0000;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arvalid = resetn && state == READ_ADDR;
    assign m_axi_rready  = resetn && state == READ_DATA;

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            addr_r <= 0;
            wdata_r <= 0;
            wstrb_r <= 0;
            aw_sent <= 0;
            w_sent <= 0;
            axi_error <= 0;
        end else begin
            case (state)
                IDLE: if (mem_valid) begin
                    addr_r <= mem_addr;
                    wdata_r <= mem_wdata;
                    wstrb_r <= mem_wstrb;
                    aw_sent <= 0;
                    w_sent <= 0;
                    state <= mem_write ? WRITE_SEND : READ_ADDR;
                end
                READ_ADDR: if (m_axi_arready) state <= READ_DATA;
                READ_DATA: if (r_fire) begin
                    if (m_axi_rresp != 2'b00 ||
                        m_axi_rid != {AXI_ID_WIDTH{1'b0}} || !m_axi_rlast)
                        axi_error <= 1'b1;
                    state <= IDLE;
                end
                WRITE_SEND: begin
                    if (aw_fire) aw_sent <= 1'b1;
                    if (w_fire) w_sent <= 1'b1;
                    if ((aw_sent || aw_fire) && (w_sent || w_fire))
                        state <= WRITE_RESP;
                end
                WRITE_RESP: if (b_fire) begin
                    if (m_axi_bresp != 2'b00 ||
                        m_axi_bid != {AXI_ID_WIDTH{1'b0}})
                        axi_error <= 1'b1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
