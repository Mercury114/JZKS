# Open the archived waveform without an original Vivado project.
set uart_evidence_dir [file dirname [file normalize [info script]]]
open_wave_database [file join $uart_evidence_dir tb_uart_irq_behav.wdb]
create_wave_config UART_Evidence
foreach uart_signal {clk resetn uart_rx uart_tx web_led num_data test_end global_err checks cases} {
    set uart_objects [get_objects -quiet /tb_uart_irq/$uart_signal]
    if {[llength $uart_objects]} {add_wave $uart_objects}
}
foreach uart_signal {interrupt_redirect timer_has_int id_pc id_valid pipeline_busy csr_estat csr_era csr_eentry csr_crmd id_ertn} {
    set uart_objects [get_objects -quiet /tb_uart_irq/dut/cpu/$uart_signal]
    if {[llength $uart_objects]} {add_wave $uart_objects}
}
puts "UART_EVIDENCE_WAVE_OPENED"
