`timescale 1ns / 1ps
// 创新扩展：真实串行输入检查FIFO次序、回绕、满、溢出及同时读写。
module tb_uart_fifo;
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0;
    reg uart_rx=1;
    reg rx_read=0;
    wire uart_tx, rx_valid, tx_busy, rx_overrun, rx_frame_error;
    wire [7:0] rx_data;
    wire [4:0] rx_count;
    integer checks=0;
    integer i;
    reg test_end=0;
    reg global_err=0;
    uart_mmio #(.CLKS_PER_BIT(8)) dut (
        .clk(clk), .resetn(resetn), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .tx_write(1'b0), .tx_wdata(8'b0), .rx_read(rx_read),
        .rx_data(rx_data), .rx_valid(rx_valid), .tx_busy(tx_busy),
        .rx_overrun(rx_overrun), .rx_frame_error(rx_frame_error), .rx_count(rx_count)
    );
    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (condition !== 1'b1) begin
                global_err=1;
                $display("UART_FIFO_FAIL: %0s count=%0d data=%h", message, rx_count, rx_data);
                $finish;
            end
            checks=checks+1;
        end
    endtask
    task reset_fifo;
        begin
            @(negedge clk); resetn=0; rx_read=0; uart_rx=1;
            repeat(5) @(negedge clk);
            resetn=1;
            repeat(3) @(negedge clk);
        end
    endtask
    task send_byte;
        input [7:0] value;
        integer b;
        begin
            @(negedge clk); #3; uart_rx=0;
            #160;
            for (b=0;b<8;b=b+1) begin uart_rx=value[b]; #160; end
            uart_rx=1; #160;
            repeat(3) @(negedge clk);
        end
    endtask
    task pop_byte;
        input [7:0] expected;
        reg [4:0] previous_count;
        begin
            @(negedge clk);
            check(rx_valid && rx_data===expected, "FIFO preserves byte order");
            previous_count=rx_count;
            rx_read=1;
            @(negedge clk); rx_read=0;
            check(rx_count===previous_count-1'b1, "pop decrements count");
        end
    endtask
    initial begin
        reset_fifo;
        check(!rx_valid && rx_count==0 && rx_data==0, "reset empty");
        rx_read=1; repeat(3) @(negedge clk); rx_read=0;
        check(rx_count==0, "empty pop cannot underflow");
        for(i=0;i<16;i=i+1) send_byte(i);
        check(rx_count==16 && !rx_overrun, "16 byte FIFO capacity");
        send_byte(8'hee);
        check(rx_count==16 && rx_overrun, "full FIFO drops new byte and records overrun");
        for(i=0;i<16;i=i+1) pop_byte(i);
        check(!rx_valid && rx_count==0, "drain after overrun");
        for(i=0;i<12;i=i+1) send_byte(8'h80+i);
        for(i=0;i<8;i=i+1) pop_byte(8'h80+i);
        for(i=0;i<10;i=i+1) send_byte(8'h40+i);
        for(i=8;i<12;i=i+1) pop_byte(8'h80+i);
        for(i=0;i<10;i=i+1) pop_byte(8'h40+i);
        check(rx_count==0, "read/write pointers wrap correctly");
        reset_fifo;
        for(i=0;i<16;i=i+1) send_byte(i);
        fork
            send_byte(8'hff);
            begin
                @(posedge dut.rx_done);
                @(negedge clk);
                check(rx_data==0 && rx_count==16, "simultaneous full pop reads old head");
                rx_read=1;
                @(negedge clk); rx_read=0;
            end
        join
        check(rx_count==16 && !rx_overrun, "full FIFO accepts replacement when popped same cycle");
        for(i=1;i<16;i=i+1) pop_byte(i);
        pop_byte(8'hff);
        check(rx_count==0 && !rx_frame_error, "simultaneous operation and framing correct");
        rx_read=1;
        send_byte(8'h5a);
        // Continuous empty reads consume the newly received byte on the next clock.
        repeat(3) @(negedge clk); rx_read=0;
        check(rx_count==0 && !rx_overrun, "empty reads and arrival do not corrupt count");
        test_end=1;
        $display("UART_FIFO_PASS: checks=%0d",checks);
        #100; $finish;
    end
    initial begin #500000; global_err=1; $display("UART_FIFO_FAIL: timeout"); $finish; end
endmodule
