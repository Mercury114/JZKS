`timescale 1ns / 1ps
// 创新扩展：CPU真实执行命令程序，串行解码响应，验证外设及错误恢复。
module tb_uart_console #(parameter HARDWARE_CLOCK=1'b0);
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
                $display("UART_CONSOLE_FAIL: %0s pc=%h index=%0d", message, dut.debug_wb_pc, read_index);
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
        begin cases=cases+1; $display("UART_COMMAND_PASS: %0s",name); end
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
    initial begin
        repeat(100) @(negedge clk); resetn=1;
        expect_text("UART CONSOLE READY\015\n");
        accepted_case("boot uses initialized data RAM strings");
        if(!HARDWARE_CLOCK) begin
            // HELP输出时继续发送下一命令，真正验证FIFO缓存而非逐字节等待。
            send_text("HELP\nLED 00FF\n");
            expect_text("HELP CODE <char> LED <hex> DISP <hex> SW START STOP TIME RESET STAT MIRROR ON|OFF IRQ ON|OFF|COUNT\015\n");
            expect_text("OK\015\n");
            check(web_led===16'h00ff,"LED positive logic matches webpage");
            accepted_case("HELP plus queued LED command through FIFO");
        end else begin
            send_text("LED 00FF\n"); expect_text("OK\015\n");
            check(web_led===16'h00ff,"hardware clock LED command");
            accepted_case("hardware-clock LED command");
        end
        send_text("DISP 3A\015\n"); expect_text("OK\015\n");
        check(num_data===32'h3a,"DISP and CRLF handling");
        accepted_case("DISP with CRLF");
        send_text("CODE A\n"); expect_text("ASCII=0x41\015\n");
        check(num_data===32'h41,"CODE updates display");
        accepted_case("CODE A and ASCII display");
        send_text("SW\n"); expect_text("SW=0x5A\015\n");
        accepted_case("SW webpage polarity");
        send_text("TIME\n"); expect_text("TIME=0.000 s\015\n");
        accepted_case("TIME is zero until START");
        send_text("MIRROR ON\n"); expect_text("OK\015\n");
        repeat(200) @(posedge dut.cpu_clk);
        check(web_led===16'h005a && num_data===32'h5a,"MIRROR initial outputs");
        web_switch=8'h3c;
        repeat(200) @(posedge dut.cpu_clk);
        check(web_led===16'h003c && num_data===32'h3c,"MIRROR follows switch changes");
        accepted_case("MIRROR input-to-output interaction");
        send_text("MIRROR OFF\n"); expect_text("OK\015\n");
        web_switch=8'ha5;
        repeat(200) @(posedge dut.cpu_clk);
        check(web_led===16'h003c && num_data===32'h3c,"MIRROR OFF holds outputs");
        accepted_case("MIRROR OFF");
        if(!HARDWARE_CLOCK) begin
            send_text("code a\015"); expect_text("ASCII=0x61\015\n");
            check(num_data==32'h61,"CODE argument retains case");
            accepted_case("case-insensitive command with lowercase argument");
            send_text("Z\n"); expect_text("ASCII=0x5A\015\n");
            accepted_case("single-character ASCII shortcut");
            send_text("  led 0xabcd \n"); expect_text("OK\015\n");
            check(web_led===16'habcd,"hex prefix, lowercase and whitespace");
            accepted_case("hex and whitespace parsing");
            send_text("DISP 3X\010A\n"); expect_text("OK\015\n");
            check(num_data==32'h3a,"backspace edits command");
            accepted_case("backspace editing");
            send_text("BOGUS\n"); expect_text("ERR\015\n");
            send_text("LED 10000\n"); expect_text("ERR\015\n");
            check(web_led===16'habcd,"invalid LED cannot alter output");
            send_text("DISP 100\n"); expect_text("ERR\015\n");
            send_text("DISP GG\n"); expect_text("ERR\015\n");
            check(num_data===32'h3a,"invalid DISP cannot alter output");
            send_text("HELP X\n"); expect_text("ERR\015\n");
            send_text("CODE AB\n"); expect_text("ERR\015\n");
            send_text("MIRROR ONX\n"); expect_text("ERR\015\n");
            accepted_case("unknown command, bad arguments and overflow rejected");
            for(i=0;i<64;i=i+1) send_byte("X");
            send_byte(10); expect_text("ERR LINE TOO LONG\015\n");
            send_text("sw\n"); expect_text("SW=0xA5\015\n");
            accepted_case("long-line recovery");
            send_text("STAT\n"); expect_text("STATUS=0x00000000\015\n");
            accepted_case("FIFO status register exposed to CPU");
            send_text("TIME\n"); expect_text("TIME=0.000 s\015\n");
            accepted_case("stopped stopwatch remains zero");
            send_text("MIRROR ON\n"); expect_text("OK\015\n");
            send_text("LED 0F0F\n"); expect_text("OK\015\n");
            web_switch=8'hf0;
            repeat(200) @(posedge dut.cpu_clk);
            check(web_led===16'h0f0f,"manual LED command exits MIRROR mode");
            accepted_case("manual output command exits MIRROR");
        end
        check(!dut.u_confreg.uart_rx_overrun && !dut.u_confreg.uart_rx_frame_error,"no UART errors");
        wait(!dut.u_confreg.uart_tx_busy);
        repeat(100) @(posedge dut.cpu_clk);
        check(read_index==received_count,"no duplicate CRLF responses");
        check(dut.u_confreg.uart_rx_count==0,"CPU drained receive FIFO");
        test_end=1;
        $display("UART_CONSOLE_PASS: hardware_clock=%0d cases=%0d checks=%0d",HARDWARE_CLOCK,cases,checks);
        #200; $finish;
    end
    initial begin #500000000; global_err=1; $display("UART_CONSOLE_FAIL: timeout pc=%h",dut.debug_wb_pc); $finish; end
endmodule

module tb_uart_console_hwclk;
    tb_uart_console #(.HARDWARE_CLOCK(1'b1)) test();
endmodule
