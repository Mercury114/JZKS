# 创新扩展：UART，保存常用波形并运行自检。
foreach signal {
    clk resetn uart_rx uart_tx expected_char echoed_char
    num_data rx_valid tx_busy rx_data rx_overrun rx_frame_error
    cpu_data_en cpu_data_we cpu_data_addr cpu_data_wdata cpu_data_rdata
    debug_wb_pc debug_wb_rf_we debug_wb_rf_wnum debug_wb_rf_wdata
    passed_chars test_end global_err
} {
    log_wave /tb_uart_soc/$signal
}
run all
quit
