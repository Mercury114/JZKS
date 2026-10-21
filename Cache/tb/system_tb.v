`timescale 1ns / 1ps
module system_tb;
    parameter INDEX_WIDTH = 4;
    parameter WAY_NUM = 2;
    parameter ENABLE_CACHE = 1;
    parameter LATENCY = 8;
    parameter JITTER = 0;
    parameter BOARD_ADDR_MAP = 0;
    reg clk = 0;
    reg resetn = 0;
    always #5 clk = ~clk;
    wire mem_valid, mem_write, mem_ready, mem_rvalid;
    wire [3:0] mem_wstrb;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [31:0] wb_pc, wb_data;
    wire [3:0] wb_we;
    wire [4:0] wb_num;
    wire [31:0] ia, ih, im, da, dh, dm, uc, mmio_value, mmio_writes, reads, writes;
    cache_system #(.INDEX_WIDTH(INDEX_WIDTH), .WAY_NUM(WAY_NUM), .ENABLE_CACHE(ENABLE_CACHE), .BOARD_ADDR_MAP(BOARD_ADDR_MAP)) dut(
        .clk(clk), .resetn(resetn), .hw_int_in(8'b0),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_ready(mem_ready), .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .debug_wb_pc(wb_pc), .debug_wb_rf_we(wb_we), .debug_wb_rf_wnum(wb_num), .debug_wb_rf_wdata(wb_data),
        .i_access_count(ia), .i_hit_count(ih), .i_miss_count(im),
        .d_access_count(da), .d_hit_count(dh), .d_miss_count(dm), .uncached_count(uc)
    );
    cache_memory_model #(.LATENCY(LATENCY), .JITTER(JITTER)) memory(
        .clk(clk), .resetn(resetn), .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_ready(mem_ready),
        .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata), .mmio_value(mmio_value),
        .mmio_writes(mmio_writes), .read_count(reads), .write_count(writes)
    );
    reg [1023:0] trace_name;
    reg [1023:0] expect_name;
    integer trace_file;
    integer cycles = 0;
    integer writes_seen = 0;
    integer fd;
    integer scan;
    reg [31:0] a, expected, got;
    initial begin
        if (!$value$plusargs("TRACE=%s", trace_name)) $fatal(1, "TRACE required");
        if (!$value$plusargs("EXPECT=%s", expect_name)) $fatal(1, "EXPECT required");
        trace_file = $fopen(trace_name, "w");
        if (!trace_file) $fatal(1, "cannot open trace");
        repeat (8) @(negedge clk);
        resetn = 1;
    end
    always @(posedge clk) begin
        if (resetn) begin
            cycles = cycles + 1;
            if (cycles > 2000000) $fatal(1, "system timeout pc=%h", wb_pc);
            if (|wb_we) begin
                $fdisplay(trace_file, "%08x %02x %08x", wb_pc, wb_num, wb_data);
                writes_seen = writes_seen + 1;
                if (wb_num == 29 && wb_data == 32'h55a) begin
                    $fclose(trace_file);
                    fd = $fopen(expect_name, "r");
                    if (!fd) $fatal(1, "cannot open memory expectation");
                    while (!$feof(fd)) begin
                        scan = $fscanf(fd, "%h %h\n", a, expected);
                        if (scan == 2) begin
                            if ((a & 32'h1fff0000) == 32'h1faf0000) got = mmio_value;
                            else if (a[31:20] == 12'h1c0) got = memory.inst[a[19:2]];
                            else got = memory.data[a[17:2]];
                            if (got !== expected) $fatal(1, "final memory %h got=%h expected=%h", a, got, expected);
                        end
                    end
                    $fclose(fd);
                    $display("METRICS cycles=%0d wb=%0d ia=%0d ih=%0d im=%0d da=%0d dh=%0d dm=%0d uc=%0d reads=%0d writes=%0d mmio=%0d",
                             cycles, writes_seen, ia, ih, im, da, dh, dm, uc, reads, writes, mmio_writes);
                    $display("PASS integrated CPU/cache architectural trace and final memory");
                    $finish;
                end
            end
        end
    end
endmodule
