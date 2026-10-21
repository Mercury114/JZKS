`timescale 1ns / 1ps
`default_nettype none

// CDP远程板接入：保留原remote2local的开关、复位、LED和数码管极性。
// 50MHz板载时钟直接作为CPU时钟，不沿用原多周期核心的逻辑分频。
module cache_remote_top #(
    parameter INST_INIT_FILE = "",
    parameter INDEX_WIDTH = 8,
    parameter WAY_NUM = 2,
    parameter ENABLE_CACHE = 1
)(
    input  wire        clk_50M,
    input  wire        reset_btn,
    input  wire [31:0] dip_sw,
    output wire [15:0] leds,
    output wire [7:0]  dpy0,
    output wire [7:0]  dpy1
);
    wire local_resetn;
    wire [7:0] local_switch;
    wire [15:0] local_leds;
    wire [31:0] local_num_data;
    remote2local u_remote2local(
        .remote_switch(dip_sw), .local_switch(local_switch),
        .remote_reset(reset_btn), .local_resetn(local_resetn),
        .local_leds(local_leds), .remote_leds(leds), .local_num_data(local_num_data[7:0]),
        .remote_dpy0(dpy0), .remote_dpy1(dpy1)
    );
    cache_soc_lite_top #(.SIMULATION(0), .INST_INIT_FILE(INST_INIT_FILE),
                         .INDEX_WIDTH(INDEX_WIDTH), .WAY_NUM(WAY_NUM), .ENABLE_CACHE(ENABLE_CACHE)) u_soc(
        .clk(clk_50M), .resetn(local_resetn), .num_data(local_num_data),
        .led(local_leds), .led_rg0(), .led_rg1(), .num_csn(), .num_a_g(),
        .switch(local_switch), .btn_key_col(), .btn_key_row(4'b0), .btn_step(2'b11)
    );
endmodule
`default_nettype wire
