`include "mycpu_head.v"

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

wire         reset;
assign reset = ~resetn;

wire [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus;
wire [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus;
wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus;
wire [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus;

wire fs_to_ds_valid;
wire ds_to_es_valid;
wire es_to_ms_valid;
wire ms_to_ws_valid;

wire ds_allowin;
wire es_allowin;
wire ms_allowin;
wire ws_allowin;

wire [32:0] br_bus;
wire [32:0] id_br_bus;
wire [4:0]  ws_to_rf_waddr;
wire [31:0] ws_to_rf_wdata;
wire        ws_to_rf_we;
wire        ms_hazard_valid;
wire        ms_hazard_gr_we;
wire [4:0]  ms_hazard_dest;
wire        ms_forward_valid;
wire [31:0] ms_forward_data;

// Architectural control state.  It is kept outside the five datapath stages
// so exception entry/return can flush the younger stages atomically.
reg [31:0] csr_crmd, csr_prmd, csr_ecfg, csr_estat, csr_era, csr_badv;
reg [31:0] csr_eentry, csr_save0, csr_save1, csr_save2, csr_save3;
reg [31:0] csr_tid, csr_tcfg, timer_cnt;
reg [63:0] stable_counter;
wire [13:0] id_csr_num;
reg [31:0] csr_rdata;
wire [31:0] rdcnt_value;
wire id_csr_we;
wire [31:0] id_csr_mask, id_csr_wdata;
wire [31:0] csr_tcfg_next = (csr_tcfg & ~id_csr_mask) | (id_csr_wdata & id_csr_mask);
wire id_exception, id_ertn, id_save_badv;
wire [5:0] id_ecode;
wire [8:0] id_esubcode;
wire [31:0] id_badv, id_pc;
wire id_valid, id_empty;
wire id_cache_valid;
wire [1:0] id_cache_op;
wire [31:0] id_cache_addr;
wire redirect_flush;

localparam [5:0] ECODE_INT  = 6'h00;
localparam [5:0] ECODE_ALE  = 6'h09;
localparam [5:0] ECODE_SYS  = 6'h0b;
localparam [5:0] ECODE_BRK  = 6'h0c;
localparam [5:0] ECODE_INE  = 6'h0d;

// UART IRQ fix: explicit sensitivity to every CSR value, not only csr_num.
// Adjacent accesses to the same CSR and changing TVAL must see current data.
always @(*) begin
        case (id_csr_num)
            14'h0000: csr_rdata = csr_crmd;
            14'h0001: csr_rdata = csr_prmd;
            14'h0004: csr_rdata = csr_ecfg;
            14'h0005: csr_rdata = csr_estat;
            14'h0006: csr_rdata = csr_era;
            14'h0007: csr_rdata = csr_badv;
            14'h000c: csr_rdata = csr_eentry;
            14'h0030: csr_rdata = csr_save0;
            14'h0031: csr_rdata = csr_save1;
            14'h0032: csr_rdata = csr_save2;
            14'h0033: csr_rdata = csr_save3;
            14'h0040: csr_rdata = csr_tid;
            14'h0041: csr_rdata = csr_tcfg;
            14'h0042: csr_rdata = timer_cnt;
            default:  csr_rdata = 32'b0;
        endcase
end
assign rdcnt_value = (id_pc[0]) ? stable_counter[63:32] : stable_counter[31:0];

wire timer_has_int = csr_crmd[2] && |(csr_estat[12:0] & csr_ecfg[12:0]);
wire exception_redirect = id_exception;
wire ertn_redirect = id_ertn;
// UART IRQ fix: stop ID issue when IRQ is pending, drain all older stages,
// and interrupt before the held ID instruction. ERA is that exact ID PC.
// Fetch-address arithmetic is not a retirement boundary (it may be stalled
// or already redirected), and must never be used to reconstruct ERA.
wire pipeline_busy = es_to_ms_valid || ms_hazard_valid;
wire interrupt_redirect = timer_has_int && id_valid && !pipeline_busy &&
                          !exception_redirect && !ertn_redirect;
wire normal_redirect = id_br_bus[32];
wire redirect_valid = normal_redirect | exception_redirect | ertn_redirect | interrupt_redirect;
wire [31:0] redirect_target = exception_redirect ? {csr_eentry[31:6],6'b0} :
                              ertn_redirect ? csr_era :
                              interrupt_redirect ? {csr_eentry[31:6],6'b0} :
                              id_br_bus[31:0];
assign br_bus = {redirect_valid, redirect_target};
assign redirect_flush = redirect_valid;

IF_stage u_if_stage(
    .clk(clk),
    .reset(reset),
    .ds_allowin(ds_allowin),
    .fs_to_ds_valid(fs_to_ds_valid),
    .fs_to_ds_bus(fs_to_ds_bus),
    .br_bus(br_bus),
    .inst_sram_en(inst_sram_en),
    .inst_sram_we(inst_sram_we),
    .inst_sram_addr(inst_sram_addr),
    .inst_sram_wdata(inst_sram_wdata),
    .inst_sram_rdata(inst_sram_rdata)
);

ID_stage u_id_stage(
    .clk(clk),
    .reset(reset),
    .es_allowin(es_allowin),
    .ds_allowin(ds_allowin),
    .fs_to_ds_valid(fs_to_ds_valid),
    .fs_to_ds_bus(fs_to_ds_bus),
    .ds_to_es_valid(ds_to_es_valid),
    .ds_to_es_bus(ds_to_es_bus),
    .br_bus(id_br_bus),
    .es_to_ms_valid(es_to_ms_valid),
    .es_to_ms_bus(es_to_ms_bus),
    .ms_hazard_valid(ms_hazard_valid),
    .ms_hazard_gr_we(ms_hazard_gr_we),
    .ms_hazard_dest(ms_hazard_dest),
    .ms_forward_valid(ms_forward_valid),
    .ms_forward_data(ms_forward_data),
    .ws_to_rf_we(ws_to_rf_we),
    .ws_to_rf_waddr(ws_to_rf_waddr),
    .ws_to_rf_wdata(ws_to_rf_wdata),
    .csr_rdata(csr_rdata),
    .rdcnt_low(stable_counter[31:0]),
    .rdcnt_high(stable_counter[63:32]),
    .csr_tid_value(csr_tid),
    .redirect_flush(redirect_flush),
    .pipeline_busy(pipeline_busy),
    .interrupt_pending(timer_has_int),
    .id_csr_we(id_csr_we),
    .id_csr_num(id_csr_num),
    .id_csr_mask(id_csr_mask),
    .id_csr_wdata(id_csr_wdata),
    .id_exception(id_exception),
    .id_ecode(id_ecode),
    .id_esubcode(id_esubcode),
    .id_save_badv(id_save_badv),
    .id_badv(id_badv),
    .id_ertn(id_ertn),
    .id_cache_valid(id_cache_valid),
    .id_cache_op(id_cache_op),
    .id_cache_addr(id_cache_addr),
    .id_pc(id_pc),
    .id_valid(id_valid),
    .id_empty(id_empty)
);

EXE_stage u_exe_stage(
    .clk(clk),
    .reset(reset),
    .ms_allowin(ms_allowin),
    .es_allowin(es_allowin),
    .ds_to_es_valid(ds_to_es_valid),
    .ds_to_es_bus(ds_to_es_bus),
    .es_to_ms_valid(es_to_ms_valid),
    .es_to_ms_bus(es_to_ms_bus)
);

MEM_stage u_mem_stage(
    .clk(clk),
    .reset(reset),
    .ws_allowin(ws_allowin),
    .ms_allowin(ms_allowin),
    .es_to_ms_valid(es_to_ms_valid),
    .es_to_ms_bus(es_to_ms_bus),
    .ms_to_ws_valid(ms_to_ws_valid),
    .ms_to_ws_bus(ms_to_ws_bus),
    .data_sram_en(data_sram_en),
    .data_sram_we(data_sram_we),
    .data_sram_addr(data_sram_addr),
    .data_sram_wdata(data_sram_wdata),
    .data_sram_rdata(data_sram_rdata),
    .ms_hazard_valid(ms_hazard_valid),
    .ms_hazard_gr_we(ms_hazard_gr_we),
    .ms_hazard_dest(ms_hazard_dest),
    .ms_forward_valid(ms_forward_valid),
    .ms_forward_data(ms_forward_data)
);

WB_stage u_wb_stage(
    .clk(clk),
    .reset(reset),
    .ms_to_ws_valid(ms_to_ws_valid),
    .ms_to_ws_bus(ms_to_ws_bus),
    .ws_to_rf_we(ws_to_rf_we),
    .ws_to_rf_waddr(ws_to_rf_waddr),
    .ws_to_rf_wdata(ws_to_rf_wdata),
    .debug_wb_pc(debug_wb_pc),
    .debug_wb_rf_we(debug_wb_rf_we),
    .debug_wb_rf_wnum(debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata)
);

// UART IRQ fix: ID-side CSR/exception/ERTN operations are serialized after
// EX/MEM drain. Their architectural side effects occur exactly once at ds_fire;
// normal data-path results still use the existing register-writeback path.
integer csr_i;
reg [3:0] state;
wire [31:0] pc = inst_sram_addr;
wire has_int = timer_has_int;
wire inst_ertn = id_ertn;

always @(posedge clk) begin
    if (reset) begin
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
        state <= 4'd0;
    end else begin
        state <= 4'd2;
        stable_counter <= stable_counter + 1'b1;

        if (csr_tcfg[0] && timer_cnt != 32'hffff_ffff) begin
            if (timer_cnt == 0) begin
                csr_estat[11] <= 1'b1;
                timer_cnt <= csr_tcfg[1] ? {csr_tcfg[31:2],2'b0} : 32'hffff_ffff;
            end else begin
                timer_cnt <= timer_cnt - 1'b1;
            end
        end

        if (id_csr_we) begin
            case (id_csr_num)
                14'h0000: csr_crmd  <= (csr_crmd  & ~id_csr_mask) | (id_csr_wdata & id_csr_mask);
                14'h0001: csr_prmd  <= (csr_prmd  & ~id_csr_mask) | (id_csr_wdata & id_csr_mask);
                14'h0004: csr_ecfg  <= (csr_ecfg  & ~id_csr_mask) | (id_csr_wdata & id_csr_mask);
                14'h0005: csr_estat[1:0] <= (csr_estat[1:0] & ~id_csr_mask[1:0]) |
                                           (id_csr_wdata[1:0] & id_csr_mask[1:0]);
                14'h0006: csr_era   <= (csr_era   & ~id_csr_mask) | (id_csr_wdata & id_csr_mask);
                14'h0007: csr_badv  <= (csr_badv  & ~id_csr_mask) | (id_csr_wdata & id_csr_mask);
                14'h000c: csr_eentry<= (csr_eentry& ~id_csr_mask) | (id_csr_wdata & id_csr_mask);
                14'h0030: csr_save0 <= (csr_save0 & ~id_csr_mask) | (id_csr_wdata & id_csr_mask);
                14'h0031: csr_save1 <= (csr_save1 & ~id_csr_mask) | (id_csr_wdata & id_csr_mask);
                14'h0032: csr_save2 <= (csr_save2 & ~id_csr_mask) | (id_csr_wdata & id_csr_mask);
                14'h0033: csr_save3 <= (csr_save3 & ~id_csr_mask) | (id_csr_wdata & id_csr_mask);
                14'h0040: csr_tid   <= (csr_tid   & ~id_csr_mask) | (id_csr_wdata & id_csr_mask);
                14'h0041: begin
                    csr_tcfg <= (csr_tcfg & ~id_csr_mask) | (id_csr_wdata & id_csr_mask);
                    if (csr_tcfg_next[0])
                        timer_cnt <= csr_tcfg_next & 32'hffff_fffc;
                    else
                        timer_cnt <= 32'hffff_ffff;
                end
                14'h0044: if (id_csr_mask[0] && id_csr_wdata[0]) csr_estat[11] <= 1'b0;
                default: ;
            endcase
        end

        if (id_exception) begin
            csr_prmd[1:0] <= csr_crmd[1:0];
            csr_prmd[2] <= csr_crmd[2];
            csr_crmd[1:0] <= 2'b0;
            csr_crmd[2] <= 1'b0;
            csr_estat[21:16] <= id_ecode;
            csr_estat[30:22] <= id_esubcode;
            csr_era <= id_pc;
            if (id_save_badv) csr_badv <= id_badv;
        end else if (interrupt_redirect) begin
            csr_prmd[1:0] <= csr_crmd[1:0];
            csr_prmd[2] <= csr_crmd[2];
            csr_crmd[1:0] <= 2'b0;
            csr_crmd[2] <= 1'b0;
            csr_estat[21:16] <= ECODE_INT;
            csr_estat[30:22] <= 9'b0;
            csr_era <= id_pc;
        end else if (id_ertn) begin
            csr_crmd[1:0] <= csr_prmd[1:0];
            csr_crmd[2] <= csr_prmd[2];
        end
    end
end

assign ws_allowin = 1'b1;

endmodule
