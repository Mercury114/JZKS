`timescale 1ns / 1ps
// 原教师程序 + 新Cache SoC + 原confreg；RAM用独立一拍模型替代厂商IP。
// 不生成、不声称独立golden trace；功能点来自教师程序自身的数码管自检。
module teacher_cache_tb;
    parameter WAY_NUM = 2;
    parameter ENABLE_CACHE = 1;
    parameter TARGET_POINTS = 58;
    reg clk = 0;
    reg resetn = 0;
    always #5 clk = ~clk;
    wire [31:0] num_data;
    cache_soc_lite_top #(.SIMULATION(1), .WAY_NUM(WAY_NUM), .ENABLE_CACHE(ENABLE_CACHE), .INST_INIT_FILE("program.hex")) dut(
        .clk(clk), .resetn(resetn), .num_data(num_data),
        .switch(8'hff), .btn_key_row(4'b0), .btn_step(2'b11)
    );
    integer points = 0;
    integer target;
    integer cycles = 0;
    reg [31:0] last_num = 0;
    initial begin
        target = TARGET_POINTS;
        if ($value$plusargs("POINTS=%d", target)) begin end
        repeat (12) @(negedge clk);
        resetn = 1;
    end
    always @(negedge clk) begin
        cycles = cycles + 1;
        if (resetn && num_data !== last_num && num_data != 0) begin
            last_num = num_data;
            if (num_data[7:0] != points + 1 || num_data[31:24] != points + 1)
                $fatal(1, "teacher point failed num=%h expected=%0d pc=%h", num_data, points + 1, dut.debug_wb_pc);
            points = points + 1;
            $display("PASS teacher point %0d/%0d cycle=%0d", points, target, cycles);
            if (points == target) begin
                repeat (100) @(negedge clk);
                $display("PASS teacher cache SoC: %0d points cycles=%0d ways=%0d enabled=%0d", points, cycles, WAY_NUM, ENABLE_CACHE);
                $finish;
            end
        end
        if (cycles > 20000000) $fatal(1, "teacher timeout points=%0d pc=%h", points, dut.debug_wb_pc);
    end
endmodule
