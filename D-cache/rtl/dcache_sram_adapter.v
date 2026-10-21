`timescale 1ns/1ps

// Adapter between the course CPU's one-word SRAM request and the line
// protocol used by dcache.v.  It is intentionally self-contained: the
// backing store is an inferred 64K-word RAM, while the four-word refill and
// writeback handshake remains cycle-accurate and can be replaced by a BRAM
// wrapper in the board SoC.
module dcache_sram_adapter #(
    parameter integer MEM_WORDS = 65536
)(
    input  wire        clk,
    input  wire        resetn,
    input  wire        cpu_valid,
    input  wire        cpu_write,
    input  wire [31:0] cpu_addr,
    input  wire [3:0]  cpu_wstrb,
    input  wire [31:0] cpu_wdata,
    output wire        cpu_addr_ok,
    output wire        cpu_data_ok,
    output wire [31:0] cpu_rdata,
    input  wire        ctrl_valid,
    input  wire [1:0]  ctrl_op,
    input  wire [7:0]  ctrl_index,
    input  wire [19:0] ctrl_tag,
    output wire        ctrl_done
);
    wire [7:0]  req_index = cpu_addr[11:4];
    wire [19:0] req_tag   = cpu_addr[31:12];
    wire [3:0]  req_off   = cpu_addr[3:0];

    wire rd_req, wr_req, rd_rdy, wr_rdy;
    wire [2:0] rd_type, wr_type;
    wire [31:0] rd_addr, wr_addr;
    wire [3:0] wr_wstrb;
    wire [127:0] wr_data;
    reg ret_valid, ret_last;
    reg [31:0] ret_data;
    reg [31:0] backing [0:MEM_WORDS-1];
    reg refill_active;
    reg [31:0] refill_base;
    reg [1:0] refill_word;
    integer i;

    assign rd_rdy = !refill_active;
    assign wr_rdy = 1'b1;

    dcache u_dcache(
        .clk(clk), .resetn(resetn),
        .valid(cpu_valid), .op(cpu_write), .index(req_index), .tag(req_tag),
        .offset(req_off), .wstrb(cpu_wstrb), .wdata(cpu_wdata),
        .ctrl_valid(ctrl_valid), .ctrl_op(ctrl_op), .ctrl_index(ctrl_index),
        .ctrl_tag(ctrl_tag), .ctrl_done(ctrl_done),
        .addr_ok(cpu_addr_ok), .data_ok(cpu_data_ok), .rdata(cpu_rdata),
        .rd_req(rd_req), .rd_type(rd_type), .rd_addr(rd_addr), .rd_rdy(rd_rdy),
        .ret_valid(ret_valid), .ret_last(ret_last), .ret_data(ret_data),
        .wr_req(wr_req), .wr_type(wr_type), .wr_addr(wr_addr),
        .wr_wstrb(wr_wstrb), .wr_data(wr_data), .wr_rdy(wr_rdy)
    );

    always @(posedge clk) begin
        ret_valid <= 1'b0;
        ret_last <= 1'b0;
        if (!resetn) begin
            refill_active <= 1'b0;
            refill_base <= 32'b0;
            refill_word <= 2'b0;
            ret_data <= 32'b0;
            for (i = 0; i < MEM_WORDS; i = i + 1)
                backing[i] <= 32'b0;
        end else begin
            if (rd_req && rd_rdy) begin
                refill_active <= 1'b1;
                refill_base <= rd_addr >> 2;
                refill_word <= 2'b0;
            end else if (refill_active) begin
                ret_valid <= 1'b1;
                ret_last <= (refill_word == 2'd3);
                ret_data <= backing[refill_base + refill_word];
                if (refill_word == 2'd3)
                    refill_active <= 1'b0;
                else
                    refill_word <= refill_word + 1'b1;
            end
            if (wr_req && wr_rdy) begin
                backing[(wr_addr >> 2) + 0] <= wr_data[31:0];
                backing[(wr_addr >> 2) + 1] <= wr_data[63:32];
                backing[(wr_addr >> 2) + 2] <= wr_data[95:64];
                backing[(wr_addr >> 2) + 3] <= wr_data[127:96];
            end
        end
    end
endmodule
