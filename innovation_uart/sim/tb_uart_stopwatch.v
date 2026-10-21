`timescale 1ns / 1ps
// 创新扩展：CPU真实执行命令程序，串行解码响应，验证外设及错误恢复。
module tb_uart_stopwatch #(parameter HARDWARE_CLOCK=1'b0);
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
                $display("UART_STOPWATCH_FAIL: %0s pc=%h index=%0d", message, dut.debug_wb_pc, read_index);
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
        begin cases=cases+1; $display("UART_STOPWATCH_CASE_PASS: %0s",name); end
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

    // Independent scoreboard: observe timer samples and software writes, never alter CPU registers/results.
    reg model_running=0;
    reg [31:0] model_last_tick=0;
    reg [63:0] model_ticks=0;
    reg [31:0] model_delta=0;
    reg [31:0] snapshot_low=0;
    reg [63:0] snapshot_ticks=0;
    reg [63:0] parsed_ms=0;
    reg [63:0] saved_ms=0;
    reg [63:0] saved_ticks=0;
    always @(posedge dut.cpu_clk) begin
        if(!resetn) begin model_running=0; model_last_tick=0; model_ticks=0; end
        else begin
            model_running=(dut.cpu.u_id_stage.u_regfile.rf[29]!=0);
            if(dut.cpu_data_en && dut.cpu_data_we==4'hf) begin
                if(dut.cpu_data_addr==32'h1100) begin
                    if(model_running) begin
                        model_delta=dut.cpu_data_wdata-model_last_tick;
                        model_ticks=model_ticks+{32'b0,model_delta};
                    end
                    model_last_tick=dut.cpu_data_wdata;
                end
                if(dut.cpu_data_addr==32'h1120) snapshot_low=dut.cpu_data_wdata;
                if(dut.cpu_data_addr==32'h1124) begin
                    snapshot_ticks={dut.cpu_data_wdata,snapshot_low};
                    check(snapshot_ticks===model_ticks,"64-bit accumulated ticks match independent arithmetic");
                end
            end
        end
    end

    task query_time;
        reg [7:0] value;
        reg [63:0] seconds;
        reg [63:0] milliseconds;
        integer digits;
        integer n;
        begin
            send_text("TIME\n");
            expect_text("TIME=");
            take_byte(value);
            seconds=0; digits=0;
            while(value!=".") begin
                check(value>="0" && value<="9","seconds are unsigned decimal");
                seconds=seconds*10+(value-8'h30);
                digits=digits+1;
                check(digits<=20,"decimal conversion terminates");
                take_byte(value);
            end
            check(digits>0,"at least one seconds digit");
            milliseconds=0;
            for(n=0;n<3;n=n+1) begin
                take_byte(value);
                check(value>="0" && value<="9","exactly three millisecond digits");
                milliseconds=milliseconds*10+(value-8'h30);
            end
            expect_text(" s\015\n");
            parsed_ms=seconds*1000+milliseconds;
            check(parsed_ms==snapshot_ticks/50000,"TIME decimal milliseconds match captured 50 MHz ticks");
        end
    endtask

    initial begin
        repeat(100) @(negedge clk); resetn=1;
        expect_text("UART CONSOLE READY\015\n");
        query_time;
        check(parsed_ms==0,"TIME is initially zero and stopped");
        accepted_case("initial TIME=0.000 s");
        send_text("STOP\n"); expect_text("OK\015\n");
        query_time;
        check(parsed_ms==0,"STOP before START is harmless");
        accepted_case("STOP is idempotent before START");
        send_text("START\n"); expect_text("OK\015\n");
        check(dut.cpu.u_id_stage.u_regfile.rf[29]==1,"START enables stopwatch");
        #5000000;
        query_time;
        check(parsed_ms>=5,"running stopwatch counts real peripheral ticks");
        saved_ms=parsed_ms;
        #3000000;
        query_time;
        check(parsed_ms>saved_ms,"TIME advances while running");
        accepted_case("START and repeated running TIME");

        // Test-only stimulus to the peripheral counter: let it wrap naturally after seeding near its limit.
        // CPU, software state, data RAM results and timer read bus are never forced.
        @(negedge clk); dut.u_confreg.timer=32'hffff0000;
        #2000000;
        query_time;
        check(parsed_ms>80000,"original 32-bit timer wrap does not zero stopwatch");
        accepted_case("32-bit peripheral counter rollover");
        @(negedge clk); dut.u_confreg.timer=32'hffff0000;
        #2000000;
        query_time;
        check(snapshot_ticks[63:32]!=0,"elapsed ticks carry into high 32 bits");
        check(parsed_ms>85000,"longer than original 85.9-second counter period");
        accepted_case("64-bit accumulation and decimal conversion");

        send_text("STOP\n"); expect_text("OK\015\n");
        check(dut.cpu.u_id_stage.u_regfile.rf[29]==0,"STOP disables accumulation");
        saved_ticks=model_ticks;
        query_time; saved_ms=parsed_ms;
        #2000000;
        @(negedge clk); dut.u_confreg.timer=32'h12345678;
        query_time;
        check(parsed_ms==saved_ms && snapshot_ticks==saved_ticks,"STOP freezes result despite timer continuing");
        send_text("STOP\n"); expect_text("OK\015\n");
        query_time;
        check(parsed_ms==saved_ms,"repeated STOP preserves result");
        accepted_case("STOP freezes repeated TIME queries");

        send_text("START\n"); expect_text("OK\015\n");
        check(dut.cpu.u_id_stage.u_regfile.rf[29]==1,"START resumes stopped stopwatch");
        #2000000;
        query_time;
        check(parsed_ms>saved_ms,"resumed time preserves saved elapsed value");
        check(parsed_ms-saved_ms<500,"paused timer jump must not count toward resumed time");
        accepted_case("START resumes elapsed time and excludes paused interval");

        send_text("RESET\n"); expect_text("OK\015\n"); model_ticks=0;
        check(dut.cpu.u_id_stage.u_regfile.rf[29]==0,"RESET leaves stopwatch stopped");
        query_time;
        check(parsed_ms==0 && snapshot_ticks==0,"RESET clears elapsed time");
        #1000000;
        query_time; check(parsed_ms==0,"RESET remains stopped");
        accepted_case("RESET clears and stops");

        send_text("START\n"); expect_text("OK\015\n");
        #20000000;
        query_time; saved_ms=parsed_ms; saved_ticks=snapshot_ticks;
        send_text("START\n"); expect_text("OK\015\n");
        #2000000;
        query_time;
        check(snapshot_ticks>saved_ticks && parsed_ms>saved_ms,"START while running preserves and continues elapsed time");
        accepted_case("repeated START while running never clears elapsed time");

        send_text("START X\n"); expect_text("ERR\015\n");
        send_text("STOP X\n"); expect_text("ERR\015\n");
        send_text("RESET X\n"); expect_text("ERR\015\n");
        send_text("TIME X\n"); expect_text("ERR\015\n");
        check(dut.cpu.u_id_stage.u_regfile.rf[29]==1,"invalid stopwatch commands cannot change running state");
        accepted_case("arguments rejected without state changes");
        send_text("RESET\n"); expect_text("OK\015\n"); model_ticks=0;
        query_time; check(parsed_ms==0,"RESET also clears an actively running stopwatch");
        accepted_case("RESET while running");

        check(!dut.u_confreg.uart_rx_overrun && !dut.u_confreg.uart_rx_frame_error,"no serial errors");
        wait(!dut.u_confreg.uart_tx_busy);
        repeat(100) @(posedge dut.cpu_clk);
        check(read_index==received_count,"all responses consumed exactly once");
        test_end=1;
        $display("UART_STOPWATCH_PASS: hardware_clock=%0d cases=%0d checks=%0d",HARDWARE_CLOCK,cases,checks);
        #200; $finish;
    end
    initial begin #2000000000; global_err=1; $display("UART_STOPWATCH_FAIL: timeout pc=%h",dut.debug_wb_pc); $finish; end
endmodule

module tb_uart_stopwatch_hwclk;
    tb_uart_stopwatch #(.HARDWARE_CLOCK(1'b1)) test();
endmodule
