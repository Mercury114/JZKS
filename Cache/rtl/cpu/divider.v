// Part 5: 自写迭代除法器：每拍移位、比较并按需减除数，32 次迭代得到商和余数。
// Part 5: 负数先取绝对值计算，最后恢复符号：两数异号则商为负，余数跟被除数同号。
// Part 5: 上升沿 start=1 且 busy=0 时接收输入；EXE 保证同一条指令只启动一次。
// Part 5: 启动占 1 拍，迭代占 32 拍；done 和结果保持到下次启动或复位。
// Part 5: 除零返回商全 1、余数为被除数；ISA 允许任意结果且不触发例外。
`timescale 1ns/1ps
`default_nettype none

module divider(
    input  wire        clk,        // Part 5: 时钟，工作状态和输出在上升沿更新
    input  wire        reset,      // Part 5: 高有效同步复位，优先取消正在进行的除法
    input  wire        start,      // Part 5: 启动请求；仅空闲时接收，锁存本次输入
    input  wire        signed_div, // Part 5: 1 为有符号除法，0 为无符号除法
    input  wire [31:0] dividend,   // Part 5: 被除数，对应本条指令的 R[rj]
    input  wire [31:0] divisor,    // Part 5: 除数，对应本条指令的 R[rk]
    output reg         busy,       // Part 5: 正在迭代，期间不接收新的启动请求
    output reg         done,       // Part 5: 最终结果已就绪；不是只有一拍的脉冲
    output reg  [31:0] quotient,   // Part 5: 最终商，供 div.w/div.wu 选择写回
    output reg  [31:0] remainder   // Part 5: 最终余数，供 mod.w/mod.wu 选择写回
);

// Part 5: 迭代数据：暂存计算中的值，与最终输出 quotient/remainder 分开。
reg  [31:0] quotient_work;      // Part 5: 初装被除数绝对值，高位移出原输入，低位逐步填入商位
reg  [32:0] remainder_work;     // Part 5: 工作余数，多一位容纳左移带入下一位后的临时值
reg  [31:0] divisor_abs;        // Part 5: 除数绝对值，作为无符号数使用，本次迭代期间不变
reg  [ 5:0] count;              // Part 5: 迭代计数；沿前值 0～31 对应第 1～32 次计算

// Part 5: 启动时保存本次符号和除零信息，结束时不再依赖外部输入。
reg         quotient_negative;  // Part 5: 商是否为负；被除数与除数的负号异或
reg         remainder_negative; // Part 5: 余数是否需要恢复负号；取被除数的负号
reg         divide_by_zero;     // Part 5: 本次除数为零，完成时选择固定的除零结果
reg  [31:0] original_dividend;   // Part 5: 原被除数位串，除零时直接作为余数返回

// Part 5: 组合信号：根据当前输入判断符号，或根据工作寄存器计算下一步。
wire        dividend_negative; // Part 5: 当前被除数是否为有符号负数；无符号模式下恒为 0
wire        divisor_negative;  // Part 5: 当前除数是否为有符号负数；无符号模式下恒为 0
wire [32:0] shifted_remainder; // Part 5: 旧余数乘 2，再带入尚未处理的被除数最高位
wire        subtract_ok;       // Part 5: 临时余数不小于除数，本位商可以写 1
wire [32:0] next_remainder;    // Part 5: 本次有条件减法后的新余数，等待时钟沿保存
wire [31:0] next_quotient;     // Part 5: 工作商左移，并把本次得到的商位填入最低位

// Part 5: 只有 signed_div=1 才把最高位当负号，避免无符号大数被误当负数。
assign dividend_negative = signed_div && dividend[31];
assign divisor_negative  = signed_div && divisor[31];

// Part 5: 二进制竖式的一步：带入一位 → 比较 → 够减才减 → 生成一位商。
// Part 5: 非零除数时旧余数小于除数，移位后的值小于两倍除数，所以最多减一次。
// Part 5: 旧余数此时的第 32 位为 0，保留低 32 位左移后得到完整的 33 位临时值。
assign shifted_remainder = {remainder_work[31:0], quotient_work[31]};
// Part 5: 除数高位补 0，按同样的 33 位无符号宽度比较和相减。
assign subtract_ok       = shifted_remainder >= {1'b0, divisor_abs};
assign next_remainder    = subtract_ok ? shifted_remainder - {1'b0, divisor_abs} : shifted_remainder;
// Part 5: 商向左移动，最低位填比较结果；高位中尚未处理的原被除数也随之移动。
assign next_quotient     = {quotient_work[30:0], subtract_ok};

always @(posedge clk) begin
    // Part 5: 同步取消运算；工作寄存器无需逐个清零，下次 start 会完整初始化。
    if (reset) begin
        busy <= 1'b0;
        done <= 1'b0;
        quotient <= 32'b0;
        remainder <= 32'b0;
    end
    else if (start && ~busy) begin
        // Part 5: 本沿只初始化，不迭代；随后 busy=1 的 32 个时钟沿逐位计算。
        busy <= 1'b1;
        done <= 1'b0;
        count <= 6'd0;
        // Part 5: 补码负数取反加一得到大小，主体统一执行无符号长除法。
        // Part 5: 最小负数的大小位串仍是 0x80000000，在工作寄存器中按无符号解释。
        quotient_work <= dividend_negative ? (~dividend + 32'd1) : dividend;
        divisor_abs <= divisor_negative ? (~divisor + 32'd1) : divisor;
        remainder_work <= 33'b0;
        // Part 5: 商的负号由两输入是否异号决定；非零余数与被除数同号。
        quotient_negative <= dividend_negative ^ divisor_negative;
        remainder_negative <= dividend_negative;
        // Part 5: 除零不提前结束，也走完 32 次迭代；保存原输入供最终结果分支使用。
        divide_by_zero <= divisor == 32'b0;
        original_dividend <= dividend;
    end
    else if (busy) begin
        // Part 5: 每个上升沿保存一步；<= 的右边都使用本沿之前的工作值。
        quotient_work <= next_quotient;
        remainder_work <= next_remainder;
        count <= count + 6'd1;
        // Part 5: 判断的是沿前 count=31，表示本沿正在完成第 32 次迭代。
        if (count == 6'd31) begin
            busy <= 1'b0;
            done <= 1'b1;
            if (divide_by_zero) begin
                // Part 5: 固定约定为商全 1、余数原被除数；不用取绝对值后的工作输入。
                quotient <= 32'hffffffff;
                remainder <= original_dividend;
            end
            else begin
                // Part 5: 使用 next 值包含最后一位，旧工作值此时只完成了 31 次迭代。
                // Part 5: 需要负号才取反加一；绝对值商恢复符号后实现向 0 截断。
                quotient <= quotient_negative ? (~next_quotient + 32'd1) : next_quotient;
                remainder <= remainder_negative ? (~next_remainder[31:0] + 32'd1) : next_remainder[31:0];
            end
        end
    end
    // Part 5: 空闲且无 start 时不赋值，done 与最终结果保持，便于 EXE 等后级接收。
end

endmodule

`default_nettype wire
