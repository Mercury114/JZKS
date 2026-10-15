`timescale 1ns / 1ps

module tb_top;
reg resetn;
reg clk;
wire [15:0] led;
wire [1:0] led_rg0;
wire [1:0] led_rg1;
wire [7:0] num_csn;
wire [6:0] num_a_g;
wire [3:0] btn_key_col;
wire [31:0] num_data;

initial begin
    clk = 1'b0;
    resetn = 1'b0;
    #2000 resetn = 1'b1;
end
always #5 clk = ~clk;

soc_lite_top #(.SIMULATION(1'b1)) soc_lite (
    .resetn(resetn), .clk(clk), .led(led), .led_rg0(led_rg0), .led_rg1(led_rg1),
    .num_csn(num_csn), .num_a_g(num_a_g), .num_data(num_data), .switch(8'hff),
    .btn_key_col(btn_key_col), .btn_key_row(4'b0), .btn_step(2'b11)
);

wire soc_clk = soc_lite.cpu_clk;
wire [31:0] debug_wb_pc = soc_lite.debug_wb_pc;
wire num_monitor = soc_lite.u_confreg.num_monitor;
reg [31:0] last_num;
reg [7:0] error_count;
reg finished;

always @(posedge soc_clk) begin
    if (!resetn) begin
        last_num <= 32'b0;
        error_count <= 8'b0;
        finished <= 1'b0;
    end else begin
        if (num_monitor && num_data != last_num) begin
            if (num_data[7:0] != last_num[7:0] + 1'b1 ||
                num_data[31:24] != last_num[31:24] + 1'b1) begin
                $display("FUNCTIONAL_POINT_ERROR value=%h previous=%h", num_data, last_num);
                error_count <= error_count + 1'b1;
            end else begin
                $display("FUNCTIONAL_POINT_PASS %0d", num_data[31:24]);
            end
            last_num <= num_data;
        end
        if (!finished && debug_wb_pc == 32'h1c00_0100) begin
            finished <= 1'b1;
            #40;
            if (error_count == 0) $display("----PASS!!!");
            else $display("----FAIL: %0d functional-point errors", error_count);
            $finish;
        end
    end
end

initial begin
    #200000000;
    $display("----FAIL: simulation timeout");
    $finish;
end
endmodule
