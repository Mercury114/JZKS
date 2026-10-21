// UART board fix: smoke-test the synthesized board startup, not a full UART regression.
`timescale 1ns/1ps
module tb_uart_board_boot;
    reg clk = 0;
    always #10 clk = ~clk;
    reg reset_btn = 1;
    wire txd;
    wire [15:0] leds;
    wire [7:0] dpy0, dpy1;
    integer checks = 0;
    reg test_end = 0;
    reg global_err = 1;

    looongson_remote_top dut (
        .clk_50M(clk), .clk_11M0592(1'b0), .clock_btn(1'b0),
        .reset_btn(reset_btn), .touch_btn(4'b0), .dip_sw(32'b0),
        .leds(leds), .dpy0(dpy0), .dpy1(dpy1), .rxd(1'b1), .txd(txd),
        .uart_dataready(1'b0), .uart_tbre(1'b1), .uart_tsre(1'b1)
    );

    initial begin
        #1000;
        if (txd !== 1'b1) begin
            $display("UART_BOARD_BOOT_FAIL: reset TX must be idle high");
            test_end = 1;
            $finish;
        end
        checks = checks + 1;
        reset_btn = 0;
        #100000;
        test_end = 1;
        $display("UART_BOARD_BOOT_FAIL: no startup TX, leds=%h tx=%b", leds, txd);
        $finish;
    end

    initial begin
        wait (reset_btn == 0);
        @(negedge txd);
        // Observe only: never force PC, RAM, registers, or UART counters.
        #100;
        if (leds !== 16'h0000 || txd !== 1'b0) begin
            $display("UART_BOARD_BOOT_FAIL: leds=%h tx=%b", leds, txd);
            test_end = 1;
            $finish;
        end
        checks = checks + 2;
        global_err = 0;
        test_end = 1;
        $display("UART_BOARD_BOOT_PASS: reset idle, startup LEDs, TX start; checks=%0d", checks);
        $finish;
    end
endmodule
