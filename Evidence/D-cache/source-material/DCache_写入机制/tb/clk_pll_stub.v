`timescale 1ns / 1ps

// Simulation-only replacement for the board PLL. The cache protocol is
// synchronous, so preserving the testbench clock is sufficient here.
module clk_pll(
    output wire clk_out1,
    input  wire clk_in1
);
    assign clk_out1 = clk_in1;
endmodule
