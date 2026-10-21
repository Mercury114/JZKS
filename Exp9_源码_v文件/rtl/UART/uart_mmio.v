// 创新扩展：UART，16字节接收FIFO，CPU每读一次RXDATA弹出一个字节。
module uart_mmio #(
    parameter integer CLKS_PER_BIT = 5208
)(
    input  wire       clk,
    input  wire       resetn,
    input  wire       uart_rx,
    output wire       uart_tx,
    input  wire       tx_write,
    input  wire [7:0] tx_wdata,
    input  wire       rx_read,
    output wire [7:0] rx_data,
    output wire       rx_valid,
    output wire       tx_busy,
    output reg        rx_overrun,
    output reg        rx_frame_error,
    output reg  [4:0] rx_count
);
    reg [7:0] fifo [0:15];
    reg [3:0] read_ptr;
    reg [3:0] write_ptr;
    wire [7:0] received_data;
    wire rx_done;
    wire frame_error;
    wire tx_start = tx_write && !tx_busy;
    assign rx_valid = (rx_count != 0);
    assign rx_data = rx_valid ? fifo[read_ptr] : 8'b0;
    wire pop = rx_read && rx_valid;
    // 创新扩展：FIFO满且同周期读出时，仍允许写入新字节。
    wire push = rx_done && ((rx_count < 16) || pop);

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .resetn(resetn),
        .tx_start(tx_start), .tx_data(tx_wdata),
        .tx(uart_tx), .tx_busy(tx_busy), .tx_done()
    );
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .resetn(resetn), .rx(uart_rx),
        .rx_data(received_data), .rx_done(rx_done), .frame_error(frame_error)
    );

    always @(posedge clk) begin
        if (!resetn) begin
            read_ptr <= 0;
            write_ptr <= 0;
            rx_count <= 0;
            rx_overrun <= 1'b0;
            rx_frame_error <= 1'b0;
        end else begin
            if (frame_error) rx_frame_error <= 1'b1;
            if (rx_done && !push) rx_overrun <= 1'b1;
            if (push) begin
                fifo[write_ptr] <= received_data;
                write_ptr <= write_ptr + 1'b1;
            end
            if (pop) read_ptr <= read_ptr + 1'b1;
            case ({push, pop})
                2'b10: rx_count <= rx_count + 1'b1;
                2'b01: rx_count <= rx_count - 1'b1;
                default: rx_count <= rx_count;
            endcase
        end
    end
endmodule
