`default_nettype none

module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    output wire        inst_sram_en,
    output wire [3:0]  inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    output wire        data_sram_en,
    output wire [3:0]  data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    output wire [31:0] debug_wb_pc,
    output wire [3:0]  debug_wb_rf_we,
    output wire [4:0]  debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

localparam S_FETCH          = 4'd0;
localparam S_FETCH_WAIT     = 4'd1;
localparam S_EXEC           = 4'd2;
localparam S_MEM_READ       = 4'd3;
localparam S_MEM_READ_WAIT  = 4'd4;
localparam S_MEM_WRITE      = 4'd5;
localparam S_WB             = 4'd6;

localparam ECODE_INT  = 6'h00;
localparam ECODE_ADEF = 6'h08;
localparam ECODE_ALE  = 6'h09;
localparam ECODE_SYS  = 6'h0b;
localparam ECODE_BRK  = 6'h0c;
localparam ECODE_INE  = 6'h0d;

reg [3:0]  state;
reg [31:0] pc;
reg [31:0] inst;
reg [31:0] rf [0:31];
reg [31:0] mem_addr_r;
reg [31:0] mem_wdata_r;
reg [3:0]  mem_we_r;
reg [2:0]  mem_op_r;
reg [4:0]  mem_dest_r;
reg [31:0] wb_pc_r;
reg [4:0]  wb_dest_r;
reg [31:0] wb_data_r;
reg        wb_we_r;

reg [31:0] csr_crmd;
reg [31:0] csr_prmd;
reg [31:0] csr_ecfg;
reg [31:0] csr_estat;
reg [31:0] csr_era;
reg [31:0] csr_badv;
reg [31:0] csr_eentry;
reg [31:0] csr_save0;
reg [31:0] csr_save1;
reg [31:0] csr_save2;
reg [31:0] csr_save3;
reg [31:0] csr_tid;
reg [31:0] csr_tcfg;
reg [31:0] timer_cnt;
reg [63:0] stable_counter;

wire [5:0] op_31_26 = inst[31:26];
wire [3:0] op_25_22 = inst[25:22];
wire [1:0] op_21_20 = inst[21:20];
wire [4:0] op_19_15 = inst[19:15];
wire [4:0] rd        = inst[4:0];
wire [4:0] rj        = inst[9:5];
wire [4:0] rk        = inst[14:10];
wire [11:0] i12      = inst[21:10];
wire [19:0] i20      = inst[24:5];
wire [15:0] i16      = inst[25:10];
wire [25:0] i26      = {inst[9:0], inst[25:10]};
wire [31:0] rj_value = rj == 5'd0 ? 32'b0 : rf[rj];
wire [31:0] rk_value = rk == 5'd0 ? 32'b0 : rf[rk];
wire [31:0] rd_value = rd == 5'd0 ? 32'b0 : rf[rd];
wire signed [31:0] signed_rj = rj_value;
wire signed [31:0] signed_rk = rk_value;
wire signed [63:0] signed_product = signed_rj * signed_rk;
wire [63:0] unsigned_product = rj_value * rk_value;
// Keep division operands explicitly signed and equally wide.  This avoids
// simulator-dependent signedness propagation through expression operators.
wire signed [63:0] signed_dividend = {{32{rj_value[31]}}, rj_value};
wire signed [63:0] signed_divisor  = {{32{rk_value[31]}}, rk_value};
wire signed [63:0] signed_quotient = signed_dividend / signed_divisor;
wire signed [63:0] signed_remainder = signed_dividend % signed_divisor;

wire inst_add_w   = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h00;
wire inst_sub_w   = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h02;
wire inst_slt     = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h04;
wire inst_sltu    = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h05;
wire inst_nor     = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h08;
wire inst_and     = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h09;
wire inst_or      = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h0a;
wire inst_xor     = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h0b;
wire inst_sll_w   = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h0e;
wire inst_srl_w   = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h0f;
wire inst_sra_w   = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h10;
wire inst_mul_w   = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h18;
wire inst_mulh_w  = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h19;
wire inst_mulh_wu = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h1 && op_19_15==5'h1a;
wire inst_div_w   = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h2 && op_19_15==5'h00;
wire inst_mod_w   = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h2 && op_19_15==5'h01;
wire inst_div_wu  = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h2 && op_19_15==5'h02;
wire inst_mod_wu  = op_31_26==6'h00 && op_25_22==4'h0 && op_21_20==2'h2 && op_19_15==5'h03;
wire inst_slli_w  = op_31_26==6'h00 && op_25_22==4'h1 && op_21_20==2'h0 && op_19_15==5'h01;
wire inst_srli_w  = op_31_26==6'h00 && op_25_22==4'h1 && op_21_20==2'h0 && op_19_15==5'h09;
wire inst_srai_w  = op_31_26==6'h00 && op_25_22==4'h1 && op_21_20==2'h0 && op_19_15==5'h11;
wire inst_addi_w  = op_31_26==6'h00 && op_25_22==4'ha;
wire inst_slti    = op_31_26==6'h00 && op_25_22==4'h8;
wire inst_sltui   = op_31_26==6'h00 && op_25_22==4'h9;
wire inst_andi    = op_31_26==6'h00 && op_25_22==4'hd;
wire inst_ori     = op_31_26==6'h00 && op_25_22==4'he;
wire inst_xori    = op_31_26==6'h00 && op_25_22==4'hf;
wire inst_lu12i_w = op_31_26==6'h05 && !inst[25];
wire inst_pcaddu12i = op_31_26==6'h07 && !inst[25];
wire inst_ld_b    = op_31_26==6'h0a && op_25_22==4'h0;
wire inst_ld_h    = op_31_26==6'h0a && op_25_22==4'h1;
wire inst_ld_w    = op_31_26==6'h0a && op_25_22==4'h2;
wire inst_st_b    = op_31_26==6'h0a && op_25_22==4'h4;
wire inst_st_h    = op_31_26==6'h0a && op_25_22==4'h5;
wire inst_st_w    = op_31_26==6'h0a && op_25_22==4'h6;
wire inst_ld_bu   = op_31_26==6'h0a && op_25_22==4'h8;
wire inst_ld_hu   = op_31_26==6'h0a && op_25_22==4'h9;
wire inst_jirl    = op_31_26==6'h13;
wire inst_b       = op_31_26==6'h14;
wire inst_bl      = op_31_26==6'h15;
wire inst_beq     = op_31_26==6'h16;
wire inst_bne     = op_31_26==6'h17;
wire inst_blt     = op_31_26==6'h18;
wire inst_bge     = op_31_26==6'h19;
wire inst_bltu    = op_31_26==6'h1a;
wire inst_bgeu    = op_31_26==6'h1b;
wire inst_csr     = op_31_26==6'h01 && op_25_22==4'h0 && op_21_20==2'h0;
wire inst_csrrd   = inst_csr && rj==5'd0;
wire inst_csrwr   = inst_csr && rj==5'd1;
wire inst_csrxchg = inst_csr && rj>5'd1;
wire [13:0] csr_num = inst[23:10];
wire inst_ertn    = inst == 32'h0648_3800;
wire inst_syscall = (inst & 32'hffff_8000) == 32'h002b_0000;
wire inst_break   = (inst & 32'hffff_8000) == 32'h002a_0000;
wire inst_rdcntid = inst[31:15] == 17'b0 && inst[14:10] == 5'h18;
wire inst_rdcntvl = inst[31:15] == 17'b0 && inst[14:10] == 5'h19;
wire inst_rdcntvh = inst[31:15] == 17'b0 && inst[14:10] == 5'h1a;

wire inst_load  = inst_ld_b | inst_ld_h | inst_ld_w | inst_ld_bu | inst_ld_hu;
wire inst_store = inst_st_b | inst_st_h | inst_st_w;
wire inst_known = inst_add_w | inst_sub_w | inst_slt | inst_sltu | inst_nor |
                  inst_and | inst_or | inst_xor | inst_sll_w | inst_srl_w |
                  inst_sra_w | inst_mul_w | inst_mulh_w | inst_mulh_wu |
                  inst_div_w | inst_mod_w | inst_div_wu | inst_mod_wu |
                  inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w |
                  inst_slti | inst_sltui | inst_andi | inst_ori | inst_xori |
                  inst_lu12i_w | inst_pcaddu12i | inst_load | inst_store |
                  inst_jirl | inst_b | inst_bl | inst_beq | inst_bne |
                  inst_blt | inst_bge | inst_bltu | inst_bgeu | inst_csr |
                  inst_ertn | inst_syscall | inst_break | inst_rdcntid |
                  inst_rdcntvl | inst_rdcntvh;

wire [31:0] imm_si12 = {{20{i12[11]}}, i12};
wire [31:0] imm_ui12 = {20'b0, i12};
wire [31:0] imm_i20  = {i20, 12'b0};
wire [31:0] br_offs  = inst_b | inst_bl ? {{4{i26[25]}}, i26, 2'b0} : {{14{i16[15]}}, i16, 2'b0};
wire [31:0] mem_addr_exec = rj_value + imm_si12;
wire has_int = csr_crmd[2] && |(csr_estat[12:0] & csr_ecfg[12:0]);
wire [7:0] load_byte = mem_addr_r[1:0] == 2'd0 ? data_sram_rdata[7:0] :
                      mem_addr_r[1:0] == 2'd1 ? data_sram_rdata[15:8] :
                      mem_addr_r[1:0] == 2'd2 ? data_sram_rdata[23:16] : data_sram_rdata[31:24];
wire [15:0] load_half = mem_addr_r[1] ? data_sram_rdata[31:16] : data_sram_rdata[15:0];

function [31:0] read_csr;
    input [13:0] number;
    begin
        case (number)
            14'h0000: read_csr = csr_crmd;
            14'h0001: read_csr = csr_prmd;
            14'h0004: read_csr = csr_ecfg;
            14'h0005: read_csr = csr_estat;
            14'h0006: read_csr = csr_era;
            14'h0007: read_csr = csr_badv;
            14'h000c: read_csr = csr_eentry;
            14'h0030: read_csr = csr_save0;
            14'h0031: read_csr = csr_save1;
            14'h0032: read_csr = csr_save2;
            14'h0033: read_csr = csr_save3;
            14'h0040: read_csr = csr_tid;
            14'h0041: read_csr = csr_tcfg;
            14'h0042: read_csr = timer_cnt;
            default:  read_csr = 32'b0;
        endcase
    end
endfunction

task write_csr;
    input [13:0] number;
    input [31:0] mask;
    input [31:0] value;
    reg [31:0] next_value;
    begin
        case (number)
            14'h0000: csr_crmd <= (csr_crmd & ~mask) | (value & mask);
            14'h0001: csr_prmd <= (csr_prmd & ~mask) | (value & mask);
            14'h0004: csr_ecfg <= (csr_ecfg & ~mask) | (value & mask);
            14'h0005: csr_estat[1:0] <= (csr_estat[1:0] & ~mask[1:0]) | (value[1:0] & mask[1:0]);
            14'h0006: csr_era <= (csr_era & ~mask) | (value & mask);
            14'h0007: csr_badv <= (csr_badv & ~mask) | (value & mask);
            14'h000c: csr_eentry <= (csr_eentry & ~mask) | (value & mask);
            14'h0030: csr_save0 <= (csr_save0 & ~mask) | (value & mask);
            14'h0031: csr_save1 <= (csr_save1 & ~mask) | (value & mask);
            14'h0032: csr_save2 <= (csr_save2 & ~mask) | (value & mask);
            14'h0033: csr_save3 <= (csr_save3 & ~mask) | (value & mask);
            14'h0040: csr_tid <= (csr_tid & ~mask) | (value & mask);
            14'h0041: begin
                next_value = (csr_tcfg & ~mask) | (value & mask);
                csr_tcfg <= next_value;
                if (next_value[0])
                    timer_cnt <= {next_value[31:2], 2'b0};
            end
            14'h0044: if (mask[0] && value[0]) csr_estat[11] <= 1'b0;
            default: ;
        endcase
    end
endtask

task raise_exception;
    input [5:0] ecode;
    input [8:0] esubcode;
    input       save_badv;
    input [31:0] badv_value;
    begin
        csr_prmd[1:0] <= csr_crmd[1:0];
        csr_prmd[2] <= csr_crmd[2];
        csr_crmd[1:0] <= 2'b0;
        csr_crmd[2] <= 1'b0;
        csr_estat[21:16] <= ecode;
        csr_estat[30:22] <= esubcode;
        csr_era <= pc;
        if (save_badv) csr_badv <= badv_value;
        pc <= {csr_eentry[31:6], 6'b0};
        state <= S_FETCH;
    end
endtask

assign inst_sram_en    = state == S_FETCH;
assign inst_sram_we    = 4'b0;
assign inst_sram_addr  = pc;
assign inst_sram_wdata = 32'b0;
assign data_sram_en    = state == S_MEM_READ || state == S_MEM_WRITE;
assign data_sram_we    = state == S_MEM_WRITE ? mem_we_r : 4'b0;
assign data_sram_addr  = mem_addr_r;
assign data_sram_wdata = mem_wdata_r;
assign debug_wb_pc       = wb_pc_r;
assign debug_wb_rf_we    = {4{wb_we_r && state == S_WB}};
assign debug_wb_rf_wnum  = wb_dest_r;
assign debug_wb_rf_wdata = wb_data_r;

integer i;
always @(posedge clk) begin
    if (!resetn) begin
        state <= S_FETCH;
        pc <= 32'h1c00_0000;
        inst <= 32'b0;
        mem_addr_r <= 32'b0;
        mem_wdata_r <= 32'b0;
        mem_we_r <= 4'b0;
        mem_op_r <= 3'b0;
        wb_pc_r <= 32'b0;
        wb_dest_r <= 5'b0;
        wb_data_r <= 32'b0;
        wb_we_r <= 1'b0;
        csr_crmd <= 32'h0000_0008;
        csr_prmd <= 32'b0;
        csr_ecfg <= 32'b0;
        csr_estat <= 32'b0;
        csr_era <= 32'b0;
        csr_badv <= 32'b0;
        csr_eentry <= 32'b0;
        csr_save0 <= 32'b0;
        csr_save1 <= 32'b0;
        csr_save2 <= 32'b0;
        csr_save3 <= 32'b0;
        csr_tid <= 32'b0;
        csr_tcfg <= 32'b0;
        timer_cnt <= 32'hffff_ffff;
        stable_counter <= 64'b0;
        for (i=0; i<32; i=i+1) rf[i] <= 32'b0;
    end else begin
        rf[0] <= 32'b0;
        stable_counter <= stable_counter + 1'b1;
        if (csr_tcfg[0] && timer_cnt != 32'hffff_ffff) begin
            if (timer_cnt == 32'b0) begin
                csr_estat[11] <= 1'b1;
                timer_cnt <= csr_tcfg[1] ? {csr_tcfg[31:2], 2'b0} : 32'hffff_ffff;
            end else begin
                timer_cnt <= timer_cnt - 1'b1;
            end
        end

        case (state)
            S_FETCH: state <= S_FETCH_WAIT;
            S_FETCH_WAIT: begin
                inst <= inst_sram_rdata;
                state <= S_EXEC;
            end
            S_EXEC: begin
                wb_we_r <= 1'b0;
                if (has_int) begin
                    raise_exception(ECODE_INT, 9'b0, 1'b0, 32'b0);
                end else if (pc[1:0] != 2'b00) begin
                    raise_exception(ECODE_ADEF, 9'b0, 1'b1, pc);
                end else if (inst_ertn) begin
                    csr_crmd[1:0] <= csr_prmd[1:0];
                    csr_crmd[2] <= csr_prmd[2];
                    pc <= csr_era;
                    state <= S_FETCH;
                end else if (inst_syscall) begin
                    raise_exception(ECODE_SYS, 9'b0, 1'b0, 32'b0);
                end else if (inst_break) begin
                    raise_exception(ECODE_BRK, 9'b0, 1'b0, 32'b0);
                end else if (!inst_known) begin
                    raise_exception(ECODE_INE, 9'b0, 1'b0, 32'b0);
                end else if (inst_load || inst_store) begin
                    if ((inst_ld_w || inst_st_w) && mem_addr_exec[1:0] != 2'b00 ||
                        (inst_ld_h || inst_ld_hu || inst_st_h) && mem_addr_exec[0]) begin
                        raise_exception(ECODE_ALE, 9'b0, 1'b1, mem_addr_exec);
                    end else begin
                        mem_addr_r <= mem_addr_exec;
                        mem_wdata_r <= inst_st_b ? (rd_value << {mem_addr_exec[1:0],3'b0}) :
                                       inst_st_h ? (rd_value << {mem_addr_exec[1],4'b0}) : rd_value;
                        mem_we_r <= inst_st_b ? (4'b0001 << mem_addr_exec[1:0]) :
                                    inst_st_h ? (mem_addr_exec[1] ? 4'b1100 : 4'b0011) :
                                    inst_st_w ? 4'b1111 : 4'b0;
                        mem_op_r <= inst_ld_b  ? 3'd1 : inst_ld_h  ? 3'd2 :
                                    inst_ld_bu ? 3'd3 : inst_ld_hu ? 3'd4 : 3'd0;
                        mem_dest_r <= rd;
                        if (inst_load) state <= S_MEM_READ;
                        else begin
                            state <= S_MEM_WRITE;
                            pc <= pc + 3'd4;
                        end
                    end
                end else if (inst_b || inst_bl || inst_beq || inst_bne || inst_blt || inst_bge || inst_bltu || inst_bgeu || inst_jirl) begin
                    if (inst_bl || inst_jirl) begin
                        wb_pc_r <= pc;
                        wb_dest_r <= inst_bl ? 5'd1 : rd;
                        wb_data_r <= pc + 3'd4;
                        wb_we_r <= (inst_bl || rd != 5'd0);
                        pc <= inst_bl ? pc + br_offs : rj_value + {{14{i16[15]}}, i16, 2'b0};
                        state <= S_WB;
                    end else begin
                        if (inst_b || (inst_beq && rj_value == rd_value) ||
                            (inst_bne && rj_value != rd_value) ||
                            (inst_blt && signed_rj < $signed(rd_value)) ||
                            (inst_bge && signed_rj >= $signed(rd_value)) ||
                            (inst_bltu && rj_value < rd_value) ||
                            (inst_bgeu && rj_value >= rd_value))
                            pc <= pc + br_offs;
                        else
                            pc <= pc + 3'd4;
                        state <= S_FETCH;
                    end
                end else if (inst_csr) begin
                    wb_pc_r <= pc;
                    wb_dest_r <= rd;
                    wb_data_r <= read_csr(csr_num);
                    wb_we_r <= rd != 5'd0;
                    if (inst_csrwr) write_csr(csr_num, 32'hffff_ffff, rd_value);
                    else if (inst_csrxchg) write_csr(csr_num, rj_value, rd_value);
                    pc <= pc + 3'd4;
                    state <= S_WB;
                end else if (inst_rdcntid || inst_rdcntvl || inst_rdcntvh) begin
                    wb_pc_r <= pc;
                    wb_dest_r <= rj;
                    wb_data_r <= inst_rdcntid ? csr_tid :
                                 inst_rdcntvl ? stable_counter[31:0] : stable_counter[63:32];
                    wb_we_r <= rj != 5'd0;
                    pc <= pc + 3'd4;
                    state <= S_WB;
                end else begin
                    wb_pc_r <= pc;
                    wb_dest_r <= rd;
                    wb_we_r <= rd != 5'd0;
                    if (inst_add_w) wb_data_r <= rj_value + rk_value;
                    else if (inst_sub_w) wb_data_r <= rj_value - rk_value;
                    else if (inst_slt || inst_slti) wb_data_r <= $signed(rj_value) < $signed(inst_slti ? imm_si12 : rk_value);
                    else if (inst_sltu || inst_sltui) wb_data_r <= rj_value < (inst_sltui ? imm_si12 : rk_value);
                    else if (inst_nor) wb_data_r <= ~(rj_value | rk_value);
                    else if (inst_and || inst_andi) wb_data_r <= rj_value & (inst_andi ? imm_ui12 : rk_value);
                    else if (inst_or || inst_ori) wb_data_r <= rj_value | (inst_ori ? imm_ui12 : rk_value);
                    else if (inst_xor || inst_xori) wb_data_r <= rj_value ^ (inst_xori ? imm_ui12 : rk_value);
                    else if (inst_sll_w) wb_data_r <= rj_value << rk_value[4:0];
                    else if (inst_srl_w) wb_data_r <= rj_value >> rk_value[4:0];
                    else if (inst_sra_w) wb_data_r <= $signed(rj_value) >>> rk_value[4:0];
                    else if (inst_slli_w) wb_data_r <= rj_value << rk[4:0];
                    else if (inst_srli_w) wb_data_r <= rj_value >> rk[4:0];
                    else if (inst_srai_w) wb_data_r <= $signed(rj_value) >>> rk[4:0];
                    else if (inst_addi_w) wb_data_r <= rj_value + imm_si12;
                    else if (inst_lu12i_w) wb_data_r <= imm_i20;
                    else if (inst_pcaddu12i) wb_data_r <= pc + imm_i20;
                    else if (inst_mul_w) wb_data_r <= unsigned_product[31:0];
                    else if (inst_mulh_w) wb_data_r <= signed_product[63:32];
                    else if (inst_mulh_wu) wb_data_r <= unsigned_product[63:32];
                    else if (inst_div_w) wb_data_r <= rk_value == 0 ? 32'b0 : signed_quotient[31:0];
                    else if (inst_mod_w) wb_data_r <= rk_value == 0 ? 32'b0 : signed_remainder[31:0];
                    else if (inst_div_wu) wb_data_r <= rk_value == 0 ? 32'b0 : rj_value / rk_value;
                    else if (inst_mod_wu) wb_data_r <= rk_value == 0 ? 32'b0 : rj_value % rk_value;
                    else wb_data_r <= 32'b0;
                    pc <= pc + 3'd4;
                    state <= S_WB;
                end
            end
            S_MEM_READ: state <= S_MEM_READ_WAIT;
            S_MEM_READ_WAIT: begin
                wb_pc_r <= pc;
                wb_dest_r <= mem_dest_r;
                wb_we_r <= mem_dest_r != 5'd0;
                case (mem_op_r)
                    3'd1: wb_data_r <= {{24{load_byte[7]}}, load_byte};
                    3'd2: wb_data_r <= {{16{load_half[15]}}, load_half};
                    3'd3: wb_data_r <= {24'b0, load_byte};
                    3'd4: wb_data_r <= {16'b0, load_half};
                    default: wb_data_r <= data_sram_rdata;
                endcase
                pc <= pc + 3'd4;
                state <= S_WB;
            end
            S_MEM_WRITE: state <= S_FETCH;
            S_WB: begin
                if (wb_we_r && wb_dest_r != 5'd0) rf[wb_dest_r] <= wb_data_r;
                state <= S_FETCH;
            end
            default: state <= S_FETCH;
        endcase
    end
end

endmodule

`default_nettype wire
