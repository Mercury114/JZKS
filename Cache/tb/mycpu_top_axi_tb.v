`timescale 1ns/1ps
`default_nettype none

// Runs real instructions through the five-stage CPU, I/D caches, uncached
// MMIO path and an independently stalled AXI4 memory peripheral.
module mycpu_top_axi_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;
    wire [31:0] wb_pc, wb_data;
    wire [3:0] wb_we;
    wire [4:0] wb_num;
    wire axi_error;
    wire [3:0] awid, arid;
    wire [31:0] awaddr, araddr, wdata;
    wire [7:0] awlen, arlen;
    wire [2:0] awsize, arsize, awprot, arprot;
    wire [1:0] awburst, arburst;
    wire awlock, arlock, awvalid, wlast, wvalid, bready, arvalid, rready;
    wire [3:0] awcache, arcache, wstrb;
    wire awready, wready, bvalid, arready, rvalid, rlast;
    wire [3:0] bid, rid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;

    mycpu_top_axi #(.INDEX_WIDTH(4), .WAY_NUM(2)) dut(
        .clk(clk), .resetn(resetn), .hw_int_in(8'b0),
        .debug_wb_pc(wb_pc), .debug_wb_rf_we(wb_we),
        .debug_wb_rf_wnum(wb_num), .debug_wb_rf_wdata(wb_data), .axi_error(axi_error),
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

    reg [31:0] inst [0:1023];
    reg [31:0] data [0:1023];
    reg [31:0] mmio_value = 0;
    reg aw_seen = 0, w_seen = 0, write_pending = 0, bvalid_r = 0;
    reg read_pending = 0, rvalid_r = 0;
    reg [31:0] awaddr_r = 0, wdata_r = 0, rdata_r = 0;
    reg [3:0] wstrb_r = 0;
    integer write_delay = 0, read_delay = 0, cycles = 0;
    integer ar_count = 0, r_count = 0, aw_count = 0, w_count = 0, b_count = 0;
    integer mmio_writes = 0;
    integer i, lane;
    reg [31:0] merged;
    reg [31:0] chosen_addr, chosen_wdata;
    reg [3:0] chosen_wstrb;
    wire aw_fire = awvalid && awready;
    wire w_fire = wvalid && wready;
    wire ar_fire = arvalid && arready;

    // Different stalls on AW/W/AR exercise the independent AXI handshakes.
    assign awready = resetn && !aw_seen && !write_pending && !bvalid_r && cycles[0];
    assign wready = resetn && !w_seen && !write_pending && !bvalid_r && cycles[1];
    assign arready = resetn && !read_pending && !rvalid_r && cycles[2];
    assign bvalid = bvalid_r;
    assign bid = 0;
    assign bresp = 0;
    assign rvalid = rvalid_r;
    assign rid = 0;
    assign rresp = 0;
    assign rlast = 1;
    assign rdata = rdata_r;

    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            inst[i] = 32'h02800000;
            data[i] = 0;
        end
        // r1=0x100; r2=0x12a; cached store/load; uncached MMIO store;
        // r29=0x12b signals completion. The load-use dependency is intentional.
        inst[0] = 32'h02800000 | (32'h100 << 10) | 1;
        inst[1] = 32'h02800000 | (32'h12a << 10) | 2;
        inst[2] = 32'h29800000 | (1 << 5) | 2;
        inst[3] = 32'h28800000 | (1 << 5) | 3;
        inst[4] = 32'h14000000 | (32'hbfaff << 5) | 4;
        inst[5] = 32'h02800000 | (32'h50 << 10) | (4 << 5) | 4;
        inst[6] = 32'h29800000 | (4 << 5) | 3;
        inst[7] = 32'h02800000 | (1 << 10) | (3 << 5) | 29;
        inst[8] = 32'h50000000;
        repeat (5) @(negedge clk);
        resetn = 1;
    end

    always @(posedge clk) begin
        if (!resetn) begin
            cycles <= 0;
            aw_seen <= 0; w_seen <= 0; write_pending <= 0; bvalid_r <= 0;
            read_pending <= 0; rvalid_r <= 0;
        end else begin
            cycles <= cycles + 1;
            if (cycles > 10000) $fatal(1, "AXI CPU timeout pc=%h", wb_pc);
            if (aw_fire) begin
                if (awlen != 0 || awsize != 2 || awburst != 2'b01 || awid != 0)
                    $fatal(1, "bad AW attributes");
                aw_seen <= 1;
                awaddr_r <= awaddr;
                aw_count <= aw_count + 1;
            end
            if (w_fire) begin
                if (!wlast) $fatal(1, "missing WLAST");
                w_seen <= 1;
                wdata_r <= wdata;
                wstrb_r <= wstrb;
                w_count <= w_count + 1;
            end
            if (!write_pending && !bvalid_r &&
                (aw_seen || aw_fire) && (w_seen || w_fire)) begin
                chosen_addr = aw_fire ? awaddr : awaddr_r;
                chosen_wdata = w_fire ? wdata : wdata_r;
                chosen_wstrb = w_fire ? wstrb : wstrb_r;
                merged = 0;
                if ((chosen_addr & 32'h1fff0000) == 32'h1faf0000)
                    merged = mmio_value;
                else merged = data[chosen_addr[11:2]];
                for (lane = 0; lane < 4; lane = lane + 1)
                    if (chosen_wstrb[lane])
                        merged[lane*8 +: 8] = chosen_wdata[lane*8 +: 8];
                if ((chosen_addr & 32'h1fff0000) == 32'h1faf0000) begin
                    mmio_value <= merged;
                    mmio_writes <= mmio_writes + 1;
                end else data[chosen_addr[11:2]] <= merged;
                aw_seen <= 0; w_seen <= 0;
                write_pending <= 1;
                write_delay <= 3;
            end
            if (write_pending) begin
                if (write_delay != 0) write_delay <= write_delay - 1;
                else begin write_pending <= 0; bvalid_r <= 1; end
            end
            if (bvalid_r && bready) begin bvalid_r <= 0; b_count <= b_count + 1; end

            if (ar_fire) begin
                if (arlen != 0 || arsize != 2 || arburst != 2'b01 || arid != 0)
                    $fatal(1, "bad AR attributes");
                read_pending <= 1;
                read_delay <= 2;
                if ((araddr & 32'h1fff0000) == 32'h1faf0000) rdata_r <= mmio_value;
                else if (araddr[31:20] == 12'h1c0) rdata_r <= inst[araddr[11:2]];
                else rdata_r <= data[araddr[11:2]];
                ar_count <= ar_count + 1;
            end
            if (read_pending) begin
                if (read_delay != 0) read_delay <= read_delay - 1;
                else begin read_pending <= 0; rvalid_r <= 1; end
            end
            if (rvalid_r && rready) begin rvalid_r <= 0; r_count <= r_count + 1; end

            if (|wb_we && wb_num == 29) begin
                if (wb_data !== 32'h12b || mmio_value !== 32'h12a ||
                    mmio_writes != 1 || aw_count != 1 || w_count != 1 ||
                    b_count != 1 || ar_count < 8 || ar_count != r_count || axi_error)
                    $fatal(1, "AXI integrated failure wb=%h mmio=%h writes=%0d AR/R=%0d/%0d",
                           wb_data, mmio_value, mmio_writes, ar_count, r_count);
                $display("PASS AXI five-stage CPU/cache/MMIO: AR=%0d R=%0d AW=%0d W=%0d B=%0d",
                         ar_count, r_count, aw_count, w_count, b_count);
                $finish;
            end
        end
    end
endmodule
`default_nettype wire
