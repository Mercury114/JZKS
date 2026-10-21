`timescale 1ns/1ps
// 五来源外部行为回归，不读取仲裁器内部状态。
module arbiter_tb;
    reg clk=0; always #5 clk=~clk;
    reg resetn=0;
    reg i_rd_req=0,d_rd_req=0,d_wr_req=0,iu_req=0,du_req=0;
    reg [31:0] i_rd_addr=32'h1000,d_rd_addr=32'h2000,d_wr_addr=32'h3000,iu_addr=32'h4000,du_addr=32'h5000;
    reg [127:0] d_wr_data=128'hddccbbaa_88776655_44332211_10203040;
    reg du_write=0; reg [3:0] du_wstrb=5; reg [31:0] du_wdata=32'habcd1234;
    wire i_rd_rdy,d_rd_rdy,d_wr_rdy,iu_ready,du_ready;
    wire i_ret_valid,i_ret_last,d_ret_valid,d_ret_last,iu_done,du_done;
    wire [31:0] i_ret_data,d_ret_data,iu_rdata,du_rdata;
    wire mem_valid,mem_write,mem_ready,mem_rvalid;
    wire [3:0] mem_wstrb; wire [31:0] mem_addr,mem_wdata,mem_rdata;
    cache_mem_arbiter dut(.*);
    reg [31:0] mem[0:8191];
    reg [31:0] lfsr=32'h9fe372a1;
    reg pending=0; reg [31:0] pending_data=0; integer delay_left=0;
    reg force_stall=0,force_delay=0,all_pending=0;
    integer cycle=0,zero_count=0,delayed_count=0,stall_count=0;
    wire accept=mem_valid&&mem_ready;
    wire immediate=accept&&!force_delay&&lfsr[3:2]==0;
    assign mem_ready=resetn&&!pending&&!force_stall&&(lfsr[1:0]!=0);
    assign mem_rvalid=resetn&&(immediate || (pending&&delay_left==0&&lfsr[5]));
    assign mem_rdata=immediate?mem[mem_addr[14:2]]:pending_data;
    integer k;
    always @(posedge clk) begin
        lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
        cycle<=cycle+1;
        if(!resetn) begin pending<=0; delay_left<=0; end
        else begin
            if(mem_valid&&!mem_ready) stall_count<=stall_count+1;
            if(pending) begin
                if(delay_left>0) delay_left<=delay_left-1;
                else if(mem_rvalid) pending<=0;
                if(mem_valid) $fatal(1,"more than one backend word outstanding");
            end
            if(accept) begin
                if(mem_write) for(k=0;k<4;k=k+1)
                    if(mem_wstrb[k]) mem[mem_addr[14:2]][k*8+:8]<=mem_wdata[k*8+:8];
                if(immediate) zero_count<=zero_count+1;
                else begin
                    delayed_count<=delayed_count+1;
                    pending<=1; pending_data<=mem[mem_addr[14:2]];
                    delay_left<=force_delay?12:lfsr[8:6];
                end
            end
        end
    end
    integer grants[0:4],completed[0:4],accepted[0:4];
    integer transaction=-1,word_number=0,seen_words=0,last_owner=-1,owner_now;
    integer total_done=0,wb_acks=0,epoch_done=0;
    reg stalled=0,old_write; reg [3:0] old_strobe;
    reg [31:0] old_addr,old_data;
    reg wb_final_seen=0;
    reg [31:0] expected_addr;
    // 接受源请求、逐字主存接受、逐字完成三层分别记账。
    always @(posedge clk) begin
        if(!resetn) begin
            for(integer q=0;q<5;q=q+1) begin grants[q]=0; completed[q]=0; accepted[q]=0; end
            transaction=-1; word_number=0; seen_words=0; last_owner=-1;
            total_done=0; wb_acks=0; stalled=0; wb_final_seen=0;
        end else begin
            if(i_rd_rdy) accepted[0]=accepted[0]+1;
            if(d_rd_rdy) accepted[1]=accepted[1]+1;
            if(iu_ready) accepted[3]=accepted[3]+1;
            if(du_ready) accepted[4]=accepted[4]+1;
            if((i_rd_rdy+d_rd_rdy+iu_ready+du_ready)>1) $fatal(1,"multiple source grants");
            if(stalled && (!mem_valid || mem_addr!==old_addr || mem_wdata!==old_data || mem_write!==old_write || mem_wstrb!==old_strobe))
                $fatal(1,"backend request changed under backpressure");
            stalled=mem_valid&&!mem_ready;
            old_addr=mem_addr; old_data=mem_wdata; old_write=mem_write; old_strobe=mem_wstrb;
            if(d_wr_rdy) begin
                if(!wb_final_seen) $fatal(1,"writeback ready before last response");
                wb_acks=wb_acks+1; wb_final_seen=0;
            end else if(wb_final_seen) $fatal(1,"missing final writeback ready");
            if(mem_valid) begin
                // 外设/U通道完整地址（含低2位）不得被对齐截断。
                if(mem_addr[31:16]==iu_addr[31:16] && iu_addr[31:16]!=0) owner_now=3;
                else if(mem_addr[31:16]==du_addr[31:16] && du_addr[31:16]!=0) owner_now=4;
                else owner_now=(mem_addr>>12)-1;
                if(owner_now<0 || owner_now>4) $fatal(1,"unknown backend address %h",mem_addr);
                if(transaction<0) begin
                    transaction=owner_now; word_number=0; seen_words=0;
                    grants[owner_now]=grants[owner_now]+1;
                    if(all_pending && owner_now!=(last_owner+1)%5) $fatal(1,"round robin order %0d after %0d",owner_now,last_owner);
                    last_owner=owner_now;
                end
                if(owner_now!=transaction) $fatal(1,"cache line interleaved");
                expected_addr=transaction==3 ? iu_addr :
                              transaction==4 ? du_addr : (transaction+1)*4096+word_number*4;
                if(mem_addr!==expected_addr) $fatal(1,"address/beat mismatch got %h expected %h",mem_addr,expected_addr);
                if(mem_write!==(transaction==2 || (transaction==4&&du_write))) $fatal(1,"write routing");
                if(transaction==2 && (mem_wstrb!==15 || mem_wdata!==d_wr_data[word_number*32+:32])) $fatal(1,"line write payload");
                if(transaction==4 && du_write && (mem_wstrb!==du_wstrb || mem_wdata!==du_wdata)) $fatal(1,"uncached write payload");
                if(!mem_write && mem_wstrb!==0) $fatal(1,"read strobes");
            end
            if(accept) seen_words=seen_words+1;
            if(mem_rvalid) begin
                if(transaction<0 || !(pending||accept)) $fatal(1,"unowned response");
                if(seen_words!=word_number+1) $fatal(1,"response before accept");
                if(i_ret_valid!==(transaction==0) || d_ret_valid!==(transaction==1) || iu_done!==(transaction==3) || du_done!==(transaction==4))
                    $fatal(1,"response routed to wrong owner");
                if(transaction==0 && (i_ret_last!==(word_number==3) || i_ret_data!==mem[expected_addr[14:2]])) $fatal(1,"I read response");
                if(transaction==1 && (d_ret_last!==(word_number==3) || d_ret_data!==mem[expected_addr[14:2]])) $fatal(1,"D read response");
                if(transaction==3 && iu_rdata!==mem[iu_addr[14:2]]) $fatal(1,"IU read response");
                if(transaction==4 && !du_write && du_rdata!==mem[du_addr[14:2]]) $fatal(1,"DU read response");
                if(word_number==(transaction<3?3:0)) begin
                    if(transaction==2) wb_final_seen=1;
                    completed[transaction]=completed[transaction]+1; total_done=total_done+1;
                    transaction=-1;
                end else word_number=word_number+1;
            end else if(i_ret_valid||d_ret_valid||i_ret_last||d_ret_last||iu_done||du_done) $fatal(1,"unsolicited response");
        end
    end
    task automatic requests(input bit enabled);
        begin i_rd_req=enabled; d_rd_req=enabled; d_wr_req=enabled; iu_req=enabled; du_req=enabled; end
    endtask
    task automatic reset_all;
        begin
            @(negedge clk); resetn=0; requests(0); all_pending=0;
            #1;
            if(mem_valid||i_rd_rdy||d_rd_rdy||d_wr_rdy||iu_ready||du_ready||i_ret_valid||d_ret_valid||iu_done||du_done)
                $fatal(1,"reset did not mask handshake outputs");
            repeat(3) @(negedge clk);
            resetn=1;
        end
    endtask
    task automatic drain;
        integer guard;
        begin
            @(negedge clk); requests(0); all_pending=0;
            // 最后一笔已接受事务完成，额外保留FINISH与IDLE两个边沿。
            guard=0;
            while(transaction>=0||mem_valid||pending) begin
                @(negedge clk); guard=guard+1; if(guard>1000) $fatal(1,"drain timeout");
            end
            repeat(3) @(negedge clk);
            for(integer q=0;q<5;q=q+1) begin
                if(grants[q]!=completed[q]) $fatal(1,"transaction lost owner %0d",q);
                if(q!=2 && accepted[q]!=completed[q]) $fatal(1,"source acceptance mismatch owner %0d",q);
            end
            if(wb_acks!=completed[2]) $fatal(1,"writeback ack count");
        end
    endtask
    task automatic concurrent_rounds(input integer rounds);
        integer start_done,guard;
        begin
            @(negedge clk); requests(1); all_pending=1;
            start_done=total_done; guard=0;
            while(total_done<start_done+rounds*5) begin
                @(negedge clk); guard=guard+1; if(guard>20000) $fatal(1,"starvation timeout");
            end
            drain();
        end
    endtask
    initial begin
        for(integer q=0;q<8192;q=q+1) mem[q]=32'h80100000+q;
        reset_all(); concurrent_rounds(25);
        // 第二轮改成带字节使能的uncached写，覆盖所有五来源持续并发。
        du_write=1; du_wstrb=5; concurrent_rounds(25);
        if(mem[du_addr[14:2]]!==32'h80cd1434) $fatal(1,"uncached byte write result %h",mem[du_addr[14:2]]);
        if(zero_count<10 || delayed_count<10 || stall_count<10) $fatal(1,"insufficient memory timing coverage");
        // 完整外设地址回归：非对齐地址的低2位必须逐位原样传到后端。
        // 有限测试存储只按低15位映射，但上面的地址断言核对完整32位。
        iu_addr=32'h1faf8123; du_addr=32'hbfaf8001; du_write=0;
        concurrent_rounds(3);
        du_write=1; du_wstrb=10; du_wdata=32'h12345678;
        concurrent_rounds(3);
        iu_addr=32'h4000; du_addr=32'h5000;
        // 在SEND被ready阻塞时复位，内存端同步清空事务。
        reset_all(); force_stall=1; @(negedge clk); i_rd_req=1;
        wait(mem_valid); repeat(3) @(negedge clk);
        reset_all(); force_stall=0;
        // 在接受了一个字但尚未rvalid时复位。
        force_delay=1; @(negedge clk); d_rd_req=1;
        wait(pending); @(negedge clk); reset_all(); force_delay=0;
        // 写回中途已完成第一字后复位，禁止错误的整行完成确认。
        @(negedge clk); d_wr_req=1;
        wait(transaction==2&&word_number==1); reset_all();
        du_write=0; concurrent_rounds(10);
        $display("PASS arbiter: 5-source round-robin/full-line exclusivity/final-WB-ack/backpressure/zero+delayed replies/full-U-address/reset; zero=%0d delayed=%0d stall=%0d",zero_count,delayed_count,stall_count);
        $finish;
    end
    initial begin #2000000; $fatal(1,"global timeout"); end
endmodule
