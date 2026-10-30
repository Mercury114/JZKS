# Re-run the debug-enabled bridge snapshot and export trace data for inspection.
open_vcd cache_axi_bridge_tb.vcd
log_vcd /cache_axi_bridge_tb/*
run all
close_vcd
