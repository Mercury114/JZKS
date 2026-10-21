`timescale 1ns / 1ps
// 直接使用仓库原confreg，检查旁路没有改变原地址译码/写入语义。
module mmio_bridge_tb;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;
    reg valid = 0, write = 0;
    reg [31:0] addr = 0, wdata = 0;
    reg [3:0] wstrb = 0;
    wire addr_ok, data_ok;
    wire [31:0] rdata;
    wire mem_valid, mem_write, mem_ready, mem_rvalid;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0] mem_wstrb;
    wire bus_en;
    wire [31:0] bus_addr, bus_wdata, bus_rdata;
    wire [3:0] bus_we;
    wire [31:0] accesses, uncached;
    cache_subsystem #(.INDEX_WIDTH(2), .WAY_NUM(2)) dut(
        .clk(clk), .resetn(resetn), .i_valid(1'b0), .i_addr(32'b0), .i_addr_ok(), .i_data_ok(), .i_rdata(),
        .d_valid(valid), .d_write(write), .d_wstrb(wstrb), .d_addr(addr), .d_wdata(wdata),
        .d_addr_ok(addr_ok), .d_data_ok(data_ok), .d_rdata(rdata),
        .cacop_valid(1'b0), .cacop_code(5'b0), .cacop_addr(32'b0), .cacop_ready(), .cacop_done(),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_ready(mem_ready), .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .i_access_count(), .i_hit_count(), .i_miss_count(), .d_access_count(accesses),
        .d_hit_count(), .d_miss_count(), .uncached_count(uncached)
    );
    cache_sram_bridge bridge(
        .clk(clk), .resetn(resetn), .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_ready(mem_ready),
        .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata), .sram_en(bus_en), .sram_we(bus_we),
        .sram_addr(bus_addr), .sram_wdata(bus_wdata), .sram_rdata(bus_rdata)
    );
    confreg #(.SIMULATION(1)) original_confreg(
        .clk(clk), .timer_clk(clk), .resetn(resetn), .conf_en(bus_en), .conf_we(bus_we),
        .conf_addr(bus_addr), .conf_wdata(bus_wdata), .conf_rdata(bus_rdata),
        .uart_rx(1'b1), .uart_tx(),
        .led(), .led_rg0(), .led_rg1(), .num_csn(), .num_a_g(), .num_data(),
        .switch(8'hff), .btn_key_col(), .btn_key_row(4'b0), .btn_step(2'b11)
    );
    integer accepted = 0, pulses = 0, responses = 0, cycles = 0;
    always @(posedge clk) if (resetn) begin
        cycles <= cycles + 1;
        if (cycles > 2000) $fatal(1, "MMIO bridge timeout");
        if (valid && addr_ok) accepted <= accepted + 1;
        if (bus_en) pulses <= pulses + 1;
        if (data_ok) responses <= responses + 1;
    end
    task access(input wr, input [31:0] a, input [31:0] value, input [3:0] mask, input [31:0] expected);
        begin
            @(negedge clk); valid = 1; write = wr; addr = a; wdata = value; wstrb = mask;
            do @(posedge clk); while (!addr_ok);
            @(negedge clk); valid = 0; addr = 0; wdata = 0; wstrb = 0;
            while (!data_ok) @(negedge clk);
            if (!wr && rdata !== expected) $fatal(1, "original MMIO semantics %h got %h expected %h", a, rdata, expected);
        end
    endtask
    initial begin
        repeat (5) @(negedge clk);
        resetn = 1;
        access(1, 32'h1faf8000, 32'h12345678, 4'b1111, 0);
        access(0, 32'hbfaf8000, 0, 0, 32'h12345678);
        // 原confreg不把8001当作8000的byte lane，旁路必须原样传地址。
        access(1, 32'hbfaf8001, 32'haaaaaaaa, 4'b0010, 0);
        access(0, 32'h1faf8000, 0, 0, 32'h12345678);
        access(0, 32'hbfaf8001, 0, 0, 0);
        // 原confreg在精确地址命中时，以任意非零we更新整个寄存器，不能假装支持byte merge。
        access(1, 32'hbfaf8000, 32'h11111111, 4'b0001, 0);
        access(0, 32'h1faf8000, 0, 0, 32'h11111111);
        repeat (3) @(negedge clk);
        if (accepted != 7 || pulses != 7 || responses != 7 || accesses != 0 || uncached != 7)
            $fatal(1, "MMIO repeated or cached accepted=%0d pulses=%0d responses=%0d", accepted, pulses, responses);
        $display("PASS original confreg + uncached SRAM bridge: 7 requests / 7 pulses / 7 completions, aliases and exact byte address preserved");
        $finish;
    end
endmodule
