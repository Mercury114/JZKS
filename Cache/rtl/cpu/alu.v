// 组合 ALU（算术逻辑单元）：不保存状态，输入变化后产生结果，不需要时钟或复位。
// alu_op 的各位选择不同运算；译码正常时最多一位为 1。
// 加减结果只保留低 32 位，比较结果为 0 或 1；当前不产生算术溢出异常。
`timescale 1ns/1ps
`default_nettype none

module alu(
    input  wire [11:0] alu_op,
    input  wire [31:0] alu_src1,  // 第一个操作数：rj 的值或 PC；移位时是被移动的数据
    input  wire [31:0] alu_src2,  // 第二个操作数；移位时低 5 位表示移动几位
    output wire [31:0] alu_result
);

wire        op_add;   // 加法
wire        op_sub;   // 减法
wire        op_slt;   // 有符号小于比较
wire        op_sltu;  // 无符号小于比较
wire        op_and;   // 按位与
wire        op_nor;   // 按位或非
wire        op_or;    // 按位或
wire        op_xor;   // 按位异或
wire        op_sll;   // 逻辑左移
wire        op_srl;   // 逻辑右移，高位补 0
wire        op_sra;   // 算术右移，高位补原符号位
wire        op_lui;   // 装入高位立即数

// 各条运算通路独立得到候选结果，最后再根据 alu_op 选出需要的一项。
wire [31:0] add_sub_result;
wire [31:0] slt_result;
wire [31:0] sltu_result;
wire [31:0] and_result;
wire [31:0] nor_result;
wire [31:0] or_result;
wire [31:0] xor_result;
wire [31:0] lui_result;
wire [31:0] sll_result;
wire [63:0] sr64_result;
wire [31:0] sr_result;

// 共享加法器的输入、结果和进位。
wire [31:0] adder_a;
wire [31:0] adder_b;
wire        adder_cin;
wire [31:0] adder_result;
wire        adder_cout;

// 控制位的顺序与 ID 级 alu_op 的打包顺序一致。
assign op_add  = alu_op[ 0];
assign op_sub  = alu_op[ 1];
assign op_slt  = alu_op[ 2];
assign op_sltu = alu_op[ 3];
assign op_and  = alu_op[ 4];
assign op_nor  = alu_op[ 5];
assign op_or   = alu_op[ 6];
assign op_xor  = alu_op[ 7];
assign op_sll  = alu_op[ 8];
assign op_srl  = alu_op[ 9];
assign op_sra  = alu_op[10];
assign op_lui  = alu_op[11];

// a-b 等于 a+~b+1，因此加、减、两种比较可以共用一个加法器。
// 做减法/比较时将 b 取反并加 1，额外保留最高进位供无符号比较使用。
assign adder_a   = alu_src1;
assign adder_b   = (op_sub | op_slt | op_sltu) ? ~alu_src2 : alu_src2;
assign adder_cin = (op_sub | op_slt | op_sltu) ? 1'b1      : 1'b0;
assign {adder_cout, adder_result} = adder_a + adder_b + adder_cin;

assign add_sub_result = adder_result;

// 有符号比较：异号时负数更小；同号时看减法结果是否为负。
// 比较的真假只放在第 0 位，其余位清零。
assign slt_result[31:1] = 31'b0;
assign slt_result[0]    = (alu_src1[31] & ~alu_src2[31])
                       | ((alu_src1[31] ~^ alu_src2[31]) & adder_result[31]);

// 无符号比较：a+~b+1 没有最高进位表示减法需要借位，即 a<b。
assign sltu_result[31:1] = 31'b0;
assign sltu_result[0]    = ~adder_cout;

// 按位逻辑运算，每一位独立计算。lu12i.w 的立即数已在 ID 中完成低位补零。
assign and_result = alu_src1 & alu_src2;
assign or_result  = alu_src1 | alu_src2;
assign nor_result = ~or_result;
assign xor_result = alu_src1 ^ alu_src2;
assign lui_result = alu_src2;

// 32 位数据只需 5 位移位量，范围是 0～31；左移从低位补 0。
assign sll_result = alu_src1 << alu_src2[4:0];

// 先把数据扩成 64 位再右移：算术右移在高 32 位复制符号，逻辑右移补 0。
// 右移后取低 32 位，保留结果的全部有效位。
assign sr64_result = {{32{op_sra & alu_src1[31]}}, alu_src1} >> alu_src2[4:0];
assign sr_result   = sr64_result[31:0];

// {32{选择位}} 将 1 位选择信号复制 32 次，用作掩码，只留下被选中的结果。
// 所有选择位为 0 时输出 0；若误置多个选择位，则是多个结果按位或，并非优先选择。
assign alu_result = ({32{op_add | op_sub}} & add_sub_result)
                  | ({32{op_slt        }} & slt_result)
                  | ({32{op_sltu       }} & sltu_result)
                  | ({32{op_and        }} & and_result)
                  | ({32{op_nor        }} & nor_result)
                  | ({32{op_or         }} & or_result)
                  | ({32{op_xor        }} & xor_result)
                  | ({32{op_lui        }} & lui_result)
                  | ({32{op_sll        }} & sll_result)
                  | ({32{op_srl | op_sra}} & sr_result);

endmodule

`default_nettype wire
