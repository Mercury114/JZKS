`timescale 1ns/1ps
`default_nettype none

module cache_axi_bridge_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;
    reg mem_valid = 0, mem_write = 0;
    reg [3:0] mem_wstrb = 0;
    reg [31:0] mem_addr = 0, mem_wdata = 0;
    wire mem_ready, mem_rvalid, axi_error;
    wire [31:0] mem_rdata;
    wire [3:0] awid, arid;
    wire [31:0] awaddr, araddr, wdata;
    wire [7:0] awlen, arlen;
    wire [2:0] awsize, arsize, awprot, arprot;
    wire [1:0] awburst, arburst;
    wire awlock, arlock, awvalid, wlast, wvalid, bready, arvalid, rready;
    wire [3:0] awcache, arcache, wstrb;
    reg awready = 0, wready = 0, bvalid = 0, arready = 0, rvalid = 0;
    reg [3:0] bid = 0, rid = 0;
    reg [1:0] bresp = 0, rresp = 0;
    reg [31:0] rdata = 0;
    reg rlast = 1;
    integer completions = 0;

    cache_axi_bridge dut(
        .clk(clk), .resetn(resetn), .mem_valid(mem_valid), .mem_write(mem_write),
        .mem_wstrb(mem_wstrb), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(mem_ready), .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata), .axi_error(axi_error),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen),
        .m_axi_awsize(awsize), .m_axi_awburst(awburst), .m_axi_awlock(awlock),
        .m_axi_awcache(awcache), .m_axi_awprot(awprot), .m_axi_awvalid(awvalid),
        .m_axi_awready(awready), .m_axi_wdata(wdata), .m_axi_wstrb(wstrb),
        .m_axi_wlast(wlast), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen),
        .m_axi_arsize(arsize), .m_axi_arburst(arburst), .m_axi_arlock(arlock),
        .m_axi_arcache(arcache), .m_axi_arprot(arprot), .m_axi_arvalid(arvalid),
        .m_axi_arready(arready), .m_axi_rid(rid), .m_axi_rdata(rdata),
        .m_axi_rresp(rresp), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    always @(posedge clk) if (mem_rvalid) completions <= completions + 1;
    initial begin #20000; $fatal(1, "AXI bridge timeout"); end
    initial begin
        repeat (3) @(negedge clk);
        resetn = 1;

        // Read byte lane 3 by fetching its containing aligned word. AR must
        // stay valid with stable payload under backpressure; R completes later.
        @(negedge clk);
        mem_valid = 1; mem_write = 0; mem_addr = 32'h00000103;
        if (!mem_ready) $fatal(1, "read request not accepted");
        @(negedge clk); mem_valid = 0;
        repeat (3) begin
            if (!arvalid || araddr !== 32'h00000100 || arlen !== 0 ||
                arsize !== 3'd2 || arburst !== 2'b01 || mem_rvalid)
                $fatal(1, "AR backpressure/payload failure");
            @(negedge clk);
        end
        arready = 1;
        @(negedge clk); arready = 0;
        if (arvalid || !rready || mem_rvalid) $fatal(1, "read accepted before R");
        repeat (2) @(negedge clk);
        rdata = 32'hA1B2C3D4; rvalid = 1;
        #1;
        if (!mem_rvalid || mem_rdata !== rdata) $fatal(1, "R completion missing");
        @(negedge clk); rvalid = 0;
        if (completions != 1 || !mem_ready || axi_error) $fatal(1, "read completion count");

        // AW and W are independent: AW accepted first, W two cycles later.
        mem_valid = 1; mem_write = 1; mem_addr = 32'h00000102;
        mem_wdata = 32'h12340000; mem_wstrb = 4'b1100;
        @(negedge clk); mem_valid = 0;
        if (!awvalid || !wvalid || awaddr !== 32'h00000102 || awsize !== 3'd1 ||
            wdata !== 32'h12340000 || wstrb !== 4'b1100 || !wlast)
            $fatal(1, "write payload failure");
        awready = 1;
        @(negedge clk); awready = 0;
        if (awvalid || !wvalid || mem_rvalid) $fatal(1, "AW/W independence failure");
        repeat (2) @(negedge clk);
        wready = 1;
        @(negedge clk); wready = 0;
        if (!bready || mem_rvalid || mem_ready) $fatal(1, "write completed before B");
        repeat (2) @(negedge clk);
        bvalid = 1;
        #1;
        if (!mem_rvalid) $fatal(1, "B completion missing");
        @(negedge clk); bvalid = 0;
        if (completions != 2 || !mem_ready || axi_error) $fatal(1, "write completion count");

        // W may also arrive before AW. A slave error is reported and the
        // request still completes, so the CPU cannot deadlock on an AXI error.
        mem_valid = 1; mem_addr = 32'h201; mem_wstrb = 4'b0010;
        @(negedge clk); mem_valid = 0;
        if (!awvalid || awaddr !== 32'h201 || awsize !== 3'd0 ||
            !wvalid || wstrb !== 4'b0010)
            $fatal(1, "byte write address/size failure");
        wready = 1;
        @(negedge clk); wready = 0;
        if (!awvalid || wvalid || mem_rvalid) $fatal(1, "W-first handshake failure");
        awready = 1;
        @(negedge clk); awready = 0;
        bresp = 2'b10; bvalid = 1;
        @(negedge clk); bvalid = 0;
        if (completions != 3 || !axi_error || !mem_ready)
            $fatal(1, "AXI error propagation failure");
        $display("PASS cache_axi_bridge: independent channels, backpressure, completion, error");
        $finish;
    end
endmodule
`default_nettype wire
