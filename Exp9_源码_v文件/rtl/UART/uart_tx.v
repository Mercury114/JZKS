// 创新扩展：UART，8N1，低位先发送；resetn 为同步低有效复位。
module uart_tx #(
    parameter integer CLKS_PER_BIT = 5208
)(
    input  wire       clk,
    input  wire       resetn,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx,
    output reg        tx_busy,
    output reg        tx_done
);
    localparam IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
    localparam integer CNT_W = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;
    reg [1:0] state;
    reg [CNT_W-1:0] bit_cnt;
    reg [2:0] bit_index;
    reg [7:0] data_buf;

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            bit_cnt <= 0;
            bit_index <= 0;
            data_buf <= 0;
            tx <= 1'b1;
            tx_busy <= 1'b0;
            tx_done <= 1'b0;
        end else begin
            tx_done <= 1'b0;
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                    bit_cnt <= 0;
                    bit_index <= 0;
                    if (tx_start) begin
                        data_buf <= tx_data;
                        tx <= 1'b0;
                        tx_busy <= 1'b1;
                        state <= START;
                    end
                end
                START: begin
                    if (bit_cnt == CLKS_PER_BIT-1) begin
                        bit_cnt <= 0;
                        tx <= data_buf[0];
                        state <= DATA;
                    end else bit_cnt <= bit_cnt + 1'b1;
                end
                DATA: begin
                    if (bit_cnt == CLKS_PER_BIT-1) begin
                        bit_cnt <= 0;
                        if (bit_index == 7) begin
                            tx <= 1'b1;
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            tx <= data_buf[bit_index + 3'd1];
                        end
                    end else bit_cnt <= bit_cnt + 1'b1;
                end
                STOP: begin
                    if (bit_cnt == CLKS_PER_BIT-1) begin
                        bit_cnt <= 0;
                        tx_busy <= 1'b0;
                        tx_done <= 1'b1;
                        state <= IDLE;
                    end else bit_cnt <= bit_cnt + 1'b1;
                end
                default: begin
                    state <= IDLE;
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                end
            endcase
        end
    end
endmodule
