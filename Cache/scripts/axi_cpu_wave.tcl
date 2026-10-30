# Run from Cache/build/axi with the debug-enabled integrated CPU snapshot.
log_wave -r /
create_wave_config

add_wave_divider {Clock and CPU writeback}
add_wave /mycpu_top_axi_tb/clk
add_wave /mycpu_top_axi_tb/resetn
add_wave -radix hex /mycpu_top_axi_tb/wb_pc
add_wave -radix hex /mycpu_top_axi_tb/wb_we
add_wave -radix unsigned /mycpu_top_axi_tb/wb_num
add_wave -radix hex /mycpu_top_axi_tb/wb_data
add_wave /mycpu_top_axi_tb/axi_error

add_wave_divider {Cache request to AXI bridge}
add_wave /mycpu_top_axi_tb/dut/mem_valid
add_wave /mycpu_top_axi_tb/dut/mem_write
add_wave /mycpu_top_axi_tb/dut/mem_ready
add_wave -radix hex /mycpu_top_axi_tb/dut/mem_addr
add_wave -radix hex /mycpu_top_axi_tb/dut/mem_wdata
add_wave -radix hex /mycpu_top_axi_tb/dut/mem_wstrb
add_wave /mycpu_top_axi_tb/dut/mem_rvalid

add_wave_divider {Read address AR}
add_wave /mycpu_top_axi_tb/arvalid
add_wave /mycpu_top_axi_tb/arready
add_wave -radix hex /mycpu_top_axi_tb/araddr
add_wave -radix unsigned /mycpu_top_axi_tb/arlen

add_wave_divider {Read data R}
add_wave /mycpu_top_axi_tb/rvalid
add_wave /mycpu_top_axi_tb/rready
add_wave -radix hex /mycpu_top_axi_tb/rdata
add_wave /mycpu_top_axi_tb/rlast

add_wave_divider {Write address AW}
add_wave /mycpu_top_axi_tb/awvalid
add_wave /mycpu_top_axi_tb/awready
add_wave -radix hex /mycpu_top_axi_tb/awaddr

add_wave_divider {Write data W}
add_wave /mycpu_top_axi_tb/wvalid
add_wave /mycpu_top_axi_tb/wready
add_wave -radix hex /mycpu_top_axi_tb/wdata
add_wave -radix hex /mycpu_top_axi_tb/wstrb
add_wave /mycpu_top_axi_tb/wlast

add_wave_divider {Write response B and MMIO result}
add_wave /mycpu_top_axi_tb/bvalid
add_wave /mycpu_top_axi_tb/bready
add_wave -radix hex /mycpu_top_axi_tb/bresp
add_wave -radix hex /mycpu_top_axi_tb/mmio_value
add_wave -radix unsigned /mycpu_top_axi_tb/mmio_writes

save_wave_config mycpu_top_axi_tb.wcfg
run all
