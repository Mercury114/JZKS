`timescale 1ns / 1ps
// 创新扩展：CPU真实执行命令程序，串行解码响应，验证外设及错误恢复。
module tb_uart_irq #(parameter HARDWARE_CLOCK=1'b0);
    localparam integer UART_DIV = HARDWARE_CLOCK ? 326 : 64;
    localparam integer BIT_NS = HARDWARE_CLOCK ? 104167 : UART_DIV*20;
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0;
    reg uart_rx=1;
    wire uart_tx;
    wire [15:0] led;
    wire [15:0] web_led=~led;
    wire [31:0] num_data;
    reg [7:0] web_switch=8'h5a;
    wire [7:0] local_switch=~web_switch;
    integer checks=0;
    integer cases=0;
    integer received_count=0;
    integer read_index=0;
    integer i;
    reg [7:0] transcript[0:4095];
    reg test_end=0;
    reg global_err=0;
    reg [31:0] timer_sample=0;
    reg [31:0] first_timer=0;
    reg [31:0] decoded_hex=0;
    soc_lite_top #(.SIMULATION(!HARDWARE_CLOCK), .UART_CLKS_PER_BIT(UART_DIV)) dut (
        .clk(clk), .resetn(resetn), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .led(led), .num_data(num_data), .led_rg0(), .led_rg1(),
        .num_csn(), .num_a_g(), .switch(local_switch),
        .btn_key_col(), .btn_key_row(4'b0), .btn_step(2'b11)
    );
    always @(posedge dut.cpu_clk)
        if(dut.conf_en && !(|dut.conf_we) && dut.conf_addr==32'hbfafe000)
            timer_sample=dut.u_confreg.timer_r2;

    task check;
        input condition;
        input [8*120-1:0] message;
        begin
            if(condition !== 1'b1) begin
                global_err=1;
                $display("UART_IRQ_FAIL: %0s pc=%h index=%0d", message, dut.debug_wb_pc, read_index);
                $finish;
            end
            checks=checks+1;
        end
    endtask
    function integer text_length;
        input [8*256-1:0] text;
        integer n;
        begin
            text_length=0;
            for(n=0;n<256;n=n+1) if(text[n*8+:8]!=0) text_length=n+1;
        end
    endfunction
    task send_byte;
        input [7:0] value;
        integer b;
        begin
            @(negedge clk); #3; uart_rx=0;
            #(BIT_NS);
            for(b=0;b<8;b=b+1) begin uart_rx=value[b]; #(BIT_NS); end
            uart_rx=1; #(BIT_NS);
        end
    endtask
    task send_text;
        input [8*256-1:0] text;
        integer n;
        begin for(n=text_length(text)-1;n>=0;n=n-1) send_byte(text[n*8+:8]); end
    endtask
    task take_byte;
        output [7:0] value;
        begin
            wait(received_count>read_index);
            value=transcript[read_index];
            read_index=read_index+1;
        end
    endtask
    task expect_text;
        input [8*256-1:0] text;
        integer n;
        reg [7:0] actual;
        begin
            for(n=text_length(text)-1;n>=0;n=n-1) begin
                take_byte(actual);
                if(actual!==text[n*8+:8]) begin
                    $display("UART_RESPONSE_MISMATCH: got=%h expected=%h text=%0s",actual,text[n*8+:8],text);
                    check(1'b0,"serial response mismatch");
                end
            end
            checks=checks+1;
        end
    endtask
    task receive_hex8;
        integer n;
        reg [7:0] value;
        reg [3:0] digit;
        begin
            decoded_hex=0;
            for(n=0;n<8;n=n+1) begin
                take_byte(value);
                check((value>=8'h30 && value<=8'h39)||(value>=8'h41 && value<=8'h46),"hex response digit");
                digit=value<=8'h39 ? value-8'h30 : value-8'h37;
                decoded_hex={decoded_hex[27:0],digit};
            end
        end
    endtask
    task accepted_case;
        input [8*80-1:0] name;
        begin cases=cases+1; $display("UART_IRQ_CASE_PASS: %0s",name); end
    endtask
    // 独立监听所有TX字节，命令发送期间也不会漏掉响应。
    initial begin: tx_monitor
        reg [7:0] value;
        integer b;
        forever begin
            @(negedge uart_tx);
            #(BIT_NS/2);
            check(uart_tx===1'b0,"TX start bit");
            for(b=0;b<8;b=b+1) begin #(BIT_NS); value[b]=uart_tx; end
            #(BIT_NS);
            check(uart_tx===1'b1,"TX stop bit");
            check(received_count<4096,"transcript capacity");
            transcript[received_count]=value;
            received_count=received_count+1;
        end
    end

    // 创新扩展：观察真实CPU异常入口、ERA、清中断和ERTN，独立核对寄存器现场。
    reg in_handler=0;
    integer entries=0;
    integer returns=0;
    integer model_count=0;
    integer count_snapshot=0;
    integer saved_count=0;
    integer saved_entries=0;
    integer timer_cycles=0;
    integer last_expiry=0;
    integer regular_periods=0;
    integer register_index;
    reg [31:0] saved_rf[0:31];
    reg [31:0] interrupted_pc;
    reg [31:0] interrupted_crmd;
    reg [15:0] saved_led;
    reg accelerate_hw=0;
    always @(posedge dut.cpu_clk) begin
        timer_cycles=timer_cycles+1;
        if(dut.cpu_resetn) begin
            if(dut.cpu.csr_tcfg[0] && dut.cpu.timer_cnt==0) begin
                if(last_expiry!=0 && !HARDWARE_CLOCK) begin
                    check(timer_cycles-last_expiry==25001,"periodic timer expires every configured N+1 CPU clocks");
                    regular_periods=regular_periods+1;
                end
                last_expiry=timer_cycles;
            end
            if(!dut.cpu.csr_tcfg[0]) last_expiry=0;
            if(dut.cpu.interrupt_redirect) begin
                check(!in_handler,"interrupt is not nested while global IE is cleared");
                check(dut.cpu.csr_estat[11] && dut.cpu.csr_ecfg[11],"timer pending and timer interrupt mask enabled");
                in_handler=1;
                entries=entries+1;
                check(dut.cpu.id_valid && !dut.cpu.pipeline_busy,"IRQ is accepted at a precise drained ID boundary");
                interrupted_pc=dut.cpu.id_pc;
                interrupted_crmd=dut.cpu.csr_crmd;
                for(register_index=0;register_index<32;register_index=register_index+1)
                    saved_rf[register_index]=dut.cpu.u_id_stage.u_regfile.rf[register_index];
            end
            if(in_handler && dut.cpu_data_en && dut.cpu_data_we==4'hf && dut.cpu_data_addr==32'hbfaff100)
                check(1'b0,"ISR must not perform blocking UART output");
            if(dut.cpu_data_en && dut.cpu_data_we==4'hf && dut.cpu_data_addr==32'h1160) begin
                if(in_handler) begin
                    check(dut.cpu_data_wdata==model_count+1,"each ISR increments software IRQ counter exactly once");
                    model_count=model_count+1;
                end else begin
                    check(dut.cpu_data_wdata==0,"only initialization or IRQ ON may reset IRQ counter");
                    model_count=0;
                end
            end
            if(!in_handler && dut.cpu_data_en && !(|dut.cpu_data_we) && dut.cpu_data_addr==32'h1160)
                count_snapshot=model_count;
            if(in_handler && dut.cpu_data_en && dut.cpu_data_we==4'hf && dut.cpu_data_addr==32'hbfaff020)
                check(dut.cpu_data_wdata==(model_count[0] ? 32'h00000000 : 32'hffffffff),"LED output toggles inside real interrupt handler");
            if(in_handler && dut.cpu.state==4'd2 && dut.cpu.inst_ertn) begin
                check(dut.cpu.csr_crmd[2]==0,"global IE is disabled inside handler");
                check(dut.cpu.csr_era===interrupted_pc,"ERA preserves interrupted instruction address");
                check(!dut.cpu.csr_estat[11],"TICLR clears pending before ERTN");
                check(dut.cpu.csr_prmd[2:0]===interrupted_crmd[2:0],"PRMD preserves previous privilege and IE");
                for(register_index=1;register_index<32;register_index=register_index+1)
                    check(dut.cpu.u_id_stage.u_regfile.rf[register_index]===saved_rf[register_index],"all general registers including SP restored before ERTN");
                returns=returns+1;
                in_handler=0;
                #1;
                check(dut.cpu.pc===interrupted_pc && dut.cpu.csr_crmd[2]===1'b1,"ERTN resumes original PC and restores IE");
            end
        end
    end

    // Hardware-mode boundary stimulus only advances the hardware timer toward expiry.
    // It never changes PC, CSR masks/control, CPU registers, software counter or LED data.
    // TCFG is still configured by the actual firmware for 0.5 seconds at 3.125MHz.
    always @(negedge dut.cpu_clk)
        if(HARDWARE_CLOCK && accelerate_hw && dut.cpu.csr_tcfg[0] && dut.cpu.timer_cnt>2000)
            dut.cpu.timer_cnt=1000;

    task query_count;
        begin
            send_text("IRQ COUNT\n");
            expect_text("IRQ_COUNT=0x");
            receive_hex8;
            expect_text("\015\n");
            check(decoded_hex==count_snapshot,"serial IRQ COUNT equals atomic software counter snapshot");
        end
    endtask

    initial begin
        repeat(100) @(negedge clk); resetn=1;
        expect_text("UART CONSOLE READY\015\n");
        check(dut.cpu.csr_eentry==32'h1c001000,"aligned EENTRY configured by firmware");
        check(dut.cpu.csr_ecfg==32'h800 && !dut.cpu.csr_crmd[2],"only timer mask enabled; IRQ disabled at boot");
        query_count;
        check(decoded_hex==0 && entries==0,"no IRQ or LED blinking until IRQ ON");
        accepted_case("boot and zero IRQ count");

        send_text("IRQ\n"); expect_text("ERR\015\n");
        send_text("IRQ ON X\n"); expect_text("ERR\015\n");
        send_text("IRQ OFF X\n"); expect_text("ERR\015\n");
        send_text("IRQ COUNT X\n"); expect_text("ERR\015\n");
        send_text("IRQ BOGUS\n"); expect_text("ERR\015\n");
        check(!dut.cpu.csr_tcfg[0],"invalid IRQ arguments have no side effects");
        accepted_case("invalid IRQ commands rejected");

        send_text("IRQ ON\n"); expect_text("OK\015\n");
        check(dut.cpu.csr_tcfg==(HARDWARE_CLOCK ? 32'd1562503 : 32'd25003),"real hardware and accelerated simulation timer configuration");
        check(dut.cpu.csr_crmd[2] && dut.cpu.u_id_stage.u_regfile.rf[25]==0,"IRQ ON enables IE and exits MIRROR");
        if(HARDWARE_CLOCK) begin
            @(negedge dut.cpu_clk);
            saved_count=dut.cpu.timer_cnt;
            repeat(100) @(negedge dut.cpu_clk);
            check(dut.cpu.timer_cnt==saved_count-100,"actual hardware timer decrements once per CPU clock");
            accelerate_hw=1;
        end
        wait(returns>=3);
        check(entries==returns,"each observed interrupt returns normally");
        if(!HARDWARE_CLOCK) check(regular_periods>=2,"periodic reload verified without timer forcing");
        accepted_case("periodic timer invokes handler and toggles LEDs");

        saved_count=model_count;
        send_text("irq on\n"); expect_text("OK\015\n");
        check(model_count>=saved_count,"repeated IRQ ON does not reset count");
        query_count;
        accepted_case("idempotent ON and live counter query");

        send_text("CODE A\n"); expect_text("ASCII=0x41\015\n");
        check(num_data==32'h41 && dut.cpu.csr_tcfg[0],"ASCII query works while IRQ blinking continues");
        send_text("DISP 3A\n"); expect_text("OK\015\n");
        check(num_data==32'h3a && dut.cpu.csr_tcfg[0],"display command does not stop independent LED blinking");
        send_text("SW\n"); expect_text("SW=0x5A\015\n");
        accepted_case("ASCII display and switch commands coexist with IRQ");

        send_text("START\n"); expect_text("OK\015\n");
        #2000000;
        send_text("TIME\n"); expect_text("TIME=");
        begin: discard_time
            reg [7:0] value;
            value=0;
            while(value!=10) take_byte(value);
        end
        send_text("STOP\n"); expect_text("OK\015\n");
        check(dut.cpu.u_id_stage.u_regfile.rf[29]==0 && dut.cpu.csr_tcfg[0],"stopwatch STOP does not disable independent IRQ timer");
        send_text("RESET\n"); expect_text("OK\015\n");
        send_text("TIME\n"); expect_text("TIME=0.000 s\015\n");
        check(dut.cpu.csr_tcfg[0],"stopwatch RESET does not stop IRQ");
        accepted_case("stopwatch and UART formatting survive asynchronous interrupts");

        send_text("IRQ OFF\n"); expect_text("OK\015\n");
        check(!dut.cpu.csr_tcfg[0] && !dut.cpu.csr_crmd[2] && !dut.cpu.csr_estat[11],"OFF disables timer and IE and clears pending");
        saved_count=model_count; saved_entries=entries; saved_led=web_led;
        #2000000;
        query_count;
        check(decoded_hex==saved_count && entries==saved_entries && web_led==saved_led,"OFF freezes count and final LED state");
        send_text("IRQ OFF\n"); expect_text("OK\015\n");
        accepted_case("OFF freezes LEDs and count and is idempotent");

        send_text("IRQ ON\n"); expect_text("OK\015\n");
        send_text("LED 00FF\n"); expect_text("OK\015\n");
        saved_entries=entries;
        #2000000;
        check(web_led==16'h00ff && !dut.cpu.csr_tcfg[0] && entries==saved_entries,"manual LED takes ownership without later ISR overwrites");
        accepted_case("manual LED command stops blink atomically");

        send_text("IRQ ON\n"); expect_text("OK\015\n");
        send_text("LED GG\n"); expect_text("ERR\015\n");
        check(dut.cpu.csr_tcfg[0],"invalid manual command must not stop blinking");
        send_text("MIRROR ON\n"); expect_text("OK\015\n");
        web_switch=8'h3c;
        repeat(300) @(negedge dut.cpu_clk);
        check(web_led==16'h003c && num_data==32'h3c && !dut.cpu.csr_tcfg[0],"MIRROR stops IRQ and follows switches");
        send_text("IRQ ON\n"); expect_text("OK\015\n");
        check(dut.cpu.u_id_stage.u_regfile.rf[25]==0 && dut.cpu.csr_tcfg[0],"IRQ ON takes ownership back from MIRROR");
        accepted_case("MIRROR and IRQ ownership and invalid command behavior");

        send_text("IRQ OFF\n"); expect_text("OK\015\n");
        send_text("CODE a\n"); expect_text("ASCII=0x61\015\n");
        check(num_data==32'h61 && entries==returns,"foreground resumes after every interrupt");
        check(!dut.u_confreg.uart_rx_overrun && !dut.u_confreg.uart_rx_frame_error,"no UART overflow or framing errors during IRQ activity");
        wait(!dut.u_confreg.uart_tx_busy);
        repeat(100) @(negedge dut.cpu_clk);
        check(read_index==received_count && dut.u_confreg.uart_rx_count==0,"all UART responses and input consumed exactly once");
        accepted_case("complete interrupt and foreground recovery");
        test_end=1;
        $display("UART_IRQ_PASS: hardware_clock=%0d cases=%0d checks=%0d entries=%0d returns=%0d",HARDWARE_CLOCK,cases,checks,entries,returns);
        #200; $finish;
    end
    initial begin #1000000000; global_err=1; $display("UART_IRQ_FAIL: timeout pc=%h state=%h",dut.cpu.pc,dut.cpu.state); $finish; end
endmodule

module tb_uart_irq_hwclk;
    tb_uart_irq #(.HARDWARE_CLOCK(1'b1)) test();
endmodule
