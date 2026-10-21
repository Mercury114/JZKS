`timescale 1ns / 1ps
// 创新扩展：UART，实际硬件分频路径，CPU 为 3.125 MHz，UART 每位326拍。
module tb_uart_soc_hwclk;
    tb_uart_soc #(.USE_HARDWARE_CLOCK(1'b1)) test();
endmodule
