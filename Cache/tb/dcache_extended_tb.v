`timescale 1ns/1ps
// 独立外部行为测试：ref_mem 表示 CPU 看见的最新值，mem 表示主存实际值。
// 不依赖 DUT 内部状态；每次整行写回逐字对照参考值。
module dcache_case #(parameter WAYS=2)(output reg done=0);
    localparam IW=2, TW=26, WORDS=16384;
    reg clk=0; always #5 clk=~clk;
    reg resetn=0, valid=0, op=0;
    reg [IW-1:0] index=0; reg [TW-1:0] tag=0;
    reg [3:0] offset=0,wstrb=0; reg [31:0] wdata=0;
    reg ctrl_valid=0,ctrl_index_mode=0; reg [1:0] ctrl_op=0,ctrl_way=0;
    reg [IW-1:0] ctrl_index=0; reg [TW-1:0] ctrl_tag=0;
    wire ctrl_ready,ctrl_done,addr_ok,data_ok,rd_req,rd_rdy,ret_valid,ret_last,wr_req,wr_rdy;
    wire [31:0] rdata,rd_addr,ret_data,wr_addr,access_count,hit_count,miss_count;
    wire [2:0] rd_type,wr_type; wire [3:0] wr_wstrb; wire [127:0] wr_data;
    cache_dcache #(.INDEX_WIDTH(IW),.WAY_NUM(WAYS)) dut(
        .clk(clk),.resetn(resetn),.valid(valid),.op(op),.index(index),.tag(tag),.offset(offset),
        .wstrb(wstrb),.wdata(wdata),.addr_ok(addr_ok),.data_ok(data_ok),.rdata(rdata),
        .ctrl_valid(ctrl_valid),.ctrl_op(ctrl_op),.ctrl_index(ctrl_index),.ctrl_tag(ctrl_tag),
        .ctrl_index_mode(ctrl_index_mode),.ctrl_way(ctrl_way),.ctrl_ready(ctrl_ready),.ctrl_done(ctrl_done),
        .rd_req(rd_req),.rd_rdy(rd_rdy),.rd_type(rd_type),.rd_addr(rd_addr),
        .ret_valid(ret_valid),.ret_last(ret_last),.ret_data(ret_data),
        .wr_req(wr_req),.wr_rdy(wr_rdy),.wr_type(wr_type),.wr_addr(wr_addr),
        .wr_wstrb(wr_wstrb),.wr_data(wr_data),.access_count(access_count),.hit_count(hit_count),.miss_count(miss_count));
    reg [31:0] mem[0:WORDS-1],ref_mem[0:WORDS-1];
    reg active=0,fast_first=0,read_enable=1,write_enable=1;
    integer cycle=0,base=0,beat=0,rd_count=0,wr_count=0,done_count=0,expect_access=0;
    integer n,b;
    // 随机段的替换策略参考模型只存地址和访问时间，不照抄DUT的LRU排名算法。
    reg model_check=0;
    reg model_valid[0:WAYS-1][0:3];
    integer model_tag[0:WAYS-1][0:3],model_time[0:WAYS-1][0:3];
    integer model_clock=0,seed,rv;

    assign rd_rdy=read_enable && !active && cycle%5==0;
    assign wr_rdy=write_enable && cycle%4==0;
    wire immediate=fast_first && rd_req && rd_rdy;
    assign ret_valid=resetn && (immediate || (active && cycle%3!=1));
    assign ret_last=active && beat==3;
    assign ret_data=immediate ? mem[rd_addr>>2] : mem[base+beat];
    reg rd_stalled=0,wr_stalled=0; reg [31:0] old_rd_addr,old_wr_addr;
    reg [127:0] old_wr_data;
    always @(posedge clk) begin
        cycle<=cycle+1;
        if(!resetn) begin
            active<=0; rd_count<=0; wr_count<=0; done_count<=0;
            rd_stalled<=0; wr_stalled<=0;
        end else begin
            if(ctrl_done) done_count<=done_count+1;
            if(rd_stalled && (!rd_req || rd_addr!==old_rd_addr)) $fatal(1,"W%0d unstable read request",WAYS);
            if(wr_stalled && (!wr_req || wr_addr!==old_wr_addr || wr_data!==old_wr_data)) $fatal(1,"W%0d unstable writeback",WAYS);
            rd_stalled<=rd_req&&!rd_rdy; old_rd_addr<=rd_addr;
            wr_stalled<=wr_req&&!wr_rdy; old_wr_addr<=wr_addr; old_wr_data<=wr_data;
            if(rd_req && rd_rdy) begin
                if(rd_type!==3'b100 || rd_addr[3:0]!=0) $fatal(1,"read protocol");
                active<=1; base<=rd_addr>>2; beat<=immediate ? 1 : 0; rd_count<=rd_count+1;
            end else if(active && ret_valid) begin
                if(beat==3) active<=0; else beat<=beat+1;
            end
            if(wr_req && wr_rdy) begin
                if(wr_type!==3'b100 || wr_wstrb!==15 || wr_addr[3:0]!=0) $fatal(1,"write protocol");
                for(b=0;b<4;b=b+1) begin
                    if(wr_data[b*32+:32]!==ref_mem[(wr_addr>>2)+b])
                        $fatal(1,"W%0d dirty line %h word%0d got%h expected%h",WAYS,wr_addr,b,wr_data[b*32+:32],ref_mem[(wr_addr>>2)+b]);
                    mem[(wr_addr>>2)+b]<=wr_data[b*32+:32];
                end
                wr_count<=wr_count+1;
            end
        end
    end
    task automatic reset_cache;
        begin
            @(negedge clk); resetn=0; valid=0; ctrl_valid=0; expect_access=0;
            #1; if(addr_ok || data_ok || rd_req || wr_req || ctrl_ready || ctrl_done) $fatal(1,"reset outputs");
            repeat(2) @(negedge clk);
            resetn=1;
        end
    endtask
    task automatic cpu(input bit write,input [31:0] a,input [31:0] value,input [3:0] strobe);
        integer timeout,lane,mw,chosen,si,before_misses;
        reg [31:0] expected; reg expected_miss;
        begin
            @(negedge clk); valid=1; op=write; index=a[IW+3:4]; tag=a[31:IW+4];
            offset=a[3:0]; wdata=value; wstrb=strobe;
            timeout=0;
            do begin @(posedge clk); timeout=timeout+1; if(timeout>300) $fatal(1,"CPU address timeout"); end while(!addr_ok);
            before_misses=miss_count;
            expected_miss=0;
            if(model_check) begin
                si=(a>>4)&3; chosen=-1;
                for(mw=0;mw<WAYS;mw=mw+1)
                    if(model_valid[mw][si] && model_tag[mw][si]==(a>>6)) chosen=mw;
                expected_miss=chosen<0;
                if(chosen<0) begin
                    for(mw=0;mw<WAYS;mw=mw+1)
                        if(!model_valid[mw][si] && chosen<0) chosen=mw;
                    if(chosen<0) begin
                        chosen=0;
                        for(mw=1;mw<WAYS;mw=mw+1)
                            if(model_time[mw][si]<model_time[chosen][si]) chosen=mw;
                    end
                end
                model_clock=model_clock+1;
                model_valid[chosen][si]=1; model_tag[chosen][si]=a>>6;
                model_time[chosen][si]=model_clock;
            end
            expected=ref_mem[a>>2];
            if(write) begin
                for(lane=0;lane<4;lane=lane+1) if(strobe[lane]) expected[lane*8+:8]=value[lane*8+:8];
                ref_mem[a>>2]=expected;
            end
            expect_access=expect_access+1;
            // 握手后立即污染所有实时 CPU payload，捕获重复 store/未锁存请求。
            #1; valid=0; op=1; index=3; tag=26'h1ff; offset=12; wstrb=15; wdata=32'hdeadcafe;
            timeout=0;
            while(!data_ok) begin @(negedge clk); timeout=timeout+1; if(timeout>300) $fatal(1,"CPU response timeout"); end
            if(!write && rdata!==expected) $fatal(1,"W%0d read %h got%h expected%h",WAYS,a,rdata,expected);
            if(model_check && miss_count!=before_misses+expected_miss) $fatal(1,"W%0d random LRU miss mismatch %h",WAYS,a);
            if(access_count!==expect_access || access_count!==hit_count+miss_count) $fatal(1,"statistics");
            @(posedge clk); #1; if(data_ok) $fatal(1,"duplicate CPU response");
        end
    endtask
    task automatic management(input [1:0] command,input bit by_index,input [31:0] a,input [1:0] way,input bit hold_valid);
        integer t,old_done; reg [31:0] old_access;
        begin
            @(negedge clk); ctrl_valid=1; ctrl_op=command; ctrl_index_mode=by_index;
            ctrl_index=a[IW+3:4]; ctrl_tag=a[31:IW+4]; ctrl_way=way;
            valid=1; old_access=access_count; old_done=done_count;
            #1; if(addr_ok) $fatal(1,"management priority");
            t=0;
            do begin @(posedge clk); t=t+1; if(t>300) $fatal(1,"control ready timeout"); end while(!ctrl_ready);
            #1; valid=0; if(!hold_valid) ctrl_valid=0;
            t=0; while(!ctrl_done) begin @(negedge clk); t=t+1; if(t>300) $fatal(1,"control done timeout"); end
            repeat(5) @(negedge clk);
            if(done_count!=old_done+1 || access_count!==old_access) $fatal(1,"duplicate management/false CPU accept");
            ctrl_valid=0;
            @(negedge clk);
        end
    endtask
    integer s,j,old_r,old_w; reg [31:0] a;
    initial begin
        for(n=0;n<WORDS;n=n+1) begin mem[n]=32'h12000000+n; ref_mem[n]=mem[n]; end
        reset_cache();
        // 穷举16种字节使能，含零使能，覆盖四个字和写分配。
        for(s=0;s<16;s=s+1) begin
            a=32'h1000+s*64+(s%4)*4;
            cpu(1,a,32'h89abcdef^s,s[3:0]); cpu(0,a,0,0);
            management(2,0,a,0,0);
        end
        // 零字节写不能使 clean 行变 dirty（命中与缺失）。
        for(j=0;j<2;j=j+1) begin
            a=32'h2000+j*64;
            if(j==0) cpu(0,a,0,0);
            cpu(1,a,32'hffffffff,0); old_w=wr_count;
            management(1,0,a,0,0); if(wr_count!=old_w) $fatal(1,"zero strobe dirtied line");
        end
        // 脏行四字不同，主存背压后写回，保留有效的 op1 之后仍应命中。
        reset_cache();
        for(j=0;j<4;j=j+1) cpu(1,32'h3000+j*4,32'h87654000+j,15);
        old_r=rd_count; old_w=wr_count;
        management(1,0,32'h3000,0,1);
        if(wr_count!=old_w+1) $fatal(1,"writeback missing");
        for(j=0;j<4;j=j+1) cpu(0,32'h3000+j*4,0,0);
        if(rd_count!=old_r) $fatal(1,"op1 invalidated line");
        management(2,0,32'h3000,0,0); cpu(0,32'h3000,0,0);
        if(rd_count!=old_r+1) $fatal(1,"op2 did not invalidate");
        // 命中管理不存在的 tag 不能影响其他行。
        old_r=rd_count; management(0,0,32'h3fc0,0,0); cpu(0,32'h3000,0,0);
        if(rd_count!=old_r) $fatal(1,"control tag miss invalidated unrelated line");
        // op0显式丢弃脏内容，不得误写回；下一次访问从旧主存重新取。
        cpu(1,32'h3800,32'h1199aabb,15); old_w=wr_count;
        management(0,0,32'h3800,0,0);
        if(wr_count!=old_w) $fatal(1,"invalidate-only wrote memory");
        ref_mem[32'h3800>>2]=mem[32'h3800>>2]; cpu(0,32'h3800,0,0);
        // 真LRU：填满后反向命中，淘汰反向命中序列中最早被访问的路。
        reset_cache();
        for(j=0;j<WAYS;j=j+1) cpu(1,32'h4000+j*64,32'hab000000+j,15);
        for(j=WAYS-1;j>=0;j=j-1) cpu(0,32'h4000+j*64,0,0);
        old_w=wr_count; cpu(0,32'h4000+WAYS*64,0,0);
        if(wr_count!=old_w+1 || mem[(32'h4000+(WAYS-1)*64)>>2]!==ref_mem[(32'h4000+(WAYS-1)*64)>>2]) $fatal(1,"LRU victim wrong");
        old_r=rd_count; cpu(0,32'h4000+(WAYS-1)*64,0,0);
        if(rd_count!=old_r+1) $fatal(1,"LRU victim survived");
        // 每一路索引初始化；高位way按路数掩码，不需要匹配tag。
        reset_cache();
        for(j=0;j<WAYS;j=j+1) cpu(0,32'h5000+j*64,0,0);
        for(j=0;j<WAYS;j=j+1) management(0,1,32'h5fc0,j|(4-WAYS),0);
        old_r=rd_count;
        for(j=0;j<WAYS;j=j+1) cpu(0,32'h5000+j*64,0,0);
        if(rd_count!=old_r+WAYS) $fatal(1,"index invalidation failed");
        // 索引op2脏写回，索引op1保留；与hit管理走相同写回路径。
        reset_cache(); cpu(1,32'h6000,32'h77777777,15);
        old_w=wr_count; management(1,1,32'h6fc0,0,0);
        if(wr_count!=old_w+1) $fatal(1,"index op1 writeback");
        cpu(1,32'h6004,32'h22222222,15); management(2,1,32'h6fc0,0,0);
        old_r=rd_count; cpu(0,32'h6004,0,0);
        if(rd_count!=old_r+1) $fatal(1,"index op2 invalidation");
        // 确定性随机读写：访问时间模型逐次检查命中/缺失及真正LRU。
        reset_cache();
        for(j=0;j<WAYS;j=j+1) for(s=0;s<4;s=s+1) begin
            model_valid[j][s]=0; model_tag[j][s]=0; model_time[j][s]=0;
        end
        model_clock=0; model_check=1; seed=32'h31027+WAYS;
        for(j=0;j<600;j=j+1) begin
            rv=$random(seed); a=32'h8000+((rv&1023)<<2);
            cpu(rv[12],a,32'hac12503f^rv,rv[19:16]);
        end
        model_check=0;
        for(s=0;s<4;s=s+1) for(j=0;j<WAYS;j=j+1) management(2,1,s*16,j,0);
        for(j=(32'h8000>>2);j<(32'h9000>>2);j=j+1)
            if(mem[j]!==ref_mem[j]) $fatal(1,"random final memory mismatch");
        // 请求握手同拍首beat，后续ret仍带空拍。
        reset_cache(); fast_first=1;
        cpu(0,32'h700c,0,0); cpu(1,32'h7044,32'haabbccdd,5); cpu(0,32'h7044,0,0);
        management(2,0,32'h7040,0,0); fast_first=0;
        // 忙时控制不得ready。中途复位必须取消主存请求并屏蔽输出。
        reset_cache(); read_enable=0;
        @(negedge clk); valid=1; op=0; index=0; tag=26'h1e0; offset=0;
        @(posedge clk); #1; valid=0; ctrl_valid=1;
        if(ctrl_ready) $fatal(1,"busy ready");
        repeat(4) @(negedge clk);
        if(!rd_req) $fatal(1,"read request did not wait");
        reset_cache(); read_enable=1; cpu(0,32'h7800,0,0);
        cpu(1,32'h7900,32'h55667788,15); write_enable=0;
        @(negedge clk); ctrl_valid=1; ctrl_op=1; ctrl_index_mode=0;
        ctrl_index=0; ctrl_tag=32'h7900>>6;
        @(posedge clk); #1; ctrl_valid=0;
        repeat(3) @(negedge clk);
        if(!wr_req || ctrl_ready) $fatal(1,"writeback backpressure not active");
        reset_cache(); write_enable=1; cpu(0,32'h7a00,0,0);
        $display("PASS cache_dcache WAYS=%0d: strobes/writeallocate/4word WB/true-LRU/control/stalls/gaps/first-beat/reset",WAYS);
        done=1;
    end
endmodule
module dcache_extended_tb;
    wire d1,d2,d4;
    dcache_case #(.WAYS(1)) w1(d1);
    dcache_case #(.WAYS(2)) w2(d2);
    dcache_case #(.WAYS(4)) w4(d4);
    initial begin wait(d1&&d2&&d4); $display("PASS all dcache extended cases"); $finish; end
    initial begin #1000000; $fatal(1,"global timeout"); end
endmodule
