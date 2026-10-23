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
# UART IRQ fix: explicit firmware profiles keep course fixtures immutable.
if {![info exists firmware]} {set firmware ex9}
if {![info exists build_dir]} {set build_dir [file join $scripts_dir [expr {$firmware eq "uart" ? "console_build_uart" : "console_build"}]]}
set xpr [file join $build_dir pipeline_uart.xpr]
if {[file exists $xpr]} {error "Project already exists: $xpr"}
create_project pipeline_uart $build_dir -part xc7a200tfbg676-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property target_simulator XSim [current_project]
# Keep the explicitly listed course files enabled.  Automatic hierarchy
# management otherwise disables every in-place source before it can infer the
# top-level module from the non-ASCII project path.
set_property source_mgmt_mode None [current_project]
foreach name {
    mycpu_top.v mycpu_head.v tools.v alu.v regfile.v IF_stage.v ID_stage.v EXE_stage.v MEM_stage.v WB_stage.v
    bridge_1x2.v confreg.v remote2local.v soc_lite_top.v loongson_remote_top.v course_ram.v
    dcache.v dcache_sram_adapter.v
    UART/uart_tx.v UART/uart_rx.v UART/uart_mmio.v
} {
    add_files -norecurse [file join $rtl_dir $name]
}
add_files -fileset constrs_1 -norecurse [file join $rtl_dir loongson_remote.xdc]
if {$firmware eq "uart"} {
    set image_dir [file join $repo_dir innovation_uart sw obj]
} else {
    set image_dir [file join $hardware_dir ip_ascii]
}
foreach name {inst_ram data_ram} {
    set image [expr {$firmware eq "uart" ? [file join $image_dir ${name}.mif] : [file join $image_dir $name ${name}.mif]}]
    if {![file exists $image]} {error "Image missing: $image (run prepare_images.py for UART)"}
    add_files -norecurse $image
    add_files -fileset sim_1 -norecurse $image
}
foreach name {tb_uart_console.v tb_uart_fifo.v tb_uart_stopwatch.v tb_uart_irq.v tb_uart_board_boot.v} {
    add_files -fileset sim_1 -norecurse [file join $repo_dir innovation_uart sim $name]
}
set_property is_enabled true [get_files -of_objects [get_filesets sources_1]]
set_property is_enabled true [get_files -of_objects [get_filesets sim_1]]
set_property top looongson_remote_top [get_filesets sources_1]
set_property top tb_uart_console [get_filesets sim_1]
set_property xsim.simulate.runtime 1000ns [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "UART_CONSOLE_PROJECT_CREATED: $xpr"
