`timescale 1ns/1ps
// Part 6: 期望状态由 Python 按手册生成，检查异常提交、年轻副作用和返回。
module cpu_handshake_tb;
reg clk = 0;
reg resetn = 0;
reg [7:0] hw_int = 0;
wire inst_en;
wire [3:0] inst_we;
wire [31:0] inst_addr;
wire [31:0] inst_wdata;
reg [31:0] inst_rdata;
wire data_en;
wire [3:0] data_we;
wire [31:0] data_addr;
wire [31:0] data_wdata;
reg [31:0] data_rdata;
wire [31:0] pc;
wire [3:0] we;
wire [4:0] rd;
wire [31:0] value;
reg [31:0] rom [0:1023];
reg [31:0] ram [0:255];
reg [31:0] expect_ram [0:255];
integer i;
integer lane;
integer cycles = 0;
integer exceptions = 0;
integer exp_exceptions;
integer irq_mask;
integer reset_case;
reg reset_done = 0;
reg [31:0] fault_pc;
reg [1023:0] rom_file;
reg [1023:0] expect_file;
reg ipending=0, dpending=0, cpending=0;
reg [31:0] ia, da, dr;
integer idelay=0, ddelay=0, cdelay=0, accepted_stores=0, accepted_cacops=0;
integer canceled_fetches=0, expected_cacops=0, smc=0, seed=1, zero_delay=0;
reg [31:0] rng=1;
wire inst_addr_ok = resetn && !ipending && rng[0];
wire inst_data_ok = resetn && ((ipending && idelay==0) || (zero_delay && inst_en && inst_addr_ok));
wire data_addr_ok = resetn && !dpending && rng[3];
wire data_data_ok = resetn && ((dpending && ddelay==0) || (zero_delay && data_en && data_addr_ok));
wire cacop_ready = resetn && !cpending && rng[6];
wire cacop_valid;
wire cacop_done = resetn && ((cpending && cdelay==0) || (zero_delay && cacop_valid && cacop_ready));
wire [4:0] cacop_code;
wire [31:0] cacop_addr;
reg [31:0] ca;
reg [4:0] cc;
reg [31:0] store_pc [0:255];
integer j;
cache_cpu dut(
    .clk(clk), .resetn(resetn), .hw_int_in(hw_int),
    .inst_addr_ok(inst_addr_ok), .inst_data_ok(inst_data_ok),
    .data_addr_ok(data_addr_ok), .data_data_ok(data_data_ok),
    .cacop_valid(cacop_valid), .cacop_code(cacop_code), .cacop_addr(cacop_addr),
    .cacop_ready(cacop_ready), .cacop_done(cacop_done),
    .inst_sram_en(inst_en), .inst_sram_we(inst_we), .inst_sram_addr(inst_addr),
    .inst_sram_wdata(inst_wdata), .inst_sram_rdata(inst_rdata),
    .data_sram_en(data_en), .data_sram_we(data_we), .data_sram_addr(data_addr),
    .data_sram_wdata(data_wdata), .data_sram_rdata(data_rdata),
    .debug_wb_pc(pc), .debug_wb_rf_we(we), .debug_wb_rf_wnum(rd), .debug_wb_rf_wdata(value)
);
always #5 clk = ~clk;
initial begin
    if (!$value$plusargs("ROM=%s",rom_file) || !$value$plusargs("EXPECT=%s",expect_file)
        || !$value$plusargs("FAULT=%h",fault_pc) || !$value$plusargs("EXCEPTIONS=%d",exp_exceptions)
        || !$value$plusargs("IRQ=%d",irq_mask) || !$value$plusargs("RESET=%d",reset_case)) begin
        $fatal(1,"missing test arguments");
    end
    if ($value$plusargs("SEED=%d",seed)) rng=seed;
    if ($value$plusargs("CACOPS=%d",expected_cacops)) begin end
    if ($value$plusargs("SMC=%d",smc)) begin end
    if ($value$plusargs("ZERO=%d",zero_delay)) begin end
    $readmemh(rom_file,rom);
    $readmemh(expect_file,expect_ram);
    for (i=0; i<256; i=i+1) begin
        ram[i]=0;
    end
    hw_int=irq_mask;
    repeat (5) @(negedge clk);
    resetn=1;
end
always @* begin
    inst_rdata = ipending ? rom[ia[11:2]] : rom[inst_addr[11:2]];
    data_rdata = dpending ? dr : ram[data_addr[9:2]];
end
always @(posedge clk) begin
    rng <= {rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    if (!resetn) begin
        ipending<=0; dpending<=0; cpending<=0;
        accepted_stores<=0; accepted_cacops<=0; canceled_fetches<=0;
    end else begin
        if (ipending && idelay>0) idelay<=idelay-1;
        if (dpending && ddelay>0) ddelay<=ddelay-1;
        if (cpending && cdelay>0) cdelay<=cdelay-1;
        if (inst_en && inst_addr_ok) begin
            if (inst_addr[1:0] || inst_addr<32'h1c000000 || inst_addr>=32'h1c001000)
                $fatal(1,"invalid instruction fetch escaped ADEF %h",inst_addr);
            ipending<=1; ia<=inst_addr; idelay<=2+rng[11:8];
        end
        if (inst_data_ok) begin
            ipending<=0;
            if (dut.u_if.discard || dut.wb_flush || dut.br_bus[32]) canceled_fetches<=canceled_fetches+1;
        end
        if (data_en && data_addr_ok) begin
            if (dut.u_exe.es_exception || dut.u_mem.ms_cancel || dut.wb_flush || dut.ms_busy || dut.ws_busy)
                $fatal(1,"fault/older instruction allowed RAM request");
            dpending<=1; da<=data_addr; dr<=ram[data_addr[9:2]]; ddelay<=3+rng[15:12];
            if (|data_we) begin
                for(j=0;j<accepted_stores;j=j+1)
                    if(store_pc[j]===dut.u_exe.es_pc) $fatal(1,"store duplicated pc=%h",dut.u_exe.es_pc);
                store_pc[accepted_stores]<=dut.u_exe.es_pc;
                accepted_stores<=accepted_stores+1;
            end
            for (lane=0; lane<4; lane=lane+1)
                if (data_we[lane]) ram[data_addr[9:2]][lane*8 +: 8] <= data_wdata[lane*8 +: 8];
        end
        if(data_data_ok) dpending<=0;
        if(cacop_valid && cacop_ready) begin
            if(dut.ms_busy || dut.ws_busy || dpending || accepted_cacops>=expected_cacops)
                $fatal(1,"CACOP not serialized or unexpected code %h",cacop_code);
            if(expected_cacops==6) begin
                case(accepted_cacops)
                    0: if(cacop_code!==0) $fatal(1,"CACOP code0");
                    1: if(cacop_code!==1) $fatal(1,"CACOP code1");
                    2: if(cacop_code!==8) $fatal(1,"CACOP code8");
                    3: if(cacop_code!==9) $fatal(1,"CACOP code9");
                    4: if(cacop_code!==16) $fatal(1,"CACOP code16");
                    5: if(cacop_code!==17) $fatal(1,"CACOP code17");
                endcase
                if(cacop_addr!==32'h120) $fatal(1,"CACOP sign-extended address %h",cacop_addr);
            end
            cpending<=1; ca<=cacop_addr; cc<=cacop_code; cdelay<=12+rng[19:16];
            accepted_cacops<=accepted_cacops+1;
        end
        if(cacop_done) begin
            cpending<=0;
            // Synthetic self-modifying-code model: I-hit invalidation makes the replacement visible.
            if(smc && (cpending ? cc : cacop_code)==5'h10) rom[cpending ? ca[11:2] : cacop_addr[11:2]]<=32'h02802c08; // addi.w r8,r0,11
        end
        if(dut.u_wb.ws_valid && dut.u_wb.sys_op[7] && |we) $fatal(1,"CACOP wrote GPR");
    end
end
always @(negedge clk) begin
    cycles=cycles+1;
    if (resetn && dut.u_wb.wb_ex) begin
        exceptions=exceptions+1;
        if (pc !== fault_pc) begin
            $fatal(1,"exception PC %h expected %h",pc,fault_pc);
        end
        hw_int=0;
    end
    if (resetn && pc==fault_pc && |we) begin
        $fatal(1,"faulting instruction wrote GPR");
    end
    if (reset_case && !reset_done && dut.u_wb.wb_ex) begin
        // Part 6: 在异常提交前复位，再从入口完整重跑，检查无旧现场/旧除法残留。
        resetn=0;
        repeat (4) @(negedge clk);
        for (i=0; i<256; i=i+1) begin
            ram[i]=0;
        end
        exceptions=0;
        hw_int=irq_mask;
        reset_done=1;
        resetn=1;
    end
    if (resetn && |we && rd==29 && value==32'h55a) begin
        if (exceptions != exp_exceptions) begin
            $fatal(1,"exception count=%0d expected=%0d",exceptions,exp_exceptions);
        end
        for (i=0; i<256; i=i+1) begin
            if (expect_ram[i] !== 32'hffffffff && ram[i] !== expect_ram[i]) begin
                $fatal(1,"RAM[%h]=%h expected=%h",i*4,ram[i],expect_ram[i]);
            end
        end
        if(accepted_cacops!=expected_cacops) $fatal(1,"CACOP count %d expected %d",accepted_cacops,expected_cacops);
        $display("PASS CPU handshake exceptions=%0d cycles=%0d stores=%0d cacops=%0d canceled_fetches=%0d reset=%0d",exceptions,cycles,accepted_stores,accepted_cacops,canceled_fetches,reset_case);
        $finish;
    end
    if (cycles>30000) begin
        $fatal(1,"control timeout pc=%h",pc);
    end
end
endmodule

// Deliberate stage-level fault injection: a canceled accepted response must not
// complete a younger load/CACOP. Architectural serialization normally prevents
// this overlap, but the external-port ownership is tested independently.
`include "mycpu_head.v"
module cpu_flush_drain_tb;
reg clk=0, reset=1, wb_flush=0;
reg ds_valid=0, addr_ok=0, data_ok=0, cache_ready=0, cache_done=0;
reg [31:0] rdata=0;
reg [`DS_TO_ES_BUS_WD-1:0] ds_bus=0;
wire allowin, to_mem, en, cv;
wire [3:0] we;
wire [31:0] addr,wd,ca;
wire [4:0] cc;
wire [`ES_TO_MS_BUS_WD-1:0] mb;
wire [`ES_TO_DS_BUS_WD-1:0] fb;
wire busy,system_op;
exe_stage dut(.clk(clk),.reset(reset),.wb_flush(wb_flush),.older_cancel(1'b0),.older_busy(1'b0),
 .es_busy(busy),.es_system(system_op),.ms_allowin(1'b1),.es_allowin(allowin),
 .ds_to_es_valid(ds_valid),.ds_to_es_bus(ds_bus),.es_to_ms_valid(to_mem),.es_to_ms_bus(mb),.es_to_ds_bus(fb),
 .data_sram_en(en),.data_sram_we(we),.data_sram_addr(addr),.data_sram_wdata(wd),
 .data_addr_ok(addr_ok),.data_data_ok(data_ok),.data_sram_rdata(rdata),
 .cacop_valid(cv),.cacop_code(cc),.cacop_addr(ca),.cacop_ready(cache_ready),.cacop_done(cache_done));
always #5 clk=~clk;
task launch;
 input [4:0] dest;
 input [31:0] address;
 input is_cache;
 begin
  @(negedge clk);
  if(!allowin) $fatal(1,"stage unable to accept test instruction");
  ds_bus=0;
  ds_bus[149:138]=1; ds_bus[137]=!is_cache; ds_bus[136]=!is_cache;
  ds_bus[134:130]=dest; ds_bus[129:98]=address; ds_bus[0]=1;
  ds_bus[`DS_TO_ES_BUS_WD-1]=is_cache;
  ds_valid=1;
  @(negedge clk);ds_valid=0;
 end
