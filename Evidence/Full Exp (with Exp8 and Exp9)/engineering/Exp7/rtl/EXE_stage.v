`include "mycpu_head.v"

module EXE_stage(
    input  wire        clk,
    input  wire        reset,
    input  wire        ms_allowin,
    output wire        es_allowin,
    input  wire        ds_to_es_valid,
    input  wire [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus,
    output wire        es_to_ms_valid,
    output wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus
);

reg         es_valid;
wire        es_ready_go;

wire [18:0] alu_op;
wire        gr_we;
wire        mem_we;
wire [4:0]  dest;
wire [31:0] imm;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] ds_pc;
wire        res_from_mem;
wire        src1_is_pc;
wire        src2_is_imm;
wire [2:0]  mem_op;

assign {
    alu_op, gr_we, mem_we, dest, imm, rj_value, rkd_value, ds_pc, res_from_mem, src1_is_pc, src2_is_imm, mem_op
} = ds_to_es_bus;

wire [31:0] alu_src1 = src1_is_pc ? ds_pc : rj_value;
wire [31:0] alu_src2 = src2_is_imm ? imm : rkd_value;
wire [31:0] alu_result;

alu u_alu(
    .alu_op(alu_op),
    .alu_src1(alu_src1),
    .alu_src2(alu_src2),
    .alu_result(alu_result)
);

wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus_d;
reg  [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus_r;
assign es_to_ms_bus_d = {alu_result, rkd_value, gr_we, mem_we, dest, res_from_mem, ds_pc, mem_op};
assign es_to_ms_bus = es_to_ms_bus_r;

assign es_ready_go    = 1'b1;
assign es_allowin     = !es_valid || es_ready_go && ms_allowin;
assign es_to_ms_valid = es_valid && es_ready_go;

always @(posedge clk) begin
    if (reset) begin
        es_valid <= 1'b0;
        es_to_ms_bus_r <= {`ES_TO_MS_BUS_WD{1'b0}};
    end else begin
        if (es_allowin)
            es_valid <= ds_to_es_valid;
        if (ds_to_es_valid && es_allowin)
            es_to_ms_bus_r <= es_to_ms_bus_d;
    end
end

endmodule
