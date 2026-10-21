// 二进制译码器：in 是一个编号，out 中对应编号那一位为 1，其余位为 0。
// 例如 2 位输入为 2（二进制 10）时，4 位输出为 0100。
// ID 用这些组合逻辑模块识别操作码；不保存状态，不需要时钟或复位。
`timescale 1ns/1ps
`default_nettype none

module decoder_2_4(
    input  wire [ 1:0] in,
    output wire [ 3:0] out
);

genvar i;

// generate 在展开电路时生成 4 个比较器，不是运行时逐个循环计算。
generate
    for (i = 0; i < 4; i = i + 1) begin : gen_for_dec_2_4
        assign out[i] = (in == i);
    end
endgenerate

endmodule

module decoder_4_16(
    input  wire [ 3:0] in,
    output wire [15:0] out
);

genvar i;

// generate 在展开电路时生成 16 个比较器，不是运行时逐个循环计算。
generate
    for (i = 0; i < 16; i = i + 1) begin : gen_for_dec_4_16
        assign out[i] = (in == i);
    end
endgenerate

endmodule

module decoder_5_32(
    input  wire [ 4:0] in,
    output wire [31:0] out
);

genvar i;

// generate 在展开电路时生成 32 个比较器，不是运行时逐个循环计算。
generate
    for (i = 0; i < 32; i = i + 1) begin : gen_for_dec_5_32
        assign out[i] = (in == i);
    end
endgenerate

endmodule

module decoder_6_64(
    input  wire [ 5:0] in,
    output wire [63:0] out
);

genvar i;

// generate 在展开电路时生成 64 个比较器，不是运行时逐个循环计算。
generate
    for (i = 0; i < 64; i = i + 1) begin : gen_for_dec_6_64
        assign out[i] = (in == i);
    end
endgenerate

endmodule

`default_nettype wire
