`include "mycpu_head.v"

module ID_stage(
    input  wire        clk,
    input  wire        reset,
    input  wire        es_allowin,
    output wire        ds_allowin,
    input  wire        fs_to_ds_valid,
    input  wire [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus,
    output wire        ds_to_es_valid,
    output wire [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus,
    output wire [32:0] br_bus,
    input  wire        es_to_ms_valid,
    input  wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus,
    input  wire        ms_hazard_valid,
    input  wire        ms_hazard_gr_we,
    input  wire [4:0]  ms_hazard_dest,
    input  wire        ms_forward_valid,
    input  wire [31:0] ms_forward_data,
    input  wire        ws_to_rf_we,
    input  wire [4:0]  ws_to_rf_waddr,
    input  wire [31:0] ws_to_rf_wdata,
    input  wire [31:0] csr_rdata,
    input  wire [31:0] rdcnt_low,
    input  wire [31:0] rdcnt_high,
    input  wire [31:0] csr_tid_value,
    input  wire        redirect_flush,
    output wire        id_csr_we,
    output wire [13:0] id_csr_num,
    output wire [31:0] id_csr_mask,
    output wire [31:0] id_csr_wdata,
    output wire        id_exception,
    output wire [5:0]  id_ecode,
    output wire [8:0]  id_esubcode,
    output wire        id_save_badv,
    output wire [31:0] id_badv,
    output wire        id_ertn,
    output wire        id_cache_valid,
    output wire [1:0]  id_cache_op,
    output wire [31:0] id_cache_addr,
    output wire [31:0] id_pc,
    output wire        id_valid,
    output wire        id_empty
);

reg         ds_valid;
wire        ds_ready_go;
wire [31:0] ds_pc;
wire [31:0] ds_inst;

reg [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus_r;
assign {ds_inst, ds_pc} = fs_to_ds_bus_r;

wire [18:0] alu_op;
wire        load_op;
wire        src1_is_pc;
wire        src2_is_imm;
wire        res_from_mem;
wire        dst_is_r1;
wire        gr_we;
wire        mem_we;
wire        src_reg_is_rd;
wire [4: 0] dest;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] imm;
wire [31:0] br_offs;
wire [31:0] jirl_offs;

wire [5:0]  op_31_26;
wire [3:0]  op_25_22;
wire [1:0]  op_21_20;
wire [4:0]  op_19_15;
wire [4:0]  rd;
wire [4:0]  rj;
wire [4:0]  rk;
wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;

wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [3:0]  op_21_20_d;
wire [31:0] op_19_15_d;

wire inst_add_w, inst_sub_w, inst_slt, inst_sltu, inst_nor, inst_and, inst_or, inst_xor;
wire inst_mul_w, inst_mulh_w, inst_mulh_wu, inst_div_w, inst_mod_w, inst_div_wu, inst_mod_wu;
wire inst_slli_w, inst_srli_w, inst_srai_w, inst_addi_w, inst_ld_w, inst_st_w;
wire inst_ld_b, inst_ld_h, inst_ld_bu, inst_ld_hu, inst_st_b, inst_st_h;
wire inst_jirl, inst_b, inst_bl, inst_beq, inst_bne;
wire inst_blt, inst_bge, inst_bltu, inst_bgeu, inst_lu12i_w;
// 新增：声明 andi, ori, xori 指令信号
wire inst_andi, inst_ori, inst_xori;
wire inst_slti, inst_sltui, inst_sll_w, inst_srl_w, inst_sra_w, inst_pcaddu12i;
wire inst_csr, inst_csrrd, inst_csrwr, inst_csrxchg;
wire inst_ertn, inst_syscall, inst_break;
wire inst_rdcntid, inst_rdcntvl, inst_rdcntvh;
wire inst_cacop;
wire inst_known;
wire [13:0] csr_num;

wire need_ui5, need_si12, need_si16, need_si20, need_si26, src2_is_4;
wire [2:0] mem_op;
wire [4:0] rf_raddr1, rf_raddr2;
wire [31:0] rf_rdata1, rf_rdata2;
wire rj_eq_rd;

wire [31:0] es_hazard_alu_result, es_hazard_rkd_value, es_hazard_pc;
wire        es_hazard_gr_we, es_hazard_mem_we, es_hazard_res_from_mem;
wire [4:0]  es_hazard_dest;
wire [2:0]  es_hazard_mem_op;
wire        ds_uses_rj, ds_uses_rkd;
wire        ms_raw_hazard, ds_raw_hazard;
assign op_31_26 = ds_inst[31:26];
assign op_25_22 = ds_inst[25:22];
assign op_21_20 = ds_inst[21:20];
assign op_19_15 = ds_inst[19:15];
assign rd = ds_inst[4:0];
assign rj = ds_inst[9:5];
assign rk = ds_inst[14:10];
assign i12 = ds_inst[21:10];
assign i20 = ds_inst[24:5];
assign i16 = ds_inst[25:10];
assign i26 = {ds_inst[9:0], ds_inst[25:10]};

decoder_6_64 u_dec0(.in(op_31_26), .out(op_31_26_d));
decoder_4_16 u_dec1(.in(op_25_22), .out(op_25_22_d));
decoder_2_4  u_dec2(.in(op_21_20), .out(op_21_20_d));
decoder_5_32 u_dec3(.in(op_19_15), .out(op_19_15_d));

assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_mul_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
assign inst_mulh_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
assign inst_mulh_wu= op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
assign inst_div_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
assign inst_mod_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
assign inst_div_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
assign inst_mod_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];
assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_ld_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
assign inst_ld_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
assign inst_ld_bu  = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
assign inst_ld_hu  = op_31_26_d[6'h0a] & op_25_22_d[4'h9];
assign inst_st_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
assign inst_st_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h5];
assign inst_jirl   = op_31_26_d[6'h13];
assign inst_b      = op_31_26_d[6'h14];
assign inst_bl     = op_31_26_d[6'h15];
assign inst_beq    = op_31_26_d[6'h16];
assign inst_bne    = op_31_26_d[6'h17];
assign inst_blt    = op_31_26_d[6'h18];
assign inst_bge    = op_31_26_d[6'h19];
assign inst_bltu   = op_31_26_d[6'h1a];
assign inst_bgeu   = op_31_26_d[6'h1b];
assign inst_lu12i_w= op_31_26_d[6'h05] & ~ds_inst[25];

// 新增：andi, ori, xori 译码逻辑
assign inst_andi   = op_31_26_d[6'h00] & op_25_22_d[4'hd];
assign inst_ori    = op_31_26_d[6'h00] & op_25_22_d[4'he];
assign inst_xori   = op_31_26_d[6'h00] & op_25_22_d[4'hf];
assign inst_slti   = op_31_26_d[6'h00] & op_25_22_d[4'h8];
assign inst_sltui  = op_31_26_d[6'h00] & op_25_22_d[4'h9];
assign inst_sll_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
assign inst_srl_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
assign inst_sra_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
assign inst_pcaddu12i = op_31_26_d[6'h07] & ~ds_inst[25];

// CSR, exception and stable counter instructions are decoded here so that
// they obey the same ID-stage hazard/redirect rules as ordinary instructions.
assign inst_csr     = op_31_26_d[6'h01] & op_25_22_d[4'h0] & op_21_20_d[2'h0];
assign inst_csrrd   = inst_csr & (rj == 5'd0);
assign inst_csrwr   = inst_csr & (rj == 5'd1);
assign inst_csrxchg = inst_csr & (rj > 5'd1);
assign csr_num      = ds_inst[23:10];
assign inst_ertn    = (ds_inst == 32'h0648_3800);
assign inst_syscall = ((ds_inst & 32'hffff_8000) == 32'h002b_0000);
assign inst_break   = ((ds_inst & 32'hffff_8000) == 32'h002a_0000);
assign inst_rdcntid = (ds_inst[31:15] == 17'b0) & (ds_inst[14:10] == 5'h18);
assign inst_rdcntvl = (ds_inst[31:15] == 17'b0) & (ds_inst[14:10] == 5'h19);
assign inst_rdcntvh = (ds_inst[31:15] == 17'b0) & (ds_inst[14:10] == 5'h1a);
assign inst_cacop   = op_31_26_d[6'h18];
assign inst_known = inst_add_w | inst_sub_w | inst_slt | inst_sltu | inst_nor |
                   inst_and | inst_or | inst_xor | inst_mul_w | inst_mulh_w |
                   inst_mulh_wu | inst_div_w | inst_mod_w | inst_div_wu |
                   inst_mod_wu | inst_slli_w | inst_srli_w | inst_srai_w |
                   inst_addi_w | inst_ld_w | inst_st_w | inst_ld_b | inst_ld_h |
                   inst_ld_bu | inst_ld_hu | inst_st_b | inst_st_h | inst_jirl |
                   inst_b | inst_bl | inst_beq | inst_bne | inst_blt | inst_bge |
                   inst_bltu | inst_bgeu | inst_lu12i_w | inst_andi | inst_ori |
                   inst_xori | inst_slti | inst_sltui | inst_sll_w | inst_srl_w |
                   inst_sra_w | inst_pcaddu12i | inst_csr | inst_ertn |
                   inst_syscall | inst_break | inst_rdcntid | inst_rdcntvl |
                   inst_rdcntvh | inst_cacop;

// 修改：alu_op 生成，加入 andi, ori, xori
assign alu_op[0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w |
                   inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu |
                   inst_st_b | inst_st_h | inst_jirl | inst_bl | inst_pcaddu12i |
                   inst_csr | inst_rdcntid | inst_rdcntvl | inst_rdcntvh;
assign alu_op[1] = inst_sub_w;
assign alu_op[2] = inst_slt | inst_slti;
assign alu_op[3] = inst_sltu | inst_sltui;
assign alu_op[4] = inst_and | inst_andi;
assign alu_op[5] = inst_nor;
assign alu_op[6] = inst_or | inst_ori;
assign alu_op[7] = inst_xor | inst_xori;
assign alu_op[8] = inst_slli_w | inst_sll_w;
assign alu_op[9] = inst_srli_w | inst_srl_w;
assign alu_op[10]= inst_srai_w | inst_sra_w;
assign alu_op[11]= inst_lu12i_w;
assign alu_op[12]= inst_mul_w;
assign alu_op[13]= inst_mulh_w;
assign alu_op[14]= inst_mulh_wu;
assign alu_op[15]= inst_div_w;
assign alu_op[16]= inst_mod_w;
assign alu_op[17]= inst_div_wu;
assign alu_op[18]= inst_mod_wu;

// 修改：need_si12 和 src2_is_imm 加入 andi, ori, xori
assign need_ui5  = inst_slli_w | inst_srli_w | inst_srai_w;
assign need_si12 = inst_addi_w | inst_ld_w | inst_st_w |
                   inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu |
                   inst_st_b | inst_st_h |
                   inst_andi | inst_ori | inst_xori | inst_slti | inst_sltui;
assign need_si16 = inst_jirl | inst_beq | inst_bne;
assign need_si20 = inst_lu12i_w | inst_pcaddu12i;
assign need_si26 = inst_b | inst_bl;
assign src2_is_4 = inst_jirl | inst_bl;

// 000: word, 001/010: signed byte/half, 011/100: unsigned byte/half,
// 101/110: byte/half store.
assign mem_op = inst_ld_b  ? 3'b001 :
                inst_ld_h  ? 3'b010 :
                inst_ld_bu ? 3'b011 :
                inst_ld_hu ? 3'b100 :
                inst_st_b  ? 3'b101 :
                inst_st_h  ? 3'b110 : 3'b000;

assign imm = src2_is_4 ? 32'h4 :
             need_si20 ? {i20[19:0], 12'b0} :
             need_ui5  ? {27'b0, rk} :
             (inst_andi | inst_ori | inst_xori) ? {20'b0, i12} :
             {{20{i12[11]}}, i12[11:0]};
assign br_offs = need_si26 ? {{4{i26[25]}}, i26[25:0], 2'b0} : {{14{i16[15]}}, i16[15:0], 2'b0};
assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

assign src_reg_is_rd = inst_beq | inst_bne | inst_blt | inst_bge |
                       inst_bltu | inst_bgeu | inst_st_w | inst_st_b | inst_st_h;
assign src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;
assign src2_is_imm   = inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w |
                       inst_ld_w | inst_st_w | inst_ld_b | inst_ld_h |
                       inst_ld_bu | inst_ld_hu | inst_st_b | inst_st_h |
                       inst_lu12i_w | inst_jirl | inst_bl | inst_andi |
                       inst_ori | inst_xori | inst_slti | inst_sltui | inst_pcaddu12i |
                       inst_csr | inst_rdcntid | inst_rdcntvl | inst_rdcntvh;
assign res_from_mem  = inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu;
assign dst_is_r1     = inst_bl;
assign gr_we         = (inst_add_w | inst_sub_w | inst_slt | inst_sltu | inst_nor |
                       inst_and | inst_or | inst_xor | inst_mul_w | inst_mulh_w |
                       inst_mulh_wu | inst_div_w | inst_mod_w | inst_div_wu |
                       inst_mod_wu | inst_slli_w | inst_srli_w | inst_srai_w |
                       inst_addi_w | inst_lu12i_w | inst_pcaddu12i | inst_andi |
                       inst_ori | inst_xori | inst_slti | inst_sltui | inst_sll_w |
                       inst_srl_w | inst_sra_w | inst_jirl | inst_bl | res_from_mem |
                       inst_csr | inst_rdcntid | inst_rdcntvl | inst_rdcntvh) &
                       ~inst_ertn & ~inst_syscall & ~inst_break & inst_known;
assign mem_we        = inst_st_w | inst_st_b | inst_st_h;
assign dest          = dst_is_r1 ? 5'd1 :
                       (inst_rdcntid | inst_rdcntvl | inst_rdcntvh) ? rj : rd;

assign rf_raddr1 = rj;
assign rf_raddr2 = (src_reg_is_rd | inst_csr) ? rd : rk;
wire es_forward_valid = es_to_ms_valid && es_hazard_gr_we &&
                        !es_hazard_res_from_mem && (es_hazard_dest != 5'd0);
wire es_rj_forward = es_forward_valid && (rf_raddr1 == es_hazard_dest);
wire es_rkd_forward = es_forward_valid && (rf_raddr2 == es_hazard_dest);
wire ms_rj_forward = ms_forward_valid && ms_hazard_gr_we &&
                     (ms_hazard_dest != 5'd0) && (rf_raddr1 == ms_hazard_dest);
wire ms_rkd_forward = ms_forward_valid && ms_hazard_gr_we &&
                      (ms_hazard_dest != 5'd0) && (rf_raddr2 == ms_hazard_dest);

assign rj_value  = inst_csr ? ((inst_csrxchg) ?
                   (es_rj_forward ? es_hazard_alu_result :
                    ms_rj_forward ? ms_forward_data : rf_rdata1) : csr_rdata) :
                   inst_rdcntid ? csr_tid_value :
                   (inst_rdcntvh ? rdcnt_high :
                    (inst_rdcntvl ? rdcnt_low :
                     (es_rj_forward ? es_hazard_alu_result :
                      ms_rj_forward ? ms_forward_data : rf_rdata1)));
assign rkd_value = es_rkd_forward ? es_hazard_alu_result :
                   ms_rkd_forward ? ms_forward_data : rf_rdata2;
assign rj_eq_rd  = (rj_value == rkd_value);

assign {es_hazard_alu_result, es_hazard_rkd_value, es_hazard_gr_we,
        es_hazard_mem_we, es_hazard_dest, es_hazard_res_from_mem,
        es_hazard_pc, es_hazard_mem_op} = es_to_ms_bus;
assign ds_uses_rj  = ~(inst_b | inst_bl | inst_lu12i_w | inst_pcaddu12i);
assign ds_uses_rkd = inst_beq | inst_bne | inst_blt | inst_bge |
                     inst_bltu | inst_bgeu | inst_st_w | inst_st_b | inst_st_h |
                     inst_add_w | inst_sub_w | inst_slt | inst_sltu |
                     inst_nor | inst_and | inst_or | inst_xor |
                     inst_mul_w | inst_mulh_w | inst_mulh_wu | inst_div_w |
                     inst_mod_w | inst_div_wu | inst_mod_wu |
                     inst_sll_w | inst_srl_w | inst_sra_w | inst_csrxchg;
wire es_load_hazard = es_to_ms_valid && es_hazard_gr_we &&
                      es_hazard_res_from_mem && (es_hazard_dest != 5'd0) &&
                      ((ds_uses_rj && (rj == es_hazard_dest)) ||
                       (ds_uses_rkd && (rf_raddr2 == es_hazard_dest)));
assign ms_raw_hazard = ms_hazard_valid && ms_hazard_gr_we &&
                       (ms_hazard_dest != 5'd0) &&
                       !ms_forward_valid &&
                       ((ds_uses_rj && (rj == ms_hazard_dest)) ||
                        (ds_uses_rkd && (rf_raddr2 == ms_hazard_dest)));
assign ds_raw_hazard = ds_valid && (es_load_hazard || ms_raw_hazard);

wire [31:0] effective_addr = rj_value + imm;
wire addr_error = ((inst_ld_w | inst_st_w) && (effective_addr[1:0] != 2'b00)) |
                  ((inst_ld_h | inst_ld_hu | inst_st_h) && effective_addr[0]);
wire local_exception = inst_syscall | inst_break | !inst_known | addr_error;
// redirect_flush is derived from id_exception/ertn in mycpu_top.  Feeding it
// back into these decode outputs creates a zero-delay control loop exactly
// when an exception is decoded.  The stage-valid register is flushed on the
// next clock edge, so no combinational suppression is required here.
assign id_exception = ds_valid && ds_ready_go && local_exception;
assign id_ecode = inst_syscall ? 6'h0b : inst_break ? 6'h0c :
                  !inst_known ? 6'h0d : addr_error ? 6'h09 : 6'h00;
assign id_esubcode = 9'b0;
assign id_save_badv = (!inst_known) ? 1'b0 : addr_error;
assign id_badv = addr_error ? effective_addr : ds_pc;
assign id_ertn = ds_valid && ds_ready_go && inst_ertn;
assign id_cache_valid = ds_valid && ds_ready_go && inst_cacop;
assign id_cache_op = ds_inst[4:3];
assign id_cache_addr = rj_value + imm;
assign id_csr_we = ds_valid && ds_ready_go && inst_csr && !inst_csrrd;
assign id_csr_num = csr_num;
assign id_csr_mask = inst_csrxchg ?
                     (es_rj_forward ? es_hazard_alu_result :
                      ms_rj_forward ? ms_forward_data : rf_rdata1) :
                     32'hffff_ffff;
assign id_csr_wdata = (rd == 5'd0) ? 32'b0 :
                      (es_rkd_forward ? es_hazard_alu_result :
                       ms_rkd_forward ? ms_forward_data : rf_rdata2);
assign id_pc = ds_pc;
assign id_valid = ds_valid;
assign id_empty = !ds_valid;
wire br_taken;
wire [31:0] br_target;
wire [32:0] branch_sub_result = {1'b0, rj_value} - {1'b0, rkd_value};
wire rj_lt_rd_signed = (rj_value[31] & ~rkd_value[31]) |
                       ((rj_value[31] ~^ rkd_value[31]) && branch_sub_result[31]);
wire rj_lt_rd_unsigned = branch_sub_result[32];
assign br_taken = (inst_beq && rj_eq_rd || inst_bne && !rj_eq_rd ||
                   inst_blt && rj_lt_rd_signed || inst_bge && !rj_lt_rd_signed ||
                   inst_bltu && rj_lt_rd_unsigned || inst_bgeu && !rj_lt_rd_unsigned ||
                   inst_jirl || inst_bl || inst_b) &&
                  ds_valid && ds_ready_go;
assign br_target = (inst_beq || inst_bne || inst_blt || inst_bge ||
                    inst_bltu || inst_bgeu || inst_bl || inst_b) ?
                   (ds_pc + br_offs) : (rj_value + jirl_offs);
assign br_bus = {br_taken, br_target};

assign ds_to_es_bus = {
    alu_op,
    gr_we,
    mem_we,
    dest,
    imm,
    rj_value,
    rkd_value,
    ds_pc,
    res_from_mem,
    src1_is_pc,
    src2_is_imm,
    mem_op
};

assign ds_ready_go    = ~ds_raw_hazard;
assign ds_allowin     = !ds_valid || ds_ready_go && es_allowin;
assign ds_to_es_valid = ds_valid && ds_ready_go && !local_exception && !inst_ertn && !inst_cacop;

always @(posedge clk) begin
    if (reset) begin
        ds_valid <= 1'b0;
        fs_to_ds_bus_r <= {`FS_TO_DS_BUS_WD{1'b0}};
    end else begin
        if (br_taken || redirect_flush)
            ds_valid <= 1'b0;
        else if (ds_allowin)
            ds_valid <= fs_to_ds_valid;
        if (fs_to_ds_valid && ds_allowin && !br_taken)
            fs_to_ds_bus_r <= fs_to_ds_bus;
    end
end

regfile u_regfile(
    .clk(clk),
    .raddr1(rf_raddr1),
    .rdata1(rf_rdata1),
    .raddr2(rf_raddr2),
    .rdata2(rf_rdata2),
    .we(ws_to_rf_we),
    .waddr(ws_to_rf_waddr),
    .wdata(ws_to_rf_wdata)
);

endmodule
