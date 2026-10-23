set project_root [file normalize [file dirname [info script]]]
set project_dir [file join $project_root vivado_ex9]
file mkdir $project_dir

create_project loongson_ex9 $project_dir -part xc7a200tfbg676-1 -force
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

set rtl_files [list \
    [file join $project_root rtl mycpu_top.v] \
    [file join $project_root rtl bridge_1x2.v] \
    [file join $project_root rtl confreg.v] \
    [file join $project_root rtl soc_lite_top.v] \
    [file join $project_root rtl remote2local.v] \
    [file join $project_root rtl loongson_remote_top.v]]
add_files -norecurse $rtl_files

set ip_files [list \
    [file join $project_root ip_ascii clk_pll clk_pll.xci] \
    [file join $project_root ip_ascii data_ram data_ram.xci] \
    [file join $project_root ip_ascii inst_ram inst_ram.xci]]
add_files -norecurse $ip_files
add_files -fileset constrs_1 -norecurse [file join $project_root rtl loongson_remote.xdc]
add_files -fileset sim_1 -norecurse [file join $project_root tb_top.v]
set_property top looongson_remote_top [get_filesets sources_1]
set_property top tb_top [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_project
exit
