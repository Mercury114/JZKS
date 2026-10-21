`timescale 1ns / 1ps

// 创新扩展：UART，使用仓库原版 CPU、实际 RAM IP 和 UART 程序进行系统自检。
module tb_uart_soc #(parameter USE_HARDWARE_CLOCK=1'b0);
    // 创新扩展：UART，同时支持快速仿真和原 SoC 的硬件 /16 时钟路径。
    localparam integer CLKS_PER_BIT = USE_HARDWARE_CLOCK ? 326 : 5208;
    // 创新扩展：UART，硬件模式按网页9600波特率发/收，验证取整误差也可正常通信。
    localparam integer BIT_TIME_NS = USE_HARDWARE_CLOCK ? 104167 : CLKS_PER_BIT * 20;

    reg clk = 1'b0;
    always #10 clk = ~clk;  // 创新扩展：UART，50 MHz，与当前上板 cpu_clk 一致。
    reg resetn = 1'b0;
    reg uart_rx = 1'b1;
    wire uart_tx;
    wire [15:0] led;
    wire [31:0] num_data;
    integer checks = 0;
    integer passed_chars = 0;
    reg [7:0] expected_char = 0;
    reg [7:0] echoed_char = 0;
    reg test_end = 1'b0;
    reg global_err = 1'b0;

    soc_lite_top #(.SIMULATION(!USE_HARDWARE_CLOCK)) dut (
        .clk(clk), .resetn(resetn),
        .uart_rx(uart_rx), .uart_tx(uart_tx),
        .led(led), .led_rg0(), .led_rg1(),
        .num_csn(), .num_a_g(), .num_data(num_data),
        .switch(8'hff), .btn_key_col(),
        .btn_key_row(4'b0), .btn_step(2'b11)
    );

    // 创新扩展：UART，集中显示常用信号，便于在波形窗口观察和截图。
    wire cpu_data_en = dut.cpu_data_en;
    wire [3:0] cpu_data_we = dut.cpu_data_we;
    wire [31:0] cpu_data_addr = dut.cpu_data_addr;
    wire [31:0] cpu_data_wdata = dut.cpu_data_wdata;
    wire [31:0] cpu_data_rdata = dut.cpu_data_rdata;
    wire [31:0] debug_wb_pc = dut.debug_wb_pc;
    wire [3:0] debug_wb_rf_we = dut.debug_wb_rf_we;
    wire [4:0] debug_wb_rf_wnum = dut.debug_wb_rf_wnum;
    wire [31:0] debug_wb_rf_wdata = dut.debug_wb_rf_wdata;
    wire rx_valid = dut.u_confreg.uart_rx_valid;
    wire tx_busy = dut.u_confreg.uart_tx_busy;
    wire [7:0] rx_data = dut.u_confreg.uart_rx_data;
    wire rx_overrun = dut.u_confreg.uart_rx_overrun;
    wire rx_frame_error = dut.u_confreg.uart_rx_frame_error;

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (condition !== 1'b1) begin
                global_err = 1'b1;
                $display("UART_SOC_FAIL: %0s time=%0t pc=%h", message, $time, debug_wb_pc);
                $finish;
            end else checks = checks + 1;
        end
    endtask

    // 创新扩展：UART，模拟网页串口输入，起始位0、低位先发、停止位1。
    task send_byte;
        input [7:0] data;
        integer bit_index;
        begin
            @(negedge clk);
            #3; uart_rx = 1'b0;  // 创新扩展：UART，输入边沿不与采样时钟完全重合。
            #(BIT_TIME_NS);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx = data[bit_index];
                #(BIT_TIME_NS);
            end
            uart_rx = 1'b1;
            #(BIT_TIME_NS);
            $display("UART_RX_SENT: 0x%02h", data);
        end
    endtask

    // 创新扩展：UART，独立解码 CPU 发出的串行数据，不能用接收寄存器代替检查。
    task receive_echo;
        input [7:0] expected;
        integer bit_index;
        reg [7:0] actual;
        begin
            @(negedge uart_tx);
            #(BIT_TIME_NS / 2);
            check(uart_tx === 1'b0, "TX start bit");
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                #(BIT_TIME_NS);
                actual[bit_index] = uart_tx;
            end
            #(BIT_TIME_NS);
            check(uart_tx === 1'b1, "TX stop bit");
            echoed_char = actual;
            check(actual === expected, "Echoed byte must equal injected byte");
        end
    endtask

    task test_character;
        input [7:0] data;
        begin
            expected_char = data;
            // 创新扩展：UART，发送和监听并行，避免 CPU 开始回显时尚未监听。
            fork
                send_byte(data);
                receive_echo(data);
            join
            wait(tx_busy === 1'b0);
            repeat(20) @(negedge clk);
            check(num_data === {24'b0, data}, "Display register must equal character code");
            check(rx_valid === 1'b0, "CPU must consume RXDATA");
            check(rx_overrun === 1'b0, "No receive overrun");
            check(rx_frame_error === 1'b0, "No UART framing error");
            passed_chars = passed_chars + 1;
            $display("UART_CHAR_PASS: input=0x%02h echo=0x%02h display=0x%02h",
                     data, echoed_char, num_data[7:0]);
        end
    endtask

    initial begin
        repeat(100) @(negedge clk);
        resetn = 1'b1;
        repeat(100) @(negedge clk);
        check(uart_tx === 1'b1, "TX idle must be high");
        check(tx_busy === 1'b0 && rx_valid === 1'b0, "UART must start empty and idle");

        test_character(8'h41);  // A -> 41
        test_character(8'h42);  // B -> 42
        test_character(8'h30);  // 0 -> 30
        test_character(8'h61);  // a -> 61

        test_end = 1'b1;
        $display("UART_SOC_PASS: chars=%0d checks=%0d", passed_chars, checks);
        $display("Test end! test_end=%b global_err=%b", test_end, global_err);
        #200;
        $finish;
    end

    initial begin
        #20000000;  // 创新扩展：UART，20 ms 超时，失败时不输出通过标志。
        global_err = 1'b1;
        $display("UART_SOC_FAIL: timeout pc=%h num_data=%h rx_valid=%b tx_busy=%b",
                 debug_wb_pc, num_data, rx_valid, tx_busy);
        $finish;
    end
endmodule
