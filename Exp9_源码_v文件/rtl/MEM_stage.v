`include "mycpu_head.v"

module MEM_stage(
    input  wire        clk,
    input  wire        reset,
    input  wire        ws_allowin,
    output wire        ms_allowin,
    input  wire        es_to_ms_valid,
    input  wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus,
    output wire        ms_to_ws_valid,
    output wire [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus,
    output wire        data_sram_en,
    output wire [3:0]  data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    output wire        ms_hazard_valid,
    output wire        ms_hazard_gr_we,
    output wire [4:0]  ms_hazard_dest,
    output wire        ms_forward_valid,
    output wire [31:0] ms_forward_data
);

reg         ms_valid;
wire        ms_ready_go;
reg         ms_mem_wait;

wire [31:0] alu_result;
wire [31:0] rkd_value;
wire        gr_we;
wire        mem_we;
wire [4:0]  dest;
wire        res_from_mem;
wire [2:0]  mem_op;

wire [31:0] ds_pc;
reg [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus_r;
assign {alu_result, rkd_value, gr_we, mem_we, dest, res_from_mem, ds_pc, mem_op} = es_to_ms_bus_r;

assign ms_hazard_valid = ms_valid;
assign ms_hazard_gr_we = gr_we;
assign ms_hazard_dest  = dest;

// The course BMG exposes its registered read value while EN is asserted.
// Therefore a load keeps the SRAM request active throughout the one-cycle
// MEM wait.  The stage itself remains stalled, so the address and write
// controls are stable until the response is consumed.
assign data_sram_en = ms_valid && (res_from_mem || mem_we);
wire is_store_byte = mem_op == 3'b101;
wire is_store_half = mem_op == 3'b110;
wire [3:0] byte_lane = 4'b0001 << alu_result[1:0];
wire [3:0] half_lane = 4'b0011 << {alu_result[1], 1'b0};
assign data_sram_we    = ms_valid && mem_we ?
                         (is_store_byte ? byte_lane :
                          is_store_half ? half_lane : 4'b1111) : 4'b0000;
assign data_sram_addr  = alu_result;
assign data_sram_wdata = is_store_byte ? (rkd_value << {alu_result[1:0], 3'b000}) :
                         is_store_half ? (rkd_value << {alu_result[1], 4'b0000}) : rkd_value;

wire [7:0] load_byte = alu_result[1:0] == 2'd0 ? data_sram_rdata[7:0] :
                       alu_result[1:0] == 2'd1 ? data_sram_rdata[15:8] :
                       alu_result[1:0] == 2'd2 ? data_sram_rdata[23:16] : data_sram_rdata[31:24];
wire [15:0] load_half = alu_result[1] ? data_sram_rdata[31:16] : data_sram_rdata[15:0];
wire [31:0] load_result = mem_op == 3'b001 ? {{24{load_byte[7]}}, load_byte} :
                          mem_op == 3'b010 ? {{16{load_half[15]}}, load_half} :
                          mem_op == 3'b011 ? {24'b0, load_byte} :
                          mem_op == 3'b100 ? {16'b0, load_half} : data_sram_rdata;
wire [31:0] final_result = res_from_mem ? load_result : alu_result;
assign ms_to_ws_bus = {final_result, gr_we, dest, ds_pc};
assign ms_forward_valid = ms_valid && ms_ready_go;
assign ms_forward_data = final_result;

assign ms_ready_go    = !res_from_mem || ms_mem_wait;
assign ms_allowin     = !ms_valid || ms_ready_go && ws_allowin;
assign ms_to_ws_valid = ms_valid && ms_ready_go;

always @(posedge clk) begin
    if (reset) begin
        ms_valid <= 1'b0;
        ms_mem_wait <= 1'b0;
        es_to_ms_bus_r <= {`ES_TO_MS_BUS_WD{1'b0}};
    end else begin
        if (ms_allowin) begin
            ms_valid <= es_to_ms_valid;
            ms_mem_wait <= 1'b0;
        end else if (ms_valid && res_from_mem && !ms_mem_wait) begin
            ms_mem_wait <= 1'b1;
        end
        if (es_to_ms_valid && ms_allowin)
            es_to_ms_bus_r <= es_to_ms_bus;
    end
end

endmodule
