# Run from Cache/build/axi with the debug-enabled bridge snapshot.
log_wave -r /
create_wave_config

add_wave_divider {Clock and cache request}
add_wave /cache_axi_bridge_tb/clk
add_wave /cache_axi_bridge_tb/resetn
add_wave /cache_axi_bridge_tb/mem_valid
add_wave /cache_axi_bridge_tb/mem_write
add_wave /cache_axi_bridge_tb/mem_ready
add_wave -radix hex /cache_axi_bridge_tb/mem_addr
add_wave -radix hex /cache_axi_bridge_tb/mem_wdata
add_wave -radix hex /cache_axi_bridge_tb/mem_wstrb
add_wave /cache_axi_bridge_tb/mem_rvalid
add_wave -radix hex /cache_axi_bridge_tb/mem_rdata
add_wave /cache_axi_bridge_tb/axi_error

add_wave_divider {Read address AR}
add_wave /cache_axi_bridge_tb/arvalid
add_wave /cache_axi_bridge_tb/arready
add_wave -radix hex /cache_axi_bridge_tb/araddr
add_wave -radix unsigned /cache_axi_bridge_tb/arsize

add_wave_divider {Read data R}
add_wave /cache_axi_bridge_tb/rvalid
add_wave /cache_axi_bridge_tb/rready
add_wave -radix hex /cache_axi_bridge_tb/rdata
add_wave -radix hex /cache_axi_bridge_tb/rresp
add_wave /cache_axi_bridge_tb/rlast

add_wave_divider {Write address AW}
add_wave /cache_axi_bridge_tb/awvalid
add_wave /cache_axi_bridge_tb/awready
add_wave -radix hex /cache_axi_bridge_tb/awaddr
add_wave -radix unsigned /cache_axi_bridge_tb/awsize

add_wave_divider {Write data W}
add_wave /cache_axi_bridge_tb/wvalid
add_wave /cache_axi_bridge_tb/wready
add_wave -radix hex /cache_axi_bridge_tb/wdata
add_wave -radix hex /cache_axi_bridge_tb/wstrb
add_wave /cache_axi_bridge_tb/wlast

add_wave_divider {Write response B and bridge state}
add_wave /cache_axi_bridge_tb/bvalid
add_wave /cache_axi_bridge_tb/bready
add_wave -radix hex /cache_axi_bridge_tb/bresp
add_wave -radix unsigned /cache_axi_bridge_tb/dut/state
add_wave /cache_axi_bridge_tb/dut/aw_sent
add_wave /cache_axi_bridge_tb/dut/w_sent

save_wave_config cache_axi_bridge_tb.wcfg
run all
