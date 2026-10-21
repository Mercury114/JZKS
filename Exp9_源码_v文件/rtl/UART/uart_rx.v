// 创新扩展：UART，8N1，CLKS_PER_BIT >= 4；resetn 为同步低有效复位。
module uart_rx #(
    parameter integer CLKS_PER_BIT = 5208
)(
    input  wire       clk,
    input  wire       resetn,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_done,
    output reg        frame_error
);
    localparam IDLE=3'd0, START=3'd1, DATA=3'd2,
               STOP=3'd3, WAIT_HIGH=3'd4;
    localparam integer CNT_W = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;
    localparam integer HALF_BIT = (CLKS_PER_BIT-1)/2;
    (* ASYNC_REG = "TRUE" *) reg rx_meta, rx_sync;
    reg [2:0] state;
    reg [CNT_W-1:0] bit_cnt;
    reg [2:0] bit_index;
    reg [7:0] data_buf;

    // 创新扩展：外部 RX 输入先经过两级同步。
    always @(posedge clk) begin
        if (!resetn) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            bit_cnt <= 0;
            bit_index <= 0;
            data_buf <= 0;
            rx_data <= 0;
            rx_done <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            rx_done <= 1'b0;
            frame_error <= 1'b0;
            case (state)
                IDLE: begin
                    bit_cnt <= 0;
                    bit_index <= 0;
                    if (!rx_sync) state <= START;
                end
                START: begin
                    if (bit_cnt == HALF_BIT) begin
                        bit_cnt <= 0;
                        if (!rx_sync) state <= DATA;
                        else state <= IDLE;
                    end else bit_cnt <= bit_cnt + 1'b1;
                end
                DATA: begin
                    if (bit_cnt == CLKS_PER_BIT-1) begin
                        bit_cnt <= 0;
                        data_buf[bit_index] <= rx_sync;
                        if (bit_index == 7) state <= STOP;
                        else bit_index <= bit_index + 1'b1;
                    end else bit_cnt <= bit_cnt + 1'b1;
                end
                STOP: begin
                    if (bit_cnt == CLKS_PER_BIT-1) begin
                        bit_cnt <= 0;
                        if (rx_sync) begin
                            rx_data <= data_buf;
                            rx_done <= 1'b1;
                            state <= IDLE;
                        end else begin
                            frame_error <= 1'b1;
                            state <= WAIT_HIGH;
                        end
                    end else bit_cnt <= bit_cnt + 1'b1;
                end
                WAIT_HIGH: begin
                    // 创新扩展：错误帧后等待线路恢复，避免持续低电平重复报帧。
                    if (rx_sync) state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
