`timescale 1ns / 1ps

// 独立接口测试：参考模型不访问 DUT 的 tag、有效位或 LRU 数组。
// 分别以 WAY_NUM=1/2/4 编译运行；小索引便于覆盖同组冲突和跨组访问。
module icache_tb;
    parameter WAY_NUM = 2;
    localparam INDEX_WIDTH = 2;
    localparam TAG_WIDTH = 26;
    reg clk = 0;
    always #5 clk = !clk;
    reg resetn = 0;
    reg valid = 0;
    reg [INDEX_WIDTH-1:0] index = 0;
    reg [TAG_WIDTH-1:0] tag = 0;
    reg [3:0] offset = 0;
    wire addr_ok, data_ok;
    wire [31:0] rdata;
    wire rd_req;
    wire [2:0] rd_type;
    wire [31:0] rd_addr;
    reg rd_rdy = 0;
    reg ret_valid = 0;
    reg ret_last = 0;
    reg [31:0] ret_data = 0;
    reg ctrl_valid = 0;
    reg [1:0] ctrl_op = 0;
    reg [INDEX_WIDTH-1:0] ctrl_index = 0;
    reg [TAG_WIDTH-1:0] ctrl_tag = 0;
    reg ctrl_index_mode = 0;
    reg [1:0] ctrl_way = 0;
    wire ctrl_ready, ctrl_done;
    wire [31:0] access_count, hit_count, miss_count;

    cache_icache #(.INDEX_WIDTH(INDEX_WIDTH), .TAG_WIDTH(TAG_WIDTH),
                   .WAY_NUM(WAY_NUM)) dut (
        .clk(clk), .resetn(resetn), .valid(valid), .index(index), .tag(tag), .offset(offset),
        .addr_ok(addr_ok), .data_ok(data_ok), .rdata(rdata),
        .rd_req(rd_req), .rd_type(rd_type), .rd_addr(rd_addr), .rd_rdy(rd_rdy),
        .ret_valid(ret_valid), .ret_last(ret_last), .ret_data(ret_data),
        .ctrl_valid(ctrl_valid), .ctrl_op(ctrl_op), .ctrl_index(ctrl_index),
        .ctrl_tag(ctrl_tag), .ctrl_index_mode(ctrl_index_mode), .ctrl_way(ctrl_way),
        .ctrl_ready(ctrl_ready), .ctrl_done(ctrl_done),
        .access_count(access_count), .hit_count(hit_count), .miss_count(miss_count)
    );

    function [31:0] memory_word;
        input [31:0] address;
        begin memory_word = 32'h63a9f100 ^ {address[31:2], 2'b00}; end
    endfunction

    // 主存每四拍才允许一个读请求，返回四字且插入空拍。
    integer cycle = 0;
    integer beat = 0;
    reg memory_busy = 0;
    reg immediate_first = 0;
    reg [31:0] memory_base = 0;
    integer read_count = 0;
    integer blocked_cycles = 0;
    integer return_gaps = 0;
    reg request_waiting = 0;
    reg [31:0] held_rd_addr;
    reg model_valid [0:3][0:WAY_NUM-1];
    reg [TAG_WIDTH-1:0] model_tag [0:3][0:WAY_NUM-1];
    integer model_age [0:3][0:WAY_NUM-1];
    integer stamp = 0;
    integer accepted = 0;
    integer returned = 0;
    integer expected_hits = 0;
    integer expected_misses = 0;
    integer controls = 0;
    integer control_returns = 0;
    reg [31:0] queue [0:4095];
    reg [31:0] expected_rd [0:4095];
    integer miss_tail = 0;
    integer miss_head = 0;
    integer selected;
    integer oldest;
    integer s, w;

    always @(negedge clk) begin
        rd_rdy = resetn && !memory_busy && cycle % 4 == 0;
        ret_valid = resetn && memory_busy && cycle % 9 >= 4 && cycle % 3 != 1;
        ret_last = ret_valid && beat == 3;
        ret_data = memory_word(memory_base + beat * 4);
        if (immediate_first && rd_req && rd_rdy) begin
            ret_valid = 1;
            ret_last = 0;
            ret_data = memory_word(rd_addr);
        end
    end

    always @(posedge clk) begin
        cycle = cycle + 1;
        if (cycle > 18000) $fatal(1, "WATCHDOG way=%0d", WAY_NUM);
        if (!resetn) begin
            if (addr_ok || rd_req || data_ok) $fatal(1, "reset accepted or responded");
            memory_busy = 0;
            beat = 0;
            accepted = 0;
            returned = 0;
            expected_hits = 0;
            expected_misses = 0;
            read_count = 0;
            miss_tail = 0;
            miss_head = 0;
            controls = 0;
            control_returns = 0;
            request_waiting = 0;
            stamp = 0;
            for (s = 0; s < 4; s = s + 1)
                for (w = 0; w < WAY_NUM; w = w + 1) begin
                    model_valid[s][w] = 0;
                    model_tag[s][w] = 0;
                    model_age[s][w] = 0;
                end
        end else begin
            if (data_ok) begin
                if (returned >= accepted) $fatal(1, "unaccepted/duplicate response");
                if (rdata !== queue[returned])
                    $fatal(1, "response %0d got=%h expected=%h", returned, rdata, queue[returned]);
                returned = returned + 1;
            end
            if (ctrl_done) begin
                control_returns = control_returns + 1;
                if (control_returns > controls) $fatal(1, "unaccepted control response");
            end
            if (ctrl_valid && addr_ok) $fatal(1, "management priority broken");
            if (valid && addr_ok) begin
                queue[accepted] = memory_word({tag, index, offset[3:2], 2'b00});
                accepted = accepted + 1;
                selected = -1;
                for (w = 0; w < WAY_NUM; w = w + 1)
                    if (model_valid[index][w] && model_tag[index][w] == tag) selected = w;
                if (selected >= 0) expected_hits = expected_hits + 1;
                else begin
                    expected_misses = expected_misses + 1;
                    expected_rd[miss_tail] = {tag, index, 4'b0000};
                    miss_tail = miss_tail + 1;
                    for (w = WAY_NUM-1; w >= 0; w = w - 1)
                        if (!model_valid[index][w]) selected = w;
                    if (selected < 0) begin
                        oldest = 32'h7fffffff;
                        for (w = 0; w < WAY_NUM; w = w + 1)
                            if (model_age[index][w] < oldest) begin
                                oldest = model_age[index][w];
                                selected = w;
                            end
                    end
                    model_valid[index][selected] = 1;
                    model_tag[index][selected] = tag;
                end
                stamp = stamp + 1;
                model_age[index][selected] = stamp;
            end
            if (ctrl_valid && ctrl_ready) begin
                if (accepted != returned || data_ok) $fatal(1, "control accepted before draining");
                controls = controls + 1;
                selected = -1;
                if (ctrl_index_mode) selected = ctrl_way & (WAY_NUM - 1);
                else for (w = 0; w < WAY_NUM; w = w + 1)
                    if (model_valid[ctrl_index][w] && model_tag[ctrl_index][w] == ctrl_tag) selected = w;
                if (selected >= 0 && (ctrl_op == 0 || ctrl_op == 2))
                    model_valid[ctrl_index][selected] = 0;
            end
            if (request_waiting && (!rd_req || rd_addr !== held_rd_addr || rd_type !== 3'b100))
                $fatal(1, "read request changed while stalled");
            request_waiting = rd_req && !rd_rdy;
            if (request_waiting) begin
                held_rd_addr = rd_addr;
                blocked_cycles = blocked_cycles + 1;
            end
            if (ret_valid) begin
                if (!memory_busy && !(rd_req && rd_rdy))
                    $fatal(1, "memory returned without request");
                if (memory_busy) begin
                    if (beat == 3) begin memory_busy = 0; beat = 0; end
                    else beat = beat + 1;
                end
            end else if (memory_busy) return_gaps = return_gaps + 1;
            if (rd_req && rd_rdy) begin
                if (memory_busy || miss_head == miss_tail) $fatal(1, "unexpected memory read");
                if (rd_type !== 3'b100 || rd_addr !== expected_rd[miss_head])
                    $fatal(1, "wrong memory read got=%h expected=%h", rd_addr, expected_rd[miss_head]);
                miss_head = miss_head + 1;
                read_count = read_count + 1;
                memory_base = rd_addr;
                memory_busy = 1;
                beat = ret_valid ? 1 : 0;
            end
        end
    end

    task send;
        input [31:0] address;
        begin
            @(negedge clk);
            valid = 1;
            {tag, index, offset} = address;
            @(posedge clk);
            while (!addr_ok) @(posedge clk);
            @(negedge clk);
            valid = 0;
        end
    endtask
    task drain;
        begin
            @(negedge clk);
            while (accepted != returned || memory_busy || data_ok) @(negedge clk);
            if (access_count !== accepted || hit_count !== expected_hits || miss_count !== expected_misses)
                $fatal(1, "counter mismatch access=%0d/%0d hit=%0d/%0d miss=%0d/%0d",
                       access_count, accepted, hit_count, expected_hits, miss_count, expected_misses);
            if (read_count != expected_misses) $fatal(1, "memory count mismatch");
        end
    endtask
    task manage;
        input [1:0] operation;
        input by_index;
        input [1:0] way;
        input [31:0] address;
        begin
            @(negedge clk);
            ctrl_valid = 1;
            ctrl_op = operation;
            ctrl_index_mode = by_index;
            ctrl_way = way;
            ctrl_index = address[5:4];
            ctrl_tag = address[31:6];
            // 同时摆一个普通请求，检查管理优先且不虚报 addr_ok。
            valid = 1;
            @(posedge clk);
            while (!ctrl_ready) @(posedge clk);
            @(negedge clk);
            valid = 0;
            ctrl_valid = 0;
            while (!ctrl_done) @(negedge clk);
        end
    endtask

    integer k;
    integer before_count;
    integer before_cycle;
    reg [31:0] address;
    initial begin
        repeat (4) @(negedge clk);
        resetn = 1;
        // 首次 miss、同一行四字、跨行和跨组。
        send(32'h0000010c);
        send(32'h00000100);
        send(32'h00000104);
        send(32'h00000108);
        send(32'h00000110);
        send(32'h00000120);
        send(32'h00000130);
        drain;

        // 冷填同组全部路，再倒序触摸；随后冲突替换须严格符合 LRU。
        for (k = 0; k < WAY_NUM; k = k + 1) send(32'h1000 + k * 64);
        for (k = WAY_NUM-1; k >= 0; k = k - 1) send(32'h1000 + k * 64 + 4);
        send(32'h1000 + WAY_NUM * 64);
        send(32'h1000);
        send(32'h1000 + (WAY_NUM-1) * 64);
        drain;

        // 热命中持续发射：32 个请求必须在连续 32 个时钟沿被接受。
        send(32'h4040);
        drain;
        @(negedge clk);
        before_count = accepted;
        before_cycle = cycle;
        valid = 1;
        for (k = 0; k < 32; k = k + 1) begin
            {tag, index, offset} = 32'h4040 + (k % 4) * 4;
            @(posedge clk);
            if (!addr_ok) $fatal(1, "hot-hit throughput bubble %0d", k);
            if (k >= 2 && !data_ok) $fatal(1, "hot-hit response bubble %0d", k);
            @(negedge clk);
        end
        valid = 0;
        if (accepted - before_count != 32 || cycle - before_cycle != 32)
            $fatal(1, "hot-hit acceptance throughput mismatch");
        drain;

        // 管理在 miss 尚未完成时到达，必须等待最后普通响应结束。
        send(32'h808c);
        manage(2, 0, 0, 32'h8080);
        send(32'h8080);
        drain;
        manage(1, 0, 0, 32'h8080); // 写回为空操作，随后应继续命中。
        send(32'h8084);
        manage(0, 0, 0, 32'habcd0080); // 不匹配 tag 不得误无效化。
        send(32'h8088);
        manage(0, 1, 3, 32'h8080); // 检查直接索引和 way 掩码。
        for (k = 0; k < WAY_NUM; k = k + 1) send(32'h9000 + k * 64);
        drain;

        // 后半程允许读请求握手同拍返回首字，不能漏掉该字。
        immediate_first = 1;
        // 确定性分散序列，参考模型交叉核查替换、管理后排名和精确计数。
        for (k = 0; k < 180; k = k + 1) begin
            address = 32'h10000 + ((k * 17 + k / 7) % 9) * 64
                      + ((k / 3) % 4) * 16 + (k % 4) * 4;
            send(address);
            if (k % 29 == 7) manage(2, 1, k % 4, address);
        end
        drain;
        repeat (3) @(negedge clk);
        if (controls != control_returns) $fatal(1, "control completion mismatch");
        if (!blocked_cycles || !return_gaps) $fatal(1, "backpressure/gap coverage missing");
        $display("ICACHE PASS WAY_NUM=%0d accepted=%0d returned=%0d hits=%0d misses=%0d memory_reads=%0d controls=%0d blocked=%0d gaps=%0d cycles=%0d",
                 WAY_NUM, accepted, returned, expected_hits, expected_misses,
                 read_count, controls, blocked_cycles, return_gaps, cycle);
        // 中途复位取消尚未完成的请求；复位期间即使 valid 仍高也不得接受。
        send(32'hf0000000);
        while (!memory_busy) @(negedge clk);
        @(negedge clk);
        resetn = 0;
        valid = 1;
        ctrl_valid = 1;
        #1;
        if (addr_ok || rd_req || data_ok) $fatal(1, "asynchronous reset gating failed");
        repeat (3) @(negedge clk);
        valid = 0;
        ctrl_valid = 0;
        resetn = 1;
        send(32'hf000000c);
        drain;
        if (accepted != 1 || returned != 1 || expected_misses != 1)
            $fatal(1, "post-reset refill/count failure");
        $display("ICACHE RESET PASS WAY_NUM=%0d accepted=1 returned=1 misses=1", WAY_NUM);
        $finish;
    end
endmodule
