`timescale 1ns / 1ps
module subsystem_tb;
    parameter WAY_NUM = 2;
    reg clk = 0;
    reg resetn = 0;
    always #5 clk = ~clk;
    reg i_valid = 0, d_valid = 0, d_write = 0, cacop_valid = 0;
    reg [31:0] i_addr = 0, d_addr = 0, d_wdata = 0, cacop_addr = 0;
    reg [3:0] d_wstrb = 0;
    reg [4:0] cacop_code = 0;
    wire i_addr_ok, i_data_ok, d_addr_ok, d_data_ok, cacop_ready, cacop_done;
    wire [31:0] i_rdata, d_rdata;
    wire mem_valid, mem_write, mem_ready, mem_rvalid;
    wire [3:0] mem_wstrb;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [31:0] ia, ih, im, da, dh, dm, uc, mmio_value, mmio_writes, reads, writes;
    cache_subsystem #(.INDEX_WIDTH(2), .WAY_NUM(WAY_NUM)) dut(
        .clk(clk), .resetn(resetn),
        .i_valid(i_valid), .i_addr(i_addr), .i_addr_ok(i_addr_ok), .i_data_ok(i_data_ok), .i_rdata(i_rdata),
        .d_valid(d_valid), .d_write(d_write), .d_wstrb(d_wstrb), .d_addr(d_addr), .d_wdata(d_wdata),
        .d_addr_ok(d_addr_ok), .d_data_ok(d_data_ok), .d_rdata(d_rdata),
        .cacop_valid(cacop_valid), .cacop_code(cacop_code), .cacop_addr(cacop_addr),
        .cacop_ready(cacop_ready), .cacop_done(cacop_done),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_ready(mem_ready), .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .i_access_count(ia), .i_hit_count(ih), .i_miss_count(im),
        .d_access_count(da), .d_hit_count(dh), .d_miss_count(dm), .uncached_count(uc)
    );
    cache_memory_model #(.LATENCY(2), .JITTER(1)) memory(
        .clk(clk), .resetn(resetn), .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_ready(mem_ready),
        .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata), .mmio_value(mmio_value),
        .mmio_writes(mmio_writes), .read_count(reads), .write_count(writes)
    );
    integer cycles = 0;
    integer i_accepted = 0, i_completed = 0, d_accepted = 0, d_completed = 0, controls = 0;
    reg held = 0;
    reg [68:0] held_payload;
    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (cycles > 200000) $fatal(1, "subsystem timeout");
        if (!resetn) begin
            if (mem_valid || i_addr_ok || d_addr_ok || i_data_ok || d_data_ok)
                $fatal(1, "activity during reset");
            held <= 0;
        end else begin
            if (i_valid && i_addr_ok) i_accepted <= i_accepted + 1;
            if (i_data_ok) i_completed <= i_completed + 1;
            if (d_valid && d_addr_ok) d_accepted <= d_accepted + 1;
            if (d_data_ok) d_completed <= d_completed + 1;
            if (cacop_done) controls <= controls + 1;
            if (i_data_ok && i_completed >= i_accepted) $fatal(1, "unowned I response");
            if (d_data_ok && d_completed >= d_accepted) $fatal(1, "unowned D response");
            if (held && (!mem_valid || held_payload !== {mem_write, mem_wstrb, mem_addr, mem_wdata}))
                $fatal(1, "memory request changed under backpressure");
            held <= mem_valid && !mem_ready;
            held_payload <= {mem_write, mem_wstrb, mem_addr, mem_wdata};
        end
    end
    task instruction(input [31:0] a, input [31:0] expected);
        begin
            @(negedge clk); i_valid = 1; i_addr = a;
            do @(posedge clk); while (!i_addr_ok);
            @(negedge clk); i_valid = 0; i_addr = 32'hdead0000;
            while (!i_data_ok) @(negedge clk);
            if (i_rdata !== expected) $fatal(1, "I read %h got %h expected %h", a, i_rdata, expected);
        end
    endtask
    task data_access(input wr, input [31:0] a, input [31:0] value, input [3:0] mask,
                     input [31:0] expected);
        begin
            @(negedge clk); d_valid = 1; d_write = wr; d_addr = a; d_wdata = value; d_wstrb = mask;
            do @(posedge clk); while (!d_addr_ok);
            // 接受后破坏请求字段，检查 miss/旁路只使用锁存副本。
            @(negedge clk); d_valid = 0; d_addr = 32'hdead0000; d_wdata = 0; d_wstrb = 0;
            while (!d_data_ok) @(negedge clk);
            if (!wr && d_rdata !== expected) $fatal(1, "D read %h got %h expected %h", a, d_rdata, expected);
        end
    endtask
    task control(input [4:0] code, input [31:0] a);
        begin
            @(negedge clk); cacop_valid = 1; cacop_code = code; cacop_addr = a;
            do @(posedge clk); while (!cacop_ready);
            @(negedge clk); cacop_valid = 0;
            while (!cacop_done) @(negedge clk);
        end
    endtask
    integer n;
    integer m;
    initial begin
        repeat (5) @(negedge clk);
        resetn = 1;
        // 双路同时 miss，随后 I 顺序跨行，D 连续脏替换和字节合并。
        fork
            begin
                for (n = 0; n < 120; n = n + 1)
                    instruction(32'h1c000000 + (n % 40) * 4, 32'h02800000);
            end
            begin
                for (m = 0; m < 40; m = m + 1) begin
                    data_access(1, 32'h1000 + m * 64, 32'h12340000 + m, 4'b1111, 0);
                    data_access(1, 32'h1000 + m * 64, 32'h0000ab00, 4'b0010, 0);
                    data_access(0, 32'h1000 + m * 64, 0, 0, 32'h1234ab00 + m);
                    // 两个地址都必须旁路，且一次 store 对应一次外设写。
                    data_access(1, m[0] ? 32'hbfaff050 : 32'h1faff050, m, 4'b1111, 0);
                    data_access(0, 32'hbfaff050, 0, 0, m);
                end
            end
        join
        // 脏块全部hit写回；已被替换的行应当已经写回。
        for (m = 0; m < 40; m = m + 1) control(5'h11, 32'h1000 + m * 64);
        for (m = 0; m < 40; m = m + 1)
            if (memory.data[(32'h1000 + m * 64) / 4] !== 32'h1234ab00 + m)
                $fatal(1, "dirty line not committed word=%0d", m);
        // I-cache coherence：先读旧指令，D修改代码并写回，I无效后应见新值。
        instruction(32'h1c000000, 32'h02800000);
        data_access(1, 32'h1c000000, 32'h0280a80f, 4'b1111, 0);
        control(5'h11, 32'h1c000000);
        instruction(32'h1c000000, 32'h02800000);
        control(5'h10, 32'h1c000000);
        instruction(32'h1c000000, 32'h0280a80f);
        for (m = 0; m < WAY_NUM; m = m + 1) begin
            control(5'h00, 32'h1000 + m);
            control(5'h01, 32'h1000 + m);
            control(5'h08, 32'h1000 + m);
            control(5'h09, 32'h1000 + m);
        end
        repeat (5) @(negedge clk);
        if (i_accepted != i_completed || d_accepted != d_completed || mmio_writes != 40 || uc != 80)
            $fatal(1, "counts I=%0d/%0d D=%0d/%0d mmio=%0d uc=%0d",
                   i_accepted, i_completed, d_accepted, d_completed, mmio_writes, uc);
        if (ia != ih + im || da != dh + dm) $fatal(1, "cache statistics mismatch");
        $display("PASS subsystem ways=%0d I=%0d D=%0d controls=%0d mmio_writes=%0d cycles=%0d",
                 WAY_NUM, i_completed, d_completed, controls, mmio_writes, cycles);
        $finish;
    end
endmodule
