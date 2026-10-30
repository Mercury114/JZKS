# Re-run the debug-enabled CPU snapshot and export selected top-level signals.
open_vcd mycpu_top_axi_tb.vcd
foreach sig {clk resetn wb_pc wb_we wb_num wb_data axi_error arvalid arready araddr rvalid rready rdata rresp rlast awvalid awready awaddr wvalid wready wdata wstrb wlast bvalid bready bresp mmio_value mmio_writes} {
    log_vcd /mycpu_top_axi_tb/$sig
}
run all
close_vcd
