`timescale 1ns/1ps
// UART IRQ regression: architectural CSR values and precise pipeline boundaries.
module tb_pipeline_control;
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0;
    wire inst_en, data_en;
    wire [3:0] inst_we, data_we;
    wire [31:0] inst_addr, inst_wdata, data_addr, data_wdata;
    reg [31:0] inst_rdata=0, data_rdata=0;
    reg [31:0] rom[0:1023];
    reg [31:0] mem[0:4095];
    integer test_case;
    integer i;
    integer checks=0;
    integer entries=0;
    integer returns=0;
    integer count=0;
    integer iterations=0;
    integer completed_iterations=0;
    reg armed=0;
    reg in_handler=0;
    reg [31:0] saved_pc;
    reg [31:0] saved_rf[1:31];
    mycpu_top dut(.clk(clk),.resetn(resetn),
        .inst_sram_en(inst_en),.inst_sram_we(inst_we),.inst_sram_addr(inst_addr),
        .inst_sram_wdata(inst_wdata),.inst_sram_rdata(inst_rdata),
        .data_sram_en(data_en),.data_sram_we(data_we),.data_sram_addr(data_addr),
        .data_sram_wdata(data_wdata),.data_sram_rdata(data_rdata),
        .debug_wb_pc(),.debug_wb_rf_we(),.debug_wb_rf_wnum(),.debug_wb_rf_wdata());
    task check;
        input condition;
        input [8*120-1:0] message;
        begin
            if(condition!==1'b1) begin
                $display("PIPELINE_CONTROL_FAIL: case=%0d %0s idpc=%h era=%h entries=%0d returns=%0d",test_case,message,dut.id_pc,dut.csr_era,entries,returns);
                $display("CSR_RESULTS: %h %h %h %h %h %h tid=%h",mem['h100/4],mem['h104/4],mem['h108/4],mem['h10c/4],mem['h110/4],mem['h114/4],dut.csr_tid);
                $fatal(1);
            end
            checks=checks+1;
        end
    endtask
    task csr_checks;
        begin
            check(mem['h100/4]===32'h0,"CSRWR returns old value with no encoded immediate added");
            check(mem['h104/4]===32'h12345678,"CSRRD returns exact CSR value");
            check(mem['h108/4]===32'h12345678,"CSRXCHG returns old CSR instead of GPR mask");
            check(mem['h10c/4]===32'h12cd5601,"CSRXCHG applies mask and value correctly");
            check(mem['h110/4]===32'h76543210,"load-dependent CSRWR waits for source and returns old CSR");
            check(mem['h114/4]===32'h0,"CSRWR rd=zero still clears CSR");
        end
    endtask
    always @(posedge clk) begin
        if(inst_en) inst_rdata<=rom[inst_addr[11:2]];
        if(data_en) begin
            if(data_we[0]) mem[data_addr[13:2]][7:0]<=data_wdata[7:0];
            if(data_we[1]) mem[data_addr[13:2]][15:8]<=data_wdata[15:8];
            if(data_we[2]) mem[data_addr[13:2]][23:16]<=data_wdata[23:16];
            if(data_we[3]) mem[data_addr[13:2]][31:24]<=data_wdata[31:24];
            data_rdata<=mem[data_addr[13:2]];
        end
        if(resetn) begin
            if(dut.interrupt_redirect) begin
                check(!in_handler,"no nested interrupts");
                check(dut.id_valid && !dut.es_to_ms_valid && !dut.ms_hazard_valid,"all older pipeline side effects committed before IRQ entry");
                in_handler=1; entries=entries+1; saved_pc=dut.id_pc;
                for(i=1;i<32;i=i+1) saved_rf[i]=dut.u_id_stage.u_regfile.rf[i];
            end
            if(dut.id_exception) check(1'b0,"no unexpected synchronous exceptions");
            if(dut.id_ertn) begin
                check(in_handler,"ERTN belongs to a real IRQ");
                check(dut.csr_era===saved_pc,"ERA is exact held instruction PC");
                check(!dut.csr_estat[11],"pending timer interrupt acknowledged");
                for(i=1;i<32;i=i+1)
                    check(dut.u_id_stage.u_regfile.rf[i]===saved_rf[i],"ERTN waits until every register including SP is restored");
                in_handler=0; returns=returns+1;
            end
            if(data_en && data_we==4'hf) begin
                if(data_addr==32'h120) armed=1;
                if(test_case==1 && armed) begin
                    if(data_addr==32'h100) begin
                        check(!in_handler && data_wdata==iterations+1,"foreground increment/store never skipped or repeated by IRQ");
                        iterations=iterations+1;
                    end
                    if(data_addr==32'h104) begin
                        check(!in_handler && data_wdata==iterations+7,"single synchronous load and immediate consumer are correct");
                        completed_iterations=completed_iterations+1;
                    end
                    if(data_addr==32'h110) begin
                        check(in_handler && data_wdata==count+1,"one original single-load counter increment per IRQ");
                        count=count+1;
                    end
                end
                if(test_case==0 && data_addr==32'h3fc) begin
                    #1; csr_checks;
                    $display("PIPELINE_CONTROL_PASS: case=csr checks=%0d",checks); $finish;
                end
            end
            if(test_case==1 && returns>=32 && !in_handler && completed_iterations>=100) begin
                check(entries==returns && count==entries,"all IRQs serviced once and returned");
                $display("PIPELINE_CONTROL_PASS: case=irq checks=%0d entries=%0d returns=%0d iterations=%0d",checks,entries,returns,completed_iterations);
                $finish;
            end
        end
    end
    initial begin
        if(!$value$plusargs("CASE=%d",test_case)) test_case=0;
        for(i=0;i<4096;i=i+1) mem[i]=0;
        $readmemh("control.hex",rom);
        repeat(5) @(negedge clk); resetn=1;
        #2000000; check(1'b0,"test timeout");
    end
endmodule