endtask
task flush;
 begin wb_flush=1;@(negedge clk);wb_flush=0;end
endtask
initial begin
 repeat(3) @(negedge clk);reset=0;
 launch(8,32'h100,0);
 if(!en) $fatal(1,"first load not requested");
 addr_ok=1;@(negedge clk);addr_ok=0;
 flush();
 launch(9,32'h104,0);
 if(en || to_mem) $fatal(1,"new load ignored outstanding canceled request");
 rdata=32'hdeadbeef;data_ok=1;@(negedge clk);data_ok=0;
 if(to_mem || dut.mem_done || !en) $fatal(1,"old response completed new load");
 // Immediately completing the first request after drain must override old killed=1.
 addr_ok=1;rdata=32'h12345678;data_ok=1;
 @(negedge clk);addr_ok=0;data_ok=0;
 if(!to_mem || mb[63:32]!==32'h12345678) $fatal(1,"new load response pairing failed");
 @(negedge clk);
 launch(16,32'h123,1);
 if(!cv || ca!==32'h123 || cc!==16) $fatal(1,"first CACOP request missing");
 cache_ready=1;@(negedge clk);cache_ready=0;
 flush();
 launch(17,32'h127,1);
 if(cv || to_mem) $fatal(1,"new CACOP ignored outstanding canceled operation");
 cache_done=1;@(negedge clk);cache_done=0;
 if(to_mem || dut.cache_done || !cv) $fatal(1,"old done completed new CACOP");
 cache_ready=1;cache_done=1;
 @(negedge clk);cache_ready=0;cache_done=0;
 if(!to_mem) $fatal(1,"new CACOP never completed");
 $display("PASS EXE accepted-load/CACOP flush-drain ownership");$finish;
end
initial begin #10000;$fatal(1,"stage drain timeout");end
endmodule
