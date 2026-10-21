# Repository CPU + FIFO UART console. All design files are referenced in place.
set scripts_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $scripts_dir]
set rtl_candidates {}
foreach candidate [glob -nocomplain -directory $repo_dir -types d */rtl] {
    if {[file exists [file join $candidate mycpu_top.v]]} {lappend rtl_candidates $candidate}
}
if {[llength $rtl_candidates] != 1} {error "Expected exactly one repository CPU directory"}
set rtl_dir [lindex $rtl_candidates 0]
set hardware_dir [file dirname $rtl_dir]
set build_dir [file join $scripts_dir console_build]
set xpr [file join $build_dir uart_console.xpr]
if {[file exists $xpr]} {error "Project already exists: $xpr"}
create_project uart_console $build_dir -part xc7a200tfbg676-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property target_simulator XSim [current_project]
foreach ip_name {inst_ram data_ram} {
    import_ip -files [file join $hardware_dir ip $ip_name ${ip_name}.xci]
    set coe [file normalize [file join $repo_dir innovation_uart sw obj ${ip_name}.coe]]
    if {![file exists $coe]} {error "Firmware COE missing: $coe"}
    set_property -dict [list CONFIG.Load_Init_File true CONFIG.Coe_File $coe] [get_ips $ip_name]
}
generate_target all [get_ips]
foreach name {
    mycpu_top.v bridge_1x2.v confreg.v remote2local.v soc_lite_top.v loongson_remote_top.v
    UART/uart_tx.v UART/uart_rx.v UART/uart_mmio.v
} {
    add_files -norecurse [file join $rtl_dir $name]
}
add_files -fileset constrs_1 -norecurse [file join $hardware_dir constraints loongson_remote.xdc]
foreach name {tb_uart_console.v tb_uart_fifo.v tb_uart_stopwatch.v tb_uart_irq.v} {
    add_files -fileset sim_1 -norecurse [file join $repo_dir innovation_uart sim $name]
}
set_property top looongson_remote_top [get_filesets sources_1]
set_property top tb_uart_console [get_filesets sim_1]
set_property xsim.simulate.runtime 1000ns [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "UART_CONSOLE_PROJECT_CREATED: $xpr"
