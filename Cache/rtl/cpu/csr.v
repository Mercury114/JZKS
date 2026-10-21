// Part 6: CSR、异常现场和定时器；所有软件读写都在 WB 完成。
// Part 6: 本阶段只使用直接地址模式，CRMD.DA=1、PG/DATF/DATM=0。
`timescale 1ns/1ps
`default_nettype none

module csr(
    input  wire        clk,
    input  wire        reset,
    input  wire [ 7:0] hw_int_in,
    input  wire [13:0] csr_num,
    input  wire        csr_we,
    input  wire [31:0] csr_wmask,
    input  wire [31:0] csr_wvalue,
    input  wire        wb_ex,
    input  wire [ 5:0] wb_ecode,
    input  wire [31:0] wb_pc,
    input  wire [31:0] wb_badv,
    input  wire        ertn_flush,
    output reg  [31:0] csr_rvalue,
    output wire [31:0] ex_entry,
    output wire [31:0] ex_era,
    output wire [ 1:0] current_plv,
    output wire        has_int,
    output reg  [63:0] stable_counter,
    output reg  [31:0] counter_id
);

reg  [ 2:0] crmd;
reg  [ 2:0] prmd;
reg  [12:0] ecfg;
reg  [ 1:0] software_int;
reg  [ 7:0] hardware_int;
reg  [ 5:0] ecode;
reg  [31:0] era;
reg  [31:0] badv;
reg  [31:0] eentry;
reg  [31:0] save0;
reg  [31:0] save1;
reg  [31:0] save2;
reg  [31:0] save3;
reg  [31:0] tcfg;
reg  [31:0] timer_cnt;
reg         timer_int;
wire [12:0] interrupt_status;
wire [31:0] write_value;
wire        write_tcfg;
wire        clear_timer;
wire        timer_expired;

// Part 6: 未实现的 CSR 读零、写忽略；保留位和只读位不接受软件写入。
always @(*) begin
    case (csr_num)
        14'h0000: csr_rvalue = {28'b0, 1'b1, crmd};
        14'h0001: csr_rvalue = {29'b0, prmd};
        14'h0004: csr_rvalue = {19'b0, ecfg};
        14'h0005: csr_rvalue = {10'b0, ecode, 3'b0, interrupt_status};
        14'h0006: csr_rvalue = era;
        14'h0007: csr_rvalue = badv;
        14'h000c: csr_rvalue = eentry;
        14'h0030: csr_rvalue = save0;
        14'h0031: csr_rvalue = save1;
        14'h0032: csr_rvalue = save2;
        14'h0033: csr_rvalue = save3;
        14'h0040: csr_rvalue = counter_id;
        14'h0041: csr_rvalue = tcfg;
        14'h0042: csr_rvalue = timer_cnt;
        default:  csr_rvalue = 32'b0;
    endcase
end

// Part 6: CSRWR 的掩码全一；CSRXCHG 只更新 rj 指定的位。
assign write_value = (csr_wmask & csr_wvalue) | (~csr_wmask & csr_rvalue);
assign interrupt_status = {1'b0, timer_int, 1'b0, hardware_int, software_int};
assign has_int       = crmd[2] && (|(interrupt_status & ecfg));
assign ex_entry      = eentry;
assign ex_era        = era;
// Part 6: 重定向取指时使用即将生效的特权级，防止 ERTN 后漏掉用户态 ADEF。
assign current_plv   = wb_ex ? 2'b0 : ertn_flush ? prmd[1:0] : crmd[1:0];
assign write_tcfg    = csr_we && (csr_num == 14'h0041);
assign clear_timer   = csr_we && (csr_num == 14'h0044) && csr_wmask[0] && csr_wvalue[0];
assign timer_expired = tcfg[0] && (timer_cnt == 32'b0);

// Part 6: 异常保存旧 PLV/IE，再进入内核并关中断；ERTN 恢复保存值。
always @(posedge clk) begin
    if (reset) begin
        crmd <= 3'b0;
        prmd <= 3'b0;
    end
    else if (wb_ex) begin
        prmd <= crmd;
        crmd <= 3'b0;
    end
    else if (ertn_flush) begin
        crmd <= prmd;
    end
    else if (csr_we && (csr_num == 14'h0000)) begin
        crmd <= write_value[2:0];
    end
    else if (csr_we && (csr_num == 14'h0001)) begin
        prmd <= write_value[2:0];
    end
end

// Part 6: ERA 记录异常指令的 PC；只有地址类异常更新 BADV。
always @(posedge clk) begin
    if (reset) begin
        ecfg         <= 13'b0;
        software_int <= 2'b0;
        hardware_int <= 8'b0;
        ecode        <= 6'b0;
        era          <= 32'b0;
        badv         <= 32'b0;
        eentry       <= 32'b0;
        save0        <= 32'b0;
        save1        <= 32'b0;
        save2        <= 32'b0;
        save3        <= 32'b0;
        counter_id   <= 32'b0;
    end
    else begin
        hardware_int <= hw_int_in;
        if (wb_ex) begin
            ecode <= wb_ecode;
            era   <= wb_pc;
            if ((wb_ecode == 6'h08) || (wb_ecode == 6'h09)) begin
                badv <= wb_badv;
            end
        end
        else if (csr_we) begin
            case (csr_num)
                14'h0004: ecfg         <= write_value[12:0] & 13'h1bff;
                14'h0005: software_int <= write_value[1:0];
                14'h0006: era          <= write_value;
                14'h0007: badv         <= write_value;
                14'h000c: eentry       <= {write_value[31:6], 6'b0};
                14'h0030: save0        <= write_value;
                14'h0031: save1        <= write_value;
                14'h0032: save2        <= write_value;
                14'h0033: save3        <= write_value;
                14'h0040: counter_id   <= write_value;
                default: begin
                end
            endcase
        end
    end
end

// Part 6: 恒定频率计数器与可编程倒计时器是两个不同部件。
always @(posedge clk) begin
    if (reset) begin
        stable_counter <= 64'b0;
        tcfg           <= 32'b0;
        timer_cnt      <= 32'hffffffff;
        timer_int      <= 1'b0;
    end
    else begin
        stable_counter <= stable_counter + 64'd1;
        if (write_tcfg) begin
            tcfg <= write_value;
            if (write_value[0]) begin
                timer_cnt <= {write_value[31:2], 2'b0};
            end
        end
        else if (tcfg[0] && (timer_cnt != 32'hffffffff)) begin
            if ((timer_cnt == 32'b0) && tcfg[1]) begin
                timer_cnt <= {tcfg[31:2], 2'b0};
            end
            else begin
                timer_cnt <= timer_cnt - 32'd1;
            end
        end
        if (timer_expired) begin
            timer_int <= 1'b1;
        end
        else if (clear_timer) begin
            timer_int <= 1'b0;
        end
    end
end

endmodule

`default_nettype wire
